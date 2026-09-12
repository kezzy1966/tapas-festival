<script setup lang="ts">
type Tab = 'festivals' | 'establishments' | 'tapas';

const supabase = useSupabaseClient<any>() as any;
const user = useSupabaseUser();
const tab = ref<Tab>('festivals');
const loading = ref(false);
const checkingAccess = ref(false);
const isAdmin = ref(false);
const saving = ref(false);
const error = ref('');
const notice = ref('');
const email = ref('');
const password = ref('');
const authMode = ref<'login' | 'signup'>('login');
const authBusy = ref(false);
const festivals = ref<any[]>([]);
const establishments = ref<any[]>([]);
const tapas = ref<any[]>([]);
const editingFestival = ref<any | null>(null);
const editingEstablishment = ref<any | null>(null);
const editingTapa = ref<any | null>(null);
const slugManuallyEdited = ref(false);
const fieldDefinitions = ref<any[]>([]);
const fieldValues = ref<any[]>([]);

const blankFestival = () => ({ name_en: '', name_es: '', slug: '', start_date: '', end_date: '', city: '', default_tapa_price: '5.00', publication_status: 'draft', reviews_enabled: true, show_rankings: true });
const blankEstablishment = () => ({ festival_id: '', name: '', description_en: '', description_es: '', address: '', coordinates: '', phone: '', instagram: '', whatsapp: '', facebook_url: '', website_url: '', hours_notes_en: '', hours_notes_es: '', is_published: false, participation_status: 'active', closure_status: 'normal' });
const blankTapa = () => ({ establishment_id: '', name_en: '', name_es: '', description_en: '', description_es: '', price_override: '', photo_path: '', festival_number: '', is_published: false, participation_status: 'active' });
const festivalForm = ref(blankFestival());
const establishmentForm = ref(blankEstablishment());
const tapaForm = ref(blankTapa());

const db = () => supabase.schema('festival');
const valueOrNull = (value: string) => value.trim() || null;
const numberOrNull = (value: string) => value === '' ? null : Number(value);

async function load() {
  if (!user.value) return;
  loading.value = true;
  error.value = '';
  const [festivalResult, establishmentResult, tapaResult, fieldDefinitionResult, fieldValueResult] = await Promise.all([
    db().from('festivals').select('*').order('start_date', { ascending: false }),
    db().from('establishments').select('*').order('name'),
    db().from('tapas').select('*').order('festival_number', { ascending: true, nullsFirst: false }),
    db().from('field_definitions').select('*').eq('applies_to', 'establishment').eq('key', 'instagram'),
    db().from('field_values').select('*'),
  ]);
  const firstError = festivalResult.error || establishmentResult.error || tapaResult.error || fieldDefinitionResult.error || fieldValueResult.error;
  if (firstError) error.value = firstError.message;
  festivals.value = festivalResult.data || [];
  establishments.value = establishmentResult.data || [];
  tapas.value = tapaResult.data || [];
  fieldDefinitions.value = fieldDefinitionResult.data || [];
  fieldValues.value = fieldValueResult.data || [];
  loading.value = false;
}

async function checkAccess() {
  isAdmin.value = false;
  if (!user.value) return;
  checkingAccess.value = true;
  error.value = '';
  const { data, error: rpcError } = await db().rpc('is_current_admin');
  if (rpcError) error.value = rpcError.message;
  else isAdmin.value = data === true;
  checkingAccess.value = false;
  if (isAdmin.value) await load();
}

function validateCredentials() {
  const validEmail = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.value.trim());
  if (!validEmail) { error.value = 'Enter a valid email address.'; return false; }
  if (password.value.length < 8) { error.value = 'Password must be at least 8 characters.'; return false; }
  return true;
}

async function login() {
  error.value = ''; notice.value = '';
  if (!validateCredentials()) return;
  authBusy.value = true;
  const { error: authError } = await supabase.auth.signInWithPassword({ email: email.value.trim(), password: password.value });
  authBusy.value = false;
  if (authError) error.value = authError.message;
}

