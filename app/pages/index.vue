<script setup lang="ts">
type Festival = any;
type Establishment = any;
type Tapa = any;
type Stats = { tapa_id: string; rating_count: number; average_rating: number | null; good_excellent_percentage: number | null };

const supabase = useSupabaseClient<any>() as any;
const user = useSupabaseUser();
const currentUserId = computed(() => typeof user.value?.sub === 'string' ? user.value.sub : null);
const abbreviatedIdentity = computed(() => {
  const email = typeof user.value?.email === 'string' ? user.value.email : '';
  if (!email) return '';
  const [local, domain = ''] = email.split('@');
  const mask = (value: string) => `${value.slice(0, 6)}${'?'.repeat(Math.max(0, value.length - 6))}`;
  return domain ? `${mask(local)}@${mask(domain)}` : mask(local);
});
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
type EstablishmentStats = { establishment_id: string; rating_count: number; average_rating: number | null };
type MyEstablishmentReview = { id: string; rating: number };
const establishmentStats = ref<Record<string, EstablishmentStats>>({});
const myEstablishmentReviews = ref<Record<string, MyEstablishmentReview>>({});
const tapaRatingDrafts = ref<Record<string, number>>({});
const rankingTickerOverflow = ref<Record<string, boolean>>({});
const establishmentRatingDrafts = ref<Record<string, number>>({});
const barRatingBusy = ref<string | null>(null);
const barSort = ref<'numeric' | 'alphabetical' | 'unreviewed'>('numeric');
const reportOpen = ref(false);
const reportEmail = ref('');
const reportDescription = ref('');
const buildReference = useRuntimeConfig().public.buildReference as string;
const myReviews = ref<Record<string, MyReview>>({});
const publicReviews = ref<Record<string, PublicReview[]>>({});
const reviewDrafts = ref<Record<string, string>>({});
const reviewsExpanded = ref<Record<string, boolean>>({});
const reviewNotice = ref('');
const maxReviewLength = 60;
const expandedEstablishments = ref<Record<string, boolean>>({});
const selectedEstablishmentId = ref<string | null>(null);
const establishmentsPane = ref<HTMLElement | null>(null);
const highlightedTapaId = ref<string | null>(null);
const wantedTapas = ref<Record<string, boolean>>({});
const authMode = ref<'signin' | 'signup' | null>(null);
const authEmail = ref('');
const authPassword = ref('');
const authBusy = ref(false);
const authError = ref('');
const authNotice = ref('');

const wantedTapaStorageKey = (tapaId: string) => `tapas-festival:wanted-tapa:${tapaId}`;
const wantsToTry = (tapaId: string) => Boolean(wantedTapas.value[tapaId]);
function loadWantedTapas() {
  if (!import.meta.client) return;
  wantedTapas.value = Object.fromEntries(tapas.value.filter((tapa) => localStorage.getItem(wantedTapaStorageKey(tapa.id)) === '1').map((tapa) => [tapa.id, true]));
}
function toggleWantedTapa(tapaId: string) {
  if (wantsToTry(tapaId)) {
    const { [tapaId]: _, ...remaining } = wantedTapas.value;
    wantedTapas.value = remaining;
    localStorage.removeItem(wantedTapaStorageKey(tapaId));
  } else {
    wantedTapas.value = { ...wantedTapas.value, [tapaId]: true };
    localStorage.setItem(wantedTapaStorageKey(tapaId), '1');
  }
}
const db = () => supabase.schema('festival');
const valueOrNull = (value: string) => value.trim() || null;
const tapasFor = (establishmentId: string) => tapas.value.filter((tapa) => tapa.establishment_id === establishmentId);
const establishmentNameFor = (tapa: Tapa) => establishments.value.find((venue) => venue.id === tapa.establishment_id)?.name || '';
const tapaPhotoUrl = (tapa: Tapa) => tapa.photo_path ? supabase.storage.from('festival-images').getPublicUrl(tapa.photo_path).data.publicUrl : '';
const text = (english?: string | null, spanish?: string | null) => localized(english, spanish);
const weekdays = computed(() => language.value === 'es' ? ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'] : ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']);
const globalMean = computed(() => {
  const all = Object.values(stats.value);
  const count = all.reduce((sum, item) => sum + Number(item.rating_count || 0), 0);
  return count ? all.reduce((sum, item) => sum + Number(item.average_rating || 0) * Number(item.rating_count || 0), 0) / count : 3;
});
const showRankings = computed(() => festival.value?.show_rankings !== false);
const rankedTapas = computed(() => [...tapas.value]
  .filter((tapa) => tapa.participation_status === 'active')
  .sort((a, b) => {
    const scoreDifference = credibilityScore(b) - credibilityScore(a);
    if (scoreDifference) return scoreDifference;
    const countDifference = Number(stats.value[b.id]?.rating_count || 0) - Number(stats.value[a.id]?.rating_count || 0);
    if (countDifference) return countDifference;
    const averageDifference = Number(stats.value[b.id]?.average_rating || 0) - Number(stats.value[a.id]?.average_rating || 0);
    return averageDifference || text(a.name_en, a.name_es).localeCompare(text(b.name_en, b.name_es));
  }));
function programmeNumberFor(venue: Establishment) {
  return Number.parseInt(String(venue.name).match(/^\s*(\d+)/)?.[1] || '', 10) || Number.MAX_SAFE_INTEGER;
}
function hasNoStarsYet(venue: Establishment) {
  const eligible = tapasFor(venue.id).filter((tapa) => tapa.is_published && tapa.participation_status === 'active');
  return eligible.length > 0 && !eligible.some((tapa) => myReviews.value[tapa.id]);
}
const sortedEstablishments = computed(() => [...establishments.value].sort((a, b) => {
  if (barSort.value === 'alphabetical') return String(a.name).replace(/^\s*\d+\.\s*/, '').localeCompare(String(b.name).replace(/^\s*\d+\.\s*/, ''), undefined, { sensitivity: 'base' });
  if (barSort.value === 'unreviewed' && currentUserId.value) {
    const difference = Number(hasNoStarsYet(b)) - Number(hasNoStarsYet(a));
    if (difference) return difference;
  }
  return programmeNumberFor(a) - programmeNumberFor(b) || String(a.name).localeCompare(String(b.name));
}));

