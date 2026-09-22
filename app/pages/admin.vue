<script setup lang="ts">
type Tab = 'dashboard' | 'controls' | 'festivals' | 'establishments' | 'tapas' | 'reports' | 'reviews' | 'users' | 'administrators' | 'resources' | 'photos';
type FestivalControls = { festival_active: boolean; ratings_enabled: boolean; reviews_enabled: boolean; rankings_enabled: boolean; total_rating_counts_enabled: boolean; want_to_try_enabled: boolean; public_read_only: boolean };
type ControlAudit = { created_at: string; administrator: string; control: string; previous_value: boolean; new_value: boolean; festival_id: string | null };
type Administrator = { account_id: string; account: string; role: 'admin' | 'superuser'; added_at: string; status: string };
type RatingActivity = { festival_id: string; user_id?: string; user_label: string; tapa_rating_count: number; bar_rating_count: number; total_rating_count: number; tapa_ratings: Array<{ establishment_name: string; tapa_name: string; rating: number }>; bar_ratings: Array<{ establishment_name: string; rating: number }> };
type RegisteredUser = { account_id: string; account: string; role: 'user' | 'admin' | 'superuser'; registered_at: string; last_festival_activity_at: string | null; tapa_rating_count: number; written_review_count: number; bar_rating_count: number; total_activity_count: number; status: string; suspended_at: string | null; suspension_reason: string | null; total_count: number };
type RegisteredUserActivity = { activity_kind: string; festival_name: string | null; establishment_name: string; tapa_name: string | null; rating: number | null; review_text: string | null; activity_at: string };
type FullAudit = { account_id: string; account: string; email: string; role: 'user' | 'admin' | 'superuser'; created_at: string; updated_at: string; email_confirmed_at: string | null; last_sign_in_at: string | null; providers: string[]; email_password_available: boolean; status: string; last_festival_activity_at: string | null; activity_summary: { tapa_ratings: number; written_reviews: number; bar_ratings: number; total_activity: number }; role_history: Array<{ action: string; previous_role: string | null; new_role: string | null; performed_by: string; performed_by_id?: string; performed_by_email?: string; created_at: string }>; password_reset_history: Array<{ created_at: string; target_role: string; requesting_administrator: string; requesting_admin_id?: string; requesting_administrator_email?: string }>; review_moderation_history: Array<{ review_id: string; action: string; created_at: string; establishment: string; tapa: string; review_text: string | null; moderator_id?: string; moderator_email?: string }>; activity: Array<{ activity_kind: string; establishment: string; tapa: string | null; rating: number | null; review_text: string | null; activity_at: string }> };
type ModeratedReview = { review_id: string; created_at: string; user_id?: string; user_label: string; establishment_name: string; tapa_name: string; rating: number | null; review_text: string; status: 'visible' | 'hidden'; total_count: number };
type DashboardData = { headline: Record<string, number>; content: Record<string, number>; recent_activity: Array<{ time: string; type: string; user: string; user_id?: string; establishment: string; tapa: string | null; rating: number | null }>; most_active_tapas: Array<{ tapa: string; establishment: string; new_ratings: number }> };
type PhotoUploadFeedback = { state: 'idle' | 'selected' | 'processing' | 'success' | 'error'; originalName: string; originalBytes: number; storedBytes: number; path: string; error: string };
const blankPhotoFeedback = (): PhotoUploadFeedback => ({ state: 'idle', originalName: '', originalBytes: 0, storedBytes: 0, path: '', error: '' });

const supabase = useSupabaseClient<any>() as any;
const user = useSupabaseUser();
const tab = ref<Tab>('dashboard');
const dashboardLoading = ref(false);
const dashboardError = ref('');
const dashboard = ref<DashboardData>({ headline: {}, content: {}, recent_activity: [], most_active_tapas: [] });
const resources = ref<any | null>(null);
const resourcesLoading = ref(false);
const resourcesError = ref('');
const loading = ref(false);
const checkingAccess = ref(false);
const isAdmin = ref(false);
const isSuperuser = ref(false);
const canBootstrapInitialSuperuser = ref(false);
const saving = ref(false);
const error = ref('');
const notice = ref('');
const email = ref('');
const password = ref('');
const passwordVisible = ref(false);
const authMode = ref<'login' | 'signup'>('login');
const authBusy = ref(false);
const festivals = ref<any[]>([]);
const establishments = ref<any[]>([]);
const tapas = ref<any[]>([]);
const editingFestival = ref<any | null>(null);
const editingEstablishment = ref<any | null>(null);
const editingTapa = ref<any | null>(null);
const establishmentFormElement = ref<HTMLElement | null>(null);
const tapaFormElement = ref<HTMLElement | null>(null);
const slugManuallyEdited = ref(false);
const fieldDefinitions = ref<any[]>([]);
const fieldValues = ref<any[]>([]);
const reportRows = ref<RatingActivity[]>([]);
const reportLoading = ref(false);
const reportFestivalId = ref('');
const reportUserLabel = ref('');
const reportRatingType = ref<'all' | 'tapa' | 'bar'>('all');
const expandedReportRows = ref<Record<string, boolean>>({});
const administrators = ref<Administrator[]>([]);
const administratorsLoading = ref(false);
const administratorEmail = ref('');
const administratorRole = ref<'admin' | 'superuser'>('admin');
const administratorSaving = ref(false);
const registeredUsers = ref<RegisteredUser[]>([]);
const registeredUsersAll = ref<RegisteredUser[]>([]);
const registeredUsersLoading = ref(false);
const registeredUserQuery = ref('');
type RegisteredUserSort = 'joined_desc' | 'account_asc' | 'account_desc' | 'joined_asc' | 'activity_desc' | 'activity_asc' | 'total_desc' | 'total_asc' | 'suspended_first' | 'active_first';
const registeredUserSort = ref<RegisteredUserSort>('joined_desc');
const registeredUsersPage = ref(0);
const registeredUsersTotal = ref(0);
const promotableRegisteredUserIds = ref<Set<string>>(new Set());
const passwordResetEligibleAccountIds = ref<Set<string>>(new Set());
const fullAuditEligibleAccountIds = ref<Set<string>>(new Set());
const fullAuditAccountId = ref<string | null>(null);
const fullAuditLoading = ref(false);
const fullAudit = ref<FullAudit | null>(null);
const passwordResetAccountId = ref<string | null>(null);
const registeredUserPromotionId = ref<string | null>(null);
const registeredUserSuspensionId = ref<string | null>(null);
const selectedRegisteredUser = ref<RegisteredUser | null>(null);
const registeredUserActivity = ref<RegisteredUserActivity[]>([]);
const registeredUserActivityLoading = ref(false);
const moderatedReviews = ref<ModeratedReview[]>([]);
const moderatedReviewsLoading = ref(false);
const reviewQuery = ref('');
const reviewStatus = ref<'all' | 'visible' | 'hidden'>('all');
const reviewPage = ref(0);
const reviewTotal = ref(0);
const reviewActionId = ref<string | null>(null);
const bootstrapSaving = ref(false);
const controlsFestivalId = ref('');
const controls = ref<FestivalControls | null>(null);
const controlsSiteShutdown = ref(false);
const controlsAudit = ref<ControlAudit[]>([]);
const controlsLoading = ref(false);
const controlsSaving = ref<string | null>(null);
const shutdownConfirmOpen = ref(false);
const shutdownPhrase = ref('');
const establishmentPhotoFile = ref<File | null>(null);
const tapaPhotoFile = ref<File | null>(null);
const establishmentPhotoPreview = ref('');
const tapaPhotoPreview = ref('');
const establishmentPhotoRemoveRequested = ref(false);
const tapaPhotoRemoveRequested = ref(false);
const establishmentPhotoFeedback = ref<PhotoUploadFeedback>(blankPhotoFeedback());
const tapaPhotoFeedback = ref<PhotoUploadFeedback>(blankPhotoFeedback());
const photos = ref<AdminPhoto[]>([]);
const photosLoading = ref(false);
const photosError = ref('');
const photosSort = ref<'newest' | 'oldest' | 'largest' | 'smallest' | 'bar'>('newest');
const photosQuery = ref('');
const PHOTO_BUCKET = 'festival-images';
const PHOTO_MAX_BYTES = 5 * 1024 * 1024;
const PHOTO_MAX_STORED_BYTES = 30 * 1024;
const PHOTO_MAX_DIMENSION = 1600;
const PHOTO_MIME_TYPES = ['image/jpeg', 'image/png', 'image/webp'];
type AdminPhoto = { name: string; created_at: string | null; updated_at: string | null; size_bytes: number; mime_type: string; width: number | null; height: number | null; public_url: string; kind: 'Bar' | 'Tapa' | 'Unidentified'; establishment_name: string | null; tapa_name: string | null; managed: boolean; orphaned: boolean };
type EstablishmentAttentionFilter = "all" | "missing_photos" | "missing_hours";
type EstablishmentSort = "number" | "alphabetical";
type TapaAttentionFilter = "all" | "missing_photos" | "withdrawn";
const establishmentAttentionFilter = ref<EstablishmentAttentionFilter>("all");
const establishmentSort = ref<EstablishmentSort>("number");
const tapaAttentionFilter = ref<TapaAttentionFilter>("all");
type TapaRatingDetail = { programme_number: number | null; establishment_name: string; tapa_name: string; total_rating_count: number; average_rating: number | null; rating_1_19_count: number; rating_2_29_count: number; rating_3_39_count: number; rating_4_44_count: number; rating_45_50_count: number; user_label: string; rating: number | null; review_text: string | null; created_at: string | null };
const detailTapaId = ref("");
const detailRows = ref<TapaRatingDetail[]>([]);
const detailLoading = ref(false);
const detailSort = ref<"newest" | "rating">("newest");
const reportTapas = computed(() => tapas.value.filter((tapa) => !reportFestivalId.value || establishments.value.find((venue) => venue.id === tapa.establishment_id)?.festival_id === reportFestivalId.value));
const sortedDetailRows = computed(() => [...detailRows.value].sort((a, b) => detailSort.value === "rating" ? Number(b.rating ?? -1) - Number(a.rating ?? -1) || String(b.created_at || "").localeCompare(String(a.created_at || "")) : String(b.created_at || "").localeCompare(String(a.created_at || ""))));
function missingPhoto(row: any) { return row?.photo_path == null || String(row.photo_path).trim() === ""; }
function missingOpeningHours(row: any) { const hours = row?.opening_hours; return hours == null || (typeof hours === "object" && !Array.isArray(hours) && Object.keys(hours).length === 0); }
function establishmentNumber(row: any) { const number = Number.parseInt(String(row.name || "").match(/^\s*(\d+)/)?.[1] || "", 10); return Number.isFinite(number) && number > 0 ? number : null; }
const filteredEstablishments = computed(() => establishments.value
  .filter((row) => establishmentAttentionFilter.value === "missing_photos" ? missingPhoto(row) : establishmentAttentionFilter.value === "missing_hours" ? missingOpeningHours(row) : true)
  .slice()
  .sort((a, b) => establishmentSort.value === "alphabetical"
    ? String(a.name).replace(/^\s*\d+\.\s*/, "").localeCompare(String(b.name).replace(/^\s*\d+\.\s*/, ""), undefined, { sensitivity: "base" })
    : (establishmentNumber(a) ?? Number.MAX_SAFE_INTEGER) - (establishmentNumber(b) ?? Number.MAX_SAFE_INTEGER) || String(a.name).localeCompare(String(b.name), undefined, { sensitivity: "base" })));
const filteredTapas = computed(() => tapas.value.filter((row) => tapaAttentionFilter.value === "missing_photos" ? missingPhoto(row) : tapaAttentionFilter.value === "withdrawn" ? row.participation_status === "withdrawn" : true));
const establishmentAttentionLabel = computed(() => establishmentAttentionFilter.value === "missing_photos" ? "Missing photos" : establishmentAttentionFilter.value === "missing_hours" ? "Missing opening hours" : "All bars");
const tapaAttentionLabel = computed(() => tapaAttentionFilter.value === "missing_photos" ? "Missing photos" : tapaAttentionFilter.value === "withdrawn" ? "Withdrawn" : "All tapas");
async function toggleEstablishmentParticipation(row: any) {
  const suspending = row.participation_status !== 'withdrawn';
  if (suspending && !window.confirm('Suspend this bar? It will remain visible but users will not be able to add or change ratings or reviews.')) return;
  saving.value = true; error.value = ''; notice.value = '';
  const { error: updateError } = await db().from('establishments').update({ participation_status: suspending ? 'withdrawn' : 'active' }).eq('id', row.id);
  saving.value = false;
  if (updateError) { error.value = updateError.message; return; }
  notice.value = suspending ? 'Bar suspended.' : 'Bar reactivated.';
  await load();
}
function publicPhotoUrl(path: string | null | undefined) { return path ? supabase.storage.from(PHOTO_BUCKET).getPublicUrl(path).data.publicUrl : ''; }
function validatePhotoFile(file: File | null) {
  if (!file) return 'Choose an image first.';
  if (!PHOTO_MIME_TYPES.includes(file.type)) return 'Use a JPEG, PNG, or WebP image.';
  if (file.size > PHOTO_MAX_BYTES) return 'Images must be 5 MB or smaller.';
  return '';
}
function managedPhotoPath(path: string | null | undefined) { return Boolean(path && /^(establishments|tapas)\//.test(path)); }
function formatPhotoSize(bytes: number) { if (!Number.isFinite(bytes)) return '—'; if (bytes < 1024) return Math.round(bytes) + ' B'; if (bytes < 1024 * 1024) { const kb = bytes / 1024; return kb.toFixed(kb < 100 ? 1 : 0) + ' KB'; } const mb = bytes / 1024 / 1024; return mb.toFixed(mb < 100 ? 1 : 0) + ' MB'; }
function photoReduction(feedback: PhotoUploadFeedback) { return feedback.originalBytes > 0 ? Math.max(0, (1 - feedback.storedBytes / feedback.originalBytes) * 100).toFixed(1) : '0.0'; }
function loadPhotoImage(file: File) {
  return new Promise<HTMLImageElement>((resolve, reject) => {
    const url = URL.createObjectURL(file);
    const image = new Image();
    image.onload = () => { URL.revokeObjectURL(url); resolve(image); };
    image.onerror = () => { URL.revokeObjectURL(url); reject(new Error('The selected image could not be read.')); };
    image.src = url;
  });
}
function canvasBlob(canvas: HTMLCanvasElement, quality: number) {
  return new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, 'image/webp', quality));
}
async function processPhoto(file: File) {
  const image = await loadPhotoImage(file);
  const scale = Math.min(1, PHOTO_MAX_DIMENSION / Math.max(image.naturalWidth, image.naturalHeight));
  const baseWidth = Math.max(1, Math.round(image.naturalWidth * scale));
  const baseHeight = Math.max(1, Math.round(image.naturalHeight * scale));
  const dimensions = [1, 0.875, 0.75, 0.625, 0.5, 0.4, 0.3, 0.225, 0.15];
  const qualities = [0.92, 0.84, 0.76, 0.68, 0.6, 0.52, 0.44, 0.36, 0.28];
  let best: { blob: Blob; width: number; height: number; score: number } | null = null;
  for (const dimensionScale of dimensions) {
    const width = Math.max(1, Math.round(baseWidth * dimensionScale));
    const height = Math.max(1, Math.round(baseHeight * dimensionScale));
    const canvas = document.createElement('canvas');
    canvas.width = width; canvas.height = height;
    const context = canvas.getContext('2d');
    if (!context) throw new Error('Image processing is not available in this browser.');
    context.drawImage(image, 0, 0, width, height);
    for (const quality of qualities) {
      const blob = await canvasBlob(canvas, quality);
      if (!blob || blob.size > PHOTO_MAX_STORED_BYTES) continue;
      const candidate = { blob, width, height, score: width * height * quality };
      if (!best || candidate.score > best.score) best = candidate;
    }
  }
  if (!best) throw new Error('This image could not be compressed to 30 KB while remaining usable.');
  return { blob: best.blob, originalBytes: file.size, storedBytes: best.blob.size, width: best.width, height: best.height };
}
async function uploadPhoto(kind: 'establishments' | 'tapas', id: string, file: File) {
  let processed: { blob: Blob; originalBytes: number; storedBytes: number };
  try {
    if (file.size <= PHOTO_MAX_STORED_BYTES) {
      processed = { blob: file, originalBytes: file.size, storedBytes: file.size };
    } else {
      const compressed = await processPhoto(file);
      processed = { blob: compressed.blob, originalBytes: compressed.originalBytes, storedBytes: compressed.storedBytes };
    }
  } catch (processingError: any) {
    return { path: '', error: processingError?.message || 'Unable to process this image.', originalName: file.name, originalBytes: file.size, storedBytes: 0 };
  }
  if (processed.blob.size > PHOTO_MAX_STORED_BYTES) {
    return { path: '', error: 'The image is still larger than 30 KB after processing and was not uploaded.', originalName: file.name, originalBytes: processed.originalBytes, storedBytes: processed.blob.size };
  }
  const isWebp = processed.blob.type === 'image/webp';
  const extension = isWebp ? 'webp' : file.type === 'image/jpeg' ? 'jpg' : file.type === 'image/png' ? 'png' : 'webp';
  const contentType = isWebp ? 'image/webp' : file.type;
  const prefix = kind === 'establishments' ? 'festival-bar-' : 'festival-tapa-';
  const path = kind + '/' + prefix + id + '-' + crypto.randomUUID() + '.' + extension;
  if (processed.blob.size > PHOTO_MAX_STORED_BYTES) return { path: '', error: 'The final image exceeds 30 KB and was not uploaded.', originalName: file.name, originalBytes: processed.originalBytes, storedBytes: processed.blob.size };
  const { error: uploadError } = await supabase.storage.from(PHOTO_BUCKET).upload(path, processed.blob, { cacheControl: '3600', contentType, upsert: false });
  return uploadError ? { path: '', error: uploadError.message, originalName: file.name, originalBytes: processed.originalBytes, storedBytes: processed.storedBytes } : { path, error: '', originalName: file.name, originalBytes: processed.originalBytes, storedBytes: processed.storedBytes };
}
async function removeManagedPhoto(path: string | null | undefined) {
  if (!managedPhotoPath(path)) return '';
  const { error: removeError } = await supabase.storage.from(PHOTO_BUCKET).remove([path as string]);
  return removeError?.message || '';
}
function chooseEstablishmentPhoto(event: Event) {
  const input = event.target as HTMLInputElement;
  const file = input.files?.[0] || null;
  const validationError = file ? validatePhotoFile(file) : '';
  if (validationError) { error.value = validationError; input.value = ''; return; }
  error.value = ''; establishmentPhotoFile.value = file; establishmentPhotoRemoveRequested.value = false; establishmentPhotoFeedback.value = file ? { ...blankPhotoFeedback(), state: 'selected', originalName: file.name, originalBytes: file.size } : blankPhotoFeedback(); establishmentPhotoPreview.value = file ? URL.createObjectURL(file) : publicPhotoUrl(establishmentForm.value.photo_path);
}
function chooseTapaPhoto(event: Event) {
  const input = event.target as HTMLInputElement;
  const file = input.files?.[0] || null;
  const validationError = file ? validatePhotoFile(file) : '';
  if (validationError) { error.value = validationError; input.value = ''; return; }
  error.value = ''; tapaPhotoFile.value = file; tapaPhotoRemoveRequested.value = false; tapaPhotoFeedback.value = file ? { ...blankPhotoFeedback(), state: 'selected', originalName: file.name, originalBytes: file.size } : blankPhotoFeedback(); tapaPhotoPreview.value = file ? URL.createObjectURL(file) : publicPhotoUrl(tapaForm.value.photo_path);
}
function requestEstablishmentPhotoRemoval() { if (!window.confirm('Remove this photo?')) return; establishmentPhotoFile.value = null; establishmentPhotoRemoveRequested.value = true; establishmentPhotoPreview.value = ''; establishmentPhotoFeedback.value = blankPhotoFeedback(); }
function requestTapaPhotoRemoval() { if (!window.confirm('Remove this photo?')) return; tapaPhotoFile.value = null; tapaPhotoRemoveRequested.value = true; tapaPhotoPreview.value = ''; tapaPhotoFeedback.value = blankPhotoFeedback(); }

