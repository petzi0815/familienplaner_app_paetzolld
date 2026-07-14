import { NextResponse } from 'next/server';
import { guard, notMigrated } from '@/server/legacy/compat';
import { calibreEnabled, shelfAction } from '@/server/ebooks/calibre';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

// Buch auf ein Regal legen/entfernen. Body: { book_id, shelf_id, action?: 'add'|'remove' } (Default add).
export async function POST(request: Request) {
  const g = guard(request, 'agent'); if (g) return g;
  if (!calibreEnabled()) return notMigrated('Calibre-Web');
  try {
    const body = await request.json();
    const bookId = parseInt(String(body?.book_id));
    const shelfId = parseInt(String(body?.shelf_id));
    const action = body?.action === 'remove' ? 'remove' : 'add';
    if (!Number.isFinite(bookId) || !Number.isFinite(shelfId)) {
      return NextResponse.json({ error: 'book_id und shelf_id erforderlich' }, { status: 400 });
    }
    const ok = await shelfAction(action, shelfId, bookId);
    if (!ok) return NextResponse.json({ error: 'Regal-Aktion fehlgeschlagen' }, { status: 502 });
    return NextResponse.json({ success: true, action, book_id: bookId, shelf_id: shelfId });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Fehler' }, { status: 500 });
  }
}