async function signup() {
  error.value = ''; notice.value = '';
  if (!validateCredentials()) return;
  authBusy.value = true;
  const { data, error: authError } = await supabase.auth.signUp({ email: email.value.trim(), password: password.value });
  authBusy.value = false;
  if (authError) { error.value = authError.message; return; }
  notice.value = data.session
    ? 'Account created and signed in. This account still needs administrator appointment before it can manage festival data.'
    : 'Account created. Check your email to confirm the account, then sign in. This account still needs administrator appointment before it can manage festival data.';
  password.value = '';
}


async function logout() { await supabase.auth.signOut(); }
function resetFestival() { editingFestival.value = null; slugManuallyEdited.value = false; festivalForm.value = blankFestival(); }
function slugify(value: string) {
  return value.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().trim()
    .replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '');
}
function updateGeneratedSlug() {
  if (!slugManuallyEdited.value) festivalForm.value.slug = slugify(festivalForm.value.name_en);
}
function markSlugManual() { slugManuallyEdited.value = true; }
function resetEstablishment() { editingEstablishment.value = null; establishmentForm.value = blankEstablishment(); }
function resetTapa() { editingTapa.value = null; tapaForm.value = blankTapa(); }
function editFestival(row: any) { editingFestival.value = row; slugManuallyEdited.value = true; festivalForm.value = { ...row, default_tapa_price: String(row.default_tapa_price), show_rankings: row.show_rankings !== false }; tab.value = 'festivals'; }
function instagramFor(establishmentId: string) {
  const definition = fieldDefinitions.value.find((item) => item.festival_id === establishments.value.find((venue) => venue.id === establishmentId)?.festival_id);
  const value = definition && fieldValues.value.find((item) => item.field_definition_id === definition.id && item.establishment_id === establishmentId)?.value;
  return typeof value?.en === 'string' ? value.en : '';
}
function editEstablishment(row: any) { editingEstablishment.value = row; establishmentForm.value = { ...blankEstablishment(), ...row, instagram: instagramFor(row.id), coordinates: row.latitude == null || row.longitude == null ? '' : `${row.latitude}, ${row.longitude}` }; tab.value = 'establishments'; }
function editTapa(row: any) { editingTapa.value = row; tapaForm.value = { ...blankTapa(), ...row, price_override: row.price_override == null ? '' : String(row.price_override), festival_number: row.festival_number == null ? '' : String(row.festival_number) }; tab.value = 'tapas'; }

