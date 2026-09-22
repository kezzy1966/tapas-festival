<script setup lang="ts">
import { nextTick, onMounted, onUnmounted, ref, watch } from 'vue';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import 'leaflet.markercluster';

type RatingStat = { tapa_id: string; rating_count: number; average_rating: number | null };
type Establishment = Record<string, any>;
type Tapa = Record<string, any>;

const emit = defineEmits<{ selectTapa: [tapaId: string, establishmentId: string]; selectEstablishment: [establishmentId: string] }>();

const props = defineProps<{
  establishments: Establishment[];
  tapas: Tapa[];
  stats: Record<string, RatingStat>;
  myReviews: Record<string, { id: string; rating: number | null }>;
  locationActive: boolean;
  selectedEstablishmentId: string | null;
  wantedTapas: Record<string, boolean>;
  openNowOnly: boolean;
  showRatingCounts: boolean;
}>();

const mapContainer = ref<HTMLElement | null>(null);
let map: L.Map | null = null;
let markers: L.MarkerClusterGroup | null = null;
let userMarker: L.Marker | null = null;
let selectedMarker: L.Marker | null = null;
let rotationControl: L.Control | null = null;
let rotationNorthButton: HTMLButtonElement | null = null;
let rotationLeftButton: HTMLButtonElement | null = null;
let rotationRightButton: HTMLButtonElement | null = null;
let locationWatchId: number | null = null;
let locationHasCentered = false;
const locationUnavailable = ref(false);
const bearing = ref(0);

const tiles = 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png';
const attribution = '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors';
const festivalBounds = L.latLngBounds([39.92, -0.22], [40.06, 0.04]);
const { language, t, localized } = useFestivalLanguage();
const { now: openingHoursNow, openingHoursStatus } = useOpeningHoursStatus();
function venueHoursLabel(venue: Establishment) { const status = openingHoursStatus(venue.opening_hours, openingHoursNow.value); return status === 'open' ? 'Open now' : status === 'closed' ? 'Closed now' : 'Hours unavailable'; }
const weekdays = computed(() => language.value === 'es' ? ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'] : ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']);

const mappableCount = () => props.establishments.filter(hasCoordinates).length;

function hasCoordinates(venue: Establishment) {
  return Number.isFinite(Number(venue.latitude)) && Number.isFinite(Number(venue.longitude));
}
function isNearFestivalArea(point: L.LatLng) {
  return festivalBounds.contains(point);
}
function clampToFestivalBounds(point: L.LatLng) {
  return L.latLng(
    Math.min(festivalBounds.getNorth(), Math.max(festivalBounds.getSouth(), point.lat)),
    Math.min(festivalBounds.getEast(), Math.max(festivalBounds.getWest(), point.lng)),
  );
}
function clampViewCenter(point: L.LatLng, zoom: number) {
  if (!map) return clampToFestivalBounds(point);
  const northWest = map.project(festivalBounds.getNorthWest(), zoom);
  const southEast = map.project(festivalBounds.getSouthEast(), zoom);
  const halfSize = map.getSize().divideBy(2);
  const requested = map.project(point, zoom);
  const clampAxis = (value: number, min: number, max: number) => {
    if (min > max) return (min + max) / 2;
    return Math.min(max, Math.max(min, value));
  };
  return map.unproject(L.point(
    clampAxis(requested.x, northWest.x + halfSize.x, southEast.x - halfSize.x),
    clampAxis(requested.y, northWest.y + halfSize.y, southEast.y - halfSize.y),
  ), zoom);
}
function setFestivalView(center: L.LatLng, zoom: number) {
  if (!map) return;
  map.setView(clampViewCenter(center, zoom), zoom, { animate: false });
}
function focusBoundsWithinFestival(bounds: L.LatLngBounds) {
  if (!map || !bounds.isValid()) return;
  const padding = L.point(112, 112);
  const zoom = Math.min(15, Math.max(map.getMinZoom(), map.getBoundsZoom(bounds, false, padding)));
  setFestivalView(bounds.getCenter(), zoom);
}
function escapeHtml(value: unknown) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}
function text(english?: string | null, spanish?: string | null) {
  return localized(english, spanish);
}
function openingHourRows(hours: unknown) {
  if (!hours || typeof hours !== 'object' || Array.isArray(hours)) return [];
  return Object.entries(hours as Record<string, unknown>).map(([day, periods]) => {
    const label = weekdays.value[Number(day) - 1] || day;
    if (!Array.isArray(periods) || periods.length === 0) return { day: label, times: t('closed') };
    const times = periods.map((period: any) => Array.isArray(period) ? `${period[0]}–${period[1]}` : '').filter(Boolean).join(', ');
    return times ? { day: label, times } : null;
  }).filter(Boolean) as { day: string; times: string }[];
}

