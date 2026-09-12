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
}>();

const mapContainer = ref<HTMLElement | null>(null);
let map: L.Map | null = null;
let markers: L.MarkerClusterGroup | null = null;

const tiles = 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png';
const attribution = '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors';
const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

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
  return english || spanish || '';
}
function formatHours(hours: unknown) {
  if (!hours || typeof hours !== 'object' || Array.isArray(hours)) return '';
  return Object.entries(hours as Record<string, unknown>).map(([day, periods]) => {
    const label = weekdays[Number(day) - 1] || day;
    if (!Array.isArray(periods) || periods.length === 0) return `${label}: closed`;
    const times = periods.map((period: any) => Array.isArray(period) ? `${period[0]}–${period[1]}` : '').filter(Boolean).join(', ');
    return times ? `${label}: ${times}` : '';
  }).filter(Boolean).join(' · ');
}
function venueTapas(venueId: string) {
  return props.tapas.filter((tapa) => tapa.establishment_id === venueId && tapa.publication_status === 'published');
}
function ratingText(tapa: Tapa) {
  const rating = props.stats[tapa.id];
  if (!rating || !Number(rating.rating_count)) return 'Unrated';
  return `${Number(rating.average_rating).toFixed(1)} ★ (${rating.rating_count})`;
}
function statusText(venue: Establishment) {
  if (venue.participation_status === 'withdrawn') return 'Withdrawn';
  if (venue.closure_status && venue.closure_status !== 'normal') return String(venue.closure_status).replaceAll('_', ' ');
  return '';
}
function popupHtml(venue: Establishment) {
  const hours = text(venue.hours_notes_en, venue.hours_notes_es) || formatHours(venue.opening_hours);
  const status = statusText(venue);
  const tapas = venueTapas(venue.id);
  const tapaList = tapas.length
    ? `<ul class="festival-map-popup__tapas">${tapas.map((tapa) => `<li><strong>${escapeHtml(tapa.festival_number ? `${tapa.festival_number}. ` : '')}${escapeHtml(text(tapa.name_en, tapa.name_es))}</strong>${tapa.participation_status === 'withdrawn' ? ' <em>Withdrawn</em>' : ''}<br><span>${escapeHtml(ratingText(tapa))}</span></li>`).join('')}</ul>`
    : '<p>No published tapas.</p>';
  return `<div class="festival-map-popup"><h3>${escapeHtml(venue.name)}</h3>${status ? `<p class="festival-map-popup__status">${escapeHtml(status)}</p>` : ''}${venue.address ? `<p>${escapeHtml(venue.address)}</p>` : ''}${hours ? `<p><strong>Opening hours:</strong> ${escapeHtml(hours)}</p>` : ''}<h4>Tapas</h4>${tapaList}</div>`;
}
function markerIcon(venue: Establishment) {
  const unavailable = venue.participation_status === 'withdrawn' || (venue.closure_status && venue.closure_status !== 'normal');
  return L.divIcon({
    className: 'festival-marker-wrapper',
    html: `<div class="festival-marker${unavailable ? ' festival-marker--unavailable' : ''}">●</div>`,
    iconSize: [30, 30],
    iconAnchor: [15, 15],
    popupAnchor: [0, -15],
  });
}
function updateMarkers() {
  if (!map || !markers) return;
  markers.clearLayers();
  const bounds = L.latLngBounds([]);
  props.establishments.filter(hasCoordinates).forEach((venue) => {
    const position: L.LatLngExpression = [Number(venue.latitude), Number(venue.longitude)];
    bounds.extend(position);
    markers!.addLayer(L.marker(position, { icon: markerIcon(venue), title: venue.name }).bindPopup(popupHtml(venue), { maxWidth: 330 }));
  });
  if (bounds.isValid()) map.fitBounds(bounds, { padding: [36, 36], maxZoom: 15 });
}

onMounted(async () => {
  await nextTick();
  if (!mapContainer.value) return;
  map = L.map(mapContainer.value, { scrollWheelZoom: false });
  L.tileLayer(tiles, { attribution, maxZoom: 19 }).addTo(map);
  markers = L.markerClusterGroup({ chunkedLoading: true, maxClusterRadius: 48, showCoverageOnHover: false });
  map.addLayer(markers);
  updateMarkers();
  if (!mappableCount()) map.setView([39.9864, -0.0513], 12);
});
onUnmounted(() => {
  markers?.clearLayers();
  map?.remove();
  markers = null;
  map = null;
});
watch(() => [props.establishments, props.tapas, props.stats], updateMarkers, { deep: true });
</script>

<template>
  <section class="mb-8 rounded-xl border border-stone-200 bg-white p-5 shadow-sm">
    <div class="flex flex-wrap items-baseline justify-between gap-2">
      <div><h2 class="font-display text-2xl font-bold">Festival map</h2><p class="mt-1 text-sm text-stone-600">Select a marker to see the establishment, its tapas and current ratings.</p></div>
      <span class="text-sm text-stone-600">{{ mappableCount() }} mapped</span>
    </div>
    <div ref="mapContainer" class="mt-4 h-80 overflow-hidden rounded-lg border border-stone-200 md:h-[28rem]" aria-label="Festival establishment map" />
    <p v-if="!mappableCount()" class="mt-3 text-sm text-stone-600">No establishment coordinates are available yet. All establishments remain in the list below.</p>
    <p class="mt-3 text-xs text-stone-500"><span class="font-semibold text-emerald-700">●</span> Participating · <span class="font-semibold text-stone-900">●</span> Closed or withdrawn</p>
  </section>
</template>

<style>
.festival-marker-wrapper { background: transparent; border: 0; }
.festival-marker { display: grid; width: 30px; height: 30px; place-items: center; border: 3px solid white; border-radius: 9999px; background: #047857; color: #047857; box-shadow: 0 2px 8px rgb(0 0 0 / .32); font-size: 0; }
.festival-marker--unavailable { background: #1c1917; color: #1c1917; }
.festival-map-popup h3 { margin: 0; font-size: 1rem; font-weight: 700; }
.festival-map-popup h4 { margin: .75rem 0 .25rem; font-weight: 700; }
.festival-map-popup p { margin: .4rem 0; font-size: .82rem; }
.festival-map-popup__status { color: #b91c1c; font-weight: 700; text-transform: capitalize; }
.festival-map-popup__tapas { margin: 0; padding-left: 1.1rem; font-size: .82rem; }
.festival-map-popup__tapas li { margin: .35rem 0; }
.festival-map-popup__tapas em { color: #b91c1c; font-style: normal; font-weight: 700; }
.festival-map-popup__tapas span { color: #57534e; }
</style>
