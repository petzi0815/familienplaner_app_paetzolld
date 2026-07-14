import { NextResponse } from 'next/server';
import { guard } from '@/server/legacy/compat';
import { getBook } from '@/server/legacy/buecher-db';
import { checkAndDownload } from '@/server/ebooks/wishlist';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

// Ein Wunschlisten-Buch via Shelfmark prüfen + herunterladen. Body: { id }.
export async function POST(request: Request) {
  const g = guard(request, 'agent'); if (g) return g;
  try {
    const body = await request.json();
    const id = parseInt(String(body?.id));
    if (!Number.isFinite(id)) return NextResponse.json({ error: 'id erforderlich' }, { status: 400 });
    const book = getBook(id);
    if (!book) return NextResponse.json({ error: 'Buch nicht gefunden' }, { status: 404 });
    return NextResponse.json(await checkAndDownload(book));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Fehler' }, { status: 500 });
  }
}