function credibilityScore(tapa: Tapa) {
  const item = stats.value[tapa.id];
  const count = Number(item?.rating_count || 0);
  const average = Number(item?.average_rating ?? globalMean.value);
  const priorWeight = 5;
  return (count * average + priorWeight * globalMean.value) / (count + priorWeight);
}
function hasRatingSelection(drafts: Record<string, number>, id: string, savedRating?: number | null) {
  return drafts[id] != null || savedRating != null;
}
function ratingDraft(drafts: Record<string, number>, id: string, savedRating?: number | null) {
  // The range needs a value, but an unrated control remains visually neutral.
  return Number(drafts[id] ?? savedRating ?? 3).toFixed(1);
}
function ratingLabel(drafts: Record<string, number>, id: string, savedRating?: number | null) {
  return hasRatingSelection(drafts, id, savedRating) ? `${ratingDraft(drafts, id, savedRating)} ★` : t('chooseRating');
}
function setRatingDraft(drafts: Record<string, number>, id: string, value: string) {
  const rating = Number(value);
  if (Number.isFinite(rating) && rating >= 1 && rating <= 5) drafts[id] = Math.round(rating * 10) / 10;
}
function ratingInputValue(event: Event) {
  return (event.target as HTMLInputElement).value;
}
function setRankingTicker(id: string, element: Element | null) {
  if (!import.meta.client || !(element instanceof HTMLElement)) return;
  requestAnimationFrame(() => {
    rankingTickerOverflow.value[id] = element.scrollWidth > element.clientWidth + 1;
  });
}
watch(language, () => { rankingTickerOverflow.value = {}; });
function openingHourRows(hours: unknown) {
  if (!hours || typeof hours !== 'object' || Array.isArray(hours)) return [];
  return Object.entries(hours as Record<string, unknown>).map(([day, periods]) => {
    const label = weekdays.value[Number(day) - 1] || day;
    if (!Array.isArray(periods) || periods.length === 0) return { day: label, times: t('closed') };
    const times = periods.map((period: any) => Array.isArray(period) ? `${period[0]}–${period[1]}` : '').filter(Boolean).join(', ');
    return times ? { day: label, times } : null;
  }).filter(Boolean) as { day: string; times: string }[];
}
const expandedOpeningHours = ref<Record<string, boolean>>({});
function toggleEstablishment(id: string) {
  expandedEstablishments.value[id] = !expandedEstablishments.value[id];
}
function toggleOpeningHours(id: string) {
  expandedOpeningHours.value[id] = !expandedOpeningHours.value[id];
}
async function revealEstablishmentFromMap(establishmentId: string) {
  expandedEstablishments.value[establishmentId] = true;
  await nextTick();
  const pane = establishmentsPane.value;
  const establishmentElement = document.getElementById(`festival-establishment-${establishmentId}`);
  if (pane && establishmentElement) {
    const paneRect = pane.getBoundingClientRect();
    const establishmentRect = establishmentElement.getBoundingClientRect();
    if (establishmentRect.top < paneRect.top || establishmentRect.bottom > paneRect.bottom) {
      pane.scrollTo({ top: pane.scrollTop + establishmentRect.top - paneRect.top - 12, behavior: 'smooth' });
    }
  }
}
async function revealTapaFromRanking(tapa: Tapa) {
  await revealTapaFromMap(tapa.id, tapa.establishment_id);
}
async function revealTapaFromMap(tapaId: string, establishmentId: string) {
  expandedEstablishments.value[establishmentId] = true;
  highlightedTapaId.value = tapaId;
  await nextTick();
  const pane = establishmentsPane.value;
  const tapaElement = document.getElementById(`festival-tapa-${tapaId}`);
  if (pane && tapaElement) {
    const paneRect = pane.getBoundingClientRect();
    const tapaRect = tapaElement.getBoundingClientRect();
    if (tapaRect.top < paneRect.top || tapaRect.bottom > paneRect.bottom) {
      pane.scrollTo({ top: pane.scrollTop + tapaRect.top - paneRect.top - 16, behavior: 'smooth' });
    }
  }
  window.setTimeout(() => { if (highlightedTapaId.value === tapaId) highlightedTapaId.value = null; }, 2200);
}

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
function establishmentSummaryFor(establishmentId: string) { return establishmentStats.value[establishmentId] || { rating_count: 0, average_rating: null }; }
async function loadEstablishmentStats() {
  if (!festival.value) return;
  const { data, error: statsError } = await db().from('establishment_rating_stats').select('*').eq('festival_id', festival.value.id);
  if (statsError) { ratingError.value = statsError.message; return; }
  establishmentStats.value = Object.fromEntries((data || []).map((item: EstablishmentStats) => [item.establishment_id, item]));
}
async function loadMyEstablishmentReviews() {
  myEstablishmentReviews.value = {}; establishmentRatingDrafts.value = {};
  if (!currentUserId.value || !establishments.value.length) return;
  const { data, error: reviewError } = await db().from('establishment_reviews').select('id,establishment_id,rating').in('establishment_id', establishments.value.map((venue) => venue.id)).eq('user_id', currentUserId.value);
  if (reviewError) { ratingError.value = reviewError.message; return; }
  myEstablishmentReviews.value = Object.fromEntries((data || []).map((review: MyEstablishmentReview & { establishment_id: string }) => [review.establishment_id, review]));
  establishmentRatingDrafts.value = Object.fromEntries((data || []).map((review: MyEstablishmentReview & { establishment_id: string }) => [review.establishment_id, Number(review.rating)]));
}
async function loadMyReviews() {
  myReviews.value = {}; reviewDrafts.value = {}; tapaRatingDrafts.value = {};
  if (!currentUserId.value || !tapas.value.length) return;
  const { data, error: reviewError } = await db().from('reviews').select('id,tapa_id,rating,review_text').in('tapa_id', tapas.value.map((tapa) => tapa.id)).eq('user_id', currentUserId.value);
  if (reviewError) { ratingError.value = reviewError.message; return; }
  myReviews.value = Object.fromEntries((data || []).map((review: MyReview & { tapa_id: string }) => [review.tapa_id, review]));
  reviewDrafts.value = Object.fromEntries((data || []).map((review: MyReview & { tapa_id: string }) => [review.tapa_id, review.review_text || '']));
  tapaRatingDrafts.value = Object.fromEntries((data || []).map((review: MyReview & { tapa_id: string }) => [review.tapa_id, Number(review.rating)]));
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
  loadWantedTapas();
  await Promise.all([loadStats(), loadEstablishmentStats(), loadMyReviews(), loadMyEstablishmentReviews(), loadPublicReviews()]);
  loading.value = false;
}
async function rate(tapa: Tapa, rating: number) {
  if (!currentUserId.value) { ratingError.value = t('signInAtAdmin'); return; }
  const existing = myReviews.value[tapa.id];
  const confirmedRating = existing?.rating;
  const draft = reviewDrafts.value[tapa.id] || '';
  if (draft.length > maxReviewLength) { ratingError.value = t('reviewTooLong'); return; }

  // Keep the slider on the selected value until the mutation confirms it.
  tapaRatingDrafts.value[tapa.id] = rating;
  ratingBusy.value = tapa.id;
  ratingError.value = '';
  const review_text = valueOrNull(draft);
  const result = existing
    ? await db().from('reviews').update({ rating, review_text }).eq('id', existing.id).select('id,tapa_id,rating,review_text').single()
    : await db().from('reviews').insert({ tapa_id: tapa.id, user_id: currentUserId.value, rating, review_text }).select('id,tapa_id,rating,review_text').single();
  ratingBusy.value = null;
  if (result.error || !result.data) {
    ratingError.value = result.error?.message || 'Unable to save rating.';
    if (confirmedRating == null) delete tapaRatingDrafts.value[tapa.id];
    else tapaRatingDrafts.value[tapa.id] = Number(confirmedRating);
    return;
  }

  const saved = result.data as MyReview & { tapa_id: string };
  myReviews.value = { ...myReviews.value, [tapa.id]: saved };
  tapaRatingDrafts.value[tapa.id] = Number(saved.rating);
  reviewDrafts.value[tapa.id] = saved.review_text || draft;
  // Refresh aggregate/public data only; do not reload this user's just-confirmed slider state.
  await Promise.all([loadStats(), loadEstablishmentStats(), loadMyEstablishmentReviews(), loadPublicReviews()]);
}
async function rateEstablishment(venue: Establishment, rating: number) {
  if (!currentUserId.value) { ratingError.value = t('signInAtAdmin'); openAuth('signin'); return; }
  const existing = myEstablishmentReviews.value[venue.id];
  const confirmedRating = existing?.rating;
  // Keep the selected slider position while the request is in flight.
  establishmentRatingDrafts.value[venue.id] = rating;
  barRatingBusy.value = venue.id;
  ratingError.value = '';
  const result = existing
    ? await db().from('establishment_reviews').update({ rating }).eq('id', existing.id).select('id,establishment_id,rating').single()
    : await db().from('establishment_reviews').insert({ establishment_id: venue.id, user_id: currentUserId.value, rating }).select('id,establishment_id,rating').single();
  barRatingBusy.value = null;
  if (result.error || !result.data) {
    ratingError.value = result.error?.message || 'Unable to save bar rating.';
    if (confirmedRating == null) delete establishmentRatingDrafts.value[venue.id];
    else establishmentRatingDrafts.value[venue.id] = Number(confirmedRating);
    return;
  }
  const saved = result.data as MyEstablishmentReview & { establishment_id: string };
  myEstablishmentReviews.value = { ...myEstablishmentReviews.value, [venue.id]: saved };
  establishmentRatingDrafts.value[venue.id] = Number(saved.rating);
  // Refresh the public aggregate only; retain this user's confirmed slider state.
  await loadEstablishmentStats();
}
async function removeEstablishmentRating(venue: Establishment) {
  const existing = myEstablishmentReviews.value[venue.id];
  if (!currentUserId.value || !existing) return;
  barRatingBusy.value = venue.id; ratingError.value = '';
  const { error: deleteError } = await db().from('establishment_reviews').delete().eq('id', existing.id);
  barRatingBusy.value = null;
  if (deleteError) { ratingError.value = deleteError.message; return; }
  await Promise.all([loadEstablishmentStats(), loadMyEstablishmentReviews()]);
}
function submitProblemReport() {
  const context = `Festival: ${festival.value?.slug || ''}\nPage: ${window.location.href}\nContact: ${reportEmail.value.trim() || '(not provided)'}\n\nProblem:\n${reportDescription.value.trim()}`;
  window.location.href = `mailto:?subject=${encodeURIComponent(`Tapas festival problem: ${festival.value?.slug || ''}`)}&body=${encodeURIComponent(context)}`;
  reportOpen.value = false;
}
async function saveReview(tapa: Tapa) {
  const existing = myReviews.value[tapa.id];
  if (!currentUserId.value) { ratingError.value = t('signInAtAdmin'); return; }
  if (!existing) { ratingError.value = t('chooseRatingFirst'); return; }
  const draft = reviewDrafts.value[tapa.id] || '';
  if (draft.length > maxReviewLength) { ratingError.value = t('reviewTooLong'); return; }
  ratingBusy.value = tapa.id; ratingError.value = ''; reviewNotice.value = '';
  const { error: reviewError } = await db().from('reviews').update({ review_text: valueOrNull(draft) }).eq('id', existing.id);
  ratingBusy.value = null;
  if (reviewError) { ratingError.value = reviewError.message; return; }
  reviewNotice.value = t('reviewSaved');
  await Promise.all([loadMyReviews(), loadPublicReviews()]);
}
function openAuth(mode: 'signin' | 'signup') {
  authMode.value = mode;
  authError.value = '';
  authNotice.value = '';
}
function validPublicCredentials() {
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(authEmail.value.trim())) { authError.value = t('invalidEmail'); return false; }
  if (authPassword.value.length < 8) { authError.value = t('invalidPassword'); return false; }
  return true;
}
async function loginWithGoogle() {
  authBusy.value = true;
  authError.value = '';
  authNotice.value = '';
  const { error: oauthError } = await supabase.auth.signInWithOAuth({
    provider: 'google',
    options: { redirectTo: `${window.location.origin}/` },
  });
  if (oauthError) {
    authBusy.value = false;
    authError.value = oauthError.message;
  }
}
async function submitPublicAuth() {
  if (!authMode.value || !validPublicCredentials()) return;
  authBusy.value = true;
  authError.value = '';
  authNotice.value = '';
  const email = authEmail.value.trim();
  const result = authMode.value === 'signin'
    ? await supabase.auth.signInWithPassword({ email, password: authPassword.value })
    : await supabase.auth.signUp({ email, password: authPassword.value });
  authBusy.value = false;
  if (result.error) { authError.value = result.error.message; return; }
  if (authMode.value === 'signup') authNotice.value = result.data?.session ? t('accountCreatedSignedIn') : t('accountCreatedConfirm');
  authPassword.value = '';
  if (result.data?.session) authMode.value = null;
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
  loadWantedTapas();
  await Promise.all([loadStats(), loadEstablishmentStats(), loadMyReviews(), loadMyEstablishmentReviews(), loadPublicReviews()]);
}

