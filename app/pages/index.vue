<script setup lang="ts">
type Festival = any;
type Establishment = any;
type Tapa = any;
type Stats = { tapa_id: string; rating_count: number; average_rating: number | null; good_excellent_percentage: number | null };
type MobileView = 'map' | 'rankings' | 'tapas';

const supabase = useSupabaseClient<any>() as any;
const user = useSupabaseUser();
const currentUserId = computed(() => typeof user.value?.sub === 'string' ? user.value.sub : null);
const { language, setLanguage, t, localized } = useFestivalLanguage();
const loading = ref(true);
const ratingBusy = ref<string | null>(null);
const error = ref('');
const ratingError = ref('');
const festival = ref<Festival | null>(null);
const establishments = ref<Establishment[]>([]);
const tapas = ref<Tapa[]>([]);
const stats = ref<Record<string, Stats>>({});
type MyReview = { id: string; rating: number; review_text: string | null };
type PublicReview = { id: string; tapa_id: string; rating: number; review_text: string; created_at: string };
const myReviews = ref<Record<string, MyReview>>({});
const publicReviews = ref<Record<string, PublicReview[]>>({});
const reviewDrafts = ref<Record<string, string>>({});
const reviewsExpanded = ref<Record<string, boolean>>({});
const reviewNotice = ref('');
const expandedEstablishments = ref<Record<string, boolean>>({});
const mobileView = ref<MobileView>('map');

const db = () => supabase.schema('festival');
const valueOrNull = (value: string) => value.trim() || null;
const tapasFor = (establishmentId: string) => tapas.value.filter((tapa) => tapa.establishment_id === establishmentId);
const establishmentNameFor = (tapa: Tapa) => establishments.value.find((venue) => venue.id === tapa.establishment_id)?.name || '';
const tapaPhotoUrl = (tapa: Tapa) => tapa.photo_path ? supabase.storage.from('festival-images').getPublicUrl(tapa.photo_path).data.publicUrl : '';
const priceFor = (tapa: Tapa) => tapa.price_override ?? festival.value?.default_tapa_price;
const text = (english?: string | null, spanish?: string | null) => localized(english, spanish);
const weekdays = computed(() => language.value === 'es' ? ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'] : ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']);
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
function openingHourRows(hours: unknown) {
  if (!hours || typeof hours !== 'object' || Array.isArray(hours)) return [];
  return Object.entries(hours as Record<string, unknown>).map(([day, periods]) => {
    const label = weekdays.value[Number(day) - 1] || day;
    if (!Array.isArray(periods) || periods.length === 0) return { day: label, times: t('closed') };
    const times = periods.map((period: any) => Array.isArray(period) ? `${period[0]}–${period[1]}` : '').filter(Boolean).join(', ');
    return times ? { day: label, times } : null;
  }).filter(Boolean) as { day: string; times: string }[];
}
function toggleEstablishment(id: string) { expandedEstablishments.value[id] = !expandedEstablishments.value[id]; }

function summaryFor(tapaId: string) { return stats.value[tapaId] || { rating_count: 0, average_rating: null, good_excellent_percentage: null }; }
function closureLabel(status: string | null | undefined) {
  return status && status !== 'normal' ? t('closed') : '';
}

