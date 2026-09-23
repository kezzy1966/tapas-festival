<script setup lang="ts">
import { useAuthSession } from './composables/useAuthSession';
import { usePublicSiteControls } from './composables/usePublicSiteControls';

const { syncSession } = useAuthSession();
const route = useRoute();
const router = useRouter();
const supabaseUser = useSupabaseUser();
const { language, setLanguage } = useFestivalLanguage();
const { emergencyShutdown, loaded: emergencyControlsLoaded, refresh: refreshEmergencyControls } = usePublicSiteControls();
const emergencyAdminAccess = ref(false);
const holdingMode = computed(() => String(useRuntimeConfig().public.holdingMode).toLowerCase() === 'true');
const showHoldingPage = computed(() => holdingMode.value && route.path !== '/admin' && route.path !== '/reset-password');
const siteUrl = 'https://tapascastellon.es';
const canonicalUrl = computed(() => new URL(route.path, siteUrl).toString());
const defaultDescription = 'Descubre bares y tapas participantes en Castellón, consulta valoraciones, reseñas y clasificaciones.';

useHead({
  htmlAttrs: { lang: language },
  titleTemplate: (titleChunk) => titleChunk ? titleChunk + ' · Tapas Castellón' : 'Tapas Castellón',
  meta: [
    { name: 'description', content: defaultDescription },
    { property: 'og:title', content: 'Tapas Castellón' },
    { property: 'og:description', content: defaultDescription },
    { property: 'og:site_name', content: 'Tapas Castellón' },
    { property: 'og:type', content: 'website' },
    { property: 'og:url', content: canonicalUrl, key: 'og-url' },
    { name: 'twitter:card', content: 'summary' },
    { name: 'twitter:title', content: 'Tapas Castellón' },
    { name: 'twitter:description', content: defaultDescription },
  ],
  link: [{ rel: 'canonical', href: canonicalUrl, key: 'canonical' }],
});

let emergencyRefreshPromise: Promise<void> | null = null;
async function refreshEmergencyAccess() {
  if (emergencyRefreshPromise) return emergencyRefreshPromise;
  emergencyRefreshPromise = (async () => {
    await refreshEmergencyControls();
    if (!supabaseUser.value) { emergencyAdminAccess.value = false; return; }
    const { data, error } = await useSupabaseClient<any>().schema('festival').rpc('is_current_admin');
    emergencyAdminAccess.value = !error && data === true;
  })();
  try { await emergencyRefreshPromise; } finally { emergencyRefreshPromise = null; }
}
function refreshEmergencyAccessOnFocus() { void refreshEmergencyAccess(); }
function refreshEmergencyAccessOnVisibilityChange() {
  if (document.visibilityState === 'visible') void refreshEmergencyAccess();
}

watch(supabaseUser, (user) => {
  if (user && route.query.auth === 'return') {
    router.replace('/mapa');
  }
}, { immediate: true });

onMounted(() => {
  syncSession();
  window.addEventListener('focus', refreshEmergencyAccessOnFocus);
  document.addEventListener('visibilitychange', refreshEmergencyAccessOnVisibilityChange);
  void refreshEmergencyAccess();
});
onUnmounted(() => {
  window.removeEventListener('focus', refreshEmergencyAccessOnFocus);
  document.removeEventListener('visibilitychange', refreshEmergencyAccessOnVisibilityChange);
});

watch(supabaseUser, () => { void refreshEmergencyAccess(); });

const showMaintenance = computed(() => emergencyControlsLoaded.value && emergencyShutdown.value && !emergencyAdminAccess.value && route.path !== '/admin');
</script>

<template>
  <div>
    <!-- Skip Link -->
    <a
      href="#main-content"
      class="sr-only focus:not-sr-only focus:fixed focus:top-4 focus:left-4 focus:z-[100] focus:px-4 focus:py-2 focus:bg-primary focus:text-on-primary focus:rounded-lg focus:shadow-lg focus:outline-none focus:ring-2 focus:ring-primary focus:ring-offset-2"
    >
      Skip to main content
    </a>
    <ComingSoonPage v-if="showHoldingPage" />
    <section v-else-if="showMaintenance" class="flex min-h-screen items-center justify-center bg-stone-50 p-6 text-center text-stone-900">
      <div class="max-w-lg rounded-2xl border border-stone-200 bg-white p-8 shadow-sm">
        <div class="mb-6 flex justify-center overflow-hidden rounded-md border border-stone-300 text-lg font-bold"><button type="button" class="min-h-11 min-w-11 px-3 py-2" :class="language === 'es' ? 'bg-emerald-700 text-white' : 'bg-white text-stone-600'" aria-label="Español" @click="setLanguage('es')">🇪🇸</button><button type="button" class="min-h-11 min-w-11 border-l border-stone-300 px-3 py-2" :class="language === 'en' ? 'bg-emerald-700 text-white' : 'bg-white text-stone-600'" aria-label="English" @click="setLanguage('en')">🇬🇧</button></div>
        <template v-if="language === 'es'"><h1 class="font-display text-2xl font-bold">Temporalmente no disponible</h1><p class="mt-3 text-stone-600">La web del Festival de Tapas de Castellón no está disponible temporalmente. Por favor, inténtalo de nuevo más tarde.</p></template>
        <template v-else><h1 class="font-display text-2xl font-bold">Temporarily unavailable</h1><p class="mt-3 text-stone-600">The Castellón Tapas Festival website is temporarily unavailable. Please try again later.</p></template>
      </div>
    </section>
    <NuxtPage v-else />
  </div>
</template>
