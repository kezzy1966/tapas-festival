import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { serverSupabaseClient, serverSupabaseUser } from '#supabase/server';
import type { H3Event } from 'h3';

type CallerContext = { id: string; role: 'admin' | 'superuser'; client: SupabaseClient<any> };

function isUuid(value: unknown): value is string {
  return typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

export async function requireAdminPasswordResetCaller(event: H3Event): Promise<CallerContext> {
  const sessionUser = await serverSupabaseUser(event).catch(() => null);
  const callerId = sessionUser?.sub;
  if (!isUuid(callerId)) throw createError({ statusCode: 401, statusMessage: 'Authentication required.' });
  const client = await serverSupabaseClient(event);
  const [{ data: admin, error: adminError }, { data: superuser, error: superuserError }] = await Promise.all([
    client.schema('festival').rpc('is_current_admin'),
    client.schema('festival').rpc('is_current_superuser'),
  ]);
  if (adminError || superuserError || admin !== true) throw createError({ statusCode: 403, statusMessage: 'Administrator access required.' });
  return { id: callerId, role: superuser === true ? 'superuser' : 'admin', client };
}

export function requireTargetAccountId(value: unknown): string {
  if (!isUuid(value)) throw createError({ statusCode: 400, statusMessage: 'A valid account ID is required.' });
  return value;
}

export function privilegedSupabaseClient(event: H3Event): SupabaseClient<any> {
  const config = useRuntimeConfig(event);
  const key = String(config.adminPasswordResetServiceRoleKey || '').trim();
  const url = String(config.public.supabase.url || '').trim();
  if (!key || !url) throw createError({ statusCode: 503, statusMessage: 'Password reset service is not configured.' });
  return createClient(url, key, { auth: { autoRefreshToken: false, detectSessionInUrl: false, persistSession: false } });
}

export async function targetRole(client: SupabaseClient<any>, accountId: string): Promise<'user' | 'admin' | 'superuser'> {
  const { data, error } = await client.schema('festival').rpc('password_reset_target_role', { p_account_id: accountId });
  if (error) throw createError({ statusCode: 502, statusMessage: 'Unable to verify the target account.' });
  return data === 'admin' || data === 'superuser' ? data : 'user';
}

export function canResetTarget(callerRole: CallerContext['role'], targetRoleValue: 'user' | 'admin' | 'superuser') {
  return targetRoleValue === 'user' || (callerRole === 'superuser' && targetRoleValue === 'admin');
}

export function canAuditTarget(callerId: string, callerRole: CallerContext['role'], targetId: string, targetRoleValue: 'user' | 'admin' | 'superuser') {
  if (targetRoleValue === 'superuser') return callerRole === 'superuser' && callerId === targetId;
  return callerRole === 'superuser' || targetRoleValue === 'user';
}

export async function resolveTargetEmail(client: SupabaseClient<any>, accountId: string): Promise<string> {
  const { data, error } = await client.auth.admin.getUserById(accountId);
  const email = data?.user?.email?.trim();
  if (error || !email) throw createError({ statusCode: 404, statusMessage: 'Registered account not found.' });
  return email;
}

export async function recordPasswordReset(client: SupabaseClient<any>, callerId: string, accountId: string) {
  const { error } = await client.schema('festival').rpc('record_password_reset_request', { p_requesting_admin_id: callerId, p_target_user_id: accountId });
  if (error) throw createError({ statusCode: 502, statusMessage: 'Password reset was sent, but the audit record could not be saved.' });
}
