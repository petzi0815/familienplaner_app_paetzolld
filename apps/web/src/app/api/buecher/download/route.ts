import { notMigrated } from '@/server/legacy/compat';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

// Original: startet/queued einen externen E-Book-Download via Shelfmark-API (Netzwerk) → nicht migriert.
export async function POST(request: Request) {
  void request;
  return notMigrated('E-Book-Download');
}

// GET: Download-Status-Abfrage an die externe Shelfmark-API → nicht migriert.
export async function GET() {
  return notMigrated('E-Book-Download');
}
