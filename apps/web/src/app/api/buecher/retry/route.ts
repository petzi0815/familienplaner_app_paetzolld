import { notMigrated } from '@/server/legacy/compat';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

// Original: sucht/startet einen erneuten Download via externer Shelfmark-API (Netzwerk) → nicht migriert.
export async function POST(request: Request) {
  void request;
  return notMigrated('Download-Wiederholung');
}