async function saveFestival() {
  saving.value = true; error.value = ''; notice.value = '';
  const payload = { ...festivalForm.value, name_es: valueOrNull(festivalForm.value.name_es), city: festivalForm.value.city.trim(), default_tapa_price: Number(festivalForm.value.default_tapa_price) };
  const result = editingFestival.value ? await db().from('festivals').update(payload).eq('id', editingFestival.value.id) : await db().from('festivals').insert(payload);
  saving.value = false;
  if (result.error) error.value = result.error.message; else { notice.value = 'Festival saved.'; resetFestival(); await load(); }
}
function parseCoordinates(value: string) {
  const cleaned = value.trim();
  if (!cleaned) return { latitude: null, longitude: null };
  const parts = cleaned.split(',').map((part) => part.trim());
  if (parts.length !== 2 || !parts[0] || !parts[1]) return { error: 'Enter Google Maps coordinates as latitude, longitude.' };
  const latitude = Number(parts[0]);
  const longitude = Number(parts[1]);
  if (!Number.isFinite(latitude) || latitude < -90 || latitude > 90) return { error: 'Latitude must be a number between -90 and 90.' };
  if (!Number.isFinite(longitude) || longitude < -180 || longitude > 180) return { error: 'Longitude must be a number between -180 and 180.' };
  return { latitude, longitude };
}
async function saveEstablishment() {
  saving.value = true; error.value = ''; notice.value = '';
  const f = establishmentForm.value;
  const coordinates = parseCoordinates(f.coordinates);
  if ('error' in coordinates) { error.value = coordinates.error; saving.value = false; return; }
  const { coordinates: _coordinates, instagram: _instagram, ...formValues } = f;
  const payload = { ...formValues, description_en: valueOrNull(f.description_en), description_es: valueOrNull(f.description_es), address: valueOrNull(f.address), latitude: coordinates.latitude, longitude: coordinates.longitude, phone: valueOrNull(f.phone), whatsapp: valueOrNull(f.whatsapp), facebook_url: valueOrNull(f.facebook_url), website_url: valueOrNull(f.website_url), hours_notes_en: valueOrNull(f.hours_notes_en), hours_notes_es: valueOrNull(f.hours_notes_es) };
  const result = editingEstablishment.value
    ? await db().from('establishments').update(payload).eq('id', editingEstablishment.value.id).select().single()
    : await db().from('establishments').insert(payload).select().single();
  if (result.error || !result.data) { saving.value = false; error.value = result.error?.message || 'Unable to save establishment.'; return; }
  const instagram = valueOrNull(f.instagram);
  if (instagram) {
    let definition = fieldDefinitions.value.find((item) => item.festival_id === result.data.festival_id);
    if (!definition) {
      const definitionResult = await db().from('field_definitions').insert({ festival_id: result.data.festival_id, key: 'instagram', label_en: 'Instagram', label_es: 'Instagram', field_type: 'text', applies_to: 'establishment', required: false, active: true, sort_order: 0 }).select().single();
      if (definitionResult.error || !definitionResult.data) { saving.value = false; error.value = definitionResult.error?.message || 'Unable to create the Instagram field.'; return; }
      definition = definitionResult.data;
    }
    const existingValue = fieldValues.value.find((item) => item.field_definition_id === definition.id && item.establishment_id === result.data.id);
    const instagramResult = existingValue
      ? await db().from('field_values').update({ value: { en: instagram } }).eq('id', existingValue.id)
      : await db().from('field_values').insert({ field_definition_id: definition.id, establishment_id: result.data.id, value: { en: instagram } });
    if (instagramResult.error) { saving.value = false; error.value = instagramResult.error.message; return; }
  }
  saving.value = false;
  notice.value = 'Establishment saved.'; resetEstablishment(); await load();
}
async function saveTapa() {
  saving.value = true; error.value = ''; notice.value = '';
  const f = tapaForm.value;
  if (!valueOrNull(f.name_es) && !valueOrNull(f.name_en)) { saving.value = false; error.value = 'Enter a Spanish or English tapa name.'; return; }
  const festivalId = establishments.value.find((venue) => venue.id === f.establishment_id)?.festival_id;
  const programmeNumber = numberOrNull(f.festival_number);
  const duplicate = programmeNumber != null && tapas.value.find((item) => item.id !== editingTapa.value?.id && item.festival_number === programmeNumber && establishments.value.find((venue) => venue.id === item.establishment_id)?.festival_id === festivalId);
  if (duplicate) { saving.value = false; error.value = `Programme number ${programmeNumber} is already used in this festival.`; return; }
  const payload = { ...f, name_en: valueOrNull(f.name_en), name_es: valueOrNull(f.name_es), description_en: valueOrNull(f.description_en), description_es: valueOrNull(f.description_es), photo_path: valueOrNull(f.photo_path), price_override: numberOrNull(f.price_override), festival_number: programmeNumber };
  const result = editingTapa.value ? await db().from('tapas').update(payload).eq('id', editingTapa.value.id) : await db().from('tapas').insert(payload);
  saving.value = false;
  if (result.error) error.value = result.error.message; else { notice.value = 'Tapa saved.'; resetTapa(); await load(); }
}

watch(user, checkAccess, { immediate: true });
</script>

