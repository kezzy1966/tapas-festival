<script setup lang="ts">
type Festival = any;
type Establishment = any;
type Tapa = any;
type Stats = { tapa_id: string; rating_count: number; average_rating: number | null; good_excellent_percentage: number | null };

const supabase = useSupabaseClient<any>() as any;
const user = useSupabaseUser();
const loading = ref(true);
const ratingBusy = ref<string | null>(null);
const error = ref('');
const ratingError = ref('');
const festival = ref<Festival | null>(null);
const establishments = ref<Establishment[]>([]);
const tapas = ref<Tapa[]>([]);
const stats = ref<Record<string, Stats>>({});
const myReviews = ref<Record<string, { id: string; rating: number }>>({});

const db = () => supabase.schema('festival');
const tapasFor = (establishmentId: string) => tapas.value.filter((tapa) => tapa.establishment_id === establishmentId);
const priceFor = (tapa: Tapa) => tapa.price_override ?? festival.value?.default_tapa_price;
const text = (english?: string | null, spanish?: string | null) => english || spanish || '';
const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const globalMean = computed(() => {
  const all = Object.values(stats.value);
  const count = all.reduce((sum, item) => sum + Number(item.rating_count || 0), 0);
  return count ? all.reduce((sum, item) => sum + Number(item.average_rating || 0) * Number(item.rating_count || 0), 0) / count : 3;
});
const rankedTapas = computed(() => [...tapas.value]
  .filter((tapa) => tapa.participation_status === 'active')
  .sort((a, b) => credibilityScore(b) - credibilityScore(a) || Number(stats.value[b.id]?.rating_count || 0) - Number(stats.value[a.id]?.rating_count || 0) || text(a.name_en, a.name_es).localeCompare(text(b.name_en, b.name_es))));

