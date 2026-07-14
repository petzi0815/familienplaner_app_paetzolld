import { NextResponse } from 'next/server';
import { guard, notMigrated } from '@/server/legacy/compat';
import { calibreEnabled, bookDetail } from '@/server/ebooks/calibre';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

// Buch-Detail: zugeordnete Regal-IDs + Voll-Metadaten (Titel-Hint via ?title= für die Metadaten-Suche).
export async function GET(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const g = guard(request); if (g) return g;
  if (!calibreEnabled()) return notMigrated('Calibre-Web');
  const { id } = await params;
  const title = new URL(request.url).searchParams.get('title') || undefined;
  try {
    const d = await bookDetail(parseInt(id), title);
    return NextResponse.json({ shelf_ids: d.shelfIds, book: d.book, formats: d.formats });
  } catch (error) {
    return NextResponse.json({ error: `Calibre nicht erreichbar: ${error instanceof Error ? error.message : 'Fehler'}` }, { status: 502 });
  }
}
