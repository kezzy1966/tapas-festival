export function useAuthSession() {
  const client = useSupabaseClient();
  const supabaseUser = useSupabaseUser();
  const ui = useUIStore();
  const store = usePlacesStore();

  async function login(email: string, password: string) {
    const { data, error } = await client.auth.signInWithPassword({ email, password });
    if (error) throw error;
    if (data.user) {
      ui.setUser({ email: data.user.email ?? email });
    }
  }

  async function register(email: string, password: string) {
    const { data, error } = await client.auth.signUp({ email, password });
    if (error) throw error;
    const sessionUser = data.session?.user ?? null;
    if (sessionUser) {
      ui.setUser({ email: sessionUser.email ?? email });
    }
    return { sessionCreated: Boolean(sessionUser) };
  }

  async function resetPassword(email: string) {
    const { error } = await client.auth.resetPasswordForEmail(email, {
      redirectTo: window.location.origin + "/reset-password?recovery=1",
    });
    if (error) throw error;
  }

  async function loginWithGoogle() {
    const { data, error } = await client.auth.signInWithOAuth({
      provider: 'google',
      options: {
        redirectTo: `${window.location.origin}/?auth=return`,
      },
    });
    if (error) throw error;
    return data;
  }

  async function logout() {
    const { error } = await client.auth.signOut();
    if (error) throw error;
    ui.setUser(null);
    ui.closeModal();
  }

  function syncSession() {
    watch(supabaseUser, async (user) => {
      if (user) {
        ui.setUser({ email: user.email ?? '' });
        await store.loadUserData();
      } else {
        ui.setUser(null);
        store.loadSampleData();
      }
    }, { immediate: true });
  }

  return { login, register, resetPassword, loginWithGoogle, logout, syncSession };
}