const blankFestival = () => ({ name_en: '', name_es: '', slug: '', start_date: '', end_date: '', city: '', default_tapa_price: '5.00', publication_status: 'draft', reviews_enabled: true, show_rankings: true, show_total_rating_count: true });
const blankEstablishment = () => ({ festival_id: '', name: '', description_en: '', description_es: '', address: '', coordinates: '', photo_path: '', phone: '', instagram: '', whatsapp: '', facebook_url: '', website_url: '', hours_notes_en: '', hours_notes_es: '', is_published: false, participation_status: 'active', closure_status: 'normal' });
const blankTapa = () => ({ establishment_id: '', name_en: '', name_es: '', description_en: '', description_es: '', price_override: '', photo_path: '', festival_number: '', is_published: false, participation_status: 'active' });
const festivalForm = ref(blankFestival());
const establishmentForm = ref(blankEstablishment());
const tapaForm = ref(blankTapa());

const db = () => supabase.schema('festival');
const reportUsers = computed(() => [...new Set(reportRows.value.map((row) => row.user_label))].sort());
const filteredReportRows = computed(() => reportRows.value
  .filter((row) => !reportUserLabel.value || row.user_label === reportUserLabel.value)
  .filter((row) => reportRatingType.value === 'all' || (reportRatingType.value === 'tapa' ? Number(row.tapa_rating_count) > 0 : Number(row.bar_rating_count) > 0))
  .sort((a, b) => Number(b.total_rating_count) - Number(a.total_rating_count) || a.user_label.localeCompare(b.user_label)));
const reportSummary = computed(() => filteredReportRows.value.reduce((summary, row) => {
  const tapa = reportRatingType.value === 'bar' ? 0 : Number(row.tapa_rating_count);
  const bar = reportRatingType.value === 'tapa' ? 0 : Number(row.bar_rating_count);
  summary.users += 1; summary.tapa += tapa; summary.bar += bar; summary.total += tapa + bar;
  return summary;
}, { users: 0, tapa: 0, bar: 0, total: 0 }));
function reportRowKey(row: RatingActivity) { return `${row.festival_id}:${row.user_label}`; }
function administratorRoleLabel(role: Administrator["role"]) { return role === "superuser" ? "Superadmin" : "Admin"; }
function displayAdministratorMessage(message: string) { return message.replace(/superuser/gi, "Superadmin"); }
function maskAdminIdentity(email: string | null | undefined) {
  if (!email) return "Account";
  const at = email.indexOf("@");
  const username = at >= 0 ? email.slice(0, at) : email;
  const domain = at >= 0 ? email.slice(at + 1) : "";
  const domainParts = domain.split(".");
  const suffixLength = domainParts.length > 2 && domainParts.at(-1)?.toLowerCase() === "uk" ? 2 : 1;
  const suffix = domainParts.length > 1 ? "." + domainParts.slice(-suffixLength).join(".") : "";
  const domainPrefix = suffix ? domain.slice(0, -suffix.length) : domain;
  const hiddenIdentity = username + (domainPrefix ? "." : "") + domainPrefix;
  return Array.from(hiddenIdentity, (character, index) => index < 6 || character === "." ? character : "?").join("") + suffix;
}
const currentAdminRoleLabel = computed(() => isSuperuser.value ? "Superadmin" : "Admin");
const ADMIN_MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
function adminDateTimeLines(value: string | null | undefined) {
  const date = new Date(value || "");
  if (Number.isNaN(date.getTime())) return { date: "—", time: "—" };
  const day = String(date.getDate()).padStart(2, "0");
  const year = String(date.getFullYear()).slice(-2);
  const time = [date.getHours(), date.getMinutes(), date.getSeconds()].map((part) => String(part).padStart(2, "0")).join(":");
  return { date: day + ADMIN_MONTHS[date.getMonth()] + "'" + year, time };
}
function toggleReportRow(row: RatingActivity) { const key = reportRowKey(row); expandedReportRows.value[key] = !expandedReportRows.value[key]; }
async function loadRatingActivity() {
  if (!isAdmin.value) return;
  reportLoading.value = true; error.value = '';
  const { data, error: reportError } = await $fetch<{ data?: RatingActivity[] }>('/api/admin/reporting', { method: 'POST', body: { action: 'ratings', festivalId: reportFestivalId.value || null } }).then((result) => ({ data: result.data, error: null })).catch((caught) => ({ data: null, error: caught }));
  reportLoading.value = false;
  if (reportError) { error.value = reportError.message; return; }
  reportRows.value = (data || []) as RatingActivity[];
  expandedReportRows.value = {};
}
async function loadTapaRatingDetail() {
  detailRows.value = [];
  if (!isAdmin.value || !detailTapaId.value) return;
  detailLoading.value = true; error.value = "";
  const { data, error: detailError } = await $fetch<{ data?: TapaRatingDetail[] }>('/api/admin/reporting', { method: 'POST', body: { action: 'tapa-detail', tapaId: detailTapaId.value } }).then((result) => ({ data: result.data, error: null })).catch((caught) => ({ data: null, error: caught }));
  detailLoading.value = false;
  if (detailError) { error.value = detailError.message; return; }
  detailRows.value = (data || []) as TapaRatingDetail[];
}