function venueTapas(venueId: string) {
  return props.tapas.filter((tapa) => tapa.establishment_id === venueId && tapa.is_published);
}
function ratingText(tapa: Tapa) {
  const rating = props.stats[tapa.id];
  if (!rating || !Number(rating.rating_count)) return t('notRatedYet');
  return `${Number(rating.average_rating).toFixed(1)} ★${props.showRatingCounts ? ` (${rating.rating_count})` : ""}`;
}
function statusText(venue: Establishment) {
  if (venue.participation_status === 'withdrawn') return t('suspended');
  if (venue.closure_status && venue.closure_status !== 'normal') return t('closed');
  return '';
}
function popupHtml(venue: Establishment) {
  const tapas = venueTapas(venue.id);
  const tapaList = tapas.length
    ? `<ul class="festival-map-popup__tapas">${tapas.map((tapa) => `<li><button type="button" class="festival-map-popup__tapa-link" data-tapa-id="${escapeHtml(tapa.id)}" data-establishment-id="${escapeHtml(venue.id)}">${escapeHtml(text(tapa.name_en, tapa.name_es))}${props.wantedTapas[tapa.id] ? ' <span class="festival-map-popup__wanted" aria-hidden="true">★</span>' : ''}</button></li>`).join('')}</ul>`
    : `<p>${escapeHtml(t('noPublishedTapas'))}</p>`;
  return `<div class="festival-map-popup-content"><h3><button type="button" class="festival-map-popup__establishment-link" data-popup-establishment-id="${escapeHtml(venue.id)}">${escapeHtml(venue.name)}</button></h3><p class="festival-map-popup__hours-status">${escapeHtml(venueHoursLabel(venue))}</p>${tapaList}</div>`;
}
function attachPopupTapaHandlers(popup: L.Popup) {
  const element = popup.getElement();
  if (!element) return;
  element.querySelectorAll<HTMLButtonElement>('[data-popup-establishment-id]').forEach((button) => {
    button.addEventListener('click', (event) => {
      event.preventDefault();
      event.stopPropagation();
      const establishmentId = button.dataset.popupEstablishmentId;
      if (establishmentId) emit('selectEstablishment', establishmentId);
    });
  });
  element.querySelectorAll<HTMLButtonElement>('[data-tapa-id]').forEach((button) => {
    button.addEventListener('click', (event) => {
      event.preventDefault();
      event.stopPropagation();
      const tapaId = button.dataset.tapaId;
      const establishmentId = button.dataset.establishmentId;
      if (tapaId && establishmentId) emit('selectTapa', tapaId, establishmentId);
    });
  });
}
function venueReviewProgress(venueId: string) {
  const eligibleTapas = props.tapas.filter((tapa) => tapa.establishment_id === venueId && tapa.is_published && tapa.participation_status === 'active');
  const reviewedCount = eligibleTapas.filter((tapa) => props.myReviews[tapa.id]?.rating != null).length;
  return { reviewedCount, total: eligibleTapas.length, ratio: eligibleTapas.length ? reviewedCount / eligibleTapas.length : 0 };
}
function venueHasRatedTapa(venueId: string) {
  return venueReviewProgress(venueId).reviewedCount > 0;
}
function reviewMarkerClass(venueId: string, prefix = 'festival-marker') {
  const ratio = venueReviewProgress(venueId).ratio;
  if (ratio >= 1) return ` ${prefix}--rated`;
  if (ratio > 0) return ` ${prefix}--partial`;
  return '';
}
function reviewMarkerStyle(venueId: string) {
  const { ratio } = venueReviewProgress(venueId);
  return ratio > 0 && ratio < 1 ? ` style="--reviewed-percent:${Math.round(ratio * 100)}%"` : '';
}
function venueHasWantedTapa(venueId: string) {
  return props.tapas.some((tapa) => tapa.establishment_id === venueId && Boolean(props.wantedTapas[tapa.id]));
}
function clusterIcon(cluster: L.MarkerCluster) {
  const childMarkers = cluster.getAllChildMarkers();
  const containsRatedVenue = childMarkers.some((marker) => {
    const venueId = (marker.options as any).festivalVenueId as string | undefined;
    return Boolean(venueId && venueHasRatedTapa(venueId));
  });
  const containsOpenVenue = !props.openNowOnly || childMarkers.some((marker) => {
    const venueId = (marker.options as any).festivalVenueId as string | undefined;
    const venue = venueId ? props.establishments.find((item) => item.id === venueId) : null;
    return Boolean(venue && openingHoursStatus(venue.opening_hours, openingHoursNow.value) === 'open');
  });
  return L.divIcon({
    className: 'festival-cluster-wrapper',
    html: `<div class="festival-cluster${containsRatedVenue ? ' festival-cluster--rated' : ''}${!containsOpenVenue ? ' festival-cluster--hours-faded' : ''}">${cluster.getChildCount()}</div>`,
    iconSize: [42, 42],
    iconAnchor: [21, 21],
  });
}
function markerIcon(venue: Establishment) {
  const unavailable = venue.participation_status === 'withdrawn' || (venue.closure_status && venue.closure_status !== 'normal');
  const wanted = venueHasWantedTapa(venue.id);
  const selected = props.selectedEstablishmentId === venue.id;
  const hoursFaded = props.openNowOnly && openingHoursStatus(venue.opening_hours, openingHoursNow.value) !== 'open';
  return L.divIcon({
    className: 'festival-marker-wrapper',
    html: `<div class="festival-marker${unavailable ? ' festival-marker--unavailable' : ''}${unavailable ? '' : reviewMarkerClass(venue.id)}${selected ? ' festival-marker--selected' : ''}${hoursFaded ? ' festival-marker--hours-faded' : ''}"${unavailable ? '' : reviewMarkerStyle(venue.id)}>●${wanted ? '<span class="festival-marker__wanted" aria-hidden="true">★</span>' : ''}</div>`,
    iconSize: [30, 30],
    iconAnchor: [15, 15],
    popupAnchor: [0, -15],
  });
}
const userLocationIcon = L.divIcon({ className: 'festival-user-location-wrapper', html: '<div class="festival-user-location"></div>', iconSize: [22, 22], iconAnchor: [11, 11] });
function selectedVenueIcon(venue: Establishment) {
  return L.divIcon({ className: 'festival-selected-marker-wrapper', html: `<div class="festival-selected-marker${reviewMarkerClass(venue.id, 'festival-selected-marker')}"${reviewMarkerStyle(venue.id)}>●${venueHasWantedTapa(venue.id) ? '<span class="festival-marker__wanted" aria-hidden="true">★</span>' : ''}</div>`, iconSize: [42, 42], iconAnchor: [21, 21], popupAnchor: [0, -21] });
}
function clearSelectedMarker() {
  selectedMarker?.remove();
  selectedMarker = null;
}
function focusSelectedVenue() {
  clearSelectedMarker();
  if (!map || !props.selectedEstablishmentId) return;
  const venue = props.establishments.find((item) => item.id === props.selectedEstablishmentId);
  if (!venue || !hasCoordinates(venue)) return;
  const point = L.latLng(Number(venue.latitude), Number(venue.longitude));
  selectedMarker = L.marker(point, { icon: selectedVenueIcon(venue), title: venue.name, zIndexOffset: 1000 })
    .addTo(map)
    .bindPopup(popupHtml(venue), { className: 'festival-map-popup', maxWidth: 240 });
  if (userMarker && isNearFestivalArea(userMarker.getLatLng())) {
    focusBoundsWithinFestival(L.latLngBounds([point, userMarker.getLatLng()]));
  } else {
    setFestivalView(point, Math.max(map.getZoom(), 15));
  }
}
type RotatableMap = L.Map & { setBearing: (value: number) => void; getBearing: () => number };
function normalizedBearing(value: number) {
  return ((Math.round(value) % 360) + 360) % 360;
}
function updateRotationControl() {
  const isRotated = bearing.value !== 0;
  rotationNorthButton?.classList.toggle('festival-rotation-control__north--rotated', isRotated);
  rotationNorthButton?.setAttribute('aria-pressed', String(!isRotated));
  rotationLeftButton?.setAttribute('title', t('rotateMapLeft'));
  rotationLeftButton?.setAttribute('aria-label', t('rotateMapLeft'));
  rotationNorthButton?.setAttribute('title', t('resetNorth'));
  rotationNorthButton?.setAttribute('aria-label', t('resetNorth'));
  rotationRightButton?.setAttribute('title', t('rotateMapRight'));
  rotationRightButton?.setAttribute('aria-label', t('rotateMapRight'));
}
function setBearing(value: number) {
  const rotationMap = map as RotatableMap | null;
  if (!rotationMap || typeof rotationMap.setBearing !== 'function') return;
  bearing.value = normalizedBearing(value);
  rotationMap.setBearing(bearing.value);
  updateRotationControl();
}
function addRotationControl() {
  if (!map) return;
  const RotationControl = L.Control.extend({
    options: { position: 'bottomleft' },
    onAdd() {
      const container = L.DomUtil.create('div', 'leaflet-bar festival-rotation-control');
      const addButton = (label: string, handler: () => void) => {
        const button = L.DomUtil.create('button', 'festival-rotation-control__button', container) as HTMLButtonElement;
        button.type = 'button';
        button.textContent = label;
        L.DomEvent.on(button, 'click', (event) => { L.DomEvent.stop(event); handler(); });
        return button;
      };
      rotationLeftButton = addButton('↶', () => setBearing(bearing.value - 5));
      rotationNorthButton = addButton('N', () => setBearing(0));
      rotationRightButton = addButton('↷', () => setBearing(bearing.value + 5));
      L.DomEvent.disableClickPropagation(container);
      L.DomEvent.disableScrollPropagation(container);
      updateRotationControl();
      return container;
    },
    onRemove() {
      rotationLeftButton = null;
      rotationNorthButton = null;
      rotationRightButton = null;
    },
  });
  rotationControl = new RotationControl();
  map.addControl(rotationControl);
  map.on('rotate', () => {
    const rotationMap = map as RotatableMap;
    bearing.value = normalizedBearing(rotationMap.getBearing());
    updateRotationControl();
  });
}
function stopLocationTracking() {
  if (locationWatchId !== null && typeof navigator !== 'undefined') navigator.geolocation.clearWatch(locationWatchId);
  locationWatchId = null;
}
function startLocationTracking() {
  if (!map || locationWatchId !== null || !props.locationActive) return;
  if (typeof navigator === 'undefined' || !navigator.geolocation) { locationUnavailable.value = true; return; }
  locationUnavailable.value = false;
  locationWatchId = navigator.geolocation.watchPosition((position) => {
    const point: L.LatLngExpression = [position.coords.latitude, position.coords.longitude];
    const firstLocation = !userMarker;
    if (!userMarker) userMarker = L.marker(point, { icon: userLocationIcon, interactive: false, keyboard: false, title: 'Your location' }).addTo(map!);
    else userMarker.setLatLng(point);
    if (firstLocation && props.selectedEstablishmentId) {
      focusSelectedVenue();
      locationHasCentered = true;
    } else if (!locationHasCentered) {
      if (isNearFestivalArea(userMarker!.getLatLng())) setFestivalView(userMarker!.getLatLng(), Math.max(map!.getZoom(), 15));
      locationHasCentered = true;
    }
  }, () => { locationUnavailable.value = true; stopLocationTracking(); }, { enableHighAccuracy: true, maximumAge: 15000, timeout: 10000 });
}
function updateMarkers(fitToAll = true) {
  if (!map || !markers) return;
  markers.clearLayers();
  const bounds = L.latLngBounds([]);
  props.establishments.filter(hasCoordinates).forEach((venue) => {
    const position: L.LatLngExpression = [Number(venue.latitude), Number(venue.longitude)];
    bounds.extend(position);
    const marker = L.marker(position, { icon: markerIcon(venue), title: venue.name });
    (marker.options as any).festivalVenueId = venue.id;
    markers!.addLayer(marker.bindPopup(popupHtml(venue), { className: 'festival-map-popup', maxWidth: 240 }));
  });
  if (selectedMarker && props.selectedEstablishmentId) {
    const selectedVenue = props.establishments.find((venue) => venue.id === props.selectedEstablishmentId);
    if (selectedVenue && hasCoordinates(selectedVenue)) {
      selectedMarker.setIcon(selectedVenueIcon(selectedVenue));
      selectedMarker.setPopupContent(popupHtml(selectedVenue));
    }
  }
  if (fitToAll && bounds.isValid()) map.fitBounds(bounds, { padding: [36, 36], maxZoom: 15 });
}

