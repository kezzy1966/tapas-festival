<script setup lang="ts">
const supabase = useSupabaseClient<any>() as any;
const route = useRoute();
const status = ref<'checking' | 'request' | 'recovery' | 'success' | 'invalid'>('checking');
const email = ref(typeof route.query.email === 'string' ? route.query.email : '');
const newPassword = ref('');
const confirmPassword = ref('');
const passwordVisible = ref(false);
const confirmPasswordVisible = ref(false);
const busy = ref(false);
const error = ref('');
const notice = ref('');

const neutralResetMessage = "If an account exists for that email address, we've sent a password reset link.";

function isValidEmail(value: string) { return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value.trim()); }

async function sendResetLink() {
  error.value = '';
  notice.value = '';
  if (!isValidEmail(email.value)) {
    error.value = 'Enter a valid email address.';
    return;
  }
  busy.value = true;
  try {
    const { error: resetError } = await supabase.auth.resetPasswordForEmail(email.value.trim(), {
      redirectTo: window.location.origin + '/reset-password?recovery=1',
    });
    if (resetError && import.meta.dev) {
      console.warn('[password-reset] reset request failed', { message: resetError.message, status: resetError.status, code: resetError.code });
    }
  } catch (resetError: any) {
    // Keep the same neutral response for unknown accounts and delivery errors.
    if (import.meta.dev) {
      console.warn('[password-reset] reset request failed', { message: resetError?.message, status: resetError?.status, code: resetError?.code });
    }
  } finally {
    busy.value = false;
  }
  notice.value = neutralResetMessage;
}

async function changePassword() {
  error.value = '';
  notice.value = '';
  if (newPassword.value.length < 8) {
    error.value = 'Password must be at least 8 characters.';
    return;
  }
  if (newPassword.value !== confirmPassword.value) {
    error.value = 'Passwords do not match.';
    return;
  }
  busy.value = true;
  let updateError: any = null;
  try {
    ({ error: updateError } = await supabase.auth.updateUser({ password: newPassword.value }));
  } catch (caughtError: any) {
    updateError = caughtError;
  }
  busy.value = false;
  if (updateError) {
    if (import.meta.dev) {
      console.warn('[password-reset] password update failed', { message: updateError.message, status: updateError.status, code: updateError.code });
    }
    status.value = 'invalid';
    error.value = 'This password reset link is invalid or has expired. Request a new reset link.';
    return;
  }
  newPassword.value = '';
  confirmPassword.value = '';
  passwordVisible.value = false;
  confirmPasswordVisible.value = false;
  status.value = 'success';
  notice.value = 'Your password has been changed.';
  await supabase.auth.signOut();
}

function requestNewLink() {
  status.value = 'request';
  error.value = '';
  notice.value = '';
}

onMounted(async () => {
  let recoveryEvent = false;
  const { data: authListener } = supabase.auth.onAuthStateChange((event: string) => {
    if (event === 'PASSWORD_RECOVERY') {
      recoveryEvent = true;
      status.value = 'recovery';
    }
  });
  const recoveryMarker = window.location.hash.includes('type=recovery') || route.query.recovery === '1' || typeof route.query.code === 'string';
  const { data } = await supabase.auth.getSession();
  if (recoveryEvent || (recoveryMarker && data.session)) status.value = 'recovery';
  else if (recoveryMarker) status.value = 'invalid';
  else status.value = 'request';
  authListener?.subscription?.unsubscribe();
});
</script>

