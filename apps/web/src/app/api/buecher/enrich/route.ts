import { notMigrated } from '@/server/legacy/compat';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

// Original: Metadaten-Anreicherung via Google-Books-API (Netzwerk) → nicht migriert.
export async function GET(request: Request) {
  void request;
  return notMigrated('Metadaten-Anreicherung');
}