watch(user, () => {
  if (!user.value && barSort.value === 'unreviewed') barSort.value = 'numeric';
  void Promise.all([loadMyReviews(), loadMyEstablishmentReviews()]);
});
onMounted(loadFestival);
</script>

<template>
  <main id="main-content" class="min-h-screen bg-stone-50 text-stone-900" tabindex="-1">
    <section class="mx-auto max-w-6xl pb-8 sm:px-5 sm:pt-4 md:px-8"><p v-if="loading" class="text-stone-600">{{ t('loading') }}</p><p v-else-if="error" class="rounded-lg border border-red-200 bg-red-50 p-4 text-red-800">{{ t('unableToLoad') }} {{ error }}</p><p v-else-if="!festival" class="rounded-lg border border-stone-200 bg-white p-5 text-stone-600">{{ t('noFestival') }}</p>
      <template v-else>
        <div><ClientOnly><FestivalMap :establishments="establishments" :tapas="tapas" :stats="stats" :my-reviews="myReviews" :location-active="true" :selected-establishment-id="selectedEstablishmentId" :wanted-tapas="wantedTapas" @select-tapa="revealTapaFromMap" @select-establishment="revealEstablishmentFromMap" /></ClientOnly></div>
        <div class="mx-4 mb-4 flex flex-col gap-2 rounded-lg border border-stone-200 bg-white px-3 py-2 sm:mx-0 sm:mb-6 sm:flex-row sm:items-center sm:justify-between">
          <div class="min-w-0"><p class="text-xs font-semibold uppercase tracking-widest text-emerald-700">tapas-festival</p><h1 class="whitespace-nowrap font-display text-[clamp(1rem,5.5vw,1.75rem)] font-bold leading-tight tracking-tight">{{ festival ? text(festival.name_en, festival.name_es) : 'Tapas festival' }}</h1></div>
          <div class="flex shrink-0 flex-wrap items-center gap-2"><div v-if="user" class="flex items-center gap-2 rounded-md border border-stone-300 bg-stone-50 px-2 py-1 text-xs font-semibold text-stone-700"><span>{{ t('signedIn') }}</span><span v-if="abbreviatedIdentity" :title="t('signedIn')">{{ abbreviatedIdentity }}</span><button type="button" class="rounded bg-white px-2 py-1 text-emerald-700 shadow-sm ring-1 ring-stone-200" @click="logout">{{ t('logOut') }}</button></div><template v-else><button type="button" class="rounded-md border border-stone-300 px-3 py-2 text-sm font-bold text-emerald-700" @click="openAuth('signin')">{{ t('signIn') }}</button><button type="button" class="rounded-md bg-emerald-700 px-3 py-2 text-sm font-bold text-white" @click="openAuth('signup')">{{ t('createAccount') }}</button></template><div class="flex overflow-hidden rounded-md border border-stone-300 text-sm font-bold" :aria-label="t('language')"><button type="button" class="px-3 py-2" :class="language === 'en' ? 'bg-emerald-700 text-white' : 'bg-white text-stone-600'" :aria-pressed="language === 'en'" @click="setLanguage('en')">EN</button><button type="button" class="border-l border-stone-300 px-3 py-2" :class="language === 'es' ? 'bg-emerald-700 text-white' : 'bg-white text-stone-600'" :aria-pressed="language === 'es'" @click="setLanguage('es')">ES</button></div></div>
        </div>
        <form v-if="!user && authMode" class="mx-4 mb-4 rounded-lg border border-stone-200 bg-white p-3 sm:mx-0 sm:mb-6" @submit.prevent="submitPublicAuth">
          <div class="flex flex-wrap items-center gap-2"><p class="mr-auto text-sm font-bold text-stone-800">{{ authMode === 'signin' ? t('signIn') : t('createAccount') }}</p><button type="button" class="text-xs font-semibold text-stone-600 underline" @click="authMode = null">×</button></div>
          <p v-if="authError" class="mt-2 rounded border border-red-200 bg-red-50 p-2 text-sm text-red-800">{{ authError }}</p><p v-if="authNotice" class="mt-2 rounded border border-emerald-200 bg-emerald-50 p-2 text-sm text-emerald-800">{{ authNotice }}</p>
          <button type="button" class="mt-3 flex min-h-11 w-full items-center justify-center gap-2 rounded border border-stone-300 bg-white px-4 py-2 text-sm font-bold text-stone-800 shadow-sm transition hover:bg-stone-50 disabled:opacity-50" :disabled="authBusy" @click="loginWithGoogle"><svg class="h-4 w-4" viewBox="0 0 24 24" aria-hidden="true"><path fill="#4285F4" d="M23.49 12.27c0-.79-.07-1.54-.19-2.27H12v4.51h6.47a5.57 5.57 0 0 1-2.4 3.58v3h3.86c2.26-2.09 3.56-5.17 3.56-8.82z"/><path fill="#34A853" d="M12 24c3.24 0 5.95-1.08 7.93-2.91l-3.86-3c-1.08.72-2.45 1.16-4.07 1.16-3.13 0-5.78-2.11-6.73-4.96H1.29v3.09A11.99 11.99 0 0 0 12 24z"/><path fill="#FBBC05" d="M5.27 14.29a7.2 7.2 0 0 1 0-4.58V6.62H1.29a12 12 0 0 0 0 10.76l3.98-3.09z"/><path fill="#EA4335" d="M12 4.75c1.77 0 3.35.61 4.6 1.8l3.42-3.42C17.95 1.19 15.24 0 12 0 7.31 0 3.25 2.69 1.29 6.62l3.98 3.09C6.22 6.86 8.87 4.75 12 4.75z"/></svg>{{ t('continueWithGoogle') }}</button>
          <p class="my-3 text-center text-xs font-semibold text-stone-500">{{ t('orContinueWith') }}</p>
          <div class="grid gap-2 sm:grid-cols-[minmax(0,1fr)_minmax(0,1fr)_auto]"><input v-model="authEmail" class="min-w-0 rounded border border-stone-300 px-3 py-2 text-sm" type="email" autocomplete="email" :placeholder="t('email')" required><input v-model="authPassword" class="min-w-0 rounded border border-stone-300 px-3 py-2 text-sm" type="password" :autocomplete="authMode === 'signin' ? 'current-password' : 'new-password'" :placeholder="`${t('password')} · ${t('passwordHint')}`" minlength="8" required><button class="rounded bg-emerald-700 px-4 py-2 text-sm font-bold text-white disabled:opacity-50" :disabled="authBusy">{{ authBusy ? (authMode === 'signin' ? t('signingIn') : t('creatingAccount')) : (authMode === 'signin' ? t('signIn') : t('createAccount')) }}</button></div>
        </form>
        <p v-else-if="authNotice" class="mx-4 mb-4 rounded border border-emerald-200 bg-emerald-50 p-2 text-sm text-emerald-800 sm:mx-0 sm:mb-6">{{ authNotice }}</p>
        <div class="mx-2 grid items-start gap-2 sm:mx-0 sm:gap-4 lg:gap-8" :class="showRankings ? 'grid-cols-[minmax(0,38fr)_minmax(0,62fr)]' : 'grid-cols-1'">
          <aside v-if="showRankings" class="sticky top-2 h-[calc(100vh-1rem)] self-start overflow-y-auto pr-1 sm:top-4 sm:h-[calc(100vh-2rem)] sm:pr-2">
            <section class="rounded-xl border border-stone-200 bg-white p-2 sm:p-5"><h2 class="font-display text-lg font-bold sm:text-2xl">{{ t('liveRankings') }}</h2><ol class="mt-3 grid gap-2 sm:mt-4"><li v-for="(tapa, index) in rankedTapas" :key="tapa.id"><button type="button" class="grid w-full grid-cols-[minmax(0,1fr)_auto] gap-x-2 rounded-lg bg-stone-50 px-2 py-2 text-left text-xs transition hover:bg-emerald-50 focus-visible:outline focus-visible:outline-2 focus-visible:outline-emerald-700 sm:px-3 sm:text-sm" @click="revealTapaFromRanking(tapa)"><p class="col-span-2 truncate font-semibold"><strong>{{ index + 1 }}.</strong> {{ text(tapa.name_en, tapa.name_es) }}</p><p :ref="(element) => setRankingTicker(tapa.id, element)" class="min-w-0 overflow-hidden whitespace-nowrap text-xs text-stone-500"><span v-if="rankingTickerOverflow[tapa.id]" class="ranking-ticker-track"><span>{{ establishmentNameFor(tapa) }}</span><span aria-hidden="true">{{ establishmentNameFor(tapa) }}</span></span><span v-else class="inline-block whitespace-nowrap">{{ establishmentNameFor(tapa) }}</span></p><p class="self-center whitespace-nowrap text-right font-semibold"><span class="hidden sm:inline">{{ t('publicRating') }} {{ summaryFor(tapa.id).average_rating == null ? '—' : Number(summaryFor(tapa.id).average_rating).toFixed(1) }} ★ ({{ summaryFor(tapa.id).rating_count }}) · {{ t('rankingScore') }} {{ credibilityScore(tapa).toFixed(1) }}</span><span class="sm:hidden">R:{{ summaryFor(tapa.id).average_rating == null ? '—' : Number(summaryFor(tapa.id).average_rating).toFixed(1) }} · S:{{ credibilityScore(tapa).toFixed(1) }}</span></p><blockquote v-if="index < 10 && highlightedReviewFor(tapa.id)" class="col-span-2 w-full border-l-2 border-amber-400 pl-2 text-xs text-stone-600"><p class="line-clamp-2 italic">“{{ highlightedReviewFor(tapa.id)?.review_text }}”</p></blockquote></button></li></ol></section>
          </aside>
          <div ref="establishmentsPane" class="sticky top-2 h-[calc(100vh-1rem)] overflow-y-auto pr-1 sm:top-4 sm:h-[calc(100vh-2rem)] sm:pr-2">
        <p v-if="ratingError" class="mb-4 rounded border border-red-200 bg-red-50 p-3 text-sm text-red-800">{{ ratingError }}</p><p v-if="reviewNotice" class="mb-4 rounded border border-emerald-200 bg-emerald-50 p-3 text-sm text-emerald-800">{{ reviewNotice }}</p>
        <div class="mb-3 flex flex-wrap items-center gap-2 rounded-lg border border-stone-200 bg-white p-2 text-xs sm:mb-4"><label class="font-semibold text-stone-700" for="bar-sort">{{ t('sortBars') }}</label><select id="bar-sort" v-model="barSort" class="rounded border border-stone-300 bg-white px-2 py-1.5" @change="barSort === 'unreviewed' && !user ? (barSort = 'numeric') : undefined"><option value="numeric">{{ t('numeric') }}</option><option value="alphabetical">{{ t('alphabetical') }}</option><option value="unreviewed" :disabled="!user">{{ t('notReviewedYet') }}</option></select><span v-if="!user" class="text-stone-500">{{ t('signInToSort') }}</span></div>
        <div class="space-y-3 pb-24 sm:space-y-6 sm:pb-32"><article :id="`festival-establishment-${venue.id}`" v-for="venue in sortedEstablishments" :key="venue.id" class="rounded-xl border border-stone-200 bg-white shadow-sm"><button type="button" class="flex w-full items-center justify-between gap-2 p-3 text-left sm:p-5" :aria-expanded="Boolean(expandedEstablishments[venue.id])" @click="toggleEstablishment(venue.id)"><h2 class="font-display text-base font-bold sm:text-2xl">{{ venue.name }}</h2><span class="text-xl text-emerald-700 transition-transform sm:text-2xl" :class="expandedEstablishments[venue.id] ? 'rotate-180' : ''" aria-hidden="true">⌄</span></button><div v-if="expandedEstablishments[venue.id]" class="border-t border-stone-200 p-3 pt-3 sm:p-5 sm:pt-4"><p v-if="venue.participation_status === 'withdrawn'" class="mt-1 text-sm font-semibold text-red-700">{{ t('withdrawn') }}</p><p v-else-if="venue.closure_status !== 'normal'" class="mt-1 text-sm font-semibold text-stone-600">{{ closureLabel(venue.closure_status) }}</p><p v-if="text(venue.description_en, venue.description_es)" class="mt-3 text-stone-700">{{ text(venue.description_en, venue.description_es) }}</p><div class="mt-4 rounded-lg border border-emerald-200 bg-emerald-50 p-3 text-sm"><div class="flex flex-wrap items-center gap-2"><p class="mr-auto font-bold text-emerald-950">{{ t('rateThisBar') }}</p><p class="text-xs text-stone-600"><strong>{{ t('barRating') }}</strong> {{ establishmentSummaryFor(venue.id).average_rating == null ? t('unrated') : Number(establishmentSummaryFor(venue.id).average_rating).toFixed(1) }} ★ · {{ establishmentSummaryFor(venue.id).rating_count }} {{ t('ratings') }}</p></div><template v-if="user"><div class="mt-2"><div class="flex min-w-0 items-center gap-2" :aria-label="`${t('rateThisBar')}: ${venue.name}`"><span class="shrink-0 text-xs tabular-nums text-stone-500">1.0</span><input class="bar-rating-slider min-w-0 flex-1" :class="hasRatingSelection(establishmentRatingDrafts, venue.id, myEstablishmentReviews[venue.id]?.rating) ? 'bar-rating-slider--rated' : 'bar-rating-slider--unrated'" type="range" min="1" max="5" step="0.1" :value="ratingDraft(establishmentRatingDrafts, venue.id, myEstablishmentReviews[venue.id]?.rating)" :disabled="barRatingBusy === venue.id" :aria-label="`${t('rateThisBar')}: ${venue.name}`" @input="setRatingDraft(establishmentRatingDrafts, venue.id, ratingInputValue($event))" @change="rateEstablishment(venue, Number(establishmentRatingDrafts[venue.id] ?? myEstablishmentReviews[venue.id]?.rating ?? 3))"><span class="shrink-0 text-xs tabular-nums text-stone-500">5.0</span><span class="shrink-0 rounded px-1.5 py-0.5 text-sm font-bold tabular-nums" :class="hasRatingSelection(establishmentRatingDrafts, venue.id, myEstablishmentReviews[venue.id]?.rating) ? 'bg-emerald-700 text-white shadow-sm' : 'bg-stone-100 text-stone-400'">{{ ratingLabel(establishmentRatingDrafts, venue.id, myEstablishmentReviews[venue.id]?.rating) }}</span><button v-if="myEstablishmentReviews[venue.id]" type="button" class="shrink-0 rounded border border-red-300 px-2 py-1 text-xs font-semibold text-red-700" :disabled="barRatingBusy === venue.id" @click="removeEstablishmentRating(venue)">{{ t('removeBarRating') }}</button></div></div></template><p v-else class="mt-2 text-stone-600"><button type="button" class="font-semibold text-emerald-700 underline" @click="openAuth('signin')">{{ t('signInToRate') }}</button></p></div><div class="mt-4 grid gap-2 text-sm text-stone-600"><p v-if="venue.address">{{ venue.address }}</p><div v-if="text(venue.hours_notes_en, venue.hours_notes_es) || openingHourRows(venue.opening_hours).length"><button type="button" class="flex w-full items-center justify-between text-left font-semibold text-stone-700 hover:text-emerald-800" :aria-expanded="Boolean(expandedOpeningHours[venue.id])" @click.stop="toggleOpeningHours(venue.id)"><span>{{ t('openingHours') }}</span><span class="transition-transform" :class="expandedOpeningHours[venue.id] ? 'rotate-180' : ''" aria-hidden="true">▸</span></button><p v-if="expandedOpeningHours[venue.id] && text(venue.hours_notes_en, venue.hours_notes_es)" class="mt-1 whitespace-pre-line">{{ text(venue.hours_notes_en, venue.hours_notes_es) }}</p><div v-else-if="expandedOpeningHours[venue.id] && openingHourRows(venue.opening_hours).length" class="mt-1 grid grid-cols-[5.5rem_1fr] gap-x-2 gap-y-1"><template v-for="row in openingHourRows(venue.opening_hours)" :key="row.day"><span class="font-medium">{{ row.day }}</span><span>{{ row.times }}</span></template></div></div><p v-if="venue.phone"><strong>{{ t('phone') }}</strong> {{ venue.phone }}</p><p v-if="venue.whatsapp"><strong>{{ t('whatsapp') }}</strong> {{ venue.whatsapp }}</p><p v-if="venue.website_url"><a class="text-emerald-700 underline" :href="venue.website_url" target="_blank" rel="noopener">{{ t('website') }}</a></p><p v-if="venue.facebook_url"><a class="text-emerald-700 underline" :href="venue.facebook_url" target="_blank" rel="noopener">{{ t('facebook') }}</a></p></div><div class="mt-5 grid gap-3 md:grid-cols-2"><section :id="`festival-tapa-${tapa.id}`" v-for="tapa in tapasFor(venue.id)" :key="tapa.id" class="rounded-lg bg-stone-50 p-2 transition sm:p-4" :class="highlightedTapaId === tapa.id ? 'ring-2 ring-emerald-500 ring-offset-2' : ''"><img v-if="tapaPhotoUrl(tapa)" :src="tapaPhotoUrl(tapa)" :alt="text(tapa.name_en, tapa.name_es)" class="mb-3 h-44 w-full rounded-md object-cover" loading="lazy"><div class="flex items-start justify-between gap-2"><div class="flex min-w-0 items-start gap-2"><button type="button" class="mt-0.5 shrink-0 text-xl leading-none text-amber-500 transition hover:scale-110 focus-visible:ring-2 focus-visible:ring-emerald-700" :class="wantsToTry(tapa.id) ? 'text-amber-500' : 'text-stone-400'" :aria-pressed="wantsToTry(tapa.id)" :aria-label="wantsToTry(tapa.id) ? t('removeWantToTry') : t('wantToTry')" :title="wantsToTry(tapa.id) ? t('removeWantToTry') : t('wantToTry')" @click.stop="toggleWantedTapa(tapa.id)">{{ wantsToTry(tapa.id) ? '★' : '☆' }}</button><h3 class="font-bold">{{ tapa.festival_number ? `${tapa.festival_number}. ` : '' }}{{ text(tapa.name_en, tapa.name_es) }}</h3></div></div><p v-if="tapa.participation_status === 'withdrawn'" class="mt-1 text-sm font-semibold text-red-700">{{ t('withdrawn') }}</p><div class="mt-2 min-h-[5rem] text-sm text-stone-600 md:line-clamp-4"><p v-if="text(tapa.description_en, tapa.description_es)">{{ text(tapa.description_en, tapa.description_es) }}</p></div><div class="mt-4 border-t border-stone-200 pt-4 text-sm"><p class="text-stone-700"><strong>{{ t('publicRating') }} {{ summaryFor(tapa.id).average_rating == null ? t('unrated') : Number(summaryFor(tapa.id).average_rating).toFixed(1) }} ★</strong> · {{ summaryFor(tapa.id).rating_count }} {{ t('ratings') }}<span v-if="summaryFor(tapa.id).good_excellent_percentage != null"> · {{ Number(summaryFor(tapa.id).good_excellent_percentage).toFixed(0) }}% {{ t('goodExcellent') }}</span></p><template v-if="tapa.participation_status === 'active'"><div class="mt-4 rounded-lg border-2 border-emerald-200 bg-white p-3"><p v-if="!user" class="text-stone-600">{{ t('chooseStars') }} <button type="button" class="font-semibold text-emerald-700 underline" @click="openAuth('signin')">{{ t('signInToRate') }}</button>.</p><template v-else><p class="font-bold text-emerald-950">{{ t('rateThisTapa') }}</p><div class="mt-2 flex min-w-0 items-center gap-2" :aria-label="`${t('rateThisTapa')}: ${text(tapa.name_en, tapa.name_es)}`"><span class="shrink-0 text-xs tabular-nums text-stone-500">1.0</span><input class="min-w-0 flex-1" :class="hasRatingSelection(tapaRatingDrafts, tapa.id, myReviews[tapa.id]?.rating) ? 'accent-emerald-700' : 'accent-stone-400 opacity-70'" type="range" min="1" max="5" step="0.1" :value="ratingDraft(tapaRatingDrafts, tapa.id, myReviews[tapa.id]?.rating)" :disabled="ratingBusy === tapa.id" :aria-label="`${t('rateThisTapa')}: ${text(tapa.name_en, tapa.name_es)}`" @input="setRatingDraft(tapaRatingDrafts, tapa.id, ratingInputValue($event))" @change="rate(tapa, Number(tapaRatingDrafts[tapa.id] ?? myReviews[tapa.id]?.rating ?? 3))"><span class="shrink-0 text-xs tabular-nums text-stone-500">5.0</span><span class="shrink-0 text-sm font-semibold tabular-nums">{{ ratingLabel(tapaRatingDrafts, tapa.id, myReviews[tapa.id]?.rating) }}</span></div><p class="mt-1 text-xs text-stone-600"><strong>{{ t('yourRating') }}</strong> {{ myReviews[tapa.id] ? `${Number(myReviews[tapa.id].rating).toFixed(1)} ★` : t('notRatedYet') }}</p><label class="mt-4 block font-semibold text-stone-800">{{ t('yourReview') }} · {{ myReviews[tapa.id]?.review_text ? t('editReview') : t('writeReview') }}<textarea v-model="reviewDrafts[tapa.id]" class="mt-1 min-h-24 w-full rounded border border-stone-300 p-2 font-normal" :maxlength="maxReviewLength" :placeholder="t('writeReview')" :disabled="ratingBusy === tapa.id" /><span class="mt-1 block text-right text-xs font-normal text-stone-500">{{ (reviewDrafts[tapa.id] || '').length }} / {{ maxReviewLength }}</span></label><button type="button" class="mt-2 rounded bg-emerald-700 px-3 py-2 font-semibold text-white disabled:opacity-50" :disabled="ratingBusy === tapa.id" @click="saveReview(tapa)">{{ t('saveReview') }}</button><button v-if="myReviews[tapa.id]" type="button" class="mt-3 ml-2 rounded border border-red-300 px-3 py-2 text-xs font-semibold text-red-700 hover:bg-red-50" :disabled="ratingBusy === tapa.id" @click="removeRating(tapa)">{{ t('removeRating') }}</button></template></div></template><div class="mt-4"><div class="flex items-center justify-between gap-2"><p class="font-semibold text-stone-800">{{ t('reviews') }}</p><button v-if="reviewsFor(tapa.id).length > 3" type="button" class="text-xs font-semibold text-emerald-700 underline" @click="reviewsExpanded[tapa.id] = !reviewsExpanded[tapa.id]">{{ reviewsExpanded[tapa.id] ? t('hideReviews') : t('showReviews') }} ({{ reviewsFor(tapa.id).length }})</button></div><p v-if="!reviewsFor(tapa.id).length" class="mt-1 text-stone-500">{{ t('noReviewsYet') }}</p><ol v-else class="mt-2 space-y-2"><li v-for="review in shownReviewsFor(tapa.id)" :key="review.id" class="rounded bg-white p-2 text-stone-700"><p class="text-xs font-semibold text-stone-500">{{ t('festivalVisitor') }} · {{ review.rating }} ★ · {{ formatReviewDate(review.created_at) }}</p><p class="mt-1 whitespace-pre-wrap">{{ review.review_text }}</p></li></ol></div></div></section></div></div></article></div>
          </div>
        </div>
        <section class="mx-4 mt-6 rounded-xl border border-stone-200 bg-white p-4 text-sm text-stone-600 sm:mx-0">
          <h2 class="font-display text-lg font-bold text-stone-900">{{ t('festivalInformation') }}</h2>
          <p v-if="showRankings" class="mt-2 text-xs text-stone-500">{{ t('rankingDescription') }}</p><dl class="mt-2 grid gap-1"><div><dt class="inline font-semibold text-stone-800">{{ t('location') }}</dt><dd class="inline"> {{ festival.city }}</dd></div></dl>
        </section>
        <footer class="mx-4 mt-6 pb-4 text-center sm:mx-0"><button type="button" class="text-xs font-semibold text-emerald-700 underline" @click="reportOpen = true">{{ t('reportProblem') }}</button><p class="mt-2 text-[10px] text-stone-400">Version: {{ buildReference }}</p></footer>
        <div v-if="reportOpen" class="fixed inset-0 z-50 flex items-center justify-center bg-stone-950/40 p-4" role="dialog" aria-modal="true" :aria-label="t('reportProblemTitle')" @click.self="reportOpen = false"><form class="w-full max-w-sm rounded-xl bg-white p-4 shadow-xl" @submit.prevent="submitProblemReport"><div class="flex items-center justify-between gap-3"><h2 class="font-display text-lg font-bold">{{ t('reportProblemTitle') }}</h2><button type="button" class="text-xl text-stone-500" aria-label="Close" @click="reportOpen = false">×</button></div><p class="mt-2 text-xs text-stone-600">{{ t('reportHint') }}</p><label class="mt-3 block text-sm font-semibold">{{ t('contactEmailOptional') }}<input v-model="reportEmail" class="mt-1 w-full rounded border border-stone-300 p-2 font-normal" type="email" autocomplete="email"></label><label class="mt-3 block text-sm font-semibold">{{ t('problemDescription') }}<textarea v-model="reportDescription" class="mt-1 min-h-28 w-full rounded border border-stone-300 p-2 font-normal" required></textarea></label><div class="mt-4 flex justify-end gap-2"><button type="button" class="rounded border px-3 py-2 text-sm" @click="reportOpen = false">×</button><button class="rounded bg-emerald-700 px-3 py-2 text-sm font-bold text-white">{{ t('sendReport') }}</button></div></form></div>
      </template>
    </section>
  </main>