async function loadStats() {
  if (!festival.value) return;
  const { data, error: statsError } = await db().from('tapa_rating_stats').select('*').eq('festival_id', festival.value.id);
  if (statsError) { error.value = statsError.message; return; }
  stats.value = Object.fromEntries((data || []).map((item: Stats) => [item.tapa_id, item]));
}
async function loadMyReviews() {
  myReviews.value = {}; reviewDrafts.value = {};
  if (!currentUserId.value || !tapas.value.length) return;
  const { data, error: reviewError } = await db().from('reviews').select('id,tapa_id,rating,review_text').in('tapa_id', tapas.value.map((tapa) => tapa.id)).eq('user_id', currentUserId.value);
  if (reviewError) { ratingError.value = reviewError.message; return; }
  myReviews.value = Object.fromEntries((data || []).map((review: MyReview & { tapa_id: string }) => [review.tapa_id, review]));
  reviewDrafts.value = Object.fromEntries((data || []).map((review: MyReview & { tapa_id: string }) => [review.tapa_id, review.review_text || '']));
}
async function loadPublicReviews() {
  publicReviews.value = {};
  if (!tapas.value.length) return;
  const { data, error: reviewError } = await db().from('reviews').select('id,tapa_id,rating,review_text,created_at').in('tapa_id', tapas.value.map((tapa) => tapa.id)).eq('moderation_status', 'visible').not('review_text', 'is', null).order('created_at', { ascending: false });
  if (reviewError) { error.value = reviewError.message; return; }
  const visible = (data || []).filter((review: PublicReview) => review.review_text?.trim());
  publicReviews.value = visible.reduce((grouped: Record<string, PublicReview[]>, review: PublicReview) => {
    (grouped[review.tapa_id] ||= []).push(review); return grouped;
  }, {});
}
function reviewsFor(tapaId: string) { return publicReviews.value[tapaId] || []; }
function shownReviewsFor(tapaId: string) { const items = reviewsFor(tapaId); return reviewsExpanded.value[tapaId] ? items : items.slice(0, 3); }
function highlightedReviewFor(tapaId: string) { return reviewsFor(tapaId).find((review) => review.rating === 5); }
function formatReviewDate(value: string) { return new Intl.DateTimeFormat(language.value === 'es' ? 'es-ES' : 'en-GB', { day: 'numeric', month: 'short', year: 'numeric' }).format(new Date(value)); }

