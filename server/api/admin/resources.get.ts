import { privilegedSupabaseClient, requireAdminPasswordResetCaller } from '../../utils/adminPasswordReset';

function formatEnvironment(config: Record<string, any>) {
  return process.env.VERCEL_ENV || process.env.NODE_ENV || 'local';
}

export default defineEventHandler(async (event) => {
  const caller = await requireAdminPasswordResetCaller(event);
  if (caller.role !== 'superuser') throw createError({ statusCode: 403, statusMessage: 'Superadmin access required.' });

  const config = useRuntimeConfig(event) as Record<string, any>;
  const privileged = privilegedSupabaseClient(event);
  const { data, error } = await privileged.schema('festival').rpc('admin_resources');
  if (error || !data) throw createError({ statusCode: 502, statusMessage: 'Resource metrics are unavailable.' });

  const publicUrl = String(config.public?.supabase?.url || '');
  let projectRef: string | null = null;
  try { projectRef = new URL(publicUrl).hostname.split('.')[0] || null; } catch { projectRef = null; }

  return {
    refreshed_at: new Date().toISOString(),
    supabase: data,
    vercel: {
      project: process.env.VERCEL_PROJECT_PRODUCTION_URL || 'Unavailable from current connection',
      environment: formatEnvironment(config),
      deployment_url: process.env.VERCEL_URL ? `https://${process.env.VERCEL_URL}` : 'Unavailable from current connection',
      commit: process.env.VERCEL_GIT_COMMIT_SHA || 'Unavailable from current connection',
      analytics: 'Configured in application; usage unavailable from current connection',
      quotas: 'Unavailable from current connection',
    },
    github: {
      repository: 'kezzy1966/tapas-festival',
      branch: process.env.VERCEL_GIT_COMMIT_REF || 'fast-admin',
      commit: process.env.VERCEL_GIT_COMMIT_SHA || 'Unavailable from current connection',
      usage: 'Unavailable from current connection',
    },
    application: {
      nuxt: '4.5.2',
      vue: '3.5.41',
      node: process.version,
      environment: formatEnvironment(config),
      commit: process.env.VERCEL_GIT_COMMIT_SHA || 'Unavailable from current connection',
      supabase_project_ref: projectRef || 'Unavailable from current connection',
      database_region: 'Unavailable from current connection',
      establishments: (data.tables || []).find((row: any) => row.table_name === 'establishments')?.estimated_rows ?? 'Unavailable from current connection',
      tapas: (data.tables || []).find((row: any) => row.table_name === 'tapas')?.estimated_rows ?? 'Unavailable from current connection',
      festivals: (data.tables || []).find((row: any) => row.table_name === 'festivals')?.estimated_rows ?? 'Unavailable from current connection',
    },
  };
});
