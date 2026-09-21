<!--* app/components/Navbar.vue -->

<script setup lang="ts">
import { usePlacesStore } from '../stores/places';
import { useUIStore } from '../stores/ui';
import { useAuthSession } from '~/composables/useAuthSession';
import { useRouter, useRoute } from 'vue-router';
import {
  MapPin,
  Search,
  X,
  Menu,
  Sparkles,
  BarChart3,
  Sun,
  Moon,
  Plus,
  CircleUserRound,
  LogOut,
} from '@lucide/vue';

const store = usePlacesStore();
const ui = useUIStore();
const { logout } = useAuthSession();
const router = useRouter();
const route = useRoute();
const supabase = useSupabaseClient<any>();
const supabaseUser = useSupabaseUser();
const isAdminAccount = ref(false);
async function refreshAdminAccess() {
  if (!supabaseUser.value) { isAdminAccount.value = false; return; }
  const { data, error } = await supabase.schema('festival').rpc('is_current_admin');
  isAdminAccount.value = !error && data === true;
}
watch(supabaseUser, () => void refreshAdminAccess(), { immediate: true });

const isLanding = computed(() => route.path === '/');

function goHome() {
  ui.showLanding = true;
  router.push('/');
}
</script>

<template>
  <header class="sticky top-0 z-30 bg-surface border-b border-border shadow-sm backdrop-blur-md bg-opacity-95">
    <div class="max-w-350 mx-auto px-4 sm:px-6 h-16 flex items-center justify-between gap-3">

      <!-- Brand & Title -->
      <router-link
        to="/"
        @click="goHome()"
        class="flex items-center gap-3 cursor-pointer hover:opacity-80 transition-opacity"
      >
        <div class="w-9 h-9 rounded-full bg-primary text-on-primary flex items-center justify-center font-serif font-bold text-lg shadow-sm"><MapPin class="w-4 h-4 text-on-primary" /></div>
        <div>
          <h1 v-if="!isLanding" class="font-serif font-bold text-xl sm:text-2xl tracking-tight leading-none text-text-primary">
            Tastemap<span class="text-highlight">.</span>
          </h1>
          <span v-else class="block font-serif font-bold text-xl sm:text-2xl tracking-tight leading-none text-text-primary">
            Tastemap<span class="text-highlight">.</span>
          </span>
          <p aria-hidden="true" class="text-[8px] md:text-[11px] text-text-tertiary font-medium">Your personal map & honest ranking</p>
        </div>
      </router-link>

      <!-- Desktop Search Bar (app only) -->
      <div v-if="!isLanding" class="hidden md:flex items-center flex-1 max-w-xs relative mx-4">
        <SearchBar variant="desktop" />
      </div>

      <!-- Desktop Action Buttons -->
      <nav aria-label="Main actions" class="hidden md:flex items-center gap-1.5 sm:gap-2">
        <template v-if="!isLanding">
          <button
            @click="ui.openModal('decider')"
            class="flex items-center gap-1.5 px-3 py-1.5 rounded-full text-xs font-semibold bg-bg-secondary hover:bg-bg-tertiary text-text-primary border border-border transition-all active:scale-95"
            title="Help me decide where to eat"
            aria-label="Help me decide where to eat">
            <Sparkles class="w-3.5 h-3.5 text-highlight-strong"/>
            <span class="hidden sm:inline">Where to eat?</span>
          </button>

          <button
            @click="ui.openModal('stats')"
            class="p-2 rounded-full text-text-secondary hover:text-text-primary hover:bg-bg-secondary transition-colors"
            title="Taste stats"
            aria-label="View taste statistics">
            <BarChart3 class="w-4 h-4" />
          </button>
        </template>

        <button
          @click="ui.toggleDarkMode()"
          class="p-2 rounded-full text-text-secondary hover:text-text-primary hover:bg-bg-secondary transition-colors"
          :title="ui.isDarkMode ? 'Light mode' : 'Dark mode'"
          aria-label="Toggle dark mode">
          <Sun v-if="ui.isDarkMode" class="w-4 h-4 text-highlight"/>
          <Moon v-else class="w-4 h-4" />
        </button>

        <div class="relative flex items-center">
          <div v-if="ui.currentUser" class="flex items-center gap-1.5 pl-1.5 pr-2 py-1 rounded-full bg-bg-secondary border border-border text-xs font-semibold">
            <div class="w-5 h-5 rounded-full bg-primary text-on-primary flex items-center justify-center text-[10px] uppercase font-bold">
              {{ ui.currentUser.email.charAt(0) }}
            </div>
            <span class="max-w-25 truncate text-text-primary text-[11px] hidden sm:inline">
              {{ ui.currentUser.email.split('@')[0] }}
            </span>
            <NuxtLink v-if="isAdminAccount" to="/admin" class="rounded-full bg-primary px-2 py-1 text-[11px] font-semibold text-on-primary">Admin</NuxtLink>
            <button @click="logout()" class="p-1 flex hover:text-red-500 text-text-tertiary transition-colors" title="Log out" aria-label="Log out">
              <LogOut class="w-3.5 h-3.5" />
            </button>
          </div>
          <button
            v-else
            @click="ui.openModal('auth')"
            class="flex items-center gap-1.5 px-3 py-1.5 rounded-full text-xs font-semibold text-text-primary bg-bg-secondary hover:bg-bg-tertiary border border-border transition-all"
            title="Log in or create an account">
            <CircleUserRound class="w-5 h-5 text-primary" />
            <span class="hidden sm:inline">Log in</span>
          </button>
        </div>

        <button
          v-if="!isLanding"
          @click="ui.openModal('addPlace')"
          class="flex items-center gap-1.5 px-3.5 py-1.5 rounded-full text-xs font-semibold bg-primary hover:bg-primary-hover text-on-primary shadow-sm transition-all active:scale-95 ml-1">
          <Plus class="w-4 h-4" />
          <span>Add place</span>
        </button>
      </nav>

      <!-- Mobile Icons -->
      <nav class="flex md:hidden items-center gap-2" aria-label="Mobile menu">
        <button
          v-if="!isLanding"
          @click="ui.openModal('search')"
          class="p-2 rounded-full text-text-secondary hover:text-text-primary hover:bg-bg-secondary transition-colors"
          aria-label="Search">
          <Search class="w-5 h-5" />
        </button>
        <button
          v-if="!isLanding"
          @click="ui.toggleMenu()"
          class="p-2 rounded-full text-text-secondary hover:text-text-primary hover:bg-bg-secondary transition-colors"
          :aria-label="ui.isMenuOpen ? 'Close menu' : 'Open menu'"
          :aria-expanded="ui.isMenuOpen"
          aria-controls="mobile-menu">
          <X v-if="ui.isMenuOpen" class="w-5 h-5" />
          <Menu v-else class="w-5 h-5" />
        </button>
      </nav>
    </div>

    <!-- Mobile Search Bar (expanded) -->
    <div v-if="ui.activeModal === 'search'" class="md:hidden border-t border-border bg-surface">
      <div class="max-w-350 mx-auto px-4 py-3 flex items-center gap-2">
        <div class="relative flex-1">
          <SearchBar variant="mobile" />
        </div>
        <button
          @click="ui.closeModal()"
          class="text-sm font-medium text-text-secondary hover:text-text-primary">
          Cancel
        </button>
      </div>
    </div>

    <!-- Mobile Dropdown Menu -->
    <Transition
      enter-active-class="transition duration-200 ease-out"
      enter-from-class="opacity-0 -translate-y-2"
      enter-to-class="opacity-100 translate-y-0"
      leave-active-class="transition duration-150 ease-in"
      leave-from-class="opacity-100 translate-y-0"
      leave-to-class="opacity-0 -translate-y-2">
      <div
        v-if="ui.isMenuOpen"
        id="mobile-menu"
        class="md:hidden absolute top-16 left-0 right-0 bg-surface border-b border-border shadow-lg z-40">
        <div class="max-w-350 mx-auto px-4 py-3 flex flex-col gap-1">

          <button
            @click="ui.openModal('decider'); ui.closeMenu()"
            class="flex items-center gap-3 px-4 py-3 rounded-xl text-sm font-medium text-text-primary hover:bg-bg-secondary transition-colors text-left">
            <Sparkles class="w-5 h-5 text-highlight-strong"/>
            <span>Where to eat?</span>
          </button>

          <button
            @click="ui.openModal('stats'); ui.closeMenu()"
            class="flex items-center gap-3 px-4 py-3 rounded-xl text-sm font-medium text-text-primary hover:bg-bg-secondary transition-colors text-left">
            <BarChart3 class="w-5 h-5 text-text-secondary"/>
            <span>Stats</span>
          </button>

          <button
            @click="ui.toggleDarkMode()"
            class="flex items-center gap-3 px-4 py-3 rounded-xl text-sm font-medium text-text-primary hover:bg-bg-secondary transition-colors text-left">
            <Sun v-if="ui.isDarkMode" class="w-5 h-5 text-highlight"/>
            <Moon v-else class="w-5 h-5 text-text-secondary"/>
            <span>{{ ui.isDarkMode ? 'Light mode' : 'Dark mode' }}</span>
          </button>

          <div class="border-t border-border my-1"></div>

          <NuxtLink v-if="ui.currentUser && isAdminAccount" to="/admin" class="flex items-center justify-center rounded-xl bg-primary px-4 py-3 text-sm font-semibold text-on-primary" @click="ui.closeMenu()">Admin</NuxtLink>

          <div v-if="ui.currentUser" class="flex items-center gap-3 px-4 py-3">
            <div class="w-8 h-8 rounded-full bg-primary text-on-primary flex items-center justify-center text-xs uppercase font-bold">
              {{ ui.currentUser.email.charAt(0) }}
            </div>
            <div class="flex-1 min-w-0">
              <p class="text-sm font-medium text-text-primary truncate">{{ ui.currentUser.email }}</p>
            </div>
            <button
              @click="logout(); ui.closeMenu()"
              class="p-2 rounded-full text-text-tertiary hover:text-red-500 hover:bg-bg-secondary transition-colors">
              <LogOut class="w-4 h-4" />
            </button>
          </div>

          <button
            v-else
            @click="ui.openModal('auth'); ui.closeMenu()"
            class="flex items-center gap-3 px-4 py-3 rounded-xl text-sm font-medium text-text-primary hover:bg-bg-secondary transition-colors text-left">
            <CircleUserRound class="w-5 h-5 text-primary"/>
            <span>Log in</span>
          </button>

          <div class="border-t border-border my-1"></div>

          <button
            @click="ui.openModal('addPlace'); ui.closeMenu()"
            class="flex items-center justify-center gap-2 px-4 py-3 rounded-xl text-sm font-semibold bg-primary hover:bg-primary-hover text-on-primary transition-colors">
            <Plus class="w-4 h-4" />
            <span>Add place</span>
          </button>

        </div>
      </div>
    </Transition>
  </header>
</template>