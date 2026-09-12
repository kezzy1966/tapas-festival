<script setup lang="ts">
import { nextTick, onMounted, onUnmounted, ref, watch } from 'vue';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import 'leaflet.markercluster';

type RatingStat = { tapa_id: string; rating_count: number; average_rating: number | null };
type Establishment = Record<string, any>;
type Tapa = Record<string, any>;

const props = defineProps<{
  establishments: Establishment[];
  tapas: Tapa[];
  stats: Record<string, RatingStat>;
  myReviews: Record<string, { id: string; rating: number }>;
  locationActive: boolean;
  selectedEstablishmentId: string | null;
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
const { language, t, localized } = useFestivalLanguage();
const weekdays = computed(() => language.value === 'es' ? ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'] : ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']);

const mappableCount = () => props.establishments.filter(hasCoordinates).length;

function hasCoordinates(venue: Establishment) {
  return Number.isFinite(Number(venue.latitude)) && Number.isFinite(Number(venue.longitude));
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
  return `${Number(rating.average_rating).toFixed(1)} ★ (${rating.rating_count})`;
}
function statusText(venue: Establishment) {
  if (venue.participation_status === 'withdrawn') return t('withdrawn');
  if (venue.closure_status && venue.closure_status !== 'normal') return t('closed');
  return '';
}
function popupHtml(venue: Establishment) {
  const hours = text(venue.hours_notes_en, venue.hours_notes_es) ? text(venue.hours_notes_en, venue.hours_notes_es).split(/\r?\n/).map((times) => ({ day: '', times })) : openingHourRows(venue.opening_hours);
  const status = statusText(venue);
  const tapas = venueTapas(venue.id);
  const tapaList = tapas.length
    ? `<ul class="festival-map-popup__tapas">${tapas.map((tapa) => `<li><strong>${escapeHtml(tapa.festival_number ? `${tapa.festival_number}. ` : '')}${escapeHtml(text(tapa.name_en, tapa.name_es))}</strong>${tapa.participation_status === 'withdrawn' ? ` <em>${escapeHtml(t('withdrawn'))}</em>` : ''}<br><span>${escapeHtml(ratingText(tapa))}</span></li>`).join('')}</ul>`
    : `<p>${escapeHtml(t('noPublishedTapas'))}</p>`;
  return `<div class="festival-map-popup-content"><h3>${escapeHtml(venue.name)}</h3>${status ? `<p class="festival-map-popup__status">${escapeHtml(status)}</p>` : ''}${venue.address ? `<p>${escapeHtml(venue.address)}</p>` : ''}${hours.length ? `<div class="festival-map-popup__hours"><strong>${escapeHtml(t('openingHours'))}</strong>${hours.map((row) => `<div class="festival-map-popup__hours-row"><span>${escapeHtml(row.day)}</span><span>${escapeHtml(row.times)}</span></div>`).join('')}</div>` : ''}<h4>${escapeHtml(t('tapas'))}</h4>${tapaList}</div>`;
}
function venueHasRatedTapa(venueId: string) {
  return props.tapas.some((tapa) => tapa.establishment_id === venueId && Boolean(props.myReviews[tapa.id]));
}
function clusterIcon(cluster: L.MarkerCluster) {
  const containsRatedVenue = cluster.getAllChildMarkers().some((marker) => {
    const venueId = (marker.options as any).festivalVenueId as string | undefined;
    return Boolean(venueId && venueHasRatedTapa(venueId));
  });
  return L.divIcon({
    className: 'festival-cluster-wrapper',
    html: `<div class="festival-cluster${containsRatedVenue ? ' festival-cluster--rated' : ''}">${cluster.getChildCount()}</div>`,
    iconSize: [42, 42],
    iconAnchor: [21, 21],
  });
}
function markerIcon(venue: Establishment) {
  const unavailable = venue.participation_status === 'withdrawn' || (venue.closure_status && venue.closure_status !== 'normal');
  const rated = venueHasRatedTapa(venue.id);
  const selected = props.selectedEstablishmentId === venue.id;
  return L.divIcon({
    className: 'festival-marker-wrapper',
    html: `<div class="festival-marker${unavailable ? ' festival-marker--unavailable' : ''}${rated ? ' festival-marker--rated' : ''}${selected ? ' festival-marker--selected' : ''}">●</div>`,
    iconSize: [30, 30],
    iconAnchor: [15, 15],
    popupAnchor: [0, -15],
  });
}
const userLocationIcon = L.divIcon({ className: 'festival-user-location-wrapper', html: '<div class="festival-user-location"></div>', iconSize: [22, 22], iconAnchor: [11, 11] });
const selectedVenueIcon = L.divIcon({ className: 'festival-selected-marker-wrapper', html: '<div class="festival-selected-marker">●</div>', iconSize: [42, 42], iconAnchor: [21, 21], popupAnchor: [0, -21] });
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
  selectedMarker = L.marker(point, { icon: selectedVenueIcon, title: venue.name, zIndexOffset: 1000 })
    .addTo(map)
    .bindPopup(popupHtml(venue), { className: 'festival-map-popup', maxWidth: 320 });
  if (userMarker) {
    map.fitBounds(L.latLngBounds([point, userMarker.getLatLng()]), { padding: [56, 56], maxZoom: 15 });
  } else {
    map.setView(point, Math.max(map.getZoom(), 15));
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
    options: { position: 'topright' },
    onAdd() {
      const container = L.DomUtil.create('div', 'leaflet-bar festival-rotation-control');
      const addButton = (label: string, handler: () => void) => {
        const button = L.DomUtil.create('button', 'festival-rotation-control__button', container) as HTMLButtonElement;
        button.type = 'button';
        button.textContent = label;
        L.DomEvent.on(button, 'click', (event) => { L.DomEvent.stop(event); handler(); });
        return button;
      };
      rotationLeftButton = addButton('↶', () => setBearing(bearing.value - 10));
      rotationNorthButton = addButton('N', () => setBearing(0));
      rotationRightButton = addButton('↷', () => setBearing(bearing.value + 10));
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
    } else if (!locationHasCentered) { map!.setView(point, Math.max(map!.getZoom(), 15)); locationHasCentered = true; }
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
    markers!.addLayer(marker.bindPopup(popupHtml(venue), { className: 'festival-map-popup', maxWidth: 320 }));
  });
  if (fitToAll && bounds.isValid()) map.fitBounds(bounds, { padding: [36, 36], maxZoom: 15 });
}

