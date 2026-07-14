import { NextResponse } from 'next/server';
import { guard } from '@/server/legacy/compat';
import { searchReleases } from '@/server/ebooks/shelfmark';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

// Externe E-Book-Suche über die familieneigene Shelfmark-Instanz (Anna's Archive).
export async function GET(request: Request) {
  const g = guard(request); if (g) return g;
  const { searchParams } = new URL(request.url);
  const query = (searchParams.get('q') ?? '').trim();
  if (query.length < 2) {
    return NextResponse.json({ error: 'Suchbegriff zu kurz (min. 2 Zeichen)' }, { status: 400 });
  }
  try {
    return NextResponse.json(await searchReleases(query));
  } catch (error) {
    return NextResponse.json(
      { error: `Shelfmark nicht erreichbar: ${error instanceof Error ? error.message : 'Fehler'}` },
      { status: 502 },
    );
  }
}
