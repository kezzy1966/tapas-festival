export function usePublicSiteControls() {
  const emergencyShutdown = useState<boolean>('festival-emergency-shutdown', () => false);
  const loaded = useState<boolean>('festival-emergency-shutdown-loaded', () => false);
  const supabase = useSupabaseClient<any>() as any;

  async function refresh() {
    const { data, error } = await supabase.schema('festival').from('site_controls')
      .select('emergency_shutdown').eq('singleton', true).maybeSingle();
    // Fail safely: only an explicit successful true activates maintenance mode.
    emergencyShutdown.value = !error && data?.emergency_shutdown === true;
    loaded.value = true;
  }

  return { emergencyShutdown, loaded, refresh };
}
