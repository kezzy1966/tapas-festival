import { readBody } from 'h3';
import { canResetTarget, privilegedSupabaseClient, requireAdminPasswordResetCaller, requireTargetAccountId, targetRole } from '../../utils/adminPasswordReset';

export default defineEventHandler(async (event) => {
  const caller = await requireAdminPasswordResetCaller(event);
  const body = await readBody<{ accountIds?: unknown }>(event);
  const accountIds = Array.isArray(body?.accountIds) ? body.accountIds.slice(0, 100).map(requireTargetAccountId) : [];
  if (!accountIds.length) return { eligibleAccountIds: [] };
  const privileged = privilegedSupabaseClient(event);
  const eligibleAccountIds: string[] = [];
  for (const accountId of accountIds) {
    if (canResetTarget(caller.role, await targetRole(privileged, accountId))) eligibleAccountIds.push(accountId);
  }
  return { eligibleAccountIds };
});
