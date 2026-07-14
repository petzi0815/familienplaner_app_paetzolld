import { NextResponse } from 'next/server';
import { guard, notMigrated } from '@/server/legacy/compat';
import { calibreEnabled, shelves } from '@/server/ebooks/calibre';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

// Calibre-Web Regale (id + Name).
export async function GET(request: Request) {
  const g = guard(request); if (g) return g;
  if (!calibreEnabled()) return notMigrated('Calibre-Web (CWA_USERNAME/CWA_PASSWORD nicht gesetzt)');
  try {
    return NextResponse.json({ shelves: await shelves() });
  } catch (error) {
    return NextResponse.json({ error: `Calibre nicht erreichbar: ${error instanceof Error ? error.message : 'Fehler'}` }, { status: 502 });
  }
}