onMounted(async () => {
  await nextTick();
  if (!mapContainer.value) return;
  (window as Window & { L?: typeof L }).L = L;
  await import('leaflet-rotate');
  map = L.map(mapContainer.value, { scrollWheelZoom: false, rotate: true, rotateControl: false, touchRotate: false, shiftKeyRotate: false, minZoom: 11, maxBounds: festivalBounds, maxBoundsViscosity: 0.25 });
  L.tileLayer(tiles, { attribution, maxZoom: 19, bounds: festivalBounds, noWrap: true }).addTo(map);
  addRotationControl();
  markers = L.markerClusterGroup({ chunkedLoading: true, maxClusterRadius: 48, showCoverageOnHover: false, iconCreateFunction: clusterIcon });
  map.addLayer(markers);
  map.on('popupopen', (event: any) => attachPopupTapaHandlers(event.popup));
  updateMarkers();
  if (!mappableCount()) map.setView([39.9864, -0.0513], 12);
  startLocationTracking();
  focusSelectedVenue();
});
onUnmounted(() => {
  stopLocationTracking();
  userMarker?.remove();
  clearSelectedMarker();
  if (rotationControl && map) map.removeControl(rotationControl);
  rotationControl = null;
  markers?.clearLayers();
  map?.remove();
  markers = null;
  map = null;
});
watch(() => [props.establishments, props.tapas, props.stats, props.myReviews, props.wantedTapas, props.openNowOnly], () => updateMarkers(false), { deep: true });
watch(language, () => { updateMarkers(false); updateRotationControl(); });
watch(openingHoursNow, () => { updateMarkers(false); if (selectedMarker && props.selectedEstablishmentId) { const venue = props.establishments.find((item) => item.id === props.selectedEstablishmentId); if (venue) selectedMarker.setPopupContent(popupHtml(venue)); } });
watch(() => props.selectedEstablishmentId, () => {
  updateMarkers(false);
  nextTick(focusSelectedVenue);
});
watch(() => props.locationActive, (active) => { if (active) startLocationTracking(); else stopLocationTracking(); });
</script>

