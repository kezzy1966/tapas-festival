<script setup lang="ts">
const { language, setLanguage } = useFestivalLanguage();
const title = computed(() => language.value === 'es' ? 'Próximamente' : 'Coming soon');
const description = computed(() => language.value === 'es'
  ? 'Tapas Castellón está preparando la web para la próxima edición.'
  : 'Tapas Castellón is preparing the website for the next edition.');

useSeoMeta({
  title,
  description,
  robots: 'noindex, nofollow',
  ogTitle: computed(() => 'Tapas Castellón · ' + title.value),
  ogDescription: description,
  ogSiteName: 'Tapas Castellón',
  twitterCard: 'summary',
  twitterTitle: computed(() => 'Tapas Castellón · ' + title.value),
  twitterDescription: description,
});
</script>

<template>
  <main class="flex min-h-screen items-center justify-center bg-stone-50 px-5 py-10 text-stone-900">
    <section class="w-full max-w-xl rounded-2xl border border-stone-200 bg-white p-7 text-center shadow-sm sm:p-12">
      <div class="mb-8 flex justify-center">
        <div class="flex overflow-hidden rounded-md border border-stone-300 text-sm font-bold" :aria-label="language === 'es' ? 'Idioma' : 'Language'">
          <button type="button" class="min-h-10 min-w-10 px-2" :class="language === 'es' ? 'bg-emerald-700 text-white' : 'bg-white text-stone-600'" :aria-pressed="language === 'es'" aria-label="Español" @click="setLanguage('es')">ESPAÑOL</button>
          <button type="button" class="min-h-10 min-w-10 border-l border-stone-300 px-2" :class="language === 'en' ? 'bg-emerald-700 text-white' : 'bg-white text-stone-600'" :aria-pressed="language === 'en'" aria-label="English" @click="setLanguage('en')">ENGLISH</button>
        </div>
      </div>

      <p class="font-display text-3xl font-bold tracking-tight text-stone-900 sm:text-4xl">Tapas Castellón</p>

      <div class="mt-8 space-y-3">
        <p class="text-lg font-semibold text-emerald-800">Descubre los sabores de Castellón.</p>
        <p class="text-stone-600">Estamos preparando la web para la próxima edición.</p>
        <p class="pt-1 text-xs font-bold tracking-[0.2em] text-emerald-700">PRÓXIMAMENTE</p>
      </div>

      <div class="mx-auto my-8 h-px max-w-xs bg-stone-200" />

      <div class="space-y-3">
        <p class="text-lg font-semibold text-emerald-800">Discover the flavours of Castellón.</p>
        <p class="text-stone-600">We're preparing the website for the next edition.</p>
        <p class="pt-1 text-xs font-bold tracking-[0.2em] text-emerald-700">COMING SOON</p>
      </div>

      <p class="mt-10 text-xs leading-5 text-stone-500">{{ language === 'es' ? 'Proyecto independiente; no es la web oficial del festival ni del Ayuntamiento de Castellón.' : 'An independent project; not the official website of the festival or Castellón City Council.' }}</p>
    </section>
  </main>
</template>
