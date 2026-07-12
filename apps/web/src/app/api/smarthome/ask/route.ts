import { NextRequest } from 'next/server';
import { notMigrated } from '@/server/legacy/compat';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

// Original: Wissensfragen via Perplexity-LLM (externer API-Call mit eingebettetem Key).
// Externe KI → in dieser Version (noch) nicht migriert. Signaturen bleiben, Body → 501.
export async function POST(request: NextRequest) {
  void request;
  return notMigrated('KI-Wissensfragen');
}

// Also support GET with query parameter for simple curl usage
export async function GET(request: NextRequest) {
  void request;
  return notMigrated('KI-Wissensfragen');
}
