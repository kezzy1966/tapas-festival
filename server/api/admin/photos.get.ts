import { privilegedSupabaseClient, requireAdminPasswordResetCaller } from '../../utils/adminPasswordReset';

type PhotoRow = { name: string; bucket_id: string; created_at: string | null; updated_at: string | null; metadata: Record<string, any> | null; id?: string | null };

function numberValue(value: unknown) { const number = Number(value); return Number.isFinite(number) ? number : 0; }
function isManagedName(name: string) { return /^(establishments|tapas)\/festival-(bar|tapa)-[0-9a-f-]{36}-[0-9a-f-]+\.(webp|jpg|jpeg|png)$/i.test(name); }

async function listAllStorageObjects(storage: any): Promise<PhotoRow[]> {
  const objects: PhotoRow[] = [];
  const visitedPrefixes = new Set<string>();
  async function walk(prefix: string): Promise<void> {
    let offset = 0;
    while (true) {
      const { data, error } = await storage.from('festival-images').list(prefix, { limit: 1000, offset, sortBy: { column: 'created_at', order: 'desc' } });
      if (error) throw createError({ statusCode: 502, statusMessage: 'Unable to load photos.' });
      const entries = Array.isArray(data) ? data : [];
      for (const entry of entries) {
        const name = prefix ? prefix + '/' + entry.name : entry.name;
        if (entry.id || entry.metadata) objects.push({ ...entry, name, bucket_id: 'festival-images' });
        else if (!visitedPrefixes.has(name)) { visitedPrefixes.add(name); await walk(name); }
      }
      if (entries.length < 1000) break;
      offset += entries.length;
    }
  }
  await walk('');
  return objects;
}

export default defineEventHandler(async (event) => {
  const caller = await requireAdminPasswordResetCaller(event);
  const privileged = privilegedSupabaseClient(event);
  const [storageResult, establishmentsResult, tapasResult] = await Promise.all([
    listAllStorageObjects(privileged.storage),
    caller.client.schema('festival').from('establishments').select('id,name,photo_path'),
    caller.client.schema('festival').from('tapas').select('id,name_en,name_es,establishment_id,photo_path'),
  ]);
  if (establishmentsResult.error || tapasResult.error) throw createError({ statusCode: 502, statusMessage: 'Unable to load photos.' });

  const establishments = establishmentsResult.data || [];
  const tapas = tapasResult.data || [];
  const byPath = new Map<string, any>();
  for (const establishment of establishments) if (establishment.photo_path) byPath.set(establishment.photo_path, { kind: 'Bar', establishment_name: establishment.name, tapa_name: null });
  for (const tapa of tapas) if (tapa.photo_path) byPath.set(tapa.photo_path, { kind: 'Tapa', establishment_name: establishments.find((row: any) => row.id === tapa.establishment_id)?.name || null, tapa_name: tapa.name_en || tapa.name_es || null });

  const publicUrl = String(useRuntimeConfig(event).public?.supabase?.url || '').replace(/\/$/, '');
  const photos = ((storageResult || []) as PhotoRow[]).map((object) => {
    const metadata = object.metadata || {};
    const match = byPath.get(object.name);
    const size = numberValue(metadata.size);
    const managed = isManagedName(object.name);
    return {
      name: object.name,
      created_at: object.created_at,
      updated_at: object.updated_at,
      size_bytes: size,
      mime_type: String(metadata.mimetype || metadata.contentType || 'application/octet-stream'),
      width: metadata.width == null ? null : numberValue(metadata.width),
      height: metadata.height == null ? null : numberValue(metadata.height),
      public_url: `${publicUrl}/storage/v1/object/public/festival-images/${object.name.split('/').map(encodeURIComponent).join('/')}`,
      kind: match?.kind || 'Unidentified',
      establishment_name: match?.establishment_name || null,
      tapa_name: match?.tapa_name || null,
      managed,
      orphaned: !match,
    };
  });
  return { photos };
});
