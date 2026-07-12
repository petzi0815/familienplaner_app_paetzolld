import { notMigrated } from '@/server/legacy/compat';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

// Original: externe Shelfmark-API-Suche (Netzwerk zu bookdl.yagemi.synology.me) → nicht migriert.
export async function GET(request: Request) {
  void request;
  return notMigrated('Buchsuche');
}
