import { getRequestURL, readBody } from 'h3';
import { canResetTarget, privilegedSupabaseClient, recordPasswordReset, requireAdminPasswordResetCaller, requireTargetAccountId, resolveTargetEmail, targetRole } from '../../utils/adminPasswordReset';

export default defineEventHandler(async (event) => {
  const caller = await requireAdminPasswordResetCaller(event);
  const body = await readBody<{ accountId?: unknown }>(event);
  const accountId = requireTargetAccountId(body?.accountId);
  const privileged = privilegedSupabaseClient(event);
  if (!canResetTarget(caller.role, await targetRole(privileged, accountId))) throw createError({ statusCode: 403, statusMessage: 'You are not allowed to send a reset for this account.' });
  const email = await resolveTargetEmail(privileged, accountId);
  const redirectTo = new URL('/reset-password?recovery=1', getRequestURL(event).origin).toString();
  const { error } = await privileged.auth.resetPasswordForEmail(email, { redirectTo });
  if (error) throw createError({ statusCode: 502, statusMessage: 'Unable to send the password reset email.' });
  await recordPasswordReset(privileged, caller.id, accountId);
  return { sent: true };
});