<template>
  <section class="mb-4 overflow-hidden border-y border-stone-200 bg-white shadow-sm sm:mb-6 sm:rounded-xl sm:border sm:p-5">
    <div ref="mapContainer" class="h-80 md:h-[28rem]" :aria-label="t('festivalMap')" />
    <p v-if="!mappableCount()" class="px-4 pt-3 text-sm text-stone-600 sm:px-0">{{ t('noCoordinates') }}</p><p v-if="locationUnavailable" class="px-4 pt-3 text-sm text-stone-600 sm:px-0">{{ t('locationUnavailable') }}</p>
  </section>
</template>

<style>
.leaflet-control-zoom { overflow: hidden; border: 2px solid #1c1917 !important; border-radius: .5rem !important; background: #fff; box-shadow: 0 2px 8px rgb(0 0 0 / .35); }
.leaflet-control-zoom a { width: 30px !important; height: 30px !important; border: 0 !important; border-bottom: 1px solid #a8a29e !important; background: #fff !important; color: #1c1917 !important; font-size: 1.35rem !important; font-weight: 800 !important; line-height: 28px !important; }
.leaflet-control-zoom a:last-child { border-bottom: 0 !important; }
.leaflet-control-zoom a:hover, .leaflet-control-zoom a:focus-visible { background: #d1fae5 !important; color: #064e3b !important; outline: 3px solid #10b981; outline-offset: -3px; }
:root[data-theme='dark'] .leaflet-control-zoom { border-color: #e7e5e4 !important; background: #1c1917; box-shadow: 0 2px 10px rgb(0 0 0 / .65); }
:root[data-theme='dark'] .leaflet-control-zoom a { border-bottom-color: #57534e !important; background: #292524 !important; color: #f5f5f4 !important; }
:root[data-theme='dark'] .leaflet-control-zoom a:hover, :root[data-theme='dark'] .leaflet-control-zoom a:focus-visible { background: #14532d !important; color: #ecfdf5 !important; outline-color: #6ee7b7; }
.festival-cluster-wrapper { background: transparent; border: 0; }
.festival-cluster { display: grid; width: 42px; height: 42px; place-items: center; border: 3px solid white; border-radius: 9999px; background: #047857; color: white; box-shadow: 0 2px 8px rgb(0 0 0 / .32); font-size: .9rem; font-weight: 800; }
.festival-cluster--rated { background: #d97706; }
.festival-cluster--hours-faded { opacity: .35; }
.festival-user-location-wrapper { background: transparent; border: 0; }
.festival-user-location { width: 22px; height: 22px; border: 4px solid white; border-radius: 9999px; background: #2563eb; box-shadow: 0 1px 7px rgb(0 0 0 / .4); }
.festival-marker-wrapper { background: transparent; border: 0; }
.festival-marker { position: relative; display: grid; width: 30px; height: 30px; place-items: center; border: 3px solid white; border-radius: 9999px; background: #047857; color: #047857; box-shadow: 0 2px 8px rgb(0 0 0 / .32); font-size: 0; }
.festival-marker--unavailable { background: #1c1917; color: #1c1917; }
.festival-marker--rated { background: #d97706; color: #d97706; }
.festival-marker--partial { background: linear-gradient(90deg, #d97706 0 var(--reviewed-percent), #047857 var(--reviewed-percent) 100%); color: transparent; }
.festival-marker--hours-faded { opacity: .35; }
.festival-marker--selected { background: #7c3aed; color: #7c3aed; box-shadow: 0 0 0 5px rgb(124 58 237 / .35), 0 3px 10px rgb(0 0 0 / .45); transform: scale(1.18); }
.festival-rotation-control { display: flex; overflow: hidden; border: 1px solid rgb(41 37 36 / .25); border-radius: .5rem; background: white; box-shadow: 0 2px 8px rgb(0 0 0 / .22); }
.festival-rotation-control__button { display: grid; width: 2.5rem; height: 2.5rem; place-items: center; border: 0; border-right: 1px solid #d6d3d1; background: white; color: #1c1917; font-size: 1.1rem; font-weight: 800; line-height: 1; cursor: pointer; }
.festival-rotation-control__button:last-child { border-right: 0; }
.festival-rotation-control__button:hover, .festival-rotation-control__button:focus-visible { background: #ecfdf5; color: #047857; outline: none; }
.festival-rotation-control__north--rotated { background: #fef3c7; color: #92400e; box-shadow: inset 0 -3px #d97706; }
.festival-selected-marker-wrapper { background: transparent; border: 0; }
.festival-selected-marker { position: relative; display: grid; width: 42px; height: 42px; place-items: center; border: 4px solid #7c3aed; border-radius: 9999px; background: #047857; color: #047857; box-shadow: 0 0 0 5px rgb(124 58 237 / .35), 0 3px 10px rgb(0 0 0 / .45); font-size: 0; }
.festival-selected-marker--rated { background: #d97706; color: #d97706; }
.festival-selected-marker--partial { background: linear-gradient(90deg, #d97706 0 var(--reviewed-percent), #047857 var(--reviewed-percent) 100%); color: transparent; }
.festival-marker__wanted { position: absolute; top: -10px; right: -9px; color: #facc15; font-size: 1rem; line-height: 1; text-shadow: 0 1px 2px rgb(0 0 0 / .75); }
.festival-map-popup__wanted { color: #d97706; }
.leaflet-popup.festival-map-popup .leaflet-popup-content-wrapper { border-radius: .75rem !important; background: #fff !important; color: #1c1917 !important; box-shadow: 0 10px 28px rgb(0 0 0 / .32) !important; }
.leaflet-popup.festival-map-popup .leaflet-popup-content { width: min(220px, calc(100vw - 96px)) !important; margin: 0 !important; color: #1c1917 !important; }
.leaflet-popup.festival-map-popup .leaflet-popup-tip { background: #fff !important; }
.festival-map-popup-content { padding: .65rem .75rem; background: #fff; color: #1c1917; }
.festival-map-popup-content h3 { margin: 0; color: #1c1917; font-size: .95rem; font-weight: 800; line-height: 1.25; }
.festival-map-popup__hours-status { font-weight: 800; }
.festival-map-popup-content p { margin: .35rem 0 0; color: #57534e; font-size: .78rem; }
.festival-map-popup__tapas { display: grid; gap: .2rem; margin: .45rem 0 0; padding: 0; color: #292524; font-size: .8rem; line-height: 1.25; list-style: none; }
.festival-map-popup__tapas li::before { content: '•'; margin-right: .35rem; color: #047857; }
.festival-map-popup__establishment-link, .festival-map-popup__tapa-link { padding: 0; border: 0; background: transparent; color: inherit; font: inherit; text-align: left; cursor: pointer; }
.festival-map-popup__establishment-link { font-weight: 800; }
.festival-map-popup__establishment-link:hover, .festival-map-popup__establishment-link:focus-visible, .festival-map-popup__tapa-link:hover, .festival-map-popup__tapa-link:focus-visible { color: #047857; text-decoration: underline; outline: none; }
</style>
