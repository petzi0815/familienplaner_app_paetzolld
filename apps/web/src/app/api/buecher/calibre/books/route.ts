import { NextResponse } from 'next/server';
import { guard, notMigrated } from '@/server/legacy/compat';
import { calibreEnabled, listBooks, shelfBooks } from '@/server/ebooks/calibre';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

// Calibre-Web Bücher: ?search= (Volltext), ?offset=&limit= (Paging) ODER ?shelf=<id> (Regal-Inhalt).
export async function GET(request: Request) {
  const g = guard(request); if (g) return g;
  if (!calibreEnabled()) return notMigrated('Calibre-Web (CWA_USERNAME/CWA_PASSWORD nicht gesetzt)');
  const { searchParams } = new URL(request.url);
  try {
    const shelf = searchParams.get('shelf');
    if (shelf) {
      const rows = await shelfBooks(parseInt(shelf));
      return NextResponse.json({ total: rows.length, rows, shelf: parseInt(shelf) });
    }
    const res = await listBooks({
      offset: parseInt(searchParams.get('offset') || '0'),
      limit: Math.min(parseInt(searchParams.get('limit') || '30'), 100),
      search: searchParams.get('search') || undefined,
      sort: searchParams.get('sort') || undefined,
      order: searchParams.get('order') || undefined,
    });
    return NextResponse.json(res);
  } catch (error) {
    return NextResponse.json({ error: `Calibre nicht erreichbar: ${error instanceof Error ? error.message : 'Fehler'}` }, { status: 502 });
  }
}
