<!--* app\components\AuthModal.vue  -->

<script setup lang="ts">
import { ref, watch, computed } from 'vue';
import { usePlacesStore } from '../stores/places';
import { useUIStore } from '../stores/ui';
import { X, AlertCircle, CheckCircle2, Loader2, UtensilsCrossed } from '@lucide/vue';
import { useForm, useField } from 'vee-validate';
import { toTypedSchema } from '@vee-validate/zod';
import { authSchema } from '~/utils/schemas';
import { useAuthSession } from '~/composables/useAuthSession';
import { useFocusTrap } from '../composables/useFocusTrap';

const store = usePlacesStore();
const ui = useUIStore();
const { login, register, resetPassword, loginWithGoogle } = useAuthSession();
const router = useRouter();

const isOpen = computed(() => ui.activeModal === 'auth');

const mode = ref<'login' | 'register' | 'reset'>('login');
const isLoading = ref(false);
const errorMessage = ref('');
const successMessage = ref('');
const passwordVisible = ref(false);

const modalRef = ref<HTMLElement | null>(null);
const { activate, deactivate } = useFocusTrap(modalRef);

watch(isOpen, (open) => {
  if (open) {
    activate();
  } else {
    deactivate();
  }
});

function onKeyDown(e: KeyboardEvent) {
  if (!isOpen.value) return;
  if (e.key === 'Escape') {
    ui.closeModal();
  }
}

const { handleSubmit, errors, resetForm } = useForm({
  validationSchema: toTypedSchema(authSchema),
  initialValues: {
    email: '',
    password: '',
  },
});

const { value: email, errorMessage: emailError } = useField<string>('email');
const { value: password, errorMessage: passwordError } = useField<string>('password');

function openPasswordReset() { ui.closeModal(); void router.push({ path: '/reset-password', query: email.value.trim() ? { email: email.value.trim() } : undefined }); }

async function handleGoogleLogin() {
  errorMessage.value = '';
  successMessage.value = '';
  isLoading.value = true;
  try {
    await loginWithGoogle();
  } catch (err) {
    errorMessage.value = err instanceof Error ? err.message : 'An error occurred during Google login.';
    isLoading.value = false;
  }
}

watch(() => ui.activeModal, (val) => {
  if (val === 'auth') {
    errorMessage.value = '';
    successMessage.value = '';
    isLoading.value = false;
    mode.value = 'login';
    passwordVisible.value = false;
    resetForm();
  }
});

const onSubmit = handleSubmit(async (formValues) => {
  errorMessage.value = '';
  successMessage.value = '';
  isLoading.value = true;

  try {
    if (mode.value === 'login') {
      await login(formValues.email, formValues.password);
      successMessage.value = 'Welcome back!';
      setTimeout(() => {
        ui.closeModal();
        router.push('/mapa');
      }, 1000);
    } else if (mode.value === 'register') {
      const { sessionCreated } = await register(formValues.email, formValues.password);
      if (sessionCreated) {
        successMessage.value = 'Account created successfully. Logged in!';
        setTimeout(() => {
          ui.closeModal();
          router.push('/mapa');
        }, 2000);
      } else {
        successMessage.value = 'Account created! Check your email to confirm before logging in.';
        setTimeout(() => ui.closeModal(), 2000);
      }
    } else if (mode.value === 'reset') {
      await resetPassword(formValues.email);
      successMessage.value = 'A password recovery link has been sent to your email.';
    }
  } catch (err) {
    errorMessage.value = err instanceof Error ? err.message : 'An error occurred during authentication.';
  } finally {
    isLoading.value = false;
  }
});
</script>