<template>
  <main class="min-h-screen bg-stone-50 p-5 text-stone-900 md:p-10">
    <section class="mx-auto max-w-md rounded-xl border border-stone-200 bg-white p-6 shadow-sm">
      <p class="text-sm font-semibold text-emerald-700">tapas-festival</p>
      <h1 class="mt-1 text-2xl font-bold">{{ status === 'recovery' ? 'Set a new password' : 'Password reset' }}</h1>
      <p v-if="status === 'checking'" class="mt-4 text-sm text-stone-600">Checking your reset link…</p>
      <template v-else-if="status === 'request'">
        <p class="mt-2 text-sm text-stone-600">Enter your email address and we’ll send a reset link if an account exists.</p><p class="mt-2 text-xs text-stone-500">If you normally sign in with Google, use Sign in with Google on the login screen.</p>
        <p v-if="error" class="mt-4 rounded border border-red-200 bg-red-50 p-3 text-sm text-red-800">{{ error }}</p>
        <p v-if="notice" class="mt-4 rounded border border-emerald-200 bg-emerald-50 p-3 text-sm text-emerald-800">{{ notice }}</p>
        <form class="mt-5 space-y-3" @submit.prevent="sendResetLink">
          <label class="block text-sm font-semibold">Email address<input v-model="email" class="mt-1 w-full rounded border p-2" type="email" autocomplete="email" required></label>
          <button class="w-full rounded bg-emerald-700 px-3 py-2 font-semibold text-white disabled:opacity-50" :disabled="busy">{{ busy ? 'Sending…' : 'Send reset link' }}</button>
        </form>
      </template>
      <template v-else-if="status === 'recovery'">
        <p class="mt-2 text-sm text-stone-600">Choose a new password for your account.</p>
        <p v-if="error" class="mt-4 rounded border border-red-200 bg-red-50 p-3 text-sm text-red-800">{{ error }}</p>
        <form class="mt-5 space-y-3" @submit.prevent="changePassword">
          <label class="block text-sm font-semibold">New password<div class="mt-1 flex items-center gap-1"><input v-model="newPassword" class="min-w-0 flex-1 rounded border p-2" :type="passwordVisible ? 'text' : 'password'" autocomplete="new-password" minlength="8" required><button type="button" class="shrink-0 rounded border border-stone-300 px-2 py-2 text-stone-600" :aria-label="passwordVisible ? 'Hide password' : 'Show password'" :title="passwordVisible ? 'Hide password' : 'Show password'" @click="passwordVisible = !passwordVisible"><Icon :name="passwordVisible ? 'lucide:eye-off' : 'lucide:eye'" class="h-4 w-4" aria-hidden="true" /></button></div></label>
          <label class="block text-sm font-semibold">Confirm new password<div class="mt-1 flex items-center gap-1"><input v-model="confirmPassword" class="min-w-0 flex-1 rounded border p-2" :type="confirmPasswordVisible ? 'text' : 'password'" autocomplete="new-password" minlength="8" required><button type="button" class="shrink-0 rounded border border-stone-300 px-2 py-2 text-stone-600" :aria-label="confirmPasswordVisible ? 'Hide password' : 'Show password'" :title="confirmPasswordVisible ? 'Hide password' : 'Show password'" @click="confirmPasswordVisible = !confirmPasswordVisible"><Icon :name="confirmPasswordVisible ? 'lucide:eye-off' : 'lucide:eye'" class="h-4 w-4" aria-hidden="true" /></button></div></label>
          <button class="w-full rounded bg-emerald-700 px-3 py-2 font-semibold text-white disabled:opacity-50" :disabled="busy">{{ busy ? 'Saving…' : 'Change password' }}</button>
        </form>
      </template>
      <template v-else-if="status === 'success'">
        <p class="mt-4 rounded border border-emerald-200 bg-emerald-50 p-3 text-sm text-emerald-800">{{ notice }}</p>
      </template>
      <template v-else>
        <p class="mt-4 rounded border border-amber-200 bg-amber-50 p-3 text-sm text-amber-900">This password reset link is invalid or has expired.</p>
        <button type="button" class="mt-4 w-full rounded bg-emerald-700 px-3 py-2 font-semibold text-white" @click="requestNewLink">Request a new reset link</button>
      </template>
      <NuxtLink to="/" class="mt-5 block text-center text-sm font-semibold text-emerald-700 hover:underline">Return to login</NuxtLink>
    </section>
  </main>
</template>
