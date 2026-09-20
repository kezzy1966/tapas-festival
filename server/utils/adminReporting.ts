import type { SupabaseClient } from '@supabase/supabase-js';
import { privilegedSupabaseClient, requireAdminPasswordResetCaller } from './adminPasswordReset';
import type { H3Event } from 'h3';

type Resolver = (accountId: unknown) => Promise<string | null>;

export function createAccountEmailResolver(client: SupabaseClient<any>): Resolver {
  const cache = new Map<string, string | null>();
  return async (accountId: unknown) => {
    if (typeof accountId !== 'string' || !accountId) return null;
    if (cache.has(accountId)) return cache.get(accountId) || null;
    const { data } = await client.auth.admin.getUserById(accountId);
    const email = data?.user?.email?.trim() || null;
    cache.set(accountId, email);
    return email;
  };
}

export async function adminReportingContext(event: H3Event) {
  const caller = await requireAdminPasswordResetCaller(event);
  const privileged = privilegedSupabaseClient(event);
  return { caller, privileged, resolveEmail: createAccountEmailResolver(privileged) };
}

export async function enrichRows<T extends Record<string, any>>(rows: T[], resolveEmail: Resolver, idField: string, labelField: string) {
  return Promise.all(rows.map(async (row) => {
    const email = await resolveEmail(row[idField]);
    return email ? { ...row, [labelField]: email } : row;
  }));
}

