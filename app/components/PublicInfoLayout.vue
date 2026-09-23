<script setup lang="ts">
defineProps<{ title: string; eyebrow: string }>();
const { language, setLanguage } = useFestivalLanguage();
</script>

<template>
  <div class="flex min-h-screen flex-col bg-stone-50 text-stone-900">
    <a href="#main-content" class="sr-only focus:not-sr-only focus:fixed focus:top-4 focus:left-4 focus:z-[100] focus:rounded-lg focus:bg-emerald-700 focus:px-4 focus:py-2 focus:text-white focus:shadow-lg">{{ language === 'es' ? 'Saltar al contenido principal' : 'Skip to main content' }}</a>
    <header class="border-b border-stone-200 bg-white"><div class="mx-auto flex max-w-4xl items-center justify-between gap-4 px-4 py-4 sm:px-6">
      <NuxtLink to="/" class="min-w-0 font-display text-xl font-bold tracking-tight text-stone-900 hover:text-emerald-800">Tapas Castellón</NuxtLink>
      <div class="flex overflow-hidden rounded-md border border-stone-300 text-sm font-bold" :aria-label="language === 'es' ? 'Idioma' : 'Language'"><button type="button" class="min-h-10 min-w-10 px-2" :class="language === 'es' ? 'bg-emerald-700 text-white' : 'bg-white text-stone-600'" :aria-pressed="language === 'es'" aria-label="Español" @click="setLanguage('es')">ES</button><button type="button" class="min-h-10 min-w-10 border-l border-stone-300 px-2" :class="language === 'en' ? 'bg-emerald-700 text-white' : 'bg-white text-stone-600'" :aria-pressed="language === 'en'" aria-label="English" @click="setLanguage('en')">EN</button></div>
    </div></header>
    <main id="main-content" class="mx-auto w-full max-w-4xl flex-1 px-4 py-10 sm:px-6 sm:py-14" tabindex="-1"><p class="text-xs font-bold uppercase tracking-[0.18em] text-emerald-700">{{ eyebrow }}</p><h1 class="mt-2 font-display text-3xl font-bold tracking-tight sm:text-4xl">{{ title }}</h1><div class="mt-8 max-w-3xl text-base leading-7 text-stone-700"><slot /></div></main>
    <footer class="border-t border-stone-200 bg-white px-4 py-6 text-sm text-stone-600 sm:px-6"><nav class="mx-auto flex max-w-4xl flex-wrap justify-center gap-x-5 gap-y-2" :aria-label="language === 'es' ? 'Enlaces del sitio' : 'Site links'"><NuxtLink class="font-semibold text-emerald-700 underline" to="/about">{{ language === 'es' ? 'Acerca de' : 'About' }}</NuxtLink><NuxtLink class="font-semibold text-emerald-700 underline" to="/contact">{{ language === 'es' ? 'Contacto' : 'Contact' }}</NuxtLink><NuxtLink class="font-semibold text-emerald-700 underline" to="/privacy">{{ language === 'es' ? 'Privacidad' : 'Privacy' }}</NuxtLink></nav></footer>
  </div>
</template>
