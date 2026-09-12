<script setup lang="ts">
type Festival = any;
type Establishment = any;
type Tapa = any;

const supabase = useSupabaseClient<any>() as any;
const loading = ref(true);
const error = ref('');
const festival = ref<Festival | null>(null);
const establishments = ref<Establishment[]>([]);
const tapas = ref<Tapa[]>([]);

const db = () => supabase.schema('festival');
const tapasFor = (establishmentId: string) => tapas.value.filter((tapa) => tapa.establishment_id === establishmentId);
const priceFor = (tapa: Tapa) => tapa.price_override ?? festival.value?.default_tapa_price;
const text = (english?: string | null, spanish?: string | null) => english || spanish || '';
const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

function formatHours(hours: unknown) {
  if (!hours || typeof hours !== 'object' || Array.isArray(hours)) return '';
  return Object.entries(hours as Record<string, unknown>)
    .map(([day, periods]) => {
      const label = weekdays[Number(day) - 1] || day;
      if (!Array.isArray(periods) || periods.length === 0) return `${label}: closed`;
      const times = periods.map((period: any) => Array.isArray(period) ? `${period[0]}–${period[1]}` : '').filter(Boolean).join(', ');
      return times ? `${label}: ${times}` : '';
    })
    .filter(Boolean)
    .join(' · ');
}

async function loadFestival() {
  loading.value = true;
  error.value = '';
  const { data: festivals, error: festivalError } = await db().from('festivals')
    .select('*').eq('publication_status', 'published').order('start_date', { ascending: false }).limit(1);
  if (festivalError) { error.value = festivalError.message; loading.value = false; return; }
  festival.value = festivals?.[0] ?? null;
  if (!festival.value) { loading.value = false; return; }
  const { data: venueRows, error: venueError } = await db().from('establishments')
    .select('*').eq('festival_id', festival.value.id).order('sort_order').order('name');
  if (venueError) { error.value = venueError.message; loading.value = false; return; }
  establishments.value = venueRows || [];
  const ids = establishments.value.map((venue) => venue.id);
  if (ids.length) {
    const { data: tapaRows, error: tapaError } = await db().from('tapas')
      .select('*').in('establishment_id', ids).order('sort_order').order('festival_number');
    if (tapaError) error.value = tapaError.message;
    else tapas.value = tapaRows || [];
  }
  loading.value = false;
}

onMounted(loadFestival);
</script>

<template>
  <main id="main-content" class="min-h-screen bg-stone-50 text-stone-900" tabindex="-1">
    <header class="border-b border-stone-200 bg-white">
      <div class="mx-auto max-w-6xl px-5 py-8 md:px-8"><p class="text-sm font-semibold uppercase tracking-widest text-emerald-700">tapas-festival</p><h1 class="mt-2 font-display text-4xl font-bold">{{ festival ? text(festival.name_en, festival.name_es) : 'Tapas festival' }}</h1><p v-if="festival && text(festival.description_en, festival.description_es)" class="mt-3 max-w-3xl text-stone-600">{{ text(festival.description_en, festival.description_es) }}</p></div>
    </header>
    <section class="mx-auto max-w-6xl px-5 py-8 md:px-8">
      <p v-if="loading" class="text-stone-600">Loading festival…</p>
      <p v-else-if="error" class="rounded-lg border border-red-200 bg-red-50 p-4 text-red-800">Unable to load festival data: {{ error }}</p>
      <p v-else-if="!festival" class="rounded-lg border border-stone-200 bg-white p-5 text-stone-600">No published festival is available yet.</p>
      <template v-else>
        <div class="mb-6 flex flex-wrap gap-4 text-sm text-stone-600"><span>{{ festival.city }}</span><span>{{ festival.start_date }} – {{ festival.end_date }}</span><span>Standard tapa price: {{ festival.currency_code }} {{ festival.default_tapa_price }}</span></div>
        <div class="space-y-6"><article v-for="venue in establishments" :key="venue.id" class="rounded-xl border border-stone-200 bg-white p-5 shadow-sm"><div class="flex flex-wrap items-start justify-between gap-3"><div><h2 class="font-display text-2xl font-bold">{{ venue.name }}</h2><p v-if="venue.participation_status === 'withdrawn'" class="mt-1 text-sm font-semibold text-red-700">Withdrawn</p><p v-else-if="venue.closure_status !== 'normal'" class="mt-1 text-sm font-semibold text-stone-600">{{ venue.closure_status.replaceAll('_', ' ') }}</p></div><span class="rounded-full bg-stone-100 px-3 py-1 text-xs font-semibold">{{ tapasFor(venue.id).length }} tapas</span></div><p v-if="text(venue.description_en, venue.description_es)" class="mt-3 text-stone-700">{{ text(venue.description_en, venue.description_es) }}</p><div class="mt-4 grid gap-2 text-sm text-stone-600"><p v-if="venue.address">{{ venue.address }}</p><p v-if="text(venue.hours_notes_en, venue.hours_notes_es)"><strong>Opening hours:</strong> {{ text(venue.hours_notes_en, venue.hours_notes_es) }}</p><p v-else-if="formatHours(venue.opening_hours)"><strong>Opening hours:</strong> {{ formatHours(venue.opening_hours) }}</p><p v-if="venue.phone"><strong>Phone:</strong> {{ venue.phone }}</p><p v-if="venue.whatsapp"><strong>WhatsApp:</strong> {{ venue.whatsapp }}</p><p v-if="venue.website_url"><a class="text-emerald-700 underline" :href="venue.website_url" target="_blank" rel="noopener">Website</a><span v-if="venue.facebook_url"> · </span></p><p v-if="venue.facebook_url"><a class="text-emerald-700 underline" :href="venue.facebook_url" target="_blank" rel="noopener">Facebook</a></p></div><div class="mt-5 grid gap-3 md:grid-cols-2"><section v-for="tapa in tapasFor(venue.id)" :key="tapa.id" class="rounded-lg bg-stone-50 p-4"><div class="flex justify-between gap-3"><h3 class="font-bold">{{ tapa.festival_number ? `${tapa.festival_number}. ` : '' }}{{ text(tapa.name_en, tapa.name_es) }}</h3><span class="whitespace-nowrap font-semibold">{{ festival.currency_code }} {{ priceFor(tapa) }}</span></div><p v-if="tapa.participation_status === 'withdrawn'" class="mt-1 text-sm font-semibold text-red-700">Withdrawn</p><p v-if="text(tapa.description_en, tapa.description_es)" class="mt-2 text-sm text-stone-600">{{ text(tapa.description_en, tapa.description_es) }}</p></section></div></article></div>
      </template>
    </section>
  </main>
</template>
