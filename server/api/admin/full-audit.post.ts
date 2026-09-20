import { readBody } from 'h3';
import { canAuditTarget, privilegedSupabaseClient, requireAdminPasswordResetCaller, requireTargetAccountId, resolveTargetEmail, targetRole } from '../../utils/adminPasswordReset';
import { createAccountEmailResolver } from '../../utils/adminReporting';

export default defineEventHandler(async (event) => {
  const caller = await requireAdminPasswordResetCaller(event);
  const body = await readBody<{ accountId?: unknown }>(event);
  const accountId = requireTargetAccountId(body?.accountId);
  const privileged = privilegedSupabaseClient(event);
  const targetRoleValue = await targetRole(privileged, accountId);
  if (!canAuditTarget(caller.id, caller.role, accountId, targetRoleValue)) {
    throw createError({ statusCode: 403, statusMessage: 'You are not allowed to audit this account.' });
  }
  const { data, error } = await privileged.schema('festival').rpc('full_account_audit', { p_account_id: accountId });
  if (error || !data) throw createError({ statusCode: 502, statusMessage: 'Unable to load the account audit.' });
  const email = await resolveTargetEmail(privileged, accountId);
  const resolveEmail = createAccountEmailResolver(privileged);
  const maskedAccount = typeof data.account === 'string' ? data.account : '';
  const replaceIdentity = async (value: unknown, id: unknown) => await resolveEmail(id) || (value === maskedAccount ? email : value);
  const roleHistory = Array.isArray(data.role_history) ? await Promise.all(data.role_history.map(async (item: Record<string, unknown>) => {
    const actorEmail = await replaceIdentity(item.performed_by, item.performed_by_id);
    return { ...item, performed_by: actorEmail, ...(typeof actorEmail === 'string' && actorEmail.includes('@') ? { performed_by_email: actorEmail } : {}) };
  })) : data.role_history;
  const passwordHistory = Array.isArray(data.password_reset_history) ? await Promise.all(data.password_reset_history.map(async (item: Record<string, unknown>) => {
    const actorEmail = await replaceIdentity(item.requesting_administrator, item.requesting_admin_id);
    return { ...item, requesting_administrator: actorEmail, ...(typeof actorEmail === 'string' && actorEmail.includes('@') ? { requesting_administrator_email: actorEmail } : {}) };
  })) : data.password_reset_history;
  const moderationHistory = Array.isArray(data.review_moderation_history) ? await Promise.all(data.review_moderation_history.map(async (item: Record<string, unknown>) => {
    const actorEmail = await resolveEmail(item.moderator_id);
    return { ...item, ...(actorEmail ? { moderator_email: actorEmail } : {}) };
  })) : data.review_moderation_history;
  const audit = { ...data, account: email, email, role_history: roleHistory, password_reset_history: passwordHistory, review_moderation_history: moderationHistory };
  return { audit };
});