</template>

<style scoped>
.bar-rating-slider {
  appearance: none;
  height: 0.55rem;
  border-radius: 9999px;
  background: #d6d3d1;
  cursor: pointer;
}
.bar-rating-slider::-webkit-slider-thumb {
  appearance: none;
  width: 1.15rem;
  height: 1.15rem;
  border-radius: 9999px;
  border: 2px solid #a8a29e;
  background: #d6d3d1;
  box-shadow: none;
}
.bar-rating-slider::-moz-range-track { height: 0.55rem; border-radius: 9999px; background: #d6d3d1; }
.bar-rating-slider::-moz-range-thumb { width: 1.15rem; height: 1.15rem; border: 2px solid #a8a29e; border-radius: 9999px; background: #d6d3d1; box-shadow: none; }
.bar-rating-slider--unrated { opacity: 0.42; filter: grayscale(1); }
.bar-rating-slider--rated { background: #a7f3d0; }
.bar-rating-slider--rated::-webkit-slider-thumb { border-color: #065f46; background: #047857; box-shadow: 0 1px 3px rgb(6 95 70 / 0.45); }
.bar-rating-slider--rated::-moz-range-track { background: #a7f3d0; }
.bar-rating-slider--rated::-moz-range-thumb { border-color: #065f46; background: #047857; box-shadow: 0 1px 3px rgb(6 95 70 / 0.45); }
.bar-rating-slider:focus-visible { outline: 2px solid #047857; outline-offset: 3px; }
.bar-rating-slider:disabled { cursor: wait; }
.ranking-ticker-track {
  display: inline-flex;
  gap: 1.5rem;
  width: max-content;
  animation: ranking-ticker 10s linear infinite alternate;
}
@keyframes ranking-ticker {
  from { transform: translateX(0); }
  to { transform: translateX(-45%); }
}
@media (prefers-reduced-motion: reduce) {
  .ranking-ticker-track { animation: none; }
}
</style>
