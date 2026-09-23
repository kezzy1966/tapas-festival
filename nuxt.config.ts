import tailwindcss from '@tailwindcss/vite';

const buildParts = new Intl.DateTimeFormat('en-GB', {
  timeZone: 'Europe/Madrid', weekday: 'short', day: '2-digit', month: 'short', year: '2-digit',
  hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
}).formatToParts(new Date());
const buildPart = (type: Intl.DateTimeFormatPartTypes) => buildParts.find((part) => part.type === type)?.value || '';
const buildReference = `${buildPart('weekday')}${buildPart('day')}${buildPart('month')}'${buildPart('year')}@${buildPart('hour')}${buildPart('minute')}`;
const configuredPublicSupabaseKey = process.env.NUXT_PUBLIC_SUPABASE_KEY || '';
if (configuredPublicSupabaseKey.startsWith('sb_secret_')) {
  throw new Error('NUXT_PUBLIC_SUPABASE_KEY must contain the Supabase publishable/anon key, never a secret key.');
}



export default defineNuxtConfig({
  compatibilityDate: '2025-07-15',
  devtools: { enabled: true },
  $production: {
    devtools: { enabled: false },
  },
  runtimeConfig: {
    nominatimContactEmail: '',
    adminPasswordResetServiceRoleKey: '',
    public: {
      buildReference,
      // Defaults to false locally and in Preview. Set NUXT_PUBLIC_HOLDING_MODE=true
      // only in Vercel Production to show the temporary public holding page.
      holdingMode: false,
    },
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
      htmlAttrs: { lang: 'es' },
      link: [
        { rel: 'icon', type: 'image/x-icon', href: '/favicon.ico' },
      ],
    },
  },
});
