import { notMigrated } from '@/server/legacy/compat';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

// Original: baut den System-Prompt für den LLM-Sprachassistenten ("Ole") — Geräte-/Alias-Liste + curl-Rezept
// gegen die exec/ask-Endpunkte, die HA-Steuerung/externe KI voraussetzen. Gehört zur KI-Schicht →
// in dieser Version (noch) nicht migriert. Signatur bleibt, Body → 501.
export async function GET() {
  return notMigrated('KI-System-Prompt');
}