async function loadDashboard() {
  if (!isAdmin.value) return;
  dashboardLoading.value = true; dashboardError.value = '';
  const { data, error: dashboardRpcError } = await $fetch<{ data?: any }>('/api/admin/reporting', { method: 'POST', body: { action: 'dashboard' } }).then((result) => ({ data: result.data, error: null })).catch((caught) => ({ data: null, error: caught }));
  dashboardLoading.value = false;
  if (dashboardRpcError) { dashboardError.value = 'Dashboard data is not available yet. Apply the dashboard migration before using these totals.'; return; }
  dashboard.value = { headline: data?.headline || {}, content: data?.content || {}, recent_activity: Array.isArray(data?.recent_activity) ? data.recent_activity : [], most_active_tapas: Array.isArray(data?.most_active_tapas) ? data.most_active_tapas : [] };
}
function dashboardCount(section: 'headline' | 'content', key: string) { return Number(dashboard.value[section]?.[key] || 0).toLocaleString(); }
function dashboardDate(value: string) { return adminDateTimeLines(value); }
function resourceBytes(value: unknown) { const bytes = Number(value || 0); if (!Number.isFinite(bytes)) return 'Unavailable from current connection'; if (bytes < 1024) return bytes + ' B'; if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB'; if (bytes < 1024 * 1024 * 1024) return (bytes / 1024 / 1024).toFixed(1) + ' MB'; return (bytes / 1024 / 1024 / 1024).toFixed(2) + ' GB'; }
function resourceRows(name: string) { return Array.isArray(resources.value?.supabase?.tables) ? resources.value.supabase.tables.filter((row: any) => row.table_name === name) : []; }
async function loadResources() { if (!isSuperuser.value) return; resourcesLoading.value = true; resourcesError.value = ''; try { resources.value = await $fetch('/api/admin/resources'); } catch { resourcesError.value = 'Resource metrics are unavailable.'; } finally { resourcesLoading.value = false; } }
const filteredPhotos = computed(() => {
  const query = photosQuery.value.trim().toLowerCase();
  return [...photos.value].filter((photo) => !query || [photo.name, photo.establishment_name, photo.tapa_name, photo.kind].some((value) => String(value || '').toLowerCase().includes(query))).sort((a, b) => {
    if (photosSort.value === 'largest') return b.size_bytes - a.size_bytes;
    if (photosSort.value === 'smallest') return a.size_bytes - b.size_bytes;
    if (photosSort.value === 'bar') return String(a.establishment_name || a.name).localeCompare(String(b.establishment_name || b.name));
    const left = String(a.created_at || ''); const right = String(b.created_at || '');
    return photosSort.value === 'oldest' ? left.localeCompare(right) : right.localeCompare(left);
  });
});
const photoSummary = computed(() => ({ total: photos.value.length, bytes: photos.value.reduce((sum, photo) => sum + photo.size_bytes, 0), average: photos.value.length ? photos.value.reduce((sum, photo) => sum + photo.size_bytes, 0) / photos.value.length : 0, largest: photos.value.reduce((max, photo) => Math.max(max, photo.size_bytes), 0), overLimit: photos.value.filter((photo) => photo.managed && photo.size_bytes > PHOTO_MAX_STORED_BYTES).length, managed: photos.value.filter((photo) => photo.managed).length, orphaned: photos.value.filter((photo) => photo.orphaned).length }));
async function loadPhotos() { if (!isAdmin.value) return; photosLoading.value = true; photosError.value = ''; try { const result = await $fetch<{ photos?: AdminPhoto[] }>('/api/admin/photos'); photos.value = result.photos || []; } catch { photosError.value = 'Photo metadata is unavailable.'; } finally { photosLoading.value = false; } }


async function loadModeratedReviews(page = reviewPage.value) {
  if (!isAdmin.value) return;
  moderatedReviewsLoading.value = true; error.value = '';
  const { data, error: reviewsError } = await $fetch<{ data?: ModeratedReview[] }>('/api/admin/reporting', { method: 'POST', body: { action: 'reviews', query: reviewQuery.value, status: reviewStatus.value, page } }).then((result) => ({ data: result.data, error: null })).catch((caught) => ({ data: null, error: caught }));
  moderatedReviewsLoading.value = false;
  if (reviewsError) { error.value = reviewsError.message; return; }
  moderatedReviews.value = (data || []) as ModeratedReview[];
  reviewTotal.value = Number(moderatedReviews.value[0]?.total_count || 0);
  reviewPage.value = page;
}

async function searchModeratedReviews() { await loadModeratedReviews(0); }

async function setReviewModeration(row: ModeratedReview, nextStatus: 'visible' | 'hidden') {
  const action = nextStatus === 'hidden' ? 'Hide' : 'Restore';
  if (!window.confirm(action + ' this review?')) return;
  reviewActionId.value = row.review_id; error.value = ''; notice.value = '';
  const { error: moderationError } = await db().rpc('set_review_moderation', {
    p_review_id: row.review_id,
    p_status: nextStatus,
  });
  reviewActionId.value = null;
  if (moderationError) { error.value = moderationError.message; return; }
  notice.value = nextStatus === 'hidden' ? 'Review hidden.' : 'Review restored.';
  await loadModeratedReviews();
}

async function bootstrapInitialSuperuser() {
  if (!window.confirm("This will make your current Admin account the initial Superadmin. Continue?")) return;
  bootstrapSaving.value = true; error.value = ""; notice.value = "";

  const { data: eligible, error: eligibilityError } = await db().rpc("can_bootstrap_initial_superuser");
  if (eligibilityError) {
    bootstrapSaving.value = false; await checkAccess(); error.value = eligibilityError.message; return;
  }
  if (eligible !== true) {
    bootstrapSaving.value = false;
    await checkAccess();
    error.value = "Your current session is not eligible to become the initial Superadmin. Please sign out and sign back in with the existing Admin account.";
    return;
  }

  const { error: bootstrapError } = await db().rpc("bootstrap_initial_superuser");
  bootstrapSaving.value = false;
  if (bootstrapError) { await checkAccess(); error.value = bootstrapError.message; return; }

  await checkAccess();
  if (!isSuperuser.value) {
    error.value = "Superadmin activation could not be confirmed. Please refresh the page.";
    return;
  }
  notice.value = "Your account is now a Superadmin.";
  tab.value = "administrators";
  await loadAdministrators();
}

async function loadAdministrators() {
  if (!isSuperuser.value) return;
  administratorsLoading.value = true; error.value = "";
  const { data, error: administratorsError } = await $fetch<{ data?: Administrator[] }>('/api/admin/reporting', { method: 'POST', body: { action: 'administrators' } }).then((result) => ({ data: result.data, error: null })).catch((caught) => ({ data: null, error: caught }));
  administratorsLoading.value = false;
  if (administratorsError) { error.value = administratorsError.message; return; }
  administrators.value = (data || []) as Administrator[];
  await loadPasswordResetEligibility(administrators.value.map((row) => row.account_id));
}

function compareRegisteredUsers(a: RegisteredUser, b: RegisteredUser) {
  const account = a.account.localeCompare(b.account, undefined, { sensitivity: 'base' });
  const date = (a.registered_at || '').localeCompare(b.registered_at || '');
  const activityDate = (a.last_festival_activity_at || '').localeCompare(b.last_festival_activity_at || '');
  const total = a.total_activity_count - b.total_activity_count;
  const status = Number(a.status === 'Suspended') - Number(b.status === 'Suspended');
  switch (registeredUserSort.value) {
    case 'account_asc': return account || date;
    case 'account_desc': return -account || date;
    case 'joined_asc': return date || account;
    case 'activity_desc': return -activityDate || account;
    case 'activity_asc': return activityDate || account;
    case 'total_desc': return -total || account;
    case 'total_asc': return total || account;
    case 'suspended_first': return -status || account;
    case 'active_first': return status || account;
    default: return -date || account;
  }
}
function applyRegisteredUserSort(page = registeredUsersPage.value) {
  const sorted = [...registeredUsersAll.value].sort(compareRegisteredUsers);
  registeredUsers.value = sorted.slice(page * 25, (page + 1) * 25);
  registeredUsersPage.value = page;
}
async function loadRegisteredUsers(page = registeredUsersPage.value) {
  if (!isAdmin.value) return;
  registeredUsersLoading.value = true; error.value = ''; promotableRegisteredUserIds.value = new Set();
  const fetchPage = (requestedPage: number) => $fetch<{ data?: RegisteredUser[] }>('/api/admin/reporting', { method: 'POST', body: { action: 'users', query: registeredUserQuery.value, page: requestedPage } });
  try {
    const first = await fetchPage(0);
    const firstRows = (first.data || []) as RegisteredUser[];
    registeredUsersTotal.value = firstRows[0]?.total_count || 0;
    const pageCount = Math.ceil(registeredUsersTotal.value / 25);
    const pages = await Promise.all(Array.from({ length: Math.max(0, pageCount - 1) }, (_, index) => fetchPage(index + 1)));
    registeredUsersAll.value = firstRows.concat(...pages.map((result) => (result.data || []) as RegisteredUser[]));
    applyRegisteredUserSort(page);
    selectedRegisteredUser.value = null;
    registeredUserActivity.value = [];
    await Promise.all([loadPromotableRegisteredUsers(), loadPasswordResetEligibility(registeredUsers.value.map((row) => row.account_id)), loadFullAuditEligibility(registeredUsers.value.map((row) => row.account_id))]);
  } catch (caught: any) { error.value = caught?.message || 'User data is unavailable.'; }
  finally { registeredUsersLoading.value = false; }
}
async function searchRegisteredUsers() { await loadRegisteredUsers(0); }

async function toggleRegisteredUserSuspension(row: RegisteredUser) {
  const suspended = row.status === 'Suspended';
  if (row.role !== 'user') return;
  if (!window.confirm(suspended ? 'Reactivate this user? They will be able to participate again.' : 'Suspend this user? They can still log in and browse, but cannot add or change Festival contributions.')) return;
  const reason = suspended ? null : window.prompt('Optional internal reason (max 240 characters):');
  registeredUserSuspensionId.value = row.account_id; error.value = ''; notice.value = '';
  const { error: actionError } = await db().rpc(suspended ? 'reactivate_user' : 'suspend_user', suspended ? { p_account_id: row.account_id } : { p_account_id: row.account_id, p_reason: reason?.trim() || null });
  registeredUserSuspensionId.value = null;
  if (actionError) { error.value = actionError.message; return; }
  notice.value = suspended ? 'User reactivated.' : 'User suspended.';
  await loadRegisteredUsers(registeredUsersPage.value);
}

async function loadPromotableRegisteredUsers() {
  promotableRegisteredUserIds.value = new Set();
  if (!isSuperuser.value || !registeredUsers.value.length) return;
  const { data, error: promotableError } = await db().rpc("list_promotable_registered_users", { p_account_ids: registeredUsers.value.map((row) => row.account_id) });
  if (promotableError) { error.value = promotableError.message; return; }
  promotableRegisteredUserIds.value = new Set((data || []).map((row: { account_id: string }) => row.account_id));
}

async function loadPasswordResetEligibility(accountIds: string[]) {
  passwordResetEligibleAccountIds.value = new Set();
  if (!isAdmin.value || !accountIds.length) return;
  try {
    const result = await $fetch<{ eligibleAccountIds?: string[] }>('/api/admin/password-reset-eligibility', {
      method: 'POST',
      body: { accountIds },
    });
    passwordResetEligibleAccountIds.value = new Set(result.eligibleAccountIds || []);
  } catch {
    // The action remains unavailable until the private server secret is configured.
  }
}

async function loadFullAuditEligibility(accountIds: string[]) {
  fullAuditEligibleAccountIds.value = new Set();
  if (!isAdmin.value || !accountIds.length) return;
  try {
    const result = await $fetch<{ eligibleAccountIds?: string[] }>('/api/admin/full-audit-eligibility', {
      method: 'POST',
      body: { accountIds },
    });
    fullAuditEligibleAccountIds.value = new Set(result.eligibleAccountIds || []);
  } catch {
    // The action remains unavailable if the trusted audit service is unavailable.
  }
}

async function openFullAudit(row: { account_id: string; account: string }) {
  if (fullAuditAccountId.value === row.account_id) {
    fullAuditAccountId.value = null;
    fullAudit.value = null;
    return;
  }
  fullAuditAccountId.value = row.account_id;
  fullAuditLoading.value = true;
  fullAudit.value = null;
  error.value = '';
  try {
    const result = await $fetch<{ audit: FullAudit }>('/api/admin/full-audit', {
      method: 'POST',
      body: { accountId: row.account_id },
    });
    fullAudit.value = result.audit;
  } catch {
    fullAuditAccountId.value = null;
    error.value = 'Unable to load the account audit.';
  } finally {
    fullAuditLoading.value = false;
  }
}

function auditRoleLabel(role: string | null | undefined) {
  return role === 'superuser' ? 'Superadmin' : role === 'admin' ? 'Admin' : 'User';
}
function auditActionLabel(action: string) {
  return action === 'added' ? 'Added as administrator' : action === 'promoted' ? 'Promoted to Superadmin' : action === 'demoted' ? 'Demoted to Admin' : action === 'removed' ? 'Administrator removed' : action;
}

function auditDateTimeLines(value: string | null | undefined) {
  const parts = new Intl.DateTimeFormat('en-GB', { timeZone: 'Europe/Madrid', day: '2-digit', month: 'short', year: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23' }).formatToParts(new Date(value || ''));
  const get = (type: Intl.DateTimeFormatPartTypes) => parts.find((part) => part.type === type)?.value || '';
  return { date: get('day') + get('month') + "'" + get('year'), time: [get('hour'), get('minute'), get('second')].join(':') };
}
type FullAuditTimelineEntry = { timestamp: string; event: string; result: string };
function fullAuditTimeline(audit: FullAudit | null): FullAuditTimelineEntry[] {
  if (!audit) return [];
  const entries: FullAuditTimelineEntry[] = [
    { timestamp: audit.created_at, event: 'Account created', result: 'Registered account' },
    ...(audit.email_confirmed_at ? [{ timestamp: audit.email_confirmed_at, event: 'Email confirmed', result: 'Confirmed' }] : []),
    ...(audit.last_sign_in_at ? [{ timestamp: audit.last_sign_in_at, event: 'Successful sign-in', result: 'Auth sign-in recorded' }] : []),
    ...audit.role_history.map((item) => ({ timestamp: item.created_at, event: auditActionLabel(item.action), result: `${auditRoleLabel(item.previous_role)} → ${auditRoleLabel(item.new_role)} · ${item.performed_by_email || item.performed_by}` })),
    ...audit.password_reset_history.map((item) => ({ timestamp: item.created_at, event: 'Password reset requested', result: `Target role: ${auditRoleLabel(item.target_role)} · Requested by ${item.requesting_administrator_email || item.requesting_administrator}` })),
    ...audit.review_moderation_history.map((item) => ({ timestamp: item.created_at, event: `Review ${item.action}`, result: `${item.establishment} · ${item.tapa}${item.moderator_email ? ` · ${item.moderator_email}` : ''}` })),
    ...audit.activity.map((item) => ({ timestamp: item.activity_at, event: item.activity_kind, result: `${item.establishment}${item.tapa ? ` · ${item.tapa}` : ''}${item.rating == null ? '' : ` · ${item.rating}`}` })),
  ];
  return entries.filter((entry) => entry.timestamp).sort((a, b) => String(b.timestamp).localeCompare(String(a.timestamp)));
}

async function sendPasswordReset(row: { account_id: string; account: string }) {
  if (!window.confirm('Send a password reset email to this user?')) return;
  passwordResetAccountId.value = row.account_id; error.value = ''; notice.value = '';
  try {
    await $fetch('/api/admin/send-password-reset', { method: 'POST', body: { accountId: row.account_id } });
    notice.value = 'Password reset email sent.';
  } catch {
    error.value = 'Unable to send the password reset email. Please try again later.';
  } finally {
    passwordResetAccountId.value = null;
  }
}

async function toggleRegisteredUserActivity(row: RegisteredUser) {
  if (selectedRegisteredUser.value?.account_id === row.account_id) {
    selectedRegisteredUser.value = null;
    registeredUserActivity.value = [];
    return;
  }
  selectedRegisteredUser.value = row;
  registeredUserActivity.value = [];
  registeredUserActivityLoading.value = true; error.value = "";
  const { data, error: activityError } = await db().rpc("registered_user_activity", { p_account_id: row.account_id });
  registeredUserActivityLoading.value = false;
  if (activityError) { error.value = activityError.message; selectedRegisteredUser.value = null; return; }
  registeredUserActivity.value = (data || []) as RegisteredUserActivity[];
}

async function promoteRegisteredUser(row: RegisteredUser, role: "admin" | "superuser") {
  const roleLabel = role === "superuser" ? "Superadmin" : "Admin";
  if (!window.confirm("Promote " + row.account + " to " + roleLabel + "?")) return;
  registeredUserPromotionId.value = row.account_id; error.value = ""; notice.value = "";
  const { error: promotionError } = await db().rpc("add_administrator_by_account_id", { p_account_id: row.account_id, p_role: role });
  registeredUserPromotionId.value = null;
  if (promotionError) { error.value = displayAdministratorMessage(promotionError.message); await loadPromotableRegisteredUsers(); return; }
  notice.value = row.account + " is now an " + roleLabel + ".";
  await Promise.all([loadRegisteredUsers(), loadAdministrators()]);
}

async function addAdministrator() {
  administratorSaving.value = true; error.value = ""; notice.value = "";
  const { error: addError } = await db().rpc("add_administrator", { p_email: administratorEmail.value, p_role: administratorRole.value });
  administratorSaving.value = false;
  if (addError) { error.value = addError.message; return; }
  notice.value = "Administrator added."; administratorEmail.value = ""; administratorRole.value = "admin";
  await loadAdministrators();
}

async function changeAdministratorRole(row: Administrator, role: "admin" | "superuser") {
  const action = role === "superuser" ? "promote" : "demote";
  if (!window.confirm("Are you sure you want to " + action + " " + row.account + "?")) return;
  administratorSaving.value = true; error.value = ""; notice.value = "";
  const { error: roleError } = await db().rpc("set_administrator_role", { p_account_id: row.account_id, p_new_role: role });
  administratorSaving.value = false;
  if (roleError) { error.value = roleError.message; return; }
  notice.value = "Administrator " + action + "d."; await loadAdministrators();
}

async function removeAdministrator(row: Administrator) {
  if (!window.confirm("Remove administrator privileges from " + row.account + "?")) return;
  administratorSaving.value = true; error.value = ""; notice.value = "";
  const { error: removeError } = await db().rpc("remove_administrator", { p_account_id: row.account_id });
  administratorSaving.value = false;
  if (removeError) { error.value = removeError.message; return; }
  notice.value = "Administrator removed."; await loadAdministrators();
}

function adminTabLabel(value: Tab) { return ({ dashboard: 'Dashboard', controls: 'Controls', festivals: 'Festival', establishments: 'Bars', tapas: 'Tapas', reviews: 'Reviews', users: 'Users', reports: 'Reports', administrators: 'Administrators', resources: 'Resources', photos: 'Photos' } as Record<Tab, string>)[value]; }
function controlsCalendarDate(timezone: string) {
  const parts = new Intl.DateTimeFormat('en-CA', { timeZone: timezone || 'Europe/Madrid', year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts();
  const value = (type: string) => parts.find((part) => part.type === type)?.value;
  return value('year') + '-' + value('month') + '-' + value('day');
}
function controlsFestivalName(festival: any) { return festival?.name_en || festival?.name_es || festival?.slug || 'Unnamed festival'; }
function controlsFestivalYear(festival: any) {
  const year = String(festival?.start_date || '').slice(0, 4);
  return year && !/\b(?:19|20)\d{2}\b/.test(controlsFestivalName(festival)) ? year : '';
}
function controlsFestivalStatus(festival: any) {
  const value = String(festival?.publication_status || 'unknown');
  return value ? value.charAt(0).toUpperCase() + value.slice(1) : 'Unknown';
}
function controlsFestivalOptionLabel(festival: any) {
  const year = controlsFestivalYear(festival);
  return controlsFestivalName(festival) + (year ? ' · ' + year : '') + ' — ' + controlsFestivalStatus(festival);
}
function isActivePublishedControlsFestival(festival: any) {
  if (festival?.publication_status !== 'published') return false;
  const today = controlsCalendarDate(festival.timezone || 'Europe/Madrid');
  return festival.start_date <= today && festival.end_date >= today;
}
function defaultControlsFestivalId() {
  const published = festivals.value.filter((festival) => festival.publication_status === 'published');
  return published.find(isActivePublishedControlsFestival)?.id || published[0]?.id || festivals.value[0]?.id || '';
}
const controlsFestival = computed(() => festivals.value.find((festival) => festival.id === controlsFestivalId.value) || null);
function openEstablishmentAttentionFilter(filter: EstablishmentAttentionFilter) { establishmentAttentionFilter.value = filter; selectTab("establishments"); }
function openTapaAttentionFilter(filter: TapaAttentionFilter) { tapaAttentionFilter.value = filter; selectTab("tapas"); }
function openHiddenReviews() { reviewStatus.value = "hidden"; reviewPage.value = 0; selectTab("reviews"); }
function clearEstablishmentAttentionFilter() { establishmentAttentionFilter.value = "all"; }
function clearTapaAttentionFilter() { tapaAttentionFilter.value = "all"; }
function selectTab(nextTab: Tab) {
  tab.value = nextTab;
  if (nextTab === 'dashboard') void loadDashboard();
  if (nextTab === 'reports') void loadRatingActivity();
  if (nextTab === 'reviews') void loadModeratedReviews();
  if (nextTab === 'users') void loadRegisteredUsers();
  if (nextTab === 'administrators') void loadAdministrators();
  if (nextTab === 'resources') void loadResources();
  if (nextTab === 'photos') void loadPhotos();
  if (nextTab === 'controls') void loadControls();
}

async function loadControls() {
  if (!isAdmin.value) return;
  if (!controlsFestivalId.value) controlsFestivalId.value = defaultControlsFestivalId();
  if (!controlsFestivalId.value) return;
  controlsLoading.value = true; error.value = '';
  const [result, auditResult, siteAuditResult] = await Promise.all([
    db().rpc("get_admin_controls", { p_festival_id: controlsFestivalId.value }),
    db().rpc("list_control_audit", { p_festival_id: controlsFestivalId.value, p_limit: 30 }),
    db().rpc("list_control_audit", { p_festival_id: null, p_limit: 30 }),
  ]);
  controlsLoading.value = false;
  if (result.error || auditResult.error || siteAuditResult.error) { error.value = result.error?.message || auditResult.error?.message || siteAuditResult.error?.message || 'Controls are unavailable. Apply the controls migration first.'; return; }
  controls.value = result.data?.controls || null;
  controlsSiteShutdown.value = result.data?.site?.emergency_shutdown === true;
  const auditRows = [...(auditResult.data || []), ...(siteAuditResult.data || [])] as ControlAudit[];
  controlsAudit.value = [...new Map(auditRows.map((row) => [`${row.created_at}:${row.administrator}:${row.control}:${row.festival_id || ""}`, row])).values()]
    .sort((left, right) => new Date(right.created_at).getTime() - new Date(left.created_at).getTime())
    .slice(0, 30);
}
async function setFestivalControl(control: keyof FestivalControls, value: boolean) {
  if (!controlsFestivalId.value) return;
  controlsSaving.value = control; error.value = ''; notice.value = '';
  const { error: saveError } = await db().rpc('set_festival_control', { p_festival_id: controlsFestivalId.value, p_control: control, p_value: value });
  controlsSaving.value = null;
  if (saveError) { error.value = saveError.message; return; }
  notice.value = 'Control updated.'; await loadControls();
}
async function setEmergencyShutdown(value: boolean) {
  if (!isSuperuser.value) return;
  if (value && shutdownPhrase.value !== 'SHUTDOWN') { error.value = 'Type SHUTDOWN to confirm public shutdown.'; return; }
  if (!value && !window.confirm('Restore the public site? Administrators will remain signed in.')) return;
  controlsSaving.value = 'emergency_shutdown'; error.value = '';
  const { error: saveError } = await db().rpc('set_emergency_shutdown', { p_value: value });
  controlsSaving.value = null;
  if (saveError) { error.value = saveError.message; return; }
  shutdownConfirmOpen.value = false; shutdownPhrase.value = ''; notice.value = value ? 'Public site disabled.' : 'Public site restored.'; await loadControls();
}
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
  isSuperuser.value = false;
  canBootstrapInitialSuperuser.value = false;
  if (!user.value) return;
  checkingAccess.value = true;
  error.value = '';
  const [adminResult, superuserResult, bootstrapResult] = await Promise.all([db().rpc('is_current_admin'), db().rpc('is_current_superuser'), db().rpc('can_bootstrap_initial_superuser')]);
  if (adminResult.error || superuserResult.error || bootstrapResult.error) error.value = adminResult.error?.message || superuserResult.error?.message || bootstrapResult.error?.message || 'Unable to check access.';
  else { isAdmin.value = adminResult.data === true; isSuperuser.value = superuserResult.data === true; canBootstrapInitialSuperuser.value = bootstrapResult.data === true; }
  checkingAccess.value = false;
  if (isAdmin.value) { await load(); if (tab.value === 'dashboard') await loadDashboard(); }
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
function resetEstablishment() { editingEstablishment.value = null; establishmentForm.value = blankEstablishment(); establishmentPhotoFile.value = null; establishmentPhotoPreview.value = ''; establishmentPhotoRemoveRequested.value = false; establishmentPhotoFeedback.value = blankPhotoFeedback(); }
function resetTapa() { editingTapa.value = null; tapaForm.value = blankTapa(); tapaPhotoFile.value = null; tapaPhotoPreview.value = ''; tapaPhotoRemoveRequested.value = false; tapaPhotoFeedback.value = blankPhotoFeedback(); }
function editFestival(row: any) { editingFestival.value = row; slugManuallyEdited.value = true; festivalForm.value = { ...row, default_tapa_price: String(row.default_tapa_price), show_rankings: row.show_rankings !== false, show_total_rating_count: row.show_total_rating_count !== false }; tab.value = 'festivals'; }
function instagramFor(establishmentId: string) {
  const definition = fieldDefinitions.value.find((item) => item.festival_id === establishments.value.find((venue) => venue.id === establishmentId)?.festival_id);
  const value = definition && fieldValues.value.find((item) => item.field_definition_id === definition.id && item.establishment_id === establishmentId)?.value;
  return typeof value?.en === 'string' ? value.en : '';
}
async function editEstablishment(row: any) { editingEstablishment.value = row; establishmentForm.value = { ...blankEstablishment(), ...row, instagram: instagramFor(row.id), coordinates: row.latitude == null || row.longitude == null ? '' : `${row.latitude}, ${row.longitude}` }; establishmentPhotoFile.value = null; establishmentPhotoRemoveRequested.value = false; establishmentPhotoFeedback.value = blankPhotoFeedback(); establishmentPhotoPreview.value = publicPhotoUrl(row.photo_path); tab.value = 'establishments'; await nextTick(); if (window.matchMedia('(max-width: 1023px)').matches) establishmentFormElement.value?.scrollIntoView({ behavior: 'smooth', block: 'start' }); }
async function editTapa(row: any) { editingTapa.value = row; tapaForm.value = { ...blankTapa(), ...row, price_override: row.price_override == null ? '' : String(row.price_override), festival_number: row.festival_number == null ? '' : String(row.festival_number) }; tapaPhotoFile.value = null; tapaPhotoRemoveRequested.value = false; tapaPhotoFeedback.value = blankPhotoFeedback(); tapaPhotoPreview.value = publicPhotoUrl(row.photo_path); tab.value = 'tapas'; await nextTick(); if (window.matchMedia('(max-width: 1023px)').matches) tapaFormElement.value?.scrollIntoView({ behavior: 'smooth', block: 'start' }); }
function closeEstablishmentEditor() { resetEstablishment(); }
function closeTapaEditor() { resetTapa(); }

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
  const previousPath = editingEstablishment.value?.photo_path || null;
  const { coordinates: _coordinates, instagram: _instagram, photo_path: _photoPath, ...formValues } = f;
  const payload = { ...formValues, photo_path: establishmentPhotoRemoveRequested.value ? null : previousPath, description_en: valueOrNull(f.description_en), description_es: valueOrNull(f.description_es), address: valueOrNull(f.address), latitude: coordinates.latitude, longitude: coordinates.longitude, phone: valueOrNull(f.phone), whatsapp: valueOrNull(f.whatsapp), facebook_url: valueOrNull(f.facebook_url), website_url: valueOrNull(f.website_url), hours_notes_en: valueOrNull(f.hours_notes_en), hours_notes_es: valueOrNull(f.hours_notes_es) };
  const result = editingEstablishment.value
    ? await db().from('establishments').update(payload).eq('id', editingEstablishment.value.id).select().single()
    : await db().from('establishments').insert(payload).select().single();
  if (result.error || !result.data) { saving.value = false; error.value = result.error?.message || 'Unable to save establishment.'; return; }
  const savedRow = result.data;
  let finalPath = payload.photo_path;
  const establishmentUpload = Boolean(establishmentPhotoFile.value);
  if (establishmentPhotoFile.value) {
    const selectedFile = establishmentPhotoFile.value;
    establishmentPhotoFeedback.value = { ...establishmentPhotoFeedback.value, state: 'processing', error: '' };
    const uploadResult = await uploadPhoto('establishments', savedRow.id, selectedFile);
    if (uploadResult.error) { establishmentPhotoFeedback.value = { ...establishmentPhotoFeedback.value, state: 'error', error: uploadResult.error, storedBytes: uploadResult.storedBytes }; saving.value = false; error.value = uploadResult.error; return; }
    const photoResult = await db().from('establishments').update({ photo_path: uploadResult.path }).eq('id', savedRow.id);
    if (photoResult.error) { await removeManagedPhoto(uploadResult.path); establishmentPhotoFeedback.value = { ...establishmentPhotoFeedback.value, state: 'error', error: photoResult.error.message }; saving.value = false; error.value = photoResult.error.message; return; }
    finalPath = uploadResult.path;
    establishmentPhotoFeedback.value = { state: 'success', originalName: uploadResult.originalName, originalBytes: uploadResult.originalBytes, storedBytes: uploadResult.storedBytes, path: uploadResult.path, error: '' };
    establishmentPhotoFile.value = null;
    establishmentPhotoPreview.value = publicPhotoUrl(uploadResult.path);
    notice.value = 'Photo uploaded successfully.';
  }
  if (previousPath && previousPath !== finalPath) {
    const removeError = await removeManagedPhoto(previousPath);
    if (removeError) notice.value = 'Establishment saved, but the previous image could not be removed.';
  }
  const instagram = valueOrNull(f.instagram);
  if (instagram) {
    let definition = fieldDefinitions.value.find((item) => item.festival_id === savedRow.festival_id);
    if (!definition) {
      const definitionResult = await db().from('field_definitions').insert({ festival_id: savedRow.festival_id, key: 'instagram', label_en: 'Instagram', label_es: 'Instagram', field_type: 'text', applies_to: 'establishment', required: false, active: true, sort_order: 0 }).select().single();
      if (definitionResult.error || !definitionResult.data) { saving.value = false; error.value = definitionResult.error?.message || 'Unable to create the Instagram field.'; return; }
      definition = definitionResult.data;
    }
    const existingValue = fieldValues.value.find((item) => item.field_definition_id === definition.id && item.establishment_id === savedRow.id);
    const instagramResult = existingValue
      ? await db().from('field_values').update({ value: { en: instagram } }).eq('id', existingValue.id)
      : await db().from('field_values').insert({ field_definition_id: definition.id, establishment_id: savedRow.id, value: { en: instagram } });
    if (instagramResult.error) { saving.value = false; error.value = instagramResult.error.message; return; }
  }
  saving.value = false;
  if (establishmentUpload) { editingEstablishment.value = savedRow; establishmentForm.value = { ...establishmentForm.value, photo_path: finalPath }; }
  else { if (notice.value) notice.value += ' Establishment saved.'; else notice.value = 'Establishment saved.'; resetEstablishment(); }
  await load();
}
async function saveTapa() {
  saving.value = true; error.value = ''; notice.value = '';
  const f = tapaForm.value;
  if (!valueOrNull(f.name_es) && !valueOrNull(f.name_en)) { saving.value = false; error.value = 'Enter a Spanish or English tapa name.'; return; }
  const festivalId = establishments.value.find((venue) => venue.id === f.establishment_id)?.festival_id;
  const programmeNumber = numberOrNull(f.festival_number);
  const duplicate = programmeNumber != null && tapas.value.find((item) => item.id !== editingTapa.value?.id && item.festival_number === programmeNumber && establishments.value.find((venue) => venue.id === item.establishment_id)?.festival_id === festivalId);
  if (duplicate) { saving.value = false; error.value = `Programme number ${programmeNumber} is already used in this festival.`; return; }
  const previousPath = editingTapa.value?.photo_path || null;
  const payload = { ...f, name_en: valueOrNull(f.name_en), name_es: valueOrNull(f.name_es), description_en: valueOrNull(f.description_en), description_es: valueOrNull(f.description_es), photo_path: tapaPhotoRemoveRequested.value ? null : previousPath, price_override: numberOrNull(f.price_override), festival_number: programmeNumber };
  const result = editingTapa.value ? await db().from('tapas').update(payload).eq('id', editingTapa.value.id).select().single() : await db().from('tapas').insert(payload).select().single();
  if (result.error || !result.data) { saving.value = false; error.value = result.error?.message || 'Unable to save tapa.'; return; }
  const savedRow = result.data;
  let finalPath = payload.photo_path;
  const tapaUpload = Boolean(tapaPhotoFile.value);
  if (tapaPhotoFile.value) {
    const selectedFile = tapaPhotoFile.value;
    tapaPhotoFeedback.value = { ...tapaPhotoFeedback.value, state: 'processing', error: '' };
    const uploadResult = await uploadPhoto('tapas', savedRow.id, selectedFile);
    if (uploadResult.error) { tapaPhotoFeedback.value = { ...tapaPhotoFeedback.value, state: 'error', error: uploadResult.error, storedBytes: uploadResult.storedBytes }; saving.value = false; error.value = uploadResult.error; return; }
    const photoResult = await db().from('tapas').update({ photo_path: uploadResult.path }).eq('id', savedRow.id);
    if (photoResult.error) { await removeManagedPhoto(uploadResult.path); tapaPhotoFeedback.value = { ...tapaPhotoFeedback.value, state: 'error', error: photoResult.error.message }; saving.value = false; error.value = photoResult.error.message; return; }
    finalPath = uploadResult.path;
    tapaPhotoFeedback.value = { state: 'success', originalName: uploadResult.originalName, originalBytes: uploadResult.originalBytes, storedBytes: uploadResult.storedBytes, path: uploadResult.path, error: '' };
    tapaPhotoFile.value = null;
    tapaPhotoPreview.value = publicPhotoUrl(uploadResult.path);
    notice.value = 'Photo uploaded successfully.';
  }
  if (previousPath && previousPath !== finalPath) {
    const removeError = await removeManagedPhoto(previousPath);
    if (removeError) notice.value = 'Tapa saved, but the previous image could not be removed.';
  }
  saving.value = false;
  if (tapaUpload) { editingTapa.value = savedRow; tapaForm.value = { ...tapaForm.value, photo_path: finalPath }; }
  else { if (notice.value) notice.value += ' Tapa saved.'; else notice.value = 'Tapa saved.'; resetTapa(); }
  await load();
}

watch(isSuperuser, (superuser) => {
  if (superuser && registeredUsers.value.length) void loadPromotableRegisteredUsers();
  if (!superuser) promotableRegisteredUserIds.value = new Set();
}, { immediate: true });

watch(user, () => {
  isAdmin.value = false;
  isSuperuser.value = false;
  canBootstrapInitialSuperuser.value = false;
  void checkAccess();
}, { immediate: true });
</script>

<template>
  <main class="min-h-screen bg-stone-50 p-5 text-stone-900 md:p-10">
    <div class="mx-auto max-w-7xl">
      <header class="mb-8 flex flex-wrap items-center justify-between gap-4">
        <div><p class="text-sm font-semibold text-emerald-700">tapas-festival</p><h1 class="font-display text-3xl font-bold">Admin</h1></div>
        <div class="flex flex-wrap items-center justify-end gap-3">
          <NuxtLink to="/" class="rounded-lg border border-emerald-700 px-3 py-2 text-sm font-semibold text-emerald-800 transition hover:bg-emerald-50">← Back to Festival</NuxtLink>
          <div v-if="user && isAdmin && !checkingAccess" class="flex flex-wrap items-center justify-end gap-x-2 gap-y-1 text-right text-sm text-stone-700"><span class="font-semibold">Logged in as:</span><span class="font-mono">{{ maskAdminIdentity(user.email) }}</span><span aria-hidden="true">—</span><span class="font-semibold">{{ currentAdminRoleLabel }}</span></div>
          <button v-if="user" class="rounded-lg border border-stone-300 px-3 py-2 text-sm" @click="logout">Log out</button>
        </div>
      </header>

      <section v-if="!user" class="mx-auto max-w-md rounded-xl border border-stone-200 bg-white p-6 shadow-sm">
        <h2 class="text-xl font-bold">Admin access</h2><p class="mt-1 text-sm text-stone-600">Sign in, or create the first development account.</p>
        <div class="mt-4 flex gap-2 border-b border-stone-200"><button type="button" class="border-b-2 px-3 py-2 text-sm font-semibold" :class="authMode === 'login' ? 'border-emerald-700 text-emerald-800' : 'border-transparent text-stone-500'" @click="authMode = 'login'; passwordVisible = false; error = ''; notice = ''">Sign in</button><button type="button" class="border-b-2 px-3 py-2 text-sm font-semibold" :class="authMode === 'signup' ? 'border-emerald-700 text-emerald-800' : 'border-transparent text-stone-500'" @click="authMode = 'signup'; passwordVisible = false; error = ''; notice = ''">Create account</button></div>
        <p v-if="error" class="mt-4 rounded border border-red-200 bg-red-50 p-3 text-sm text-red-800">{{ displayAdministratorMessage(error) }}</p><p v-if="notice" class="mt-4 rounded border border-emerald-200 bg-emerald-50 p-3 text-sm text-emerald-800">{{ displayAdministratorMessage(notice) }}</p>
        <form class="mt-5 space-y-3" @submit.prevent="authMode === 'login' ? login() : signup()"><input v-model="email" class="w-full rounded border p-2" type="email" autocomplete="email" placeholder="Email" required><div class="flex items-center gap-1"><input v-model="password" class="min-w-0 flex-1 rounded border p-2" :type="passwordVisible ? 'text' : 'password'" autocomplete="current-password" placeholder="Password (8+ characters)" minlength="8" required><button v-if="authMode === 'login'" type="button" class="inline-flex h-10 w-10 shrink-0 items-center justify-center rounded border border-stone-300 text-stone-600" :aria-label="passwordVisible ? 'Hide password' : 'Show password'" :title="passwordVisible ? 'Hide password' : 'Show password'" v-on:click="passwordVisible = !passwordVisible"><Icon :name="passwordVisible ? 'lucide:eye-off' : 'lucide:eye'" class="h-4 w-4" aria-hidden="true" /></button></div><button v-if="authMode === 'login'" type="button" class="text-left text-xs font-semibold text-emerald-700 hover:underline" v-on:click="openPasswordReset">Forgot password?</button><button class="w-full rounded bg-emerald-700 px-3 py-2 font-semibold text-white disabled:opacity-50" :disabled="authBusy">{{ authBusy ? 'Please wait…' : authMode === 'login' ? 'Log in' : 'Create account' }}</button></form>
      </section>

      <section v-else-if="checkingAccess" class="rounded-xl border border-stone-200 bg-white p-6 text-sm text-stone-600">Checking administrator access…</section>
      <section v-else-if="!isAdmin" class="rounded-xl border border-red-200 bg-red-50 p-6"><h2 class="text-xl font-bold text-red-900">Access denied</h2><p class="mt-1 text-sm text-red-800">This account is not an administrator.</p></section>
      <template v-else>
        <p v-if="error" class="mb-4 rounded border border-red-200 bg-red-50 p-3 text-sm text-red-800">{{ displayAdministratorMessage(error) }}</p>
        <p v-if="notice" class="mb-4 rounded border border-emerald-200 bg-emerald-50 p-3 text-sm text-emerald-800">{{ displayAdministratorMessage(notice) }}</p>
        <section v-if="canBootstrapInitialSuperuser" class="mb-6 flex flex-wrap items-center justify-between gap-3 rounded-xl border border-amber-200 bg-amber-50 p-4"><div><h2 class="font-bold text-amber-950">Initial Superadmin setup</h2><p class="mt-1 text-sm text-amber-900">This Admin account can establish the first Superadmin.</p></div><button type="button" class="rounded bg-amber-700 px-4 py-2 font-semibold text-white disabled:opacity-50" :disabled="bootstrapSaving" @click="bootstrapInitialSuperuser">{{ bootstrapSaving ? 'Please wait…' : 'Become initial Superadmin' }}</button></section>
        <nav class="mb-6 flex min-w-0 flex-wrap justify-center gap-x-2 gap-y-2 border-b border-stone-200 sm:justify-start sm:gap-2"><button v-for="item in (isSuperuser ? ['dashboard','controls','festivals','establishments','tapas','reviews','users','reports','administrators','resources','photos'] : ['dashboard','controls','festivals','establishments','tapas','reviews','users','reports','photos']) as Tab[]" :key="item" class="min-h-11 min-w-0 max-w-full border-b-2 px-3 py-2 text-sm font-semibold capitalize sm:px-4 sm:py-3" :class="tab === item ? 'border-emerald-700 text-emerald-800' : 'border-transparent text-stone-500'" @click="selectTab(item)">{{ adminTabLabel(item) }}</button></nav>
        <p v-if="loading" class="text-sm text-stone-500">Loading...</p>

        <section v-if="tab === 'dashboard'" class="space-y-5">
          <div class="flex flex-wrap items-end justify-between gap-3"><div><h2 class="text-xl font-bold">Dashboard</h2><p class="mt-1 text-sm text-stone-600">A quick view of festival activity and items needing attention.</p></div><button type="button" class="rounded border border-stone-300 px-3 py-2 text-sm font-semibold" :disabled="dashboardLoading" @click="loadDashboard">{{ dashboardLoading ? 'Loading...' : 'Refresh' }}</button></div>
          <p v-if="dashboardError" class="rounded border border-amber-200 bg-amber-50 p-3 text-sm text-amber-900">{{ dashboardError }}</p>
          <div class="grid gap-3 sm:grid-cols-2 xl:grid-cols-5"><div class="rounded-xl border bg-white p-4"><p class="text-xs font-semibold uppercase tracking-wide text-stone-500">Registered users</p><p class="mt-1 text-2xl font-bold">{{ dashboardCount('headline', 'registered_users') }}</p></div><div class="rounded-xl border bg-white p-4"><p class="text-xs font-semibold uppercase tracking-wide text-stone-500">Tapa ratings</p><p class="mt-1 text-2xl font-bold">{{ dashboardCount('headline', 'tapa_ratings_total') }}</p><p class="text-xs text-stone-500">{{ dashboardCount('headline', 'tapa_ratings_24h') }} in last 24h</p></div><div class="rounded-xl border bg-white p-4"><p class="text-xs font-semibold uppercase tracking-wide text-stone-500">Written reviews</p><p class="mt-1 text-2xl font-bold">{{ dashboardCount('headline', 'written_reviews_total') }}</p><p class="text-xs text-stone-500">{{ dashboardCount('headline', 'written_reviews_24h') }} in last 24h</p></div><div class="rounded-xl border bg-white p-4"><p class="text-xs font-semibold uppercase tracking-wide text-stone-500">Bar ratings</p><p class="mt-1 text-2xl font-bold">{{ dashboardCount('headline', 'bar_ratings_total') }}</p><p class="text-xs text-stone-500">{{ dashboardCount('headline', 'bar_ratings_24h') }} in last 24h</p></div><div class="rounded-xl border bg-white p-4"><p class="text-xs font-semibold uppercase tracking-wide text-stone-500">Active users</p><p class="mt-1 text-2xl font-bold">{{ dashboardCount('headline', 'active_users_24h') }}</p><p class="text-xs text-stone-500">Any activity in last 24h</p></div></div>
          <div class="grid gap-5 lg:grid-cols-[minmax(0,1.4fr)_minmax(320px,1fr)]"><section class="rounded-xl border bg-white p-4"><div class="flex items-center justify-between gap-3"><h3 class="font-bold">Recent activity</h3><span class="text-xs text-stone-500">Latest 15</span></div><div v-if="dashboard.recent_activity.length" class="mt-3 divide-y"><div v-for="(activity, index) in dashboard.recent_activity" :key="activity.time + activity.type + activity.user + index" class="grid gap-1 py-2 text-sm sm:grid-cols-[120px_minmax(0,1fr)_auto] sm:items-baseline"><span class="text-xs leading-tight text-stone-500"><span class="block whitespace-nowrap">{{ dashboardDate(activity.time).date }}</span><span class="block whitespace-nowrap">{{ dashboardDate(activity.time).time }}</span></span><span><strong>{{ activity.type }}</strong> - {{ activity.establishment }}<template v-if="activity.tapa"> - {{ activity.tapa }}</template><template v-if="activity.rating != null"> - {{ activity.rating }} stars</template></span><span class="font-mono text-xs text-stone-600">{{ activity.user }}</span></div></div><p v-else class="mt-3 text-sm text-stone-500">No recent activity.</p></section><section class="rounded-xl border bg-white p-4"><div class="flex items-center justify-between gap-3"><h3 class="font-bold">Most active tapas</h3><span class="text-xs text-stone-500">New ratings, 24h</span></div><ol v-if="dashboard.most_active_tapas.length" class="mt-3 space-y-2 text-sm"><li v-for="(item, index) in dashboard.most_active_tapas" :key="item.tapa + item.establishment" class="flex items-start justify-between gap-3"><span><strong>{{ index + 1 }}. {{ item.tapa }}</strong><span class="block text-xs text-stone-500">{{ item.establishment }}</span></span><span class="font-semibold">{{ item.new_ratings }}</span></li></ol><p v-else class="mt-3 text-sm text-stone-500">No new tapa ratings in the last 24 hours.</p></section></div>
          <div class="grid gap-5 lg:grid-cols-[minmax(0,1fr)_minmax(320px,1fr)]"><section class="rounded-xl border bg-white p-4"><h3 class="font-bold">Needs attention</h3><ul class="mt-3 space-y-2 text-sm"><li v-if="Number(dashboard.content.hidden_reviews) > 0" class="flex items-center justify-between gap-3"><span>{{ dashboardCount('content', 'hidden_reviews') }} hidden written reviews</span><button type="button" class="font-semibold text-emerald-700 hover:underline" @click="openHiddenReviews">View Reviews</button></li><li v-if="Number(dashboard.content.withdrawn_tapas) > 0" class="flex items-center justify-between gap-3"><span>{{ dashboardCount('content', 'withdrawn_tapas') }} withdrawn tapas</span><button type="button" class="font-semibold text-emerald-700 hover:underline" @click="openTapaAttentionFilter('withdrawn')">View Tapas</button></li><li v-if="Number(dashboard.content.bars_missing_hours) > 0" class="flex items-center justify-between gap-3"><span>{{ dashboardCount('content', 'bars_missing_hours') }} bars missing opening hours</span><button type="button" class="font-semibold text-emerald-700 hover:underline" @click="openEstablishmentAttentionFilter('missing_hours')">View Bars</button></li><li v-if="Number(dashboard.content.bars_missing_photos) > 0" class="flex items-center justify-between gap-3"><span>{{ dashboardCount('content', 'bars_missing_photos') }} bars missing photos</span><button type="button" class="font-semibold text-emerald-700 hover:underline" @click="openEstablishmentAttentionFilter('missing_photos')">View Bars</button></li><li v-if="Number(dashboard.content.tapas_missing_photos) > 0" class="flex items-center justify-between gap-3"><span>{{ dashboardCount('content', 'tapas_missing_photos') }} tapas missing photos</span><button type="button" class="font-semibold text-emerald-700 hover:underline" @click="openTapaAttentionFilter('missing_photos')">View Tapas</button></li><li v-if="!Number(dashboard.content.hidden_reviews) && !Number(dashboard.content.withdrawn_tapas) && !Number(dashboard.content.bars_missing_hours) && !Number(dashboard.content.bars_missing_photos) && !Number(dashboard.content.tapas_missing_photos)" class="text-stone-500">Nothing needs attention.</li></ul></section><section class="rounded-xl border bg-white p-4"><h3 class="font-bold">Festival content</h3><dl class="mt-3 grid grid-cols-2 gap-3 text-sm sm:grid-cols-3"><div><dt class="text-stone-500">Bars</dt><dd class="text-lg font-bold">{{ dashboardCount('content', 'establishments') }}</dd></div><div><dt class="text-stone-500">Tapas</dt><dd class="text-lg font-bold">{{ dashboardCount('content', 'tapas') }}</dd></div><div><dt class="text-stone-500">Active tapas</dt><dd class="text-lg font-bold">{{ dashboardCount('content', 'active_tapas') }}</dd></div><div><dt class="text-stone-500">Withdrawn tapas</dt><dd class="text-lg font-bold">{{ dashboardCount('content', 'withdrawn_tapas') }}</dd></div><div><dt class="text-stone-500">Hidden reviews</dt><dd class="text-lg font-bold">{{ dashboardCount('content', 'hidden_reviews') }}</dd></div></dl></section></div>
        </section>
        <section v-if="tab === 'controls'" class="space-y-5">
          <div><h2 class="text-xl font-bold">Controls</h2><p class="mt-1 text-sm text-stone-600">Operational controls for the selected festival. Emergency shutdown is site-wide.</p></div>
          <p v-if="controls?.public_read_only" class="rounded border-2 border-amber-500 bg-amber-50 p-3 font-extrabold text-amber-900">PUBLIC SITE IS CURRENTLY READ-ONLY</p>
          <div class="rounded-xl border bg-white p-4">
            <label class="block text-sm font-semibold">Festival being controlled<select v-model="controlsFestivalId" class="mt-1 block w-full rounded border p-2" @change="loadControls"><option v-for="festival in festivals" :key="festival.id" :value="festival.id">{{ controlsFestivalOptionLabel(festival) }}</option></select></label>
            <div v-if="controlsFestival" class="mt-3 rounded-lg border-2 border-amber-400 bg-amber-50 p-3 text-sm text-amber-950"><p class="font-semibold">You are changing Controls for</p><p class="mt-1 text-base font-bold">{{ controlsFestivalName(controlsFestival) }}<span v-if="controlsFestivalYear(controlsFestival)"> · {{ controlsFestivalYear(controlsFestival) }}</span></p><p class="mt-1">Publication status: <strong>{{ controlsFestivalStatus(controlsFestival) }}</strong></p></div>
          </div>
          <div v-if="controls" class="rounded-xl border bg-white p-4"><h3 class="font-bold">Status summary</h3><dl class="mt-3 grid gap-2 text-sm sm:grid-cols-2 lg:grid-cols-4"><div><dt>Public site</dt><dd class="font-bold" :class="controlsSiteShutdown ? 'text-red-700' : 'text-emerald-700'">{{ controlsSiteShutdown ? 'DISABLED' : 'ONLINE' }}</dd></div><div v-for="item in [['Festival','festival_active'],['Read-only','public_read_only'],['Ratings','ratings_enabled'],['Reviews','reviews_enabled'],['Rankings','rankings_enabled'],['Rating counts','total_rating_counts_enabled'],['Want to Try','want_to_try_enabled']]" :key="item[1]"><dt>{{ item[0] }}</dt><dd class="font-bold" :class="controls[item[1] as keyof FestivalControls] ? 'text-emerald-700' : 'text-red-700'">{{ controls[item[1] as keyof FestivalControls] ? (item[1] === 'festival_active' ? 'ACTIVE' : 'ON') : (item[1] === 'festival_active' ? 'INACTIVE' : 'OFF') }}</dd></div></dl></div>
          <div v-if="controls" class="rounded-xl border bg-white p-4"><h3 class="font-bold">Festival controls</h3><div class="mt-3 grid gap-3 sm:grid-cols-2"><label v-for="item in [['FESTIVAL ACTIVE','festival_active'],['RATINGS','ratings_enabled'],['REVIEWS','reviews_enabled'],['RANKINGS','rankings_enabled'],['TOTAL RATING COUNTS','total_rating_counts_enabled'],['WANT TO TRY','want_to_try_enabled'],['PUBLIC READ-ONLY MODE','public_read_only']]" :key="item[1]" class="flex items-center justify-between rounded border p-3 text-sm font-semibold"><span>{{ item[0] }}</span><input type="checkbox" :checked="controls[item[1] as keyof FestivalControls]" :disabled="controlsSaving === item[1]" @change="setFestivalControl(item[1] as keyof FestivalControls, ($event.target as HTMLInputElement).checked)"></label></div></div>
          <div class="rounded-xl border-2 border-red-300 bg-red-50 p-4"><h3 class="font-bold text-red-800">EMERGENCY PUBLIC SHUTDOWN</h3><p class="mt-1 text-sm text-red-800">Anonymous visitors and ordinary users will see the maintenance page. Admin and Superadmin access remains available.</p><template v-if="isSuperuser"><button v-if="!controlsSiteShutdown" type="button" class="mt-3 rounded bg-red-700 px-3 py-2 text-sm font-bold text-white" @click="shutdownConfirmOpen = true">Disable public site</button><button v-else type="button" class="mt-3 rounded border border-red-500 px-3 py-2 text-sm font-bold text-red-800" :disabled="controlsSaving === 'emergency_shutdown'" @click="setEmergencyShutdown(false)">Restore public site</button><div v-if="shutdownConfirmOpen" class="mt-3 rounded border border-red-300 bg-white p-3 text-sm"><p class="font-semibold">Public visitors/users will see the maintenance page. Admin/Superadmin access will remain available.</p><label class="mt-2 block">Type <strong>SHUTDOWN</strong><input v-model="shutdownPhrase" class="mt-1 w-full rounded border p-2" autocomplete="off"></label><div class="mt-2 flex gap-2"><button type="button" class="rounded bg-red-700 px-3 py-2 font-bold text-white" :disabled="shutdownPhrase !== 'SHUTDOWN' || controlsSaving === 'emergency_shutdown'" @click="setEmergencyShutdown(true)">Confirm shutdown</button><button type="button" class="rounded border px-3 py-2" @click="shutdownConfirmOpen = false; shutdownPhrase = ''">Cancel</button></div></div></template><p v-else class="mt-3 text-sm font-semibold text-red-800">Only a Superadmin can change this control.</p></div>
          <div class="overflow-x-auto rounded-xl border bg-white"><div class="p-4"><h3 class="font-bold">Recent Controls activity</h3></div><table class="w-full text-left text-sm"><thead class="bg-stone-100"><tr><th class="p-3">Date/time</th><th class="p-3">Administrator</th><th class="p-3">Control</th><th class="p-3">Old value</th><th class="p-3">New value</th></tr></thead><tbody><tr v-for="row in controlsAudit" :key="row.created_at + row.control" class="border-t"><td class="p-3">{{ adminDateTimeLines(row.created_at).date }} {{ adminDateTimeLines(row.created_at).time }}</td><td class="p-3">{{ row.administrator }}</td><td class="p-3">{{ row.control }}</td><td class="p-3">{{ row.previous_value ? 'ON' : 'OFF' }}</td><td class="p-3">{{ row.new_value ? 'ON' : 'OFF' }}</td></tr><tr v-if="!controlsAudit.length"><td colspan="5" class="p-4 text-stone-500">No control changes recorded.</td></tr></tbody></table></div>
        </section>

        <section v-if="tab === 'festivals'" class="grid gap-8 lg:grid-cols-[minmax(0,1fr)_380px]"><div><h2 class="mb-3 text-xl font-bold">Festivals</h2><div class="overflow-x-auto rounded-xl border bg-white"><table class="w-full text-left text-sm"><thead class="bg-stone-100"><tr><th class="p-3">Name</th><th class="p-3">Dates</th><th class="p-3">Status</th><th class="p-3"></th></tr></thead><tbody><tr v-for="row in festivals" :key="row.id" class="border-t"><td class="p-3">{{ row.name_en || row.name_es }}</td><td class="p-3">{{ row.start_date }} – {{ row.end_date }}</td><td class="p-3">{{ row.publication_status }}</td><td class="p-3"><button class="text-emerald-700" @click="editFestival(row)">Edit</button></td></tr></tbody></table></div></div><form class="space-y-3 rounded-xl border bg-white p-5" @submit.prevent="saveFestival"><h2 class="text-lg font-bold">{{ editingFestival ? 'Edit festival' : 'New festival' }}</h2><input v-model="festivalForm.name_en" class="w-full rounded border p-2" placeholder="English name" required @input="updateGeneratedSlug"><input v-model="festivalForm.name_es" class="w-full rounded border p-2" placeholder="Spanish name"><input v-model="festivalForm.slug" class="w-full rounded border p-2" placeholder="slug" required @input="markSlugManual"><div class="grid grid-cols-2 gap-2"><input v-model="festivalForm.start_date" class="rounded border p-2" type="date" required><input v-model="festivalForm.end_date" class="rounded border p-2" type="date" required></div><input v-model="festivalForm.city" class="w-full rounded border p-2" placeholder="City" required><input v-model="festivalForm.default_tapa_price" class="w-full rounded border p-2" type="number" min="0" step="0.01" placeholder="Default price" required><select v-model="festivalForm.publication_status" class="w-full rounded border p-2"><option value="draft">Draft</option><option value="published">Published</option><option value="archived">Archived</option></select><label class="flex gap-2 text-sm"><input v-model="festivalForm.reviews_enabled" type="checkbox"> Reviews enabled</label><label class="flex gap-2 text-sm"><input v-model="festivalForm.show_rankings" type="checkbox"> Show rankings</label><label class="flex gap-2 text-sm"><input v-model="festivalForm.show_total_rating_count" type="checkbox"> Show total tapa ratings</label><div class="flex gap-2"><button class="rounded bg-emerald-700 px-3 py-2 text-white" :disabled="saving">Save</button><button type="button" class="rounded border px-3 py-2" @click="resetFestival">Clear</button></div></form></section>

        <section v-if="tab === 'establishments'" class="grid gap-8 lg:grid-cols-[minmax(0,1fr)_440px]">
          <div><div class="mb-3 flex flex-wrap items-end justify-between gap-3"><div><h2 class="text-xl font-bold">Establishments</h2><p v-if="establishmentAttentionFilter !== 'all'" class="mt-1 text-sm text-stone-600">Filter: {{ establishmentAttentionLabel }} · {{ filteredEstablishments.length }} result{{ filteredEstablishments.length === 1 ? '' : 's' }}</p></div><label class="text-sm font-semibold">Sort<select v-model="establishmentSort" class="ml-2 rounded border p-1.5 font-normal"><option value="number">Number</option><option value="alphabetical">A–Z</option></select></label><button v-if="establishmentAttentionFilter !== 'all'" type="button" class="rounded border px-3 py-1.5 text-sm font-semibold" @click="clearEstablishmentAttentionFilter">Show all</button></div><div class="overflow-x-auto rounded-xl border bg-white"><table class="w-full text-left text-sm"><thead class="bg-stone-100"><tr><th class="p-3">Number</th><th class="p-3">Name</th><th class="p-3">Address</th><th class="p-3">Festival</th><th class="p-3">Photo</th><th class="p-3">Hours</th><th class="p-3">Status</th><th class="p-3"></th></tr></thead><tbody><template v-for="row in filteredEstablishments" :key="row.id"><tr class="border-t"><td class="p-3 tabular-nums">{{ establishmentNumber(row) ?? '—' }}</td><td class="p-3 font-medium">{{ row.name }}</td><td class="p-3">{{ row.address || '—' }}</td><td class="p-3">{{ festivals.find(f => f.id === row.festival_id)?.name_en || '—' }}</td><td class="whitespace-nowrap p-3">{{ missingPhoto(row) ? 'Missing' : 'Present' }}</td><td class="whitespace-nowrap p-3">{{ missingOpeningHours(row) ? 'Missing' : 'Present' }}</td><td class="p-3"><span class="rounded-full px-2 py-1 text-xs font-semibold" :class="row.participation_status === 'withdrawn' ? 'bg-red-100 text-red-800' : 'bg-emerald-100 text-emerald-800'">{{ row.participation_status === 'withdrawn' ? 'Suspended' : 'Active' }}</span></td><td class="p-3"><div class="flex flex-wrap items-center gap-2"><button type="button" class="font-semibold" :class="row.participation_status === 'withdrawn' ? 'text-emerald-700' : 'text-red-700'" :disabled="saving" @click="toggleEstablishmentParticipation(row)">{{ row.participation_status === 'withdrawn' ? 'Reactivate' : 'Suspend' }}</button><button type="button" class="font-semibold text-emerald-700" @click="editEstablishment(row)">Edit</button></div></td></tr><tr v-if="editingEstablishment?.id === row.id" class="border-t bg-stone-50 lg:hidden"><td colspan="7" class="p-3"><form ref="establishmentFormElement" class="lg:hidden scroll-mt-4 space-y-4 rounded-xl border bg-white p-5" @submit.prevent="saveEstablishment">
            <div class="mb-3 flex items-center justify-between gap-3"><h2 class="text-lg font-bold">{{ editingEstablishment ? 'Edit establishment' : 'New establishment' }}</h2><button type="button" class="lg:hidden rounded border px-2 py-1 text-sm font-semibold" @click="closeEstablishmentEditor">Close editor</button></div>
            <select v-model="establishmentForm.festival_id" class="w-full rounded border p-2" required><option value="" disabled>Festival</option><option v-for="f in festivals" :key="f.id" :value="f.id">{{ f.name_en || f.name_es }}</option></select>
            <div class="grid gap-3 sm:grid-cols-2"><input v-model="establishmentForm.name" class="rounded border p-2 sm:col-span-2" placeholder="Name" required><input v-model="establishmentForm.address" class="rounded border p-2 sm:col-span-2" placeholder="Address"><label class="block text-sm font-medium text-stone-700 sm:col-span-2">Google Maps coordinates<input v-model="establishmentForm.coordinates" class="mt-1 w-full rounded border p-2 font-mono text-sm" type="text" inputmode="decimal" placeholder="39.979579659748154, -0.030992736520370705"></label><div class="sm:col-span-2 rounded border border-stone-200 p-3"><p class="text-sm font-semibold">Photo</p><div v-if="establishmentPhotoFeedback.state !== 'idle'" class="mt-2 rounded border p-3 text-sm" :class="establishmentPhotoFeedback.state === 'success' ? 'border-emerald-300 bg-emerald-50 text-emerald-900' : establishmentPhotoFeedback.state === 'error' ? 'border-red-300 bg-red-50 text-red-900' : 'border-stone-200 bg-stone-50 text-stone-700'"><p class="font-semibold">{{ establishmentPhotoFeedback.state === 'success' ? '✓ Photo uploaded successfully' : establishmentPhotoFeedback.state === 'processing' ? 'Compressing and uploading…' : establishmentPhotoFeedback.state === 'error' ? 'Photo upload failed' : 'Photo selected — not uploaded yet' }}</p><p v-if="establishmentPhotoFeedback.originalName" class="mt-1 break-all text-xs">{{ establishmentPhotoFeedback.originalName }}</p><p v-if="establishmentPhotoFeedback.originalBytes" class="text-xs">Original: {{ formatPhotoSize(establishmentPhotoFeedback.originalBytes) }}</p><template v-if="establishmentPhotoFeedback.state === 'success'"><p>Saved: {{ formatPhotoSize(establishmentPhotoFeedback.storedBytes) }} · Reduction: {{ photoReduction(establishmentPhotoFeedback) }}%</p><p class="mt-1 break-all text-xs">Stored: {{ establishmentPhotoFeedback.path }}</p></template><p v-if="establishmentPhotoFeedback.error" class="mt-1 text-xs">{{ establishmentPhotoFeedback.error }}</p></div><div v-if="establishmentPhotoPreview" class="mt-2 flex flex-wrap items-center gap-3"><img :src="establishmentPhotoPreview" alt="Establishment preview" class="h-20 w-20 rounded object-cover"><button type="button" class="rounded border px-3 py-2 text-sm font-semibold" @click="requestEstablishmentPhotoRemoval">Remove photo</button></div><label class="mt-2 inline-flex cursor-pointer rounded border px-3 py-2 text-sm font-semibold"><span>{{ establishmentPhotoPreview ? "Replace photo" : "Choose photo / Upload photo" }}</span><input class="sr-only" type="file" accept="image/jpeg,image/png,image/webp" @change="chooseEstablishmentPhoto"></label><p class="mt-1 text-xs text-stone-500">JPEG, PNG or WebP · maximum 5 MB</p></div><input v-model="establishmentForm.phone" class="rounded border p-2" placeholder="Phone"><input v-model="establishmentForm.instagram" class="rounded border p-2" placeholder="Instagram"><input v-model="establishmentForm.facebook_url" class="rounded border p-2" placeholder="Facebook URL"><input v-model="establishmentForm.whatsapp" class="rounded border p-2" placeholder="WhatsApp"><input v-model="establishmentForm.website_url" class="rounded border p-2 sm:col-span-2" placeholder="Website"></div>
            <p class="text-xs text-stone-500">Paste latitude, longitude from Google Maps. Leave blank when no coordinates are available.</p>
            <textarea v-model="establishmentForm.hours_notes_en" class="w-full rounded border p-2" placeholder="Opening-hours notes (English)"/><textarea v-model="establishmentForm.hours_notes_es" class="w-full rounded border p-2" placeholder="Opening-hours notes (Spanish)"/>
            <details class="rounded border border-stone-200 p-3"><summary class="cursor-pointer text-sm font-semibold">Descriptions and closure details</summary><div class="mt-3 space-y-3"><textarea v-model="establishmentForm.description_en" class="w-full rounded border p-2" placeholder="English description"/><textarea v-model="establishmentForm.description_es" class="w-full rounded border p-2" placeholder="Spanish description"/><select v-model="establishmentForm.closure_status" class="w-full rounded border p-2"><option value="normal">Normal</option><option value="temporarily_closed">Temporarily closed</option><option value="permanently_closed">Permanently closed</option></select></div></details>
            <div class="grid gap-3 sm:grid-cols-2"><label class="flex items-center gap-2 text-sm"><input v-model="establishmentForm.is_published" type="checkbox"> Published</label><select v-model="establishmentForm.participation_status" class="rounded border p-2"><option value="active">Active</option><option value="withdrawn">Suspended</option></select></div><div class="flex gap-2"><button class="rounded bg-emerald-700 px-3 py-2 text-white" :disabled="saving">Save</button><button type="button" class="rounded border px-3 py-2" @click="resetEstablishment">Clear</button></div>
          </form></td></tr></template><tr v-if="!filteredEstablishments.length"><td colspan="7" class="p-5 text-center text-stone-500">No bars match this filter.</td></tr></tbody></table></div></div>
          <form class="hidden lg:block scroll-mt-4 space-y-4 rounded-xl border bg-white p-5" @submit.prevent="saveEstablishment">
            <div class="mb-3 flex items-center justify-between gap-3"><h2 class="text-lg font-bold">{{ editingEstablishment ? 'Edit establishment' : 'New establishment' }}</h2><button type="button" class="lg:hidden rounded border px-2 py-1 text-sm font-semibold" @click="closeEstablishmentEditor">Close editor</button></div>
            <select v-model="establishmentForm.festival_id" class="w-full rounded border p-2" required><option value="" disabled>Festival</option><option v-for="f in festivals" :key="f.id" :value="f.id">{{ f.name_en || f.name_es }}</option></select>
            <div class="grid gap-3 sm:grid-cols-2"><input v-model="establishmentForm.name" class="rounded border p-2 sm:col-span-2" placeholder="Name" required><input v-model="establishmentForm.address" class="rounded border p-2 sm:col-span-2" placeholder="Address"><label class="block text-sm font-medium text-stone-700 sm:col-span-2">Google Maps coordinates<input v-model="establishmentForm.coordinates" class="mt-1 w-full rounded border p-2 font-mono text-sm" type="text" inputmode="decimal" placeholder="39.979579659748154, -0.030992736520370705"></label><div class="sm:col-span-2 rounded border border-stone-200 p-3"><p class="text-sm font-semibold">Photo</p><div v-if="establishmentPhotoFeedback.state !== 'idle'" class="mt-2 rounded border p-3 text-sm" :class="establishmentPhotoFeedback.state === 'success' ? 'border-emerald-300 bg-emerald-50 text-emerald-900' : establishmentPhotoFeedback.state === 'error' ? 'border-red-300 bg-red-50 text-red-900' : 'border-stone-200 bg-stone-50 text-stone-700'"><p class="font-semibold">{{ establishmentPhotoFeedback.state === 'success' ? '✓ Photo uploaded successfully' : establishmentPhotoFeedback.state === 'processing' ? 'Compressing and uploading…' : establishmentPhotoFeedback.state === 'error' ? 'Photo upload failed' : 'Photo selected — not uploaded yet' }}</p><p v-if="establishmentPhotoFeedback.originalName" class="mt-1 break-all text-xs">{{ establishmentPhotoFeedback.originalName }}</p><p v-if="establishmentPhotoFeedback.originalBytes" class="text-xs">Original: {{ formatPhotoSize(establishmentPhotoFeedback.originalBytes) }}</p><template v-if="establishmentPhotoFeedback.state === 'success'"><p>Saved: {{ formatPhotoSize(establishmentPhotoFeedback.storedBytes) }} · Reduction: {{ photoReduction(establishmentPhotoFeedback) }}%</p><p class="mt-1 break-all text-xs">Stored: {{ establishmentPhotoFeedback.path }}</p></template><p v-if="establishmentPhotoFeedback.error" class="mt-1 text-xs">{{ establishmentPhotoFeedback.error }}</p></div><div v-if="establishmentPhotoPreview" class="mt-2 flex flex-wrap items-center gap-3"><img :src="establishmentPhotoPreview" alt="Establishment preview" class="h-20 w-20 rounded object-cover"><button type="button" class="rounded border px-3 py-2 text-sm font-semibold" @click="requestEstablishmentPhotoRemoval">Remove photo</button></div><label class="mt-2 inline-flex cursor-pointer rounded border px-3 py-2 text-sm font-semibold"><span>{{ establishmentPhotoPreview ? "Replace photo" : "Choose photo / Upload photo" }}</span><input class="sr-only" type="file" accept="image/jpeg,image/png,image/webp" @change="chooseEstablishmentPhoto"></label><p class="mt-1 text-xs text-stone-500">JPEG, PNG or WebP · maximum 5 MB</p></div><input v-model="establishmentForm.phone" class="rounded border p-2" placeholder="Phone"><input v-model="establishmentForm.instagram" class="rounded border p-2" placeholder="Instagram"><input v-model="establishmentForm.facebook_url" class="rounded border p-2" placeholder="Facebook URL"><input v-model="establishmentForm.whatsapp" class="rounded border p-2" placeholder="WhatsApp"><input v-model="establishmentForm.website_url" class="rounded border p-2 sm:col-span-2" placeholder="Website"></div>
            <p class="text-xs text-stone-500">Paste latitude, longitude from Google Maps. Leave blank when no coordinates are available.</p>
            <textarea v-model="establishmentForm.hours_notes_en" class="w-full rounded border p-2" placeholder="Opening-hours notes (English)"/><textarea v-model="establishmentForm.hours_notes_es" class="w-full rounded border p-2" placeholder="Opening-hours notes (Spanish)"/>
            <details class="rounded border border-stone-200 p-3"><summary class="cursor-pointer text-sm font-semibold">Descriptions and closure details</summary><div class="mt-3 space-y-3"><textarea v-model="establishmentForm.description_en" class="w-full rounded border p-2" placeholder="English description"/><textarea v-model="establishmentForm.description_es" class="w-full rounded border p-2" placeholder="Spanish description"/><select v-model="establishmentForm.closure_status" class="w-full rounded border p-2"><option value="normal">Normal</option><option value="temporarily_closed">Temporarily closed</option><option value="permanently_closed">Permanently closed</option></select></div></details>
            <div class="grid gap-3 sm:grid-cols-2"><label class="flex items-center gap-2 text-sm"><input v-model="establishmentForm.is_published" type="checkbox"> Published</label><select v-model="establishmentForm.participation_status" class="rounded border p-2"><option value="active">Active</option><option value="withdrawn">Suspended</option></select></div><div class="flex gap-2"><button class="rounded bg-emerald-700 px-3 py-2 text-white" :disabled="saving">Save</button><button type="button" class="rounded border px-3 py-2" @click="resetEstablishment">Clear</button></div>
          </form>
        </section>

        <section v-if="tab === 'tapas'" class="grid gap-8 lg:grid-cols-[minmax(0,1fr)_440px]">
          <div><div class="mb-3 flex flex-wrap items-end justify-between gap-3"><div><h2 class="text-xl font-bold">Tapas</h2><p v-if="tapaAttentionFilter !== 'all'" class="mt-1 text-sm text-stone-600">Filter: {{ tapaAttentionLabel }} · {{ filteredTapas.length }} result{{ filteredTapas.length === 1 ? '' : 's' }}</p></div><button v-if="tapaAttentionFilter !== 'all'" type="button" class="rounded border px-3 py-1.5 text-sm font-semibold" @click="clearTapaAttentionFilter">Show all</button></div><div class="overflow-x-auto rounded-xl border bg-white"><table class="w-full text-left text-sm"><thead class="bg-stone-100"><tr><th class="p-3">Name</th><th class="p-3">Establishment</th><th class="p-3">Photo</th><th class="p-3">Participation</th><th class="p-3">Price</th><th class="p-3"></th></tr></thead><tbody><template v-for="row in filteredTapas" :key="row.id"><tr class="border-t"><td class="p-3 font-medium">{{ row.name_en || row.name_es }}</td><td class="p-3">{{ establishments.find(e => e.id === row.establishment_id)?.name || '—' }}</td><td class="whitespace-nowrap p-3">{{ missingPhoto(row) ? 'Missing' : 'Present' }}</td><td class="p-3">{{ row.participation_status }}</td><td class="p-3">{{ row.price_override ?? festivals.find(f => f.id === establishments.find(e => e.id === row.establishment_id)?.festival_id)?.default_tapa_price ?? '—' }}</td><td class="p-3"><button type="button" class="font-semibold text-emerald-700" @click="editTapa(row)">Edit</button></td></tr><tr v-if="editingTapa?.id === row.id" class="border-t bg-stone-50 lg:hidden"><td colspan="6" class="p-3"><form ref="tapaFormElement" class="lg:hidden scroll-mt-4 space-y-4 rounded-xl border bg-white p-5" @submit.prevent="saveTapa"><div class="mb-3 flex items-center justify-between gap-3"><h2 class="text-lg font-bold">{{ editingTapa ? 'Edit tapa' : 'New tapa' }}</h2><button type="button" class="lg:hidden rounded border px-2 py-1 text-sm font-semibold" @click="closeTapaEditor">Close editor</button></div><select v-model="tapaForm.establishment_id" class="w-full rounded border p-2" required><option value="" disabled>Establishment</option><option v-for="e in establishments" :key="e.id" :value="e.id">{{ e.name }}</option></select><div class="grid gap-3 sm:grid-cols-2"><input v-model="tapaForm.festival_number" class="rounded border p-2" type="number" min="1" placeholder="Programme number"><input v-model="tapaForm.price_override" class="rounded border p-2" type="number" min="0" step="0.01" placeholder="Price override (optional)"><input v-model="tapaForm.name_es" class="rounded border p-2 sm:col-span-2" placeholder="Spanish name"><input v-model="tapaForm.name_en" class="rounded border p-2 sm:col-span-2" placeholder="English name"><textarea v-model="tapaForm.description_es" class="min-h-24 rounded border p-2" placeholder="Spanish description"/><textarea v-model="tapaForm.description_en" class="min-h-24 rounded border p-2" placeholder="English description"/><div class="sm:col-span-2 rounded border border-stone-200 p-3"><p class="text-sm font-semibold">Photo</p><div v-if="tapaPhotoFeedback.state !== 'idle'" class="mt-2 rounded border p-3 text-sm" :class="tapaPhotoFeedback.state === 'success' ? 'border-emerald-300 bg-emerald-50 text-emerald-900' : tapaPhotoFeedback.state === 'error' ? 'border-red-300 bg-red-50 text-red-900' : 'border-stone-200 bg-stone-50 text-stone-700'"><p class="font-semibold">{{ tapaPhotoFeedback.state === 'success' ? '✓ Photo uploaded successfully' : tapaPhotoFeedback.state === 'processing' ? 'Compressing and uploading…' : tapaPhotoFeedback.state === 'error' ? 'Photo upload failed' : 'Photo selected — not uploaded yet' }}</p><p v-if="tapaPhotoFeedback.originalName" class="mt-1 break-all text-xs">{{ tapaPhotoFeedback.originalName }}</p><p v-if="tapaPhotoFeedback.originalBytes" class="text-xs">Original: {{ formatPhotoSize(tapaPhotoFeedback.originalBytes) }}</p><template v-if="tapaPhotoFeedback.state === 'success'"><p>Saved: {{ formatPhotoSize(tapaPhotoFeedback.storedBytes) }} · Reduction: {{ photoReduction(tapaPhotoFeedback) }}%</p><p class="mt-1 break-all text-xs">Stored: {{ tapaPhotoFeedback.path }}</p></template><p v-if="tapaPhotoFeedback.error" class="mt-1 text-xs">{{ tapaPhotoFeedback.error }}</p></div><div v-if="tapaPhotoPreview" class="mt-2 flex flex-wrap items-center gap-3"><img :src="tapaPhotoPreview" alt="Tapa preview" class="h-20 w-20 rounded object-cover"><button type="button" class="rounded border px-3 py-2 text-sm font-semibold" @click="requestTapaPhotoRemoval">Remove photo</button></div><label class="mt-2 inline-flex cursor-pointer rounded border px-3 py-2 text-sm font-semibold"><span>{{ tapaPhotoPreview ? "Replace photo" : "Choose photo / Upload photo" }}</span><input class="sr-only" type="file" accept="image/jpeg,image/png,image/webp" @change="chooseTapaPhoto"></label><p class="mt-1 text-xs text-stone-500">JPEG, PNG or WebP · maximum 5 MB</p></div></div><p class="text-xs text-stone-500">Leave price blank to use the festival default.</p><div class="grid gap-3 sm:grid-cols-2"><label class="flex items-center gap-2 text-sm"><input v-model="tapaForm.is_published" type="checkbox"> Published</label><select v-model="tapaForm.participation_status" class="rounded border p-2"><option value="active">Active</option><option value="withdrawn">Withdrawn</option></select></div><div class="flex gap-2"><button class="rounded bg-emerald-700 px-3 py-2 text-white" :disabled="saving">Save</button><button type="button" class="rounded border px-3 py-2" @click="resetTapa">Clear</button></div></form></td></tr></template><tr v-if="!filteredTapas.length"><td colspan="6" class="p-5 text-center text-stone-500">No tapas match this filter.</td></tr></tbody></table></div></div>
          <form class="hidden lg:block scroll-mt-4 space-y-4 rounded-xl border bg-white p-5" @submit.prevent="saveTapa"><div class="mb-3 flex items-center justify-between gap-3"><h2 class="text-lg font-bold">{{ editingTapa ? 'Edit tapa' : 'New tapa' }}</h2><button type="button" class="lg:hidden rounded border px-2 py-1 text-sm font-semibold" @click="closeTapaEditor">Close editor</button></div><select v-model="tapaForm.establishment_id" class="w-full rounded border p-2" required><option value="" disabled>Establishment</option><option v-for="e in establishments" :key="e.id" :value="e.id">{{ e.name }}</option></select><div class="grid gap-3 sm:grid-cols-2"><input v-model="tapaForm.festival_number" class="rounded border p-2" type="number" min="1" placeholder="Programme number"><input v-model="tapaForm.price_override" class="rounded border p-2" type="number" min="0" step="0.01" placeholder="Price override (optional)"><input v-model="tapaForm.name_es" class="rounded border p-2 sm:col-span-2" placeholder="Spanish name"><input v-model="tapaForm.name_en" class="rounded border p-2 sm:col-span-2" placeholder="English name"><textarea v-model="tapaForm.description_es" class="min-h-24 rounded border p-2" placeholder="Spanish description"/><textarea v-model="tapaForm.description_en" class="min-h-24 rounded border p-2" placeholder="English description"/><div class="sm:col-span-2 rounded border border-stone-200 p-3"><p class="text-sm font-semibold">Photo</p><div v-if="tapaPhotoFeedback.state !== 'idle'" class="mt-2 rounded border p-3 text-sm" :class="tapaPhotoFeedback.state === 'success' ? 'border-emerald-300 bg-emerald-50 text-emerald-900' : tapaPhotoFeedback.state === 'error' ? 'border-red-300 bg-red-50 text-red-900' : 'border-stone-200 bg-stone-50 text-stone-700'"><p class="font-semibold">{{ tapaPhotoFeedback.state === 'success' ? '✓ Photo uploaded successfully' : tapaPhotoFeedback.state === 'processing' ? 'Compressing and uploading…' : tapaPhotoFeedback.state === 'error' ? 'Photo upload failed' : 'Photo selected — not uploaded yet' }}</p><p v-if="tapaPhotoFeedback.originalName" class="mt-1 break-all text-xs">{{ tapaPhotoFeedback.originalName }}</p><p v-if="tapaPhotoFeedback.originalBytes" class="text-xs">Original: {{ formatPhotoSize(tapaPhotoFeedback.originalBytes) }}</p><template v-if="tapaPhotoFeedback.state === 'success'"><p>Saved: {{ formatPhotoSize(tapaPhotoFeedback.storedBytes) }} · Reduction: {{ photoReduction(tapaPhotoFeedback) }}%</p><p class="mt-1 break-all text-xs">Stored: {{ tapaPhotoFeedback.path }}</p></template><p v-if="tapaPhotoFeedback.error" class="mt-1 text-xs">{{ tapaPhotoFeedback.error }}</p></div><div v-if="tapaPhotoPreview" class="mt-2 flex flex-wrap items-center gap-3"><img :src="tapaPhotoPreview" alt="Tapa preview" class="h-20 w-20 rounded object-cover"><button type="button" class="rounded border px-3 py-2 text-sm font-semibold" @click="requestTapaPhotoRemoval">Remove photo</button></div><label class="mt-2 inline-flex cursor-pointer rounded border px-3 py-2 text-sm font-semibold"><span>{{ tapaPhotoPreview ? "Replace photo" : "Choose photo / Upload photo" }}</span><input class="sr-only" type="file" accept="image/jpeg,image/png,image/webp" @change="chooseTapaPhoto"></label><p class="mt-1 text-xs text-stone-500">JPEG, PNG or WebP · maximum 5 MB</p></div></div><p class="text-xs text-stone-500">Leave price blank to use the festival default.</p><div class="grid gap-3 sm:grid-cols-2"><label class="flex items-center gap-2 text-sm"><input v-model="tapaForm.is_published" type="checkbox"> Published</label><select v-model="tapaForm.participation_status" class="rounded border p-2"><option value="active">Active</option><option value="withdrawn">Withdrawn</option></select></div><div class="flex gap-2"><button class="rounded bg-emerald-700 px-3 py-2 text-white" :disabled="saving">Save</button><button type="button" class="rounded border px-3 py-2" @click="resetTapa">Clear</button></div></form>
        </section>
        <section v-if="tab === 'reports'" class="space-y-5">
          <div class="flex flex-wrap items-end justify-between gap-3"><div><h2 class="text-xl font-bold">Reports</h2><p class="mt-1 text-sm text-stone-600">Admin-only festival activity reports.</p></div><button type="button" class="rounded border border-stone-300 px-3 py-2 text-sm font-semibold" :disabled="reportLoading" @click="loadRatingActivity">{{ reportLoading ? 'Loading…' : 'Refresh' }}</button></div>
          <section class="rounded-xl border bg-white p-4"><h3 class="font-bold">User Rating Activity</h3><div class="mt-3 grid gap-3 sm:grid-cols-3"><label class="text-sm font-semibold">Festival<select v-model="reportFestivalId" class="mt-1 w-full rounded border p-2 font-normal" @change="loadRatingActivity"><option value="">All festivals</option><option v-for="festival in festivals" :key="festival.id" :value="festival.id">{{ festival.name_en || festival.name_es }}</option></select></label><label class="text-sm font-semibold">User<select v-model="reportUserLabel" class="mt-1 w-full rounded border p-2 font-normal"><option value="">All users</option><option v-for="label in reportUsers" :key="label" :value="label">{{ label }}</option></select></label><label class="text-sm font-semibold">Rating type<select v-model="reportRatingType" class="mt-1 w-full rounded border p-2 font-normal"><option value="all">All</option><option value="tapa">Tapa</option><option value="bar">Bar</option></select></label></div></section>
          <div class="grid gap-3 sm:grid-cols-4"><div class="rounded-xl border bg-white p-4"><p class="text-sm text-stone-500">Users who have rated</p><p class="mt-1 text-2xl font-bold">{{ reportSummary.users }}</p></div><div class="rounded-xl border bg-white p-4"><p class="text-sm text-stone-500">Tapa ratings</p><p class="mt-1 text-2xl font-bold">{{ reportSummary.tapa }}</p></div><div class="rounded-xl border bg-white p-4"><p class="text-sm text-stone-500">Bar ratings</p><p class="mt-1 text-2xl font-bold">{{ reportSummary.bar }}</p></div><div class="rounded-xl border bg-white p-4"><p class="text-sm text-stone-500">Total ratings</p><p class="mt-1 text-2xl font-bold">{{ reportSummary.total }}</p></div></div>
          <div class="overflow-x-auto rounded-xl border bg-white"><table class="w-full min-w-[680px] text-left text-sm"><thead class="bg-stone-100"><tr><th class="p-3">User</th><th class="p-3 text-right">Tapa ratings</th><th class="p-3 text-right">Bar ratings</th><th class="p-3 text-right">Total</th><th class="p-3"></th></tr></thead><tbody><template v-for="row in filteredReportRows" :key="reportRowKey(row)"><tr class="border-t"><td class="p-3 font-medium">{{ row.user_label }}</td><td class="p-3 text-right">{{ row.tapa_rating_count }}</td><td class="p-3 text-right">{{ row.bar_rating_count }}</td><td class="p-3 text-right font-bold">{{ row.total_rating_count }}</td><td class="p-3 text-right"><button type="button" class="font-semibold text-emerald-700" :aria-expanded="Boolean(expandedReportRows[reportRowKey(row)])" @click="toggleReportRow(row)">{{ expandedReportRows[reportRowKey(row)] ? 'Hide' : 'Details' }}</button></td></tr><tr v-if="expandedReportRows[reportRowKey(row)]" class="border-t bg-stone-50"><td colspan="5" class="p-4"><div class="grid gap-5 md:grid-cols-2"><section v-if="reportRatingType !== 'bar'"><h4 class="font-semibold">Tapas rated</h4><ul v-if="row.tapa_ratings.length" class="mt-2 space-y-1 text-sm"><li v-for="(rating, index) in row.tapa_ratings" :key="`${rating.establishment_name}-${rating.tapa_name}-${index}`"><span class="font-medium">{{ rating.establishment_name }}</span> · {{ rating.tapa_name }} · {{ Number(rating.rating).toFixed(1) }} ★</li></ul><p v-else class="mt-2 text-sm text-stone-500">No tapa ratings.</p></section><section v-if="reportRatingType !== 'tapa'"><h4 class="font-semibold">Bars rated</h4><ul v-if="row.bar_ratings.length" class="mt-2 space-y-1 text-sm"><li v-for="(rating, index) in row.bar_ratings" :key="`${rating.establishment_name}-${index}`"><span class="font-medium">{{ rating.establishment_name }}</span> · {{ Number(rating.rating).toFixed(1) }} ★</li></ul><p v-else class="mt-2 text-sm text-stone-500">No bar ratings.</p></section></div></td></tr></template><tr v-if="!filteredReportRows.length && !reportLoading"><td colspan="5" class="p-5 text-center text-stone-500">No matching rating activity.</td></tr></tbody></table></div>
          <section class="rounded-xl border bg-white p-4"><h3 class="font-bold">Tapa Rating Detail</h3><div class="mt-3 grid gap-3 sm:grid-cols-3"><label class="text-sm font-semibold sm:col-span-2">Tapa<select v-model="detailTapaId" class="mt-1 w-full rounded border p-2 font-normal" @change="loadTapaRatingDetail"><option value="">Select a tapa</option><option v-for="tapa in reportTapas" :key="tapa.id" :value="tapa.id">{{ tapa.festival_number || "—" }} · {{ establishments.find((venue) => venue.id === tapa.establishment_id)?.name }} · {{ tapa.name_en || tapa.name_es }}</option></select></label><label class="text-sm font-semibold">Sort<select v-model="detailSort" class="mt-1 w-full rounded border p-2 font-normal"><option value="newest">Newest</option><option value="rating">Rating</option></select></label></div><div v-if="detailRows.length" class="mt-4"><p class="text-sm font-semibold">{{ detailRows[0].programme_number || "—" }} · {{ detailRows[0].establishment_name }} · {{ detailRows[0].tapa_name }}</p><p class="mt-1 text-sm">{{ detailRows[0].total_rating_count }} numeric ratings · {{ detailRows[0].average_rating == null ? "—" : Number(detailRows[0].average_rating).toFixed(1) }} ★</p><p class="text-xs text-stone-600">1.0–1.9: {{ detailRows[0].rating_1_19_count }} · 2.0–2.9: {{ detailRows[0].rating_2_29_count }} · 3.0–3.9: {{ detailRows[0].rating_3_39_count }} · 4.0–4.4: {{ detailRows[0].rating_4_44_count }} · 4.5–5.0: {{ detailRows[0].rating_45_50_count }}</p><div class="mt-3 overflow-x-auto"><table class="w-full min-w-[620px] text-left text-sm"><thead class="bg-stone-100"><tr><th class="p-2">User</th><th class="p-2">Rating</th><th class="p-2">Review</th><th class="p-2">Date</th></tr></thead><tbody><tr v-for="row in sortedDetailRows" :key="row.user_label + row.created_at" class="border-t"><td class="p-2">{{ row.user_label }}</td><td class="p-2">{{ row.rating == null ? "—" : Number(row.rating).toFixed(1) }}</td><td class="p-2">{{ row.review_text || "—" }}</td><td class="p-2"><span v-if="row.created_at" class="block whitespace-nowrap leading-tight">{{ adminDateTimeLines(row.created_at).date }}<span class="block">{{ adminDateTimeLines(row.created_at).time }}</span></span><span v-else>—</span></td></tr></tbody></table></div></div><p v-else-if="detailTapaId && !detailLoading" class="mt-3 text-sm text-stone-500">No current votes.</p></section>
        </section>

        <section v-if="tab === 'reviews'" class="space-y-5">
          <div class="flex flex-wrap items-end justify-between gap-3">
            <div><h2 class="text-xl font-bold">Reviews</h2><p class="mt-1 text-sm text-stone-600">Review written tapa feedback and hide or restore it without changing numeric ratings.</p></div>
            <p class="text-sm text-stone-500">{{ reviewTotal }} matching review{{ reviewTotal === 1 ? "" : "s" }}</p>
          </div>
          <form class="flex flex-wrap gap-3 rounded-xl border bg-white p-4" @submit.prevent="searchModeratedReviews">
            <input v-model="reviewQuery" class="min-w-0 flex-1 rounded border p-2" type="search" autocomplete="off" placeholder="Search account, bar, tapa or review">
            <select v-model="reviewStatus" class="rounded border p-2" aria-label="Review status">
              <option value="all">All</option><option value="visible">Visible</option><option value="hidden">Hidden</option>
            </select>
            <button class="rounded bg-emerald-700 px-4 py-2 font-semibold text-white disabled:opacity-50" :disabled="moderatedReviewsLoading">{{ moderatedReviewsLoading ? "Searching..." : "Search" }}</button>
          </form>
          <div class="overflow-x-auto rounded-xl border bg-white">
            <table class="w-full min-w-[900px] text-left text-sm">
              <thead class="bg-stone-100"><tr><th class="p-3">Date/time</th><th class="p-3">User</th><th class="p-3">Establishment</th><th class="p-3">Tapa</th><th class="p-3 text-center">Rating</th><th class="p-3">Written review</th><th class="p-3">Status</th><th class="p-3 text-right">Action</th></tr></thead>
              <tbody>
                <tr v-for="row in moderatedReviews" :key="row.review_id" class="border-t align-top">
                  <td class="whitespace-nowrap p-3"><span class="block whitespace-nowrap leading-tight">{{ adminDateTimeLines(row.created_at).date }}<span class="block">{{ adminDateTimeLines(row.created_at).time }}</span></span></td>
                  <td class="p-3 font-mono">{{ row.user_label }}</td>
                  <td class="p-3">{{ row.establishment_name }}</td>
                  <td class="p-3">{{ row.tapa_name }}</td>
                  <td class="p-3 text-center">{{ row.rating == null ? "-" : row.rating }}</td>
                  <td class="max-w-[28rem] whitespace-pre-wrap p-3">{{ row.review_text }}</td>
                  <td class="whitespace-nowrap p-3">{{ row.status === 'hidden' ? 'Hidden' : 'Visible' }}</td>
                  <td class="whitespace-nowrap p-3 text-right"><button type="button" class="font-semibold" :class="row.status === 'hidden' ? 'text-emerald-700' : 'text-amber-700'" :disabled="reviewActionId === row.review_id" @click="setReviewModeration(row, row.status === 'hidden' ? 'visible' : 'hidden')">{{ reviewActionId === row.review_id ? 'Saving...' : row.status === 'hidden' ? 'Restore' : 'Hide' }}</button></td>
                </tr>
                <tr v-if="!moderatedReviews.length && !moderatedReviewsLoading"><td colspan="8" class="p-5 text-center text-stone-500">No written reviews match this filter.</td></tr>
              </tbody>
            </table>
          </div>
          <div v-if="reviewTotal > 25" class="flex items-center justify-end gap-3">
            <button type="button" class="rounded border px-3 py-2 text-sm disabled:opacity-50" :disabled="moderatedReviewsLoading || reviewPage === 0" @click="loadModeratedReviews(reviewPage - 1)">Previous</button>
            <span class="text-sm text-stone-600">Page {{ reviewPage + 1 }} of {{ Math.ceil(reviewTotal / 25) }}</span>
            <button type="button" class="rounded border px-3 py-2 text-sm disabled:opacity-50" :disabled="moderatedReviewsLoading || (reviewPage + 1) * 25 >= reviewTotal" @click="loadModeratedReviews(reviewPage + 1)">Next</button>
          </div>
        </section>

        <section v-if="tab === 'users'" class="space-y-5">
          <div class="flex flex-wrap items-end justify-between gap-3"><div><h2 class="text-xl font-bold">Users</h2><p class="mt-1 text-sm text-stone-600">Search registered accounts and inspect festival activity. Account labels remain masked.</p></div><p class="text-sm text-stone-500">{{ registeredUsersTotal }} matching account{{ registeredUsersTotal === 1 ? "" : "s" }}</p></div>
          <form class="flex flex-wrap gap-3 rounded-xl border bg-white p-4" @submit.prevent="searchRegisteredUsers"><input v-model="registeredUserQuery" class="min-w-0 flex-1 rounded border p-2" type="search" autocomplete="off" placeholder="Search users (* = any characters, ? = one character)"><button class="rounded bg-emerald-700 px-4 py-2 font-semibold text-white disabled:opacity-50" :disabled="registeredUsersLoading">{{ registeredUsersLoading ? "Searching…" : "Search" }}</button><label class="flex min-w-0 flex-1 items-center gap-2 text-sm font-semibold sm:flex-none">Sort by<select v-model="registeredUserSort" class="min-w-0 rounded border p-2 font-normal" @change="applyRegisteredUserSort(registeredUsersPage)"><option value="joined_desc">Joined — newest first</option><option value="account_asc">Account A–Z</option><option value="account_desc">Account Z–A</option><option value="joined_asc">Joined — oldest first</option><option value="activity_desc">Last activity — newest first</option><option value="activity_asc">Last activity — oldest first</option><option value="total_desc">Most activity</option><option value="total_asc">Least activity</option><option value="suspended_first">Suspended first</option><option value="active_first">Active first</option></select></label></form>
          <div class="space-y-3 lg:hidden">
            <article v-for="row in registeredUsers" :key="row.account_id" class="rounded-xl border bg-white p-4 shadow-sm">
              <div class="flex flex-wrap items-start justify-between gap-3"><div class="min-w-0"><p class="break-all font-mono text-sm font-semibold">{{ row.account }}</p><p :class="row.status === 'Suspended' ? 'font-semibold text-red-700' : 'font-semibold text-emerald-700'">{{ row.status }}</p><p v-if="row.status === 'Suspended'" class="mt-1 text-xs text-stone-600">{{ row.suspended_at ? adminDateTimeLines(row.suspended_at).date : '' }}<span v-if="row.suspension_reason" class="block">{{ row.suspension_reason }}</span></p></div><div class="flex max-w-full flex-wrap gap-x-3 gap-y-2 text-sm font-semibold"><button type="button" class="text-emerald-700" @click="toggleRegisteredUserActivity(row)">{{ selectedRegisteredUser?.account_id === row.account_id ? "Hide activity" : "View activity" }}</button><button v-if="passwordResetEligibleAccountIds.has(row.account_id)" type="button" class="text-emerald-700" :disabled="passwordResetAccountId === row.account_id" @click="sendPasswordReset(row)">{{ passwordResetAccountId === row.account_id ? "Sending…" : "Password reset" }}</button><button v-if="fullAuditEligibleAccountIds.has(row.account_id)" type="button" class="text-emerald-700" :disabled="fullAuditLoading && fullAuditAccountId === row.account_id" @click="openFullAudit(row)">{{ fullAuditAccountId === row.account_id ? "Hide audit" : "Full Audit" }}</button><button v-if="row.role === 'user'" type="button" :class="row.status === 'Suspended' ? 'text-emerald-700' : 'text-red-700'" :disabled="registeredUserSuspensionId === row.account_id" @click="toggleRegisteredUserSuspension(row)">{{ registeredUserSuspensionId === row.account_id ? 'Saving…' : row.status === 'Suspended' ? 'Reactivate' : 'Suspend' }}</button><template v-if="isSuperuser && promotableRegisteredUserIds.has(row.account_id)"><button type="button" class="text-emerald-700" @click="promoteRegisteredUser(row, 'admin')">Promote to Admin</button><button type="button" class="text-emerald-700" @click="promoteRegisteredUser(row, 'superuser')">Promote to Superadmin</button></template></div></div>
              <dl class="mt-4 grid grid-cols-2 gap-3 text-sm sm:grid-cols-3"><div><dt class="text-xs text-stone-500">Registered</dt><dd>{{ adminDateTimeLines(row.registered_at).date }} {{ adminDateTimeLines(row.registered_at).time }}</dd></div><div><dt class="text-xs text-stone-500">Last activity</dt><dd>{{ row.last_festival_activity_at ? adminDateTimeLines(row.last_festival_activity_at).date : '—' }}</dd></div><div><dt class="text-xs text-stone-500">Tapa ratings</dt><dd class="font-semibold">{{ row.tapa_rating_count }}</dd></div><div><dt class="text-xs text-stone-500">Written reviews</dt><dd class="font-semibold">{{ row.written_review_count }}</dd></div><div><dt class="text-xs text-stone-500">Bar ratings</dt><dd class="font-semibold">{{ row.bar_rating_count }}</dd></div><div><dt class="text-xs text-stone-500">Total activity</dt><dd class="font-semibold">{{ row.total_activity_count }}</dd></div></dl><div v-if="selectedRegisteredUser?.account_id === row.account_id" class="mt-4 border-t pt-3"><h3 class="font-semibold">User activity</h3><p v-if="registeredUserActivityLoading" class="mt-2 text-sm text-stone-500">Loading activity…</p><div v-else-if="registeredUserActivity.length" class="mt-2 space-y-2"><div v-for="activity in registeredUserActivity" :key="activity.activity_kind + activity.activity_at + activity.establishment_name" class="rounded border p-2 text-sm"><p class="font-semibold">{{ activity.activity_kind }} · {{ activity.establishment_name }}</p><p v-if="activity.tapa_name">{{ activity.tapa_name }}</p><p class="text-xs text-stone-600">{{ activity.festival_name || "—" }} · {{ activity.rating == null ? "—" : activity.rating }} · {{ adminDateTimeLines(activity.activity_at).date }}</p><p v-if="activity.review_text" class="mt-1 whitespace-pre-wrap">{{ activity.review_text }}</p></div></div><p v-else class="mt-2 text-sm text-stone-500">No festival activity recorded for this account.</p></div><div v-if="fullAuditAccountId === row.account_id" class="mt-4 border-t pt-3"><div v-if="fullAuditLoading" class="text-sm text-stone-500">Loading read-only account audit…</div><div v-else-if="fullAudit" class="space-y-2 text-sm"><p class="font-semibold">Full Audit · {{ fullAudit.email }}</p><p>Role: {{ auditRoleLabel(fullAudit.role) }} · Status: {{ fullAudit.status }}</p><div v-for="entry in fullAuditTimeline(fullAudit)" :key="entry.timestamp + entry.event + entry.result" class="border-t pt-2"><p class="font-semibold">{{ entry.event }}</p><p class="text-xs text-stone-600">{{ auditDateTimeLines(entry.timestamp).date }} · {{ entry.result }}</p></div><p v-if="!fullAuditTimeline(fullAudit).length" class="text-stone-500">No additional audit events.</p></div></div>
            </article>
            <p v-if="!registeredUsers.length && !registeredUsersLoading" class="rounded-xl border bg-white p-5 text-center text-stone-500">No registered users match this search.</p>
          </div>
          <div class="hidden overflow-x-auto rounded-xl border bg-white lg:block"><table class="w-full min-w-[1000px] table-fixed text-left text-sm"><colgroup><col><col class="w-[112px]"><col class="w-[132px]"><col class="w-20"><col class="w-24"><col class="w-20"><col class="w-20"><col class="w-16"><col class="w-40"></colgroup><thead class="bg-stone-100"><tr><th class="px-3 py-3">Account</th><th class="px-2 py-3">Registered</th><th class="px-2 py-3">Last festival activity</th><th class="px-2 py-3 text-center">Tapa ratings</th><th class="px-2 py-3 text-center">Written reviews</th><th class="px-2 py-3 text-center">Bar ratings</th><th class="px-2 py-3 text-center">Total activity</th><th class="px-2 py-3">Status</th><th class="px-2 py-3 text-right">Actions</th></tr></thead><tbody><template v-for="row in registeredUsers" :key="row.account_id"><tr class="border-t"><td class="break-all px-3 py-3 font-mono">{{ row.account }}</td><td class="px-2 py-3"><span class="block whitespace-nowrap">{{ adminDateTimeLines(row.registered_at).date }}</span><span class="block whitespace-nowrap text-xs text-stone-600">{{ adminDateTimeLines(row.registered_at).time }}</span></td><td class="px-2 py-3"><template v-if="row.last_festival_activity_at"><span class="block whitespace-nowrap">{{ adminDateTimeLines(row.last_festival_activity_at).date }}</span><span class="block whitespace-nowrap text-xs text-stone-600">{{ adminDateTimeLines(row.last_festival_activity_at).time }}</span></template><span v-else>—</span></td><td class="px-2 py-3 text-center">{{ row.tapa_rating_count }}</td><td class="px-2 py-3 text-center">{{ row.written_review_count }}</td><td class="px-2 py-3 text-center">{{ row.bar_rating_count }}</td><td class="px-2 py-3 text-center font-semibold">{{ row.total_activity_count }}</td><td class="px-2 py-3"><span :class="row.status === 'Suspended' ? 'font-semibold text-red-700' : 'text-emerald-700'">{{ row.status }}</span><span v-if="row.status === 'Suspended'" class="mt-1 block whitespace-normal text-xs text-stone-600">{{ row.suspended_at ? adminDateTimeLines(row.suspended_at).date : '' }}<span v-if="row.suspension_reason" class="block">{{ row.suspension_reason }}</span></span></td><td class="whitespace-nowrap px-2 py-3 text-right"><div class="grid justify-items-end gap-1"><button type="button" class="font-semibold text-emerald-700" :aria-expanded="selectedRegisteredUser?.account_id === row.account_id" @click="toggleRegisteredUserActivity(row)">{{ selectedRegisteredUser?.account_id === row.account_id ? "Hide activity" : "View activity" }}</button><button v-if="passwordResetEligibleAccountIds.has(row.account_id)" type="button" class="text-xs font-semibold text-emerald-700 disabled:opacity-50" :disabled="passwordResetAccountId === row.account_id" @click="sendPasswordReset(row)">{{ passwordResetAccountId === row.account_id ? "Sending…" : "Send password reset" }}</button><button v-if="fullAuditEligibleAccountIds.has(row.account_id)" type="button" class="text-xs font-semibold text-emerald-700 disabled:opacity-50" :disabled="fullAuditLoading && fullAuditAccountId === row.account_id" @click="openFullAudit(row)">{{ fullAuditLoading && fullAuditAccountId === row.account_id ? "Loading audit…" : fullAuditAccountId === row.account_id ? "Hide audit" : "Full Audit" }}</button><button v-if="row.role === 'user'" type="button" class="text-xs font-semibold disabled:opacity-50" :class="row.status === 'Suspended' ? 'text-emerald-700' : 'text-red-700'" :disabled="registeredUserSuspensionId === row.account_id" @click="toggleRegisteredUserSuspension(row)">{{ registeredUserSuspensionId === row.account_id ? 'Saving…' : row.status === 'Suspended' ? 'Reactivate' : 'Suspend' }}</button><template v-if="isSuperuser && promotableRegisteredUserIds.has(row.account_id)"><button type="button" class="text-xs font-semibold text-emerald-700 disabled:opacity-50" :disabled="registeredUserPromotionId === row.account_id" @click="promoteRegisteredUser(row, 'admin')">Promote to Admin</button><button type="button" class="text-xs font-semibold text-emerald-700 disabled:opacity-50" :disabled="registeredUserPromotionId === row.account_id" @click="promoteRegisteredUser(row, 'superuser')">Promote to Superadmin</button></template></div></td></tr><tr v-if="selectedRegisteredUser?.account_id === row.account_id" class="border-t bg-stone-50"><td colspan="9" class="p-4"><div class="flex flex-wrap items-baseline justify-between gap-2"><h3 class="font-semibold">User activity · {{ row.account }}</h3><p class="text-sm text-stone-600">{{ row.tapa_rating_count }} tapa rating{{ row.tapa_rating_count === 1 ? "" : "s" }} · {{ row.written_review_count }} written review{{ row.written_review_count === 1 ? "" : "s" }} · {{ row.bar_rating_count }} bar rating{{ row.bar_rating_count === 1 ? "" : "s" }}</p></div><p v-if="registeredUserActivityLoading" class="mt-3 text-sm text-stone-500">Loading activity…</p><div v-else-if="registeredUserActivity.length" class="mt-3 overflow-x-auto"><table class="w-full min-w-[720px] text-left text-sm"><thead class="bg-stone-200"><tr><th class="p-2">Type</th><th class="p-2">Festival</th><th class="p-2">Establishment / bar</th><th class="p-2">Tapa</th><th class="p-2">Rating</th><th class="p-2">Written review</th><th class="p-2">Date</th></tr></thead><tbody><tr v-for="activity in registeredUserActivity" :key="activity.activity_kind + activity.activity_at + activity.establishment_name" class="border-t"><td class="p-2">{{ activity.activity_kind }}</td><td class="p-2">{{ activity.festival_name || "—" }}</td><td class="p-2">{{ activity.establishment_name }}</td><td class="p-2">{{ activity.tapa_name || "—" }}</td><td class="p-2">{{ activity.rating == null ? "—" : activity.rating }}</td><td class="max-w-md whitespace-pre-wrap p-2">{{ activity.review_text || "—" }}</td><td class="p-2"><span class="block whitespace-nowrap leading-tight">{{ adminDateTimeLines(activity.activity_at).date }}<span class="block">{{ adminDateTimeLines(activity.activity_at).time }}</span></span></td></tr></tbody></table></div><p v-else class="mt-3 text-sm text-stone-500">No festival activity recorded for this account.</p></td></tr><tr v-if="fullAuditAccountId === row.account_id" class="border-t bg-emerald-50"><td colspan="9" class="p-4"><div v-if="fullAuditLoading" class="text-sm text-stone-600">Loading read-only account audit…</div><div v-else-if="fullAudit" class="space-y-4"><div class="flex flex-wrap items-baseline justify-between gap-2"><h3 class="font-semibold">Full Audit · {{ fullAudit.email }}</h3><span class="text-xs text-stone-600">Read-only</span></div><div class="grid gap-3 text-sm sm:grid-cols-2 lg:grid-cols-4"><div><span class="font-semibold">Email</span><p>{{ fullAudit.email }}</p></div><div><span class="font-semibold">Auth UUID</span><p class="break-all font-mono text-xs">{{ fullAudit.account_id }}</p></div><div><span class="font-semibold">Current role</span><p>{{ auditRoleLabel(fullAudit.role) }}</p></div><div><span class="font-semibold">Status</span><p>{{ fullAudit.status }}</p></div><div><span class="font-semibold">Created</span><p>{{ auditDateTimeLines(fullAudit.created_at).date }} {{ auditDateTimeLines(fullAudit.created_at).time }}</p></div><div><span class="font-semibold">Email confirmed</span><p>{{ fullAudit.email_confirmed_at ? auditDateTimeLines(fullAudit.email_confirmed_at).date + ' ' + auditDateTimeLines(fullAudit.email_confirmed_at).time : 'No' }}</p></div><div><span class="font-semibold">Providers</span><p>{{ fullAudit.providers.join(', ') || '—' }}</p></div><div><span class="font-semibold">Last successful login</span><p>{{ fullAudit.last_sign_in_at ? auditDateTimeLines(fullAudit.last_sign_in_at).date + ' ' + auditDateTimeLines(fullAudit.last_sign_in_at).time : '—' }}</p></div><div><span class="font-semibold">Last festival activity</span><p>{{ fullAudit.last_festival_activity_at ? auditDateTimeLines(fullAudit.last_festival_activity_at).date + ' ' + auditDateTimeLines(fullAudit.last_festival_activity_at).time : '—' }}</p></div><div><span class="font-semibold">Activity</span><p>{{ fullAudit.activity_summary.tapa_ratings }} tapa · {{ fullAudit.activity_summary.written_reviews }} reviews · {{ fullAudit.activity_summary.bar_ratings }} bar</p></div></div><div><h4 class="font-semibold">Chronological audit · Europe/Madrid</h4><div class="mt-2 max-h-96 overflow-auto rounded border bg-white"><table class="w-full text-left text-sm"><thead class="sticky top-0 bg-stone-100"><tr><th class="p-2">Date/time</th><th class="p-2">Event</th><th class="p-2">Result</th></tr></thead><tbody><tr v-for="entry in fullAuditTimeline(fullAudit)" :key="entry.timestamp + entry.event + entry.result" class="border-t"><td class="whitespace-nowrap p-2"><span class="block">{{ auditDateTimeLines(entry.timestamp).date }}</span><span class="text-xs text-stone-600">{{ auditDateTimeLines(entry.timestamp).time }}</span></td><td class="p-2">{{ entry.event }}</td><td class="p-2">{{ entry.result }}</td></tr><tr v-if="!fullAuditTimeline(fullAudit).length"><td colspan="3" class="p-3 text-stone-500">No additional audit events.</td></tr></tbody></table></div></div><p class="text-xs text-stone-600">Password change confirmation: Not available. Authentication tokens, password data, recovery tokens, API keys, and service secrets are never returned.</p></div></td></tr></template><tr v-if="!registeredUsers.length && !registeredUsersLoading"><td colspan="9" class="p-5 text-center text-stone-500">No registered users match this search.</td></tr></tbody></table></div>
          <div v-if="registeredUsersTotal > 25" class="flex items-center justify-end gap-3"><button type="button" class="rounded border px-3 py-2 text-sm disabled:opacity-50" :disabled="registeredUsersLoading || registeredUsersPage === 0" @click="loadRegisteredUsers(registeredUsersPage - 1)">Previous</button><span class="text-sm text-stone-600">Page {{ registeredUsersPage + 1 }} of {{ Math.ceil(registeredUsersTotal / 25) }}</span><button type="button" class="rounded border px-3 py-2 text-sm disabled:opacity-50" :disabled="registeredUsersLoading || (registeredUsersPage + 1) * 25 >= registeredUsersTotal" @click="loadRegisteredUsers(registeredUsersPage + 1)">Next</button></div>
        </section>

        <section v-if="tab === 'photos'" class="space-y-5">
          <div class="flex flex-wrap items-end justify-between gap-3"><div><h2 class="text-xl font-bold">Photos</h2><p class="mt-1 text-sm text-stone-600">Read-only festival image inventory and database associations.</p></div><button type="button" class="rounded border border-stone-300 px-3 py-2 text-sm font-semibold" :disabled="photosLoading" @click="loadPhotos">{{ photosLoading ? 'Refreshing…' : 'Refresh' }}</button></div>
          <p v-if="photosError" class="rounded border border-red-200 bg-red-50 p-3 text-sm text-red-800">{{ photosError }}</p>
          <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-4"><div class="rounded-xl border bg-white p-4"><p class="text-xs uppercase tracking-wide text-stone-500">Total images</p><p class="mt-1 text-2xl font-bold">{{ photoSummary.total.toLocaleString() }}</p></div><div class="rounded-xl border bg-white p-4"><p class="text-xs uppercase tracking-wide text-stone-500">Storage</p><p class="mt-1 text-2xl font-bold">{{ resourceBytes(photoSummary.bytes) }}</p></div><div class="rounded-xl border bg-white p-4"><p class="text-xs uppercase tracking-wide text-stone-500">Average</p><p class="mt-1 text-2xl font-bold">{{ formatPhotoSize(photoSummary.average) }}</p></div><div class="rounded-xl border bg-white p-4"><p class="text-xs uppercase tracking-wide text-stone-500">Largest</p><p class="mt-1 text-2xl font-bold">{{ formatPhotoSize(photoSummary.largest) }}</p></div></div>
          <div class="grid gap-3 rounded-xl border bg-white p-4 sm:grid-cols-3"><div><span class="text-sm text-stone-500">Managed uploads</span><p class="font-bold">{{ photoSummary.managed.toLocaleString() }}</p></div><div><span class="text-sm text-stone-500">Managed images over 30 KB</span><p class="font-bold" :class="photoSummary.overLimit ? 'text-red-700' : 'text-emerald-700'">{{ photoSummary.overLimit.toLocaleString() }}</p></div><div><span class="text-sm text-stone-500">Unidentified/orphaned</span><p class="font-bold">{{ photoSummary.orphaned.toLocaleString() }}</p></div></div>
          <div class="flex flex-wrap gap-3 rounded-xl border bg-white p-4"><input v-model="photosQuery" class="min-w-0 flex-1 rounded border p-2" type="search" placeholder="Search bar, tapa or path"><select v-model="photosSort" class="rounded border p-2" aria-label="Photo sort"><option value="newest">Newest</option><option value="oldest">Oldest</option><option value="largest">Largest</option><option value="smallest">Smallest</option><option value="bar">Bar name</option></select></div>
          <div class="overflow-x-auto rounded-xl border bg-white"><table class="w-full min-w-[1050px] text-left text-sm"><thead class="bg-stone-100"><tr><th class="p-3">Preview</th><th class="p-3">Where used</th><th class="p-3">Type</th><th class="p-3">Stored path</th><th class="p-3">Size</th><th class="p-3">MIME</th><th class="p-3">Dimensions</th><th class="p-3">Created</th><th class="p-3">View</th></tr></thead><tbody><tr v-for="photo in filteredPhotos" :key="photo.name" class="border-t align-top"><td class="p-3"><img :src="photo.public_url" alt="" class="h-14 w-14 rounded object-cover"></td><td class="p-3"><span v-if="photo.establishment_name" class="block font-semibold">{{ photo.establishment_name }}</span><span v-if="photo.tapa_name" class="block">{{ photo.tapa_name }}</span><span v-if="photo.orphaned" class="text-amber-700">Orphaned / unreferenced</span></td><td class="p-3">{{ photo.kind }}<span v-if="photo.managed" class="mt-1 block text-xs text-emerald-700">Managed</span></td><td class="max-w-[28rem] break-all p-3 font-mono text-xs">{{ photo.name }}</td><td class="whitespace-nowrap p-3 font-semibold" :class="photo.managed && photo.size_bytes > PHOTO_MAX_STORED_BYTES ? 'text-red-700' : ''">{{ formatPhotoSize(photo.size_bytes) }}<span v-if="photo.managed && photo.size_bytes > PHOTO_MAX_STORED_BYTES" class="mt-1 block text-xs">OVER 30 KB</span></td><td class="p-3 text-xs">{{ photo.mime_type }}</td><td class="whitespace-nowrap p-3">{{ photo.width && photo.height ? `${photo.width} × ${photo.height}` : '—' }}</td><td class="whitespace-nowrap p-3">{{ photo.created_at ? adminDateTimeLines(photo.created_at).date + ' ' + adminDateTimeLines(photo.created_at).time : '—' }}</td><td class="p-3"><a class="font-semibold text-emerald-700 hover:underline" :href="photo.public_url" target="_blank" rel="noopener">View</a></td></tr><tr v-if="!photosLoading && !filteredPhotos.length"><td colspan="9" class="p-5 text-center text-stone-500">No photos match this search.</td></tr></tbody></table></div>
        </section>

        <section v-if="tab === 'resources' && isSuperuser" class="space-y-5">
          <div class="flex flex-wrap items-end justify-between gap-3"><div><h2 class="text-xl font-bold">Resources</h2><p class="mt-1 text-sm text-stone-600">Read-only service usage and health information.</p></div><button type="button" class="rounded border border-stone-300 px-3 py-2 text-sm font-semibold" :disabled="resourcesLoading" @click="loadResources">{{ resourcesLoading ? 'Refreshing…' : 'Refresh' }}</button></div>
          <p v-if="resourcesError" class="rounded border border-red-200 bg-red-50 p-3 text-sm text-red-800">{{ resourcesError }}</p>
          <p v-if="resources" class="text-xs text-stone-500">Last refreshed: {{ adminDateTimeLines(resources.refreshed_at).date }} {{ adminDateTimeLines(resources.refreshed_at).time }}</p>
          <div v-if="resources" class="grid gap-5 lg:grid-cols-2">
            <section class="rounded-xl border bg-white p-4"><h3 class="font-bold">Supabase</h3><dl class="mt-3 grid grid-cols-2 gap-3 text-sm sm:grid-cols-3"><div><dt class="text-stone-500">Database</dt><dd class="font-semibold">{{ resourceBytes(resources.supabase.database_size_bytes) }}</dd></div><div><dt class="text-stone-500">Festival schema</dt><dd class="font-semibold">{{ resourceBytes(resources.supabase.schemas?.festival) }}</dd></div><div><dt class="text-stone-500">Auth schema</dt><dd class="font-semibold">{{ resourceBytes(resources.supabase.schemas?.auth) }}</dd></div><div><dt class="text-stone-500">Storage schema</dt><dd class="font-semibold">{{ resourceBytes(resources.supabase.schemas?.storage) }}</dd></div><div><dt class="text-stone-500">Private schema</dt><dd class="font-semibold">{{ resourceBytes(resources.supabase.schemas?.festival_private) }}</dd></div><div><dt class="text-stone-500">Auth users</dt><dd class="font-semibold">{{ Number(resources.supabase.auth_users || 0).toLocaleString() }}</dd></div><div><dt class="text-stone-500">Auth identities</dt><dd class="font-semibold">{{ Number(resources.supabase.auth_identities || 0).toLocaleString() }}</dd></div><div><dt class="text-stone-500">Storage objects</dt><dd class="font-semibold">{{ Number(resources.supabase.storage_objects || 0).toLocaleString() }}</dd></div><div><dt class="text-stone-500">Storage bytes</dt><dd class="font-semibold">{{ resourceBytes(resources.supabase.storage_bytes) }}</dd></div></dl><div class="mt-4 overflow-x-auto"><table class="w-full text-left text-xs"><thead class="border-b text-stone-500"><tr><th class="py-2">Table</th><th class="py-2 text-right">Rows</th><th class="py-2 text-right">Size</th></tr></thead><tbody><tr v-for="row in resources.supabase.tables" :key="row.table_name" class="border-b last:border-0"><td class="py-2">festival.{{ row.table_name }}</td><td class="py-2 text-right">{{ Number(row.estimated_rows).toLocaleString() }}</td><td class="py-2 text-right">{{ resourceBytes(row.size_bytes) }}</td></tr></tbody></table></div></section>
            <section class="rounded-xl border bg-white p-4"><h3 class="font-bold">Database activity</h3><dl class="mt-3 grid grid-cols-2 gap-3 text-sm sm:grid-cols-3"><div v-for="key in ['xact_commit','xact_rollback','tup_returned','tup_fetched','tup_inserted','tup_updated','tup_deleted','blks_read','blks_hit']" :key="key"><dt class="text-stone-500">{{ key.replaceAll('_', ' ') }}</dt><dd class="font-semibold">{{ Number(resources.supabase.activity?.[key] || 0).toLocaleString() }}</dd></div><div><dt class="text-stone-500">Statistics reset</dt><dd class="font-semibold">{{ resources.supabase.activity?.stats_reset ? adminDateTimeLines(resources.supabase.activity.stats_reset).date + ' ' + adminDateTimeLines(resources.supabase.activity.stats_reset).time : 'Unavailable from current connection' }}</dd></div></dl><h3 class="mt-5 font-bold">Storage buckets</h3><div class="mt-2 overflow-x-auto"><table class="w-full text-left text-xs"><thead class="border-b text-stone-500"><tr><th class="py-2">Bucket</th><th class="py-2">Visibility</th><th class="py-2 text-right">Objects</th><th class="py-2 text-right">Bytes</th></tr></thead><tbody><tr v-for="bucket in resources.supabase.storage_buckets" :key="bucket.bucket_id" class="border-b last:border-0"><td class="py-2">{{ bucket.name }}</td><td class="py-2">{{ bucket.public ? 'Public' : 'Private' }}</td><td class="py-2 text-right">{{ Number(bucket.object_count).toLocaleString() }}</td><td class="py-2 text-right">{{ resourceBytes(bucket.bytes) }}</td></tr></tbody></table></div></section>
            <section class="rounded-xl border bg-white p-4"><h3 class="font-bold">Vercel</h3><dl class="mt-3 space-y-2 text-sm"><div class="flex justify-between gap-3"><dt class="text-stone-500">Project</dt><dd>{{ resources.vercel.project }}</dd></div><div class="flex justify-between gap-3"><dt class="text-stone-500">Environment</dt><dd>{{ resources.vercel.environment }}</dd></div><div class="flex justify-between gap-3"><dt class="text-stone-500">Commit</dt><dd class="max-w-[16rem] truncate font-mono text-xs">{{ resources.vercel.commit }}</dd></div><div class="flex justify-between gap-3"><dt class="text-stone-500">Deployment</dt><dd>{{ resources.vercel.deployment_url }}</dd></div><div class="flex justify-between gap-3"><dt class="text-stone-500">Usage/quotas</dt><dd>{{ resources.vercel.quotas }}</dd></div></dl></section>
            <section class="rounded-xl border bg-white p-4"><h3 class="font-bold">GitHub</h3><dl class="mt-3 space-y-2 text-sm"><div class="flex justify-between gap-3"><dt class="text-stone-500">Repository</dt><dd>{{ resources.github.repository }}</dd></div><div class="flex justify-between gap-3"><dt class="text-stone-500">Branch</dt><dd>{{ resources.github.branch }}</dd></div><div class="flex justify-between gap-3"><dt class="text-stone-500">Commit</dt><dd class="max-w-[16rem] truncate font-mono text-xs">{{ resources.github.commit }}</dd></div><div class="flex justify-between gap-3"><dt class="text-stone-500">Usage</dt><dd>{{ resources.github.usage }}</dd></div></dl></section>
            <section class="rounded-xl border bg-white p-4 lg:col-span-2"><h3 class="font-bold">Application</h3><dl class="mt-3 grid grid-cols-2 gap-3 text-sm sm:grid-cols-3 lg:grid-cols-5"><div><dt class="text-stone-500">Nuxt</dt><dd>{{ resources.application.nuxt }}</dd></div><div><dt class="text-stone-500">Vue</dt><dd>{{ resources.application.vue }}</dd></div><div><dt class="text-stone-500">Node</dt><dd>{{ resources.application.node }}</dd></div><div><dt class="text-stone-500">Environment</dt><dd>{{ resources.application.environment }}</dd></div><div><dt class="text-stone-500">Supabase project</dt><dd class="font-mono text-xs">{{ resources.application.supabase_project_ref }}</dd></div><div><dt class="text-stone-500">Region</dt><dd>{{ resources.application.database_region }}</dd></div><div><dt class="text-stone-500">Establishments</dt><dd>{{ Number(resources.application.establishments).toLocaleString() }}</dd></div><div><dt class="text-stone-500">Tapas</dt><dd>{{ Number(resources.application.tapas).toLocaleString() }}</dd></div><div><dt class="text-stone-500">Festivals</dt><dd>{{ Number(resources.application.festivals).toLocaleString() }}</dd></div></dl></section>
          </div>
          <p v-else-if="!resourcesLoading" class="rounded border border-stone-200 bg-white p-4 text-sm text-stone-600">Select Resources to load read-only metrics.</p>
        </section>
        <section v-if="tab === 'administrators' && isSuperuser" class="space-y-5">
          <div><h2 class="text-xl font-bold">Administrators</h2><p class="mt-1 text-sm text-stone-600">Manage festival administrator access. Full account addresses are visible only to Superadmins.</p></div>
          <form class="grid gap-3 rounded-xl border bg-white p-4 sm:grid-cols-[minmax(0,1fr)_180px_auto]" @submit.prevent="addAdministrator"><input v-model="administratorEmail" class="rounded border p-2" type="email" autocomplete="off" placeholder="Registered user email" required><select v-model="administratorRole" class="rounded border p-2"><option value="admin">Admin</option><option value="superuser">Superadmin</option></select><button class="rounded bg-emerald-700 px-4 py-2 font-semibold text-white disabled:opacity-50" :disabled="administratorSaving">Add Admin</button></form>
          <div class="overflow-x-auto rounded-xl border bg-white"><table class="w-full min-w-[720px] text-left text-sm"><thead class="bg-stone-100"><tr><th class="p-3">Account</th><th class="p-3">Role</th><th class="p-3">Added</th><th class="p-3">Status</th><th class="p-3">Actions</th></tr></thead><tbody><tr v-for="row in administrators" :key="row.account_id" class="border-t"><td class="p-3 font-medium">{{ row.account }}</td><td class="p-3 capitalize">{{ administratorRoleLabel(row.role) }}</td><td class="p-3"><span class="block whitespace-nowrap leading-tight">{{ adminDateTimeLines(row.added_at).date }}<span class="block">{{ adminDateTimeLines(row.added_at).time }}</span></span></td><td class="p-3">{{ row.status }}</td><td class="p-3"><div class="flex gap-3"><button v-if="row.role === 'admin'" type="button" class="font-semibold text-emerald-700 disabled:opacity-50" :disabled="administratorSaving" @click="changeAdministratorRole(row, 'superuser')">Promote to Superadmin</button><button v-else type="button" class="font-semibold text-amber-700 disabled:opacity-50" :disabled="administratorSaving" @click="changeAdministratorRole(row, 'admin')">Demote to Admin</button><button v-if="passwordResetEligibleAccountIds.has(row.account_id)" type="button" class="font-semibold text-emerald-700 disabled:opacity-50" :disabled="passwordResetAccountId === row.account_id" @click="sendPasswordReset(row)">{{ passwordResetAccountId === row.account_id ? 'Sending…' : 'Send password reset' }}</button><button type="button" class="font-semibold text-red-700 disabled:opacity-50" :disabled="administratorSaving" @click="removeAdministrator(row)">Remove Admin</button></div></td></tr><tr v-if="!administrators.length && !administratorsLoading"><td colspan="5" class="p-5 text-center text-stone-500">No administrators found.</td></tr></tbody></table></div>
          <p v-if="administratorsLoading" class="text-sm text-stone-500">Loading administrators…</p>
        </section>

      </template>
    </div>
  </main>
</template>