<template>
  <main class="min-h-screen bg-stone-50 p-5 text-stone-900 md:p-10">
    <div class="mx-auto max-w-7xl">
      <header class="mb-8 flex flex-wrap items-center justify-between gap-4">
        <div><p class="text-sm font-semibold text-emerald-700">tapas-festival</p><h1 class="font-display text-3xl font-bold">Admin</h1></div>
        <button v-if="user" class="rounded-lg border border-stone-300 px-3 py-2 text-sm" @click="logout">Log out</button>
      </header>

      <section v-if="!user" class="mx-auto max-w-md rounded-xl border border-stone-200 bg-white p-6 shadow-sm">
        <h2 class="text-xl font-bold">Admin access</h2><p class="mt-1 text-sm text-stone-600">Sign in, or create the first development account.</p>
        <div class="mt-4 flex gap-2 border-b border-stone-200"><button type="button" class="border-b-2 px-3 py-2 text-sm font-semibold" :class="authMode === 'login' ? 'border-emerald-700 text-emerald-800' : 'border-transparent text-stone-500'" @click="authMode = 'login'; error = ''; notice = ''">Sign in</button><button type="button" class="border-b-2 px-3 py-2 text-sm font-semibold" :class="authMode === 'signup' ? 'border-emerald-700 text-emerald-800' : 'border-transparent text-stone-500'" @click="authMode = 'signup'; error = ''; notice = ''">Create account</button></div>
        <p v-if="error" class="mt-4 rounded border border-red-200 bg-red-50 p-3 text-sm text-red-800">{{ error }}</p><p v-if="notice" class="mt-4 rounded border border-emerald-200 bg-emerald-50 p-3 text-sm text-emerald-800">{{ notice }}</p>
        <form class="mt-5 space-y-3" @submit.prevent="authMode === 'login' ? login() : signup()"><input v-model="email" class="w-full rounded border p-2" type="email" autocomplete="email" placeholder="Email" required><input v-model="password" class="w-full rounded border p-2" type="password" autocomplete="current-password" placeholder="Password (8+ characters)" minlength="8" required><button class="w-full rounded bg-emerald-700 px-3 py-2 font-semibold text-white disabled:opacity-50" :disabled="authBusy">{{ authBusy ? 'Please wait…' : authMode === 'login' ? 'Log in' : 'Create account' }}</button></form>
      </section>

      <section v-else-if="checkingAccess" class="rounded-xl border border-stone-200 bg-white p-6 text-sm text-stone-600">Checking administrator access…</section>
      <section v-else-if="!isAdmin" class="rounded-xl border border-red-200 bg-red-50 p-6"><h2 class="text-xl font-bold text-red-900">Access denied</h2><p class="mt-1 text-sm text-red-800">This account is not an administrator.</p></section>
      <template v-else>
        <p v-if="error" class="mb-4 rounded border border-red-200 bg-red-50 p-3 text-sm text-red-800">{{ error }}</p>
        <p v-if="notice" class="mb-4 rounded border border-emerald-200 bg-emerald-50 p-3 text-sm text-emerald-800">{{ notice }}</p>
        <nav class="mb-6 flex gap-2 border-b border-stone-200"><button v-for="item in ['festivals','establishments','tapas'] as Tab[]" :key="item" class="border-b-2 px-4 py-3 text-sm font-semibold capitalize" :class="tab === item ? 'border-emerald-700 text-emerald-800' : 'border-transparent text-stone-500'" @click="tab=item">{{ item }}</button></nav>
        <p v-if="loading" class="text-sm text-stone-500">Loading…</p>

        <section v-if="tab === 'festivals'" class="grid gap-8 lg:grid-cols-[minmax(0,1fr)_380px]"><div><h2 class="mb-3 text-xl font-bold">Festivals</h2><div class="overflow-x-auto rounded-xl border bg-white"><table class="w-full text-left text-sm"><thead class="bg-stone-100"><tr><th class="p-3">Name</th><th class="p-3">Dates</th><th class="p-3">Status</th><th class="p-3"></th></tr></thead><tbody><tr v-for="row in festivals" :key="row.id" class="border-t"><td class="p-3">{{ row.name_en || row.name_es }}</td><td class="p-3">{{ row.start_date }} – {{ row.end_date }}</td><td class="p-3">{{ row.publication_status }}</td><td class="p-3"><button class="text-emerald-700" @click="editFestival(row)">Edit</button></td></tr></tbody></table></div></div><form class="space-y-3 rounded-xl border bg-white p-5" @submit.prevent="saveFestival"><h2 class="text-lg font-bold">{{ editingFestival ? 'Edit festival' : 'New festival' }}</h2><input v-model="festivalForm.name_en" class="w-full rounded border p-2" placeholder="English name" required @input="updateGeneratedSlug"><input v-model="festivalForm.name_es" class="w-full rounded border p-2" placeholder="Spanish name"><input v-model="festivalForm.slug" class="w-full rounded border p-2" placeholder="slug" required @input="markSlugManual"><div class="grid grid-cols-2 gap-2"><input v-model="festivalForm.start_date" class="rounded border p-2" type="date" required><input v-model="festivalForm.end_date" class="rounded border p-2" type="date" required></div><input v-model="festivalForm.city" class="w-full rounded border p-2" placeholder="City" required><input v-model="festivalForm.default_tapa_price" class="w-full rounded border p-2" type="number" min="0" step="0.01" placeholder="Default price" required><select v-model="festivalForm.publication_status" class="w-full rounded border p-2"><option value="draft">Draft</option><option value="published">Published</option><option value="archived">Archived</option></select><label class="flex gap-2 text-sm"><input v-model="festivalForm.reviews_enabled" type="checkbox"> Reviews enabled</label><label class="flex gap-2 text-sm"><input v-model="festivalForm.show_rankings" type="checkbox"> Show rankings</label><div class="flex gap-2"><button class="rounded bg-emerald-700 px-3 py-2 text-white" :disabled="saving">Save</button><button type="button" class="rounded border px-3 py-2" @click="resetFestival">Clear</button></div></form></section>

        <section v-if="tab === 'establishments'" class="grid gap-8 lg:grid-cols-[minmax(0,1fr)_440px]">
          <div><h2 class="mb-3 text-xl font-bold">Establishments</h2><div class="overflow-x-auto rounded-xl border bg-white"><table class="w-full text-left text-sm"><thead class="bg-stone-100"><tr><th class="p-3">Name</th><th class="p-3">Festival</th><th class="p-3">Status</th><th class="p-3"></th></tr></thead><tbody><tr v-for="row in establishments" :key="row.id" class="border-t"><td class="p-3">{{ row.name }}</td><td class="p-3">{{ festivals.find(f => f.id === row.festival_id)?.name_en || '—' }}</td><td class="p-3">{{ row.participation_status }}</td><td class="p-3"><button class="text-emerald-700" @click="editEstablishment(row)">Edit</button></td></tr></tbody></table></div></div>
          <form class="space-y-4 rounded-xl border bg-white p-5" @submit.prevent="saveEstablishment">
            <h2 class="text-lg font-bold">{{ editingEstablishment ? 'Edit establishment' : 'New establishment' }}</h2>
            <select v-model="establishmentForm.festival_id" class="w-full rounded border p-2" required><option value="" disabled>Festival</option><option v-for="f in festivals" :key="f.id" :value="f.id">{{ f.name_en || f.name_es }}</option></select>
            <div class="grid gap-3 sm:grid-cols-2"><input v-model="establishmentForm.name" class="rounded border p-2 sm:col-span-2" placeholder="Name" required><input v-model="establishmentForm.address" class="rounded border p-2 sm:col-span-2" placeholder="Address"><label class="block text-sm font-medium text-stone-700 sm:col-span-2">Google Maps coordinates<input v-model="establishmentForm.coordinates" class="mt-1 w-full rounded border p-2 font-mono text-sm" type="text" inputmode="decimal" placeholder="39.979579659748154, -0.030992736520370705"></label><input v-model="establishmentForm.phone" class="rounded border p-2" placeholder="Phone"><input v-model="establishmentForm.instagram" class="rounded border p-2" placeholder="Instagram"><input v-model="establishmentForm.facebook_url" class="rounded border p-2" placeholder="Facebook URL"><input v-model="establishmentForm.whatsapp" class="rounded border p-2" placeholder="WhatsApp"><input v-model="establishmentForm.website_url" class="rounded border p-2 sm:col-span-2" placeholder="Website"></div>
            <p class="text-xs text-stone-500">Paste latitude, longitude from Google Maps. Leave blank when no coordinates are available.</p>
            <textarea v-model="establishmentForm.hours_notes_en" class="w-full rounded border p-2" placeholder="Opening-hours notes (English)"/><textarea v-model="establishmentForm.hours_notes_es" class="w-full rounded border p-2" placeholder="Opening-hours notes (Spanish)"/>
            <details class="rounded border border-stone-200 p-3"><summary class="cursor-pointer text-sm font-semibold">Descriptions and closure details</summary><div class="mt-3 space-y-3"><textarea v-model="establishmentForm.description_en" class="w-full rounded border p-2" placeholder="English description"/><textarea v-model="establishmentForm.description_es" class="w-full rounded border p-2" placeholder="Spanish description"/><select v-model="establishmentForm.closure_status" class="w-full rounded border p-2"><option value="normal">Normal</option><option value="temporarily_closed">Temporarily closed</option><option value="permanently_closed">Permanently closed</option></select></div></details>
            <div class="grid gap-3 sm:grid-cols-2"><label class="flex items-center gap-2 text-sm"><input v-model="establishmentForm.is_published" type="checkbox"> Published</label><select v-model="establishmentForm.participation_status" class="rounded border p-2"><option value="active">Active</option><option value="withdrawn">Withdrawn</option></select></div><div class="flex gap-2"><button class="rounded bg-emerald-700 px-3 py-2 text-white" :disabled="saving">Save</button><button type="button" class="rounded border px-3 py-2" @click="resetEstablishment">Clear</button></div>
          </form>
        </section>

        <section v-if="tab === 'tapas'" class="grid gap-8 lg:grid-cols-[minmax(0,1fr)_440px]">
          <div><h2 class="mb-3 text-xl font-bold">Tapas</h2><div class="overflow-x-auto rounded-xl border bg-white"><table class="w-full text-left text-sm"><thead class="bg-stone-100"><tr><th class="p-3">Name</th><th class="p-3">Establishment</th><th class="p-3">Price</th><th class="p-3"></th></tr></thead><tbody><tr v-for="row in tapas" :key="row.id" class="border-t"><td class="p-3">{{ row.name_en || row.name_es }}</td><td class="p-3">{{ establishments.find(e => e.id === row.establishment_id)?.name || '—' }}</td><td class="p-3">{{ row.price_override ?? festivals.find(f => f.id === establishments.find(e => e.id === row.establishment_id)?.festival_id)?.default_tapa_price ?? '—' }}</td><td class="p-3"><button class="text-emerald-700" @click="editTapa(row)">Edit</button></td></tr></tbody></table></div></div>
          <form class="space-y-4 rounded-xl border bg-white p-5" @submit.prevent="saveTapa"><h2 class="text-lg font-bold">{{ editingTapa ? 'Edit tapa' : 'New tapa' }}</h2><select v-model="tapaForm.establishment_id" class="w-full rounded border p-2" required><option value="" disabled>Establishment</option><option v-for="e in establishments" :key="e.id" :value="e.id">{{ e.name }}</option></select><div class="grid gap-3 sm:grid-cols-2"><input v-model="tapaForm.festival_number" class="rounded border p-2" type="number" min="1" placeholder="Programme number"><input v-model="tapaForm.price_override" class="rounded border p-2" type="number" min="0" step="0.01" placeholder="Price override (optional)"><input v-model="tapaForm.name_es" class="rounded border p-2 sm:col-span-2" placeholder="Spanish name"><input v-model="tapaForm.name_en" class="rounded border p-2 sm:col-span-2" placeholder="English name"><textarea v-model="tapaForm.description_es" class="min-h-24 rounded border p-2" placeholder="Spanish description"/><textarea v-model="tapaForm.description_en" class="min-h-24 rounded border p-2" placeholder="English description"/><input v-model="tapaForm.photo_path" class="rounded border p-2 sm:col-span-2" placeholder="Photo path (optional)"></div><p class="text-xs text-stone-500">Leave price blank to use the festival default. The photo path supports the existing Storage workflow.</p><div class="grid gap-3 sm:grid-cols-2"><label class="flex items-center gap-2 text-sm"><input v-model="tapaForm.is_published" type="checkbox"> Published</label><select v-model="tapaForm.participation_status" class="rounded border p-2"><option value="active">Active</option><option value="withdrawn">Withdrawn</option></select></div><div class="flex gap-2"><button class="rounded bg-emerald-700 px-3 py-2 text-white" :disabled="saving">Save</button><button type="button" class="rounded border px-3 py-2" @click="resetTapa">Clear</button></div></form>
        </section>
      </template>
    </div>
  </main>
</template>