function credibilityScore(tapa: Tapa) {
  const item = stats.value[tapa.id];
  const count = Number(item?.rating_count || 0);
  const average = Number(item?.average_rating ?? globalMean.value);
  const priorWeight = 5;
  return (count * average + priorWeight * globalMean.value) / (count + priorWeight);
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
function summaryFor(tapaId: string) { return stats.value[tapaId] || { rating_count: 0, average_rating: null, good_excellent_percentage: null }; }

async function loadStats() {
  if (!festival.value) return;
  const { data, error: statsError } = await db().from('tapa_rating_stats').select('*').eq('festival_id', festival.value.id);
  if (statsError) { error.value = statsError.message; return; }
  stats.value = Object.fromEntries((data || []).map((item: Stats) => [item.tapa_id, item]));
}
async function loadMyReviews() {
  myReviews.value = {};
  if (!user.value || !tapas.value.length) return;
  const { data, error: reviewError } = await db().from('reviews').select('id,tapa_id,rating').in('tapa_id', tapas.value.map((tapa) => tapa.id)).eq('user_id', user.value.id);
  if (reviewError) { ratingError.value = reviewError.message; return; }
  myReviews.value = Object.fromEntries((data || []).map((review: any) => [review.tapa_id, review]));
}
async function loadFestival() {
  loading.value = true; error.value = '';
  const { data: festivals, error: festivalError } = await db().from('festivals').select('*').eq('publication_status', 'published').order('start_date', { ascending: false }).limit(1);
  if (festivalError) { error.value = festivalError.message; loading.value = false; return; }
  festival.value = festivals?.[0] ?? null;
  if (!festival.value) { loading.value = false; return; }
  const { data: venueRows, error: venueError } = await db().from('establishments').select('*').eq('festival_id', festival.value.id).order('sort_order').order('name');
  if (venueError) { error.value = venueError.message; loading.value = false; return; }
  establishments.value = venueRows || [];
  const ids = establishments.value.map((venue) => venue.id);
  if (ids.length) {
    const { data: tapaRows, error: tapaError } = await db().from('tapas').select('*').in('establishment_id', ids).order('sort_order').order('festival_number');
    if (tapaError) error.value = tapaError.message; else tapas.value = tapaRows || [];
  }
  await Promise.all([loadStats(), loadMyReviews()]);
  loading.value = false;
}
async function rate(tapa: Tapa, rating: number) {
  if (!user.value) { ratingError.value = 'Sign in at /admin to rate this tapa.'; return; }
  ratingBusy.value = tapa.id; ratingError.value = '';
  const existing = myReviews.value[tapa.id];
  const result = existing
    ? await db().from('reviews').update({ rating }).eq('id', existing.id)
    : await db().from('reviews').insert({ tapa_id: tapa.id, user_id: user.value.id, rating });
  ratingBusy.value = null;
  if (result.error) { ratingError.value = result.error.message; return; }
  await Promise.all([loadStats(), loadMyReviews()]);
}
async function removeRating(tapa: Tapa) {
  const existing = myReviews.value[tapa.id];
  if (!existing) return;
  ratingBusy.value = tapa.id; ratingError.value = '';
  const { error: deleteError } = await db().from('reviews').delete().eq('id', existing.id);
  ratingBusy.value = null;
  if (deleteError) { ratingError.value = deleteError.message; return; }
  await Promise.all([loadStats(), loadMyReviews()]);
}

watch(user, loadMyReviews);
onMounted(loadFestival);
</script>

<template>
  <main id="main-content" class="min-h-screen bg-stone-50 text-stone-900" tabindex="-1">
    <header class="border-b border-stone-200 bg-white"><div class="mx-auto max-w-6xl px-5 py-8 md:px-8"><p class="text-sm font-semibold uppercase tracking-widest text-emerald-700">tapas-festival</p><h1 class="mt-2 font-display text-4xl font-bold">{{ festival ? text(festival.name_en, festival.name_es) : 'Tapas festival' }}</h1><p v-if="festival && text(festival.description_en, festival.description_es)" class="mt-3 max-w-3xl text-stone-600">{{ text(festival.description_en, festival.description_es) }}</p></div></header>
    <section class="mx-auto max-w-6xl px-5 py-8 md:px-8"><p v-if="loading" class="text-stone-600">Loading festival…</p><p v-else-if="error" class="rounded-lg border border-red-200 bg-red-50 p-4 text-red-800">Unable to load festival data: {{ error }}</p><p v-else-if="!festival" class="rounded-lg border border-stone-200 bg-white p-5 text-stone-600">No published festival is available yet.</p>
      <template v-else><div class="mb-6 flex flex-wrap gap-4 text-sm text-stone-600"><span>{{ festival.city }}</span><span>{{ festival.start_date }} – {{ festival.end_date }}</span><span>Standard tapa price: {{ festival.currency_code }} {{ festival.default_tapa_price }}</span></div>
        <section class="mb-8 rounded-xl border border-stone-200 bg-white p-5"><h2 class="font-display text-2xl font-bold">Live tapa ranking</h2><p class="mt-1 text-sm text-stone-600">Ranking blends each average with the festival-wide average using a five-rating baseline, so one vote does not dominate.</p><ol class="mt-4 grid gap-2 md:grid-cols-2"><li v-for="(tapa, index) in rankedTapas" :key="tapa.id" class="flex items-center justify-between rounded-lg bg-stone-50 px-3 py-2 text-sm"><span><strong>{{ index + 1 }}.</strong> {{ text(tapa.name_en, tapa.name_es) }}</span><span>{{ summaryFor(tapa.id).average_rating?.toFixed(1) ?? '—' }} ★ · {{ summaryFor(tapa.id).rating_count }} ratings</span></li></ol></section>
        <p v-if="ratingError" class="mb-4 rounded border border-red-200 bg-red-50 p-3 text-sm text-red-800">{{ ratingError }}</p>
        <div class="space-y-6"><article v-for="venue in establishments" :key="venue.id" class="rounded-xl border border-stone-200 bg-white p-5 shadow-sm"><div class="flex flex-wrap items-start justify-between gap-3"><div><h2 class="font-display text-2xl font-bold">{{ venue.name }}</h2><p v-if="venue.participation_status === 'withdrawn'" class="mt-1 text-sm font-semibold text-red-700">Withdrawn</p><p v-else-if="venue.closure_status !== 'normal'" class="mt-1 text-sm font-semibold text-stone-600">{{ venue.closure_status.replaceAll('_', ' ') }}</p></div><span class="rounded-full bg-stone-100 px-3 py-1 text-xs font-semibold">{{ tapasFor(venue.id).length }} tapas</span></div><p v-if="text(venue.description_en, venue.description_es)" class="mt-3 text-stone-700">{{ text(venue.description_en, venue.description_es) }}</p><div class="mt-4 grid gap-2 text-sm text-stone-600"><p v-if="venue.address">{{ venue.address }}</p><p v-if="text(venue.hours_notes_en, venue.hours_notes_es)"><strong>Opening hours:</strong> {{ text(venue.hours_notes_en, venue.hours_notes_es) }}</p><p v-else-if="formatHours(venue.opening_hours)"><strong>Opening hours:</strong> {{ formatHours(venue.opening_hours) }}</p><p v-if="venue.phone"><strong>Phone:</strong> {{ venue.phone }}</p><p v-if="venue.whatsapp"><strong>WhatsApp:</strong> {{ venue.whatsapp }}</p><p v-if="venue.website_url"><a class="text-emerald-700 underline" :href="venue.website_url" target="_blank" rel="noopener">Website</a></p><p v-if="venue.facebook_url"><a class="text-emerald-700 underline" :href="venue.facebook_url" target="_blank" rel="noopener">Facebook</a></p></div><div class="mt-5 grid gap-3 md:grid-cols-2"><section v-for="tapa in tapasFor(venue.id)" :key="tapa.id" class="rounded-lg bg-stone-50 p-4"><div class="flex justify-between gap-3"><h3 class="font-bold">{{ tapa.festival_number ? `${tapa.festival_number}. ` : '' }}{{ text(tapa.name_en, tapa.name_es) }}</h3><span class="whitespace-nowrap font-semibold">{{ festival.currency_code }} {{ priceFor(tapa) }}</span></div><p v-if="tapa.participation_status === 'withdrawn'" class="mt-1 text-sm font-semibold text-red-700">Withdrawn</p><p v-if="text(tapa.description_en, tapa.description_es)" class="mt-2 text-sm text-stone-600">{{ text(tapa.description_en, tapa.description_es) }}</p><div class="mt-4 border-t border-stone-200 pt-4 text-sm"><p class="text-stone-700"><strong>Public rating: {{ summaryFor(tapa.id).average_rating?.toFixed(1) ?? 'Unrated' }} ★</strong> · {{ summaryFor(tapa.id).rating_count }} ratings<span v-if="summaryFor(tapa.id).good_excellent_percentage != null"> · {{ Number(summaryFor(tapa.id).good_excellent_percentage).toFixed(0) }}% good/excellent</span></p><template v-if="tapa.participation_status === 'active'"><div class="mt-4 rounded-lg border-2 border-emerald-200 bg-white p-3"><p class="font-bold text-emerald-950">Rate this tapa</p><p v-if="!user" class="mt-1 text-stone-600">Choose 1–5 stars, then <NuxtLink class="font-semibold text-emerald-700 underline" to="/admin">sign in to submit your rating</NuxtLink>.</p><template v-else><p class="mt-1 text-stone-600"><strong>Your rating:</strong> {{ myReviews[tapa.id] ? `${myReviews[tapa.id].rating} out of 5 stars` : 'Not rated yet' }}</p><div class="mt-3 flex flex-wrap gap-2" role="group" :aria-label="`Rate ${text(tapa.name_en, tapa.name_es)}`"><button v-for="star in 5" :key="star" type="button" class="flex min-h-12 min-w-12 flex-col items-center justify-center rounded-lg border-2 px-2 font-bold transition hover:scale-105 hover:border-amber-400 hover:bg-amber-50 focus-visible:ring-2 focus-visible:ring-emerald-700 disabled:opacity-50" :class="(myReviews[tapa.id]?.rating || 0) >= star ? 'border-amber-400 bg-amber-100 text-amber-700' : 'border-stone-300 bg-white text-stone-500'" :aria-pressed="myReviews[tapa.id]?.rating === star" :disabled="ratingBusy === tapa.id" @click="rate(tapa, star)"><span class="text-xl leading-none">★</span><span class="mt-1 text-xs">{{ star }}</span><span class="sr-only">{{ star }} star{{ star === 1 ? '' : 's' }}</span></button></div><button v-if="myReviews[tapa.id]" type="button" class="mt-3 rounded border border-red-300 px-3 py-2 text-xs font-semibold text-red-700 hover:bg-red-50" :disabled="ratingBusy === tapa.id" @click="removeRating(tapa)">Remove my rating</button></template></div></template></div></section></div></article></div>
      </template>
    </section>
  </main>
</template>
