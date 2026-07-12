import { NextRequest } from 'next/server';
import { notMigrated } from '@/server/legacy/compat';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

// Original: steuert Home Assistant (HA-REST-API, Fuzzy-Matching, Command-Logging, Szenen, room-off …).
// Braucht Hardware/Netzwerk (HA-Secrets) → in dieser Version (noch) nicht migriert. Signatur bleibt, Body → 501.
export async function GET(request: NextRequest) {
  void request;
  return notMigrated('Smart-Home-Gerätesteuerung');
}
