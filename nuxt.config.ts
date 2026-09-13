import tailwindcss from '@tailwindcss/vite';

const buildParts = new Intl.DateTimeFormat('en-GB', {
  timeZone: 'Europe/Madrid', weekday: 'short', day: '2-digit', month: 'short', year: '2-digit',
  hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
}).formatToParts(new Date());
const buildPart = (type: Intl.DateTimeFormatPartTypes) => buildParts.find((part) => part.type === type)?.value || '';
const buildReference = `${buildPart('weekday')}${buildPart('day')}${buildPart('month')}'${buildPart('year')}@${buildPart('hour')}${buildPart('minute')}`;


export default defineNuxtConfig({
  compatibilityDate: '2025-07-15',
  devtools: { enabled: true },
  $production: {
    devtools: { enabled: false },
  },
  runtimeConfig: {
    nominatimContactEmail: '',
    public: { buildReference },
  },
  modules: ['@pinia/nuxt', '@nuxt/icon', '@nuxtjs/supabase','@vercel/analytics'],
  supabase: {
    redirect: false,
    redirectOptions: {
      login: '/',
      callback: '/',
      exclude: [],
    },
  },
  icon: {
    serverBundle: 'local',
  },
  css: ['~/assets/css/main.css'],
  vite: {
    plugins: [tailwindcss()],
  },
  app: {
    head: {
      htmlAttrs: { lang: 'en' },
      title: 'Food Journal | Tastemap',
      meta: [{ name: 'description', content: 'Personal London restaurant map with Elo pairwise ranking, curated lists, and taste stats' }],
    },
  },
});