<template>
  <div
    v-if="ui.activeModal === 'auth'"
    ref="modalRef"
    class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm"
    @keydown.window="onKeyDown"
    role="dialog"
    aria-modal="true"
    aria-labelledby="auth-title"
  >
    <div class="relative w-full max-w-sm bg-surface border border-border rounded-3xl p-6 shadow-2xl space-y-5 animate-fade-in">

      <!-- Modal Header -->
      <div class="flex items-center justify-between pb-3 border-b border-border">
        <div class="flex items-center gap-2">
          <div class="w-8 h-8 rounded-full bg-primary text-on-primary flex items-center justify-center font-serif font-bold text-base">
          <UtensilsCrossed />
          </div>
          <div>
            <h2 id="auth-title" class="font-serif font-bold text-xl text-text-primary">
              {{ mode === 'login' ? 'Log In' : mode === 'register' ? 'Create Account' : 'Reset Password' }}
            </h2>
            <p class="text-xs text-text-tertiary font-medium">
              Save and sync your restaurant map
            </p>
          </div>
        </div>

        <button
          @click="ui.closeModal()"
          class="p-1.5 rounded-full text-text-tertiary hover:text-text-primary hover:bg-bg-tertiary"
          aria-label="Close"
        >
          <X class="w-5 h-5" />
        </button>
      </div>

      <!-- Mode Switcher Tabs -->
      <div v-if="mode !== 'reset'" class="grid grid-cols-2 p-1 bg-bg-secondary rounded-2xl border border-border text-xs font-semibold" role="group" aria-label="Authentication mode">
        <button
          @click="mode = 'login'"
          class="py-2 rounded-xl transition-all"
          :class="mode === 'login' ? 'bg-surface text-primary shadow-sm' : 'text-text-tertiary'"
          :aria-pressed="mode === 'login'"
        >
          Log In
        </button>
        <button
          @click="mode = 'register'"
          class="py-2 rounded-xl transition-all"
          :class="mode === 'register' ? 'bg-surface text-primary shadow-sm' : 'text-text-tertiary'"
          :aria-pressed="mode === 'register'"
        >
          Sign Up
        </button>
      </div>

      <!-- Error / Success Alert -->
      <div v-if="errorMessage" role="alert" class="p-3 rounded-xl bg-danger/10 border border-danger/20 text-danger text-xs font-medium flex items-center gap-2">
        <AlertCircle class="w-4 h-4 shrink-0" />
        <span>{{ errorMessage }}</span>
      </div>

      <div v-if="successMessage" role="status" class="p-3 rounded-xl bg-primary/10 border border-primary/20 text-primary text-xs font-medium flex items-center gap-2">
        <CheckCircle2 class="w-4 h-4 shrink-0" />
        <span>{{ successMessage }}</span>
      </div>

      <!-- Google OAuth -->
      <button
        v-if="mode !== 'reset'"
        type="button"
        @click="handleGoogleLogin()"
        :disabled="isLoading"
        class="w-full flex items-center justify-center gap-2.5 py-2.5 rounded-xl text-xs font-bold bg-surface hover:bg-bg-secondary border border-border text-text-primary shadow-sm transition-all disabled:opacity-50"
      >
        <svg class="w-4 h-4" viewBox="0 0 24 24" aria-hidden="true">
          <path fill="#4285F4" d="M23.49 12.27c0-.79-.07-1.54-.19-2.27H12v4.51h6.47a5.57 5.57 0 0 1-2.4 3.58v3h3.86c2.26-2.09 3.56-5.17 3.56-8.82z"/>
          <path fill="#34A853" d="M12 24c3.24 0 5.95-1.08 7.93-2.91l-3.86-3c-1.08.72-2.45 1.16-4.07 1.16-3.13 0-5.78-2.11-6.73-4.96H1.29v3.09A11.99 11.99 0 0 0 12 24z"/>
          <path fill="#FBBC05" d="M5.27 14.29a7.2 7.2 0 0 1 0-4.58V6.62H1.29a12 12 0 0 0 0 10.76l3.98-3.09z"/>
          <path fill="#EA4335" d="M12 4.75c1.77 0 3.35.61 4.6 1.8l3.42-3.42C17.95 1.19 15.24 0 12 0 7.31 0 3.25 2.69 1.29 6.62l3.98 3.09C6.22 6.86 8.87 4.75 12 4.75z"/>
        </svg>
        <span>Continue with Google</span>
      </button>

      <div v-if="mode !== 'reset'" class="flex items-center gap-3">
        <div class="flex-1 h-px bg-border"></div>
        <span class="text-[11px] font-semibold text-text-tertiary uppercase tracking-wider">or</span>
        <div class="flex-1 h-px bg-border"></div>
      </div>

      <!-- Auth Form -->
      <form @submit.prevent="onSubmit" class="space-y-3.5">

        <div>
          <label for="auth-email" class="block text-xs font-bold uppercase tracking-wider text-text-tertiary mb-1">
            Email Address
          </label>
          <input
            id="auth-email"
            v-model="email"
            type="email"
            autocomplete="email"
            placeholder="you@email.com"
            aria-required="true"
            :aria-describedby="emailError ? 'auth-email-error' : undefined"
            class="min-w-0 flex-1 px-3.5 py-2.5 text-xs bg-bg-secondary border rounded-xl focus:outline-none focus:border-primary text-text-primary"
            :class="emailError ? 'border-danger' : 'border-border'"
          />
          <p v-if="emailError" id="auth-email-error" class="text-[11px] text-danger mt-1">{{ emailError }}</p>
        </div>

        <div v-if="mode !== 'reset'">
          <div class="flex items-center justify-between mb-1">
            <label for="auth-password" class="block text-xs font-bold uppercase tracking-wider text-text-tertiary">
              Password
            </label>
            <button
              v-if="mode === 'login'"
              type="button"
              @click="openPasswordReset"
              class="text-[11px] text-primary font-semibold hover:underline"
            >
              Forgot your password?
            </button>
          </div>
          <div class="flex items-center gap-2">
          <input
            id="auth-password"
            v-model="password"
            :type="passwordVisible ? 'text' : 'password'"
            autocomplete="current-password"
            placeholder="••••••••"
            aria-required="true"
            :aria-describedby="passwordError ? 'auth-password-error' : undefined"
            class="w-full px-3.5 py-2.5 text-xs bg-bg-secondary border rounded-xl focus:outline-none focus:border-primary text-text-primary"
            :class="passwordError ? 'border-danger' : 'border-border'"
          /><button type="button" class="inline-flex h-10 w-10 shrink-0 items-center justify-center rounded-xl border border-border text-text-tertiary hover:text-text-primary" :aria-label="passwordVisible ? 'Hide password' : 'Show password'" :title="passwordVisible ? 'Hide password' : 'Show password'" v-on:click="passwordVisible = !passwordVisible"><Icon v-if="passwordVisible" name="lucide:eye-off" class="h-4 w-4" aria-hidden="true" /><Icon v-else name="lucide:eye" class="h-4 w-4" aria-hidden="true" /></button></div>
          <p v-if="passwordError" id="auth-password-error" class="text-[11px] text-danger mt-1">{{ passwordError }}</p>
        </div>

        <!-- Submit Button -->
        <button
          type="submit"
          :disabled="isLoading"
          class="w-full py-2.5 rounded-xl text-xs font-bold bg-primary hover:bg-primary-hover text-on-primary shadow-sm transition-all flex items-center justify-center gap-2 disabled:opacity-50 mt-2"
        >
          <Loader2 v-if="isLoading" class="w-4 h-4 animate-spin" />
          <span>{{ mode === 'login' ? 'Log In to Tastemap' : mode === 'register' ? 'Create Free Account' : 'Send Recovery Email' }}</span>
        </button>

      </form>

      <!-- Back to Login option if reset -->
      <div v-if="mode === 'reset'" class="text-center pt-2">
        <button
          @click="mode = 'login'"
          class="text-xs text-primary font-semibold hover:underline"
        >
          ← Back to Log In
        </button>
      </div>

      <!-- Guest mode note -->
      <div class="pt-3 border-t border-border text-center text-xs text-text-tertiary">
        <p>You can also use Tastemap in <strong>Guest Mode</strong> without signing up.</p>
      </div>

    </div>
  </div>
</template>
