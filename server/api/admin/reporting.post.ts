import { readBody } from 'h3';
import { adminReportingContext, enrichRows } from '../../utils/adminReporting';

type Body = {
  action?: string;
  festivalId?: string | null;
  tapaId?: string;
  query?: string;
  status?: string;
  page?: number;
};

export default defineEventHandler(async (event) => {
  const { caller, resolveEmail } = await adminReportingContext(event);
  const body = await readBody<Body>(event);
  const action = body?.action;
  const schema = caller.client.schema('festival');
  const rpc = (name: string, args?: Record<string, unknown>) => schema.rpc(name, args as any) as any;
  let result: { data: any; error: any };
  switch (action) {
    case 'dashboard':
      result = await rpc('admin_dashboard');
      if (result.error) throw createError({ statusCode: 502, statusMessage: 'Dashboard data is unavailable.' });
      if (result.data?.recent_activity) {
        result.data.recent_activity = await Promise.all(result.data.recent_activity.map(async (item: any) => ({
          ...item,
          user: await resolveEmail(item.user_id) || item.user,
        })));
      }
      return { data: result.data };
    case 'ratings':
      result = await rpc('user_rating_activity', { p_festival_id: body.festivalId || null });
      if (result.error) throw createError({ statusCode: 502, statusMessage: 'Report data is unavailable.' });
      return { data: await enrichRows(result.data || [], resolveEmail, 'user_id', 'user_label') };
    case 'tapa-detail':
      result = await rpc('tapa_rating_detail', { p_tapa_id: body.tapaId });
      if (result.error) throw createError({ statusCode: 502, statusMessage: 'Report data is unavailable.' });
      return { data: await enrichRows(result.data || [], resolveEmail, 'user_id', 'user_label') };
    case 'reviews':
      result = await rpc('list_review_moderation', {
        p_query: body.query || '', p_status: body.status || 'all', p_limit: 25, p_offset: Math.max(0, Number(body.page || 0)) * 25,
      });
      if (result.error) throw createError({ statusCode: 502, statusMessage: 'Review data is unavailable.' });
      return { data: await enrichRows(result.data || [], resolveEmail, 'user_id', 'user_label') };
    case 'users':
      result = await rpc('search_registered_users_with_suspension', { p_query: body.query || '', p_limit: 25, p_offset: Math.max(0, Number(body.page || 0)) * 25 });
      if (result.error) throw createError({ statusCode: 502, statusMessage: 'User data is unavailable.' });
      return { data: await enrichRows(result.data || [], resolveEmail, 'account_id', 'account') };
    case 'administrators':
      if (caller.role !== 'superuser') throw createError({ statusCode: 403, statusMessage: 'Superadmin access required.' });
      result = await rpc('list_administrators');
      if (result.error) throw createError({ statusCode: 502, statusMessage: 'Administrator data is unavailable.' });
      return { data: await enrichRows(result.data || [], resolveEmail, 'account_id', 'account') };
    default:
      throw createError({ statusCode: 400, statusMessage: 'Unsupported Admin report.' });
  }
});