onMounted(async () => {
  await nextTick();
  if (!mapContainer.value) return;
  (window as Window & { L?: typeof L }).L = L;
  await import('leaflet-rotate');
  map = L.map(mapContainer.value, { scrollWheelZoom: false, rotate: true, rotateControl: false, touchRotate: false, shiftKeyRotate: false });
  L.tileLayer(tiles, { attribution, maxZoom: 19 }).addTo(map);
  addRotationControl();
  markers = L.markerClusterGroup({ chunkedLoading: true, maxClusterRadius: 48, showCoverageOnHover: false, iconCreateFunction: clusterIcon });
  map.addLayer(markers);
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
watch(() => [props.establishments, props.tapas, props.stats, props.myReviews], () => updateMarkers(), { deep: true });
watch(language, () => { updateMarkers(); updateRotationControl(); });
watch(() => props.selectedEstablishmentId, () => {
  updateMarkers(false);
  nextTick(focusSelectedVenue);
});
watch(() => props.locationActive, (active) => { if (active) startLocationTracking(); else stopLocationTracking(); });
</script>

<template>
  <section class="mb-8 rounded-xl border border-stone-200 bg-white p-5 shadow-sm">
    <div class="flex flex-wrap items-baseline justify-between gap-2">
      <div><h2 class="font-display text-2xl font-bold">{{ t('festivalMap') }}</h2><p class="mt-1 text-sm text-stone-600">{{ t('selectMarker') }}</p></div>
      <span class="text-sm text-stone-600">{{ mappableCount() }} {{ t('mapped') }}</span>
    </div>
    <div ref="mapContainer" class="mt-4 h-80 overflow-hidden rounded-lg border border-stone-200 md:h-[28rem]" :aria-label="t('festivalMap')" />
    <p v-if="!mappableCount()" class="mt-3 text-sm text-stone-600">{{ t('noCoordinates') }}</p><p v-if="locationUnavailable" class="mt-3 text-sm text-stone-600">{{ t('locationUnavailable') }}</p>
    <p class="mt-3 text-xs text-stone-500"><span class="font-semibold text-emerald-700">●</span> {{ t('participating') }} · <span class="font-semibold text-stone-900">●</span> {{ t('closedOrWithdrawn') }}</p>
  </section>
</template>

<style>
.festival-cluster-wrapper { background: transparent; border: 0; }
.festival-cluster { display: grid; width: 42px; height: 42px; place-items: center; border: 3px solid white; border-radius: 9999px; background: #047857; color: white; box-shadow: 0 2px 8px rgb(0 0 0 / .32); font-size: .9rem; font-weight: 800; }
.festival-cluster--rated { background: #d97706; }
.festival-user-location-wrapper { background: transparent; border: 0; }
.festival-user-location { width: 22px; height: 22px; border: 4px solid white; border-radius: 9999px; background: #2563eb; box-shadow: 0 1px 7px rgb(0 0 0 / .4); }
.festival-marker-wrapper { background: transparent; border: 0; }
.festival-marker { display: grid; width: 30px; height: 30px; place-items: center; border: 3px solid white; border-radius: 9999px; background: #047857; color: #047857; box-shadow: 0 2px 8px rgb(0 0 0 / .32); font-size: 0; }
.festival-marker--unavailable { background: #1c1917; color: #1c1917; }
.festival-marker--rated { background: #d97706; color: #d97706; }
.festival-marker--selected { background: #7c3aed; color: #7c3aed; box-shadow: 0 0 0 5px rgb(124 58 237 / .35), 0 3px 10px rgb(0 0 0 / .45); transform: scale(1.18); }
.festival-rotation-control { display: flex; overflow: hidden; border: 1px solid rgb(41 37 36 / .25); border-radius: .5rem; background: white; box-shadow: 0 2px 8px rgb(0 0 0 / .22); }
.festival-rotation-control__button { display: grid; width: 2.5rem; height: 2.5rem; place-items: center; border: 0; border-right: 1px solid #d6d3d1; background: white; color: #1c1917; font-size: 1.1rem; font-weight: 800; line-height: 1; cursor: pointer; }
.festival-rotation-control__button:last-child { border-right: 0; }
.festival-rotation-control__button:hover, .festival-rotation-control__button:focus-visible { background: #ecfdf5; color: #047857; outline: none; }
.festival-rotation-control__north--rotated { background: #fef3c7; color: #92400e; box-shadow: inset 0 -3px #d97706; }
.festival-selected-marker-wrapper { background: transparent; border: 0; }
.festival-selected-marker { display: grid; width: 42px; height: 42px; place-items: center; border: 4px solid white; border-radius: 9999px; background: #7c3aed; color: #7c3aed; box-shadow: 0 0 0 5px rgb(124 58 237 / .35), 0 3px 10px rgb(0 0 0 / .45); font-size: 0; }
.leaflet-popup.festival-map-popup .leaflet-popup-content-wrapper { border-radius: .75rem !important; background: #fff !important; color: #1c1917 !important; box-shadow: 0 10px 28px rgb(0 0 0 / .32) !important; }
.leaflet-popup.festival-map-popup .leaflet-popup-content { width: min(280px, calc(100vw - 96px)) !important; margin: 0 !important; color: #1c1917 !important; }
.leaflet-popup.festival-map-popup .leaflet-popup-tip { background: #fff !important; }
.festival-map-popup-content { padding: .9rem 1rem; background: #fff; color: #1c1917; }
.festival-map-popup-content h3 { margin: 0; color: #1c1917; font-size: 1.1rem; font-weight: 800; line-height: 1.25; }
.festival-map-popup-content h4 { margin: .75rem 0 .25rem; color: #1c1917; font-weight: 700; }
.festival-map-popup-content p { margin: .4rem 0; color: #292524; font-size: .82rem; }
.festival-map-popup__hours { margin: .5rem 0; color: #292524; font-size: .82rem; }
.festival-map-popup__hours-row { display: grid; grid-template-columns: 4.5rem minmax(0, 1fr); gap: .35rem; margin-top: .2rem; }
.festival-map-popup__hours-row span:first-child { font-weight: 600; }
.festival-map-popup__status { color: #b91c1c; font-weight: 700; text-transform: capitalize; }
.festival-map-popup__tapas { margin: 0; padding-left: 1.1rem; font-size: .82rem; }
.festival-map-popup__tapas li { margin: .35rem 0; }
.festival-map-popup__tapas em { color: #b91c1c; font-style: normal; font-weight: 700; }
.festival-map-popup__tapas span { color: #57534e; }
</style>