function calendarDate(timezone: string) {
  const parts = new Intl.DateTimeFormat('en-CA', { timeZone: timezone, year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts();
  const value = (type: string) => parts.find((part) => part.type === type)?.value;
  return `${value('year')}-${value('month')}-${value('day')}`;
}
async function loadFestival() {
  loading.value = true; error.value = '';
  const { data: festivals, error: festivalError } = await db().from('festivals').select('*').eq('publication_status', 'published').order('start_date', { ascending: false });
  if (festivalError) { error.value = festivalError.message; loading.value = false; return; }
  const published = festivals || [];
  const active = published.filter((item) => {
    const today = calendarDate(item.timezone || 'Europe/Madrid');
    return item.start_date <= today && item.end_date >= today;
  });
  festival.value = (active.length ? active : published)[0] ?? null;
  if (!festival.value) { loading.value = false; return; }
  const { data: venueRows, error: venueError } = await db().from('establishments').select('*').eq('festival_id', festival.value.id).order('sort_order').order('name');
  if (venueError) { error.value = venueError.message; loading.value = false; return; }
  establishments.value = venueRows || [];
  const ids = establishments.value.map((venue) => venue.id);
  if (ids.length) {
    const { data: tapaRows, error: tapaError } = await db().from('tapas').select('*').in('establishment_id', ids).order('sort_order').order('festival_number');
    if (tapaError) error.value = tapaError.message; else tapas.value = tapaRows || [];
  }
  await Promise.all([loadStats(), loadMyReviews(), loadPublicReviews()]);
  loading.value = false;
}
async function rate(tapa: Tapa, rating: number) {
  if (!currentUserId.value) { ratingError.value = t('signInAtAdmin'); return; }
  ratingBusy.value = tapa.id; ratingError.value = '';
  const existing = myReviews.value[tapa.id];
  const review_text = valueOrNull(reviewDrafts.value[tapa.id] || '');
  const result = existing
    ? await db().from('reviews').update({ rating, review_text }).eq('id', existing.id)
    : await db().from('reviews').insert({ tapa_id: tapa.id, user_id: currentUserId.value, rating, review_text });
  ratingBusy.value = null;
  if (result.error) { ratingError.value = result.error.message; return; }
  await Promise.all([loadStats(), loadMyReviews(), loadPublicReviews()]);
}
async function saveReview(tapa: Tapa) {
  const existing = myReviews.value[tapa.id];
  if (!currentUserId.value) { ratingError.value = t('signInAtAdmin'); return; }
  if (!existing) { ratingError.value = t('chooseRatingFirst'); return; }
  ratingBusy.value = tapa.id; ratingError.value = ''; reviewNotice.value = '';
  const { error: reviewError } = await db().from('reviews').update({ review_text: valueOrNull(reviewDrafts.value[tapa.id] || '') }).eq('id', existing.id);
  ratingBusy.value = null;
  if (reviewError) { ratingError.value = reviewError.message; return; }
  reviewNotice.value = t('reviewSaved');
  await Promise.all([loadMyReviews(), loadPublicReviews()]);
}
async function logout() {
  ratingError.value = '';
  const { error: logoutError } = await supabase.auth.signOut();
  if (logoutError) ratingError.value = logoutError.message;
}
async function removeRating(tapa: Tapa) {
  const existing = myReviews.value[tapa.id];
  if (!currentUserId.value || !existing) return;
  ratingBusy.value = tapa.id; ratingError.value = '';
  const { error: deleteError } = await db().from('reviews').delete().eq('id', existing.id);
  ratingBusy.value = null;
  if (deleteError) { ratingError.value = deleteError.message; return; }
  await Promise.all([loadStats(), loadMyReviews(), loadPublicReviews()]);
}

watch(user, loadMyReviews);
onMounted(loadFestival);
</script>

<template>
  <main id="main-content" class="min-h-screen bg-stone-50 text-stone-900" tabindex="-1">
    <header class="border-b border-stone-200 bg-white"><div class="mx-auto flex max-w-6xl items-start justify-between gap-4 px-5 py-8 md:px-8"><div><p class="text-sm font-semibold uppercase tracking-widest text-emerald-700">tapas-festival</p><h1 class="mt-2 font-display text-4xl font-bold">{{ festival ? text(festival.name_en, festival.name_es) : 'Tapas festival' }}</h1><p v-if="festival && text(festival.description_en, festival.description_es)" class="mt-3 max-w-3xl text-stone-600">{{ text(festival.description_en, festival.description_es) }}</p></div><div class="flex shrink-0 flex-wrap justify-end gap-2"><div v-if="user" class="flex items-center gap-2 rounded-md border border-stone-300 bg-stone-50 px-2 py-1 text-xs font-semibold text-stone-700"><span>{{ t('signedIn') }}</span><button type="button" class="rounded bg-white px-2 py-1 text-emerald-700 shadow-sm ring-1 ring-stone-200" @click="logout">{{ t('logOut') }}</button></div><NuxtLink v-else to="/admin" class="rounded-md border border-stone-300 px-3 py-2 text-sm font-bold text-emerald-700">{{ t('signIn') }}</NuxtLink><div class="flex overflow-hidden rounded-md border border-stone-300 text-sm font-bold" :aria-label="t('language')"><button type="button" class="px-3 py-2" :class="language === 'en' ? 'bg-emerald-700 text-white' : 'bg-white text-stone-600'" :aria-pressed="language === 'en'" @click="setLanguage('en')">EN</button><button type="button" class="border-l border-stone-300 px-3 py-2" :class="language === 'es' ? 'bg-emerald-700 text-white' : 'bg-white text-stone-600'" :aria-pressed="language === 'es'" @click="setLanguage('es')">ES</button></div></div></div></header>
    <section class="mx-auto max-w-6xl px-5 py-8 md:px-8"><p v-if="loading" class="text-stone-600">{{ t('loading') }}</p><p v-else-if="error" class="rounded-lg border border-red-200 bg-red-50 p-4 text-red-800">{{ t('unableToLoad') }} {{ error }}</p><p v-else-if="!festival" class="rounded-lg border border-stone-200 bg-white p-5 text-stone-600">{{ t('noFestival') }}</p>
      <template v-else><div class="mb-6 flex flex-wrap gap-4 text-sm text-stone-600"><span>{{ festival.city }}</span><span>{{ festival.start_date }} – {{ festival.end_date }}</span><span>{{ t('standardTapaPrice') }} {{ festival.currency_code }} {{ festival.default_tapa_price }}</span></div>
        <nav class="sticky top-0 z-20 -mx-5 mb-5 grid grid-cols-3 border-y border-stone-200 bg-white/95 px-5 py-2 shadow-sm backdrop-blur lg:hidden" aria-label="Festival views"><button v-for="view in ['map', 'rankings', 'tapas'] as MobileView[]" :key="view" type="button" class="min-h-11 rounded-md px-2 text-sm font-bold uppercase tracking-wide" :class="mobileView === view ? 'bg-emerald-700 text-white' : 'text-stone-600'" :aria-pressed="mobileView === view" @click="mobileView = view">{{ t(view) }}</button></nav>
        <div :class="mobileView === 'map' ? 'block' : 'hidden lg:block'"><ClientOnly><FestivalMap :establishments="establishments" :tapas="tapas" :stats="stats" :my-reviews="myReviews" :location-active="mobileView === 'map'" /></ClientOnly></div>
        <div :class="mobileView === 'map' ? 'hidden lg:grid' : 'grid'" class="gap-8 lg:items-start lg:grid-cols-[minmax(0,38fr)_minmax(0,62fr)]">
          <aside :class="mobileView === 'rankings' ? 'block' : 'hidden lg:block'" class="lg:sticky lg:top-4 lg:h-[calc(100vh-2rem)] lg:self-start lg:overflow-y-auto lg:pr-2">
            <section class="rounded-xl border border-stone-200 bg-white p-5"><h2 class="font-display text-2xl font-bold">{{ t('liveRankings') }}</h2><p class="mt-1 text-sm text-stone-600">{{ t('rankingDescription') }}</p><ol class="mt-4 grid gap-2"><li v-for="(tapa, index) in rankedTapas" :key="tapa.id" class="flex flex-wrap items-center justify-between gap-3 rounded-lg bg-stone-50 px-3 py-2 text-sm"><div class="min-w-0"><p class="truncate font-semibold"><strong>{{ index + 1 }}.</strong> {{ text(tapa.name_en, tapa.name_es) }}</p><p class="truncate text-xs text-stone-500">{{ establishmentNameFor(tapa) }}</p></div><div class="shrink-0 text-right"><p class="font-semibold">{{ summaryFor(tapa.id).average_rating?.toFixed(1) ?? '—' }} ★</p><p class="text-xs text-stone-500">{{ summaryFor(tapa.id).rating_count }} {{ t('ratings') }}<span v-if="summaryFor(tapa.id).good_excellent_percentage != null"> · {{ Number(summaryFor(tapa.id).good_excellent_percentage).toFixed(0) }}% {{ t('goodExcellent') }}</span></p></div><blockquote v-if="index < 10 && highlightedReviewFor(tapa.id)" class="w-full border-l-2 border-amber-400 pl-2 text-xs text-stone-600"><p class="line-clamp-2 italic">“{{ highlightedReviewFor(tapa.id)?.review_text }}”</p></blockquote></li></ol></section>
          </aside>
          <div :class="mobileView === 'tapas' ? 'block' : 'hidden lg:block'" class="lg:sticky lg:top-4 lg:h-[calc(100vh-2rem)] lg:overflow-y-auto lg:pr-2">
        <p v-if="ratingError" class="mb-4 rounded border border-red-200 bg-red-50 p-3 text-sm text-red-800">{{ ratingError }}</p><p v-if="reviewNotice" class="mb-4 rounded border border-emerald-200 bg-emerald-50 p-3 text-sm text-emerald-800">{{ reviewNotice }}</p>
        <div class="space-y-6"><article v-for="venue in establishments" :key="venue.id" class="rounded-xl border border-stone-200 bg-white shadow-sm"><button type="button" class="flex w-full items-center justify-between gap-3 p-5 text-left" :aria-expanded="Boolean(expandedEstablishments[venue.id])" @click="toggleEstablishment(venue.id)"><h2 class="font-display text-2xl font-bold">{{ venue.name }}</h2><span class="text-2xl text-emerald-700 transition-transform" :class="expandedEstablishments[venue.id] ? 'rotate-180' : ''" aria-hidden="true">⌄</span></button><div v-if="expandedEstablishments[venue.id]" class="border-t border-stone-200 p-5 pt-4"><p v-if="venue.participation_status === 'withdrawn'" class="mt-1 text-sm font-semibold text-red-700">{{ t('withdrawn') }}</p><p v-else-if="venue.closure_status !== 'normal'" class="mt-1 text-sm font-semibold text-stone-600">{{ closureLabel(venue.closure_status) }}</p><p v-if="text(venue.description_en, venue.description_es)" class="mt-3 text-stone-700">{{ text(venue.description_en, venue.description_es) }}</p><div class="mt-4 grid gap-2 text-sm text-stone-600"><p v-if="venue.address">{{ venue.address }}</p><div v-if="text(venue.hours_notes_en, venue.hours_notes_es)"><strong>{{ t('openingHours') }}</strong><p class="whitespace-pre-line">{{ text(venue.hours_notes_en, venue.hours_notes_es) }}</p></div><div v-else-if="openingHourRows(venue.opening_hours).length"><strong>{{ t('openingHours') }}</strong><div class="mt-1 grid grid-cols-[5.5rem_1fr] gap-x-2 gap-y-1"><template v-for="row in openingHourRows(venue.opening_hours)" :key="row.day"><span class="font-medium">{{ row.day }}</span><span>{{ row.times }}</span></template></div></div><p v-if="venue.phone"><strong>{{ t('phone') }}</strong> {{ venue.phone }}</p><p v-if="venue.whatsapp"><strong>{{ t('whatsapp') }}</strong> {{ venue.whatsapp }}</p><p v-if="venue.website_url"><a class="text-emerald-700 underline" :href="venue.website_url" target="_blank" rel="noopener">{{ t('website') }}</a></p><p v-if="venue.facebook_url"><a class="text-emerald-700 underline" :href="venue.facebook_url" target="_blank" rel="noopener">{{ t('facebook') }}</a></p></div><div class="mt-5 grid gap-3 md:grid-cols-2"><section v-for="tapa in tapasFor(venue.id)" :key="tapa.id" class="rounded-lg bg-stone-50 p-4"><img v-if="tapaPhotoUrl(tapa)" :src="tapaPhotoUrl(tapa)" :alt="text(tapa.name_en, tapa.name_es)" class="mb-3 h-44 w-full rounded-md object-cover" loading="lazy"><div class="flex justify-between gap-3"><h3 class="font-bold">{{ tapa.festival_number ? `${tapa.festival_number}. ` : '' }}{{ text(tapa.name_en, tapa.name_es) }}</h3><span class="whitespace-nowrap font-semibold">{{ festival.currency_code }} {{ priceFor(tapa) }}</span></div><p v-if="tapa.participation_status === 'withdrawn'" class="mt-1 text-sm font-semibold text-red-700">{{ t('withdrawn') }}</p><p v-if="text(tapa.description_en, tapa.description_es)" class="mt-2 text-sm text-stone-600">{{ text(tapa.description_en, tapa.description_es) }}</p><div class="mt-4 border-t border-stone-200 pt-4 text-sm"><p class="text-stone-700"><strong>{{ t('publicRating') }} {{ summaryFor(tapa.id).average_rating?.toFixed(1) ?? t('unrated') }} ★</strong> · {{ summaryFor(tapa.id).rating_count }} {{ t('ratings') }}<span v-if="summaryFor(tapa.id).good_excellent_percentage != null"> · {{ Number(summaryFor(tapa.id).good_excellent_percentage).toFixed(0) }}% {{ t('goodExcellent') }}</span></p><template v-if="tapa.participation_status === 'active'"><div class="mt-4 rounded-lg border-2 border-emerald-200 bg-white p-3"><p class="font-bold text-emerald-950">{{ t('rateThisTapa') }}</p><p v-if="!user" class="mt-1 text-stone-600">{{ t('chooseStars') }} <NuxtLink class="font-semibold text-emerald-700 underline" to="/admin">{{ t('signInToRate') }}</NuxtLink>.</p><template v-else><p class="mt-1 text-stone-600"><strong>{{ t('yourRating') }}</strong> {{ myReviews[tapa.id] ? `${myReviews[tapa.id].rating} ${t('outOfFive')}` : t('notRatedYet') }}</p><div class="mt-3 flex flex-wrap gap-2" role="group" :aria-label="`${t('rateThisTapa')}: ${text(tapa.name_en, tapa.name_es)}`"><button v-for="star in 5" :key="star" type="button" class="flex min-h-12 min-w-12 flex-col items-center justify-center rounded-lg border-2 px-2 font-bold transition hover:scale-105 hover:border-amber-400 hover:bg-amber-50 focus-visible:ring-2 focus-visible:ring-emerald-700 disabled:opacity-50" :class="(myReviews[tapa.id]?.rating || 0) >= star ? 'border-amber-400 bg-amber-100 text-amber-700' : 'border-stone-300 bg-white text-stone-500'" :aria-pressed="myReviews[tapa.id]?.rating === star" :disabled="ratingBusy === tapa.id" @click="rate(tapa, star)"><span class="text-xl leading-none">★</span><span class="mt-1 text-xs">{{ star }}</span><span class="sr-only">{{ star }} {{ star === 1 ? t('star') : t('stars') }}</span></button></div><label class="mt-4 block font-semibold text-stone-800">{{ t('yourReview') }} · {{ myReviews[tapa.id]?.review_text ? t('editReview') : t('writeReview') }}<textarea v-model="reviewDrafts[tapa.id]" class="mt-1 min-h-24 w-full rounded border border-stone-300 p-2 font-normal" maxlength="3000" :placeholder="t('writeReview')" :disabled="ratingBusy === tapa.id" /></label><button type="button" class="mt-2 rounded bg-emerald-700 px-3 py-2 font-semibold text-white disabled:opacity-50" :disabled="ratingBusy === tapa.id" @click="saveReview(tapa)">{{ t('saveReview') }}</button><button v-if="myReviews[tapa.id]" type="button" class="mt-3 ml-2 rounded border border-red-300 px-3 py-2 text-xs font-semibold text-red-700 hover:bg-red-50" :disabled="ratingBusy === tapa.id" @click="removeRating(tapa)">{{ t('removeRating') }}</button></template></div></template><div class="mt-4"><div class="flex items-center justify-between gap-2"><p class="font-semibold text-stone-800">{{ t('reviews') }}</p><button v-if="reviewsFor(tapa.id).length > 3" type="button" class="text-xs font-semibold text-emerald-700 underline" @click="reviewsExpanded[tapa.id] = !reviewsExpanded[tapa.id]">{{ reviewsExpanded[tapa.id] ? t('hideReviews') : t('showReviews') }} ({{ reviewsFor(tapa.id).length }})</button></div><p v-if="!reviewsFor(tapa.id).length" class="mt-1 text-stone-500">{{ t('noReviewsYet') }}</p><ol v-else class="mt-2 space-y-2"><li v-for="review in shownReviewsFor(tapa.id)" :key="review.id" class="rounded bg-white p-2 text-stone-700"><p class="text-xs font-semibold text-stone-500">{{ t('festivalVisitor') }} · {{ review.rating }} ★ · {{ formatReviewDate(review.created_at) }}</p><p class="mt-1 whitespace-pre-wrap">{{ review.review_text }}</p></li></ol></div></div></section></div></div></article></div>
          </div>
        </div>
      </template>
    </section>
  </main>
</template>
