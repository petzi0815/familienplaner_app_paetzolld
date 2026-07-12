import { NextRequest, NextResponse } from 'next/server';
import {
  getAllLebensmittel,
  addLebensmittel,
  getEinkaufsliste,
  getAblaufend,
  getStats,
} from '@/server/legacy/vorratskammer-db';
import { guard } from '@/server/legacy/compat';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(request: NextRequest) {
  const g = guard(request); if (g) return g;
  try {
    const { searchParams } = new URL(request.url);

    // Special: stats
    if (searchParams.get('stats') === 'true') {
      return NextResponse.json(getStats());
    }

    // Special: einkaufsliste
    if (searchParams.get('einkaufsliste') === 'true') {
      return NextResponse.json(getEinkaufsliste());
    }

    // Special: ablaufend
    if (searchParams.get('ablaufend') === 'true') {
      const tage = parseInt(searchParams.get('tage') || '14', 10);
      return NextResponse.json(getAblaufend(tage));
    }

    // Normal list with filters
    const filters: { kategorie?: string; status?: string; search?: string } = {};
    if (searchParams.get('kategorie')) filters.kategorie = searchParams.get('kategorie')!;
    if (searchParams.get('status')) filters.status = searchParams.get('status')!;
    if (searchParams.get('search')) filters.search = searchParams.get('search')!;

    return NextResponse.json(getAllLebensmittel(filters));
  } catch (error) {
    return NextResponse.json({ error: (error as Error).message }, { status: 500 });
  }
}

export async function POST(request: NextRequest) {
  const g = guard(request, 'agent'); if (g) return g;
  try {
    const data = await request.json();

    if (!data.name || !data.kategorie) {
      return NextResponse.json(
        { error: 'Name und Kategorie sind Pflichtfelder' },
        { status: 400 }
      );
    }

    if (!['trocken', 'kuehlschrank', 'gefrierfach'].includes(data.kategorie)) {
      return NextResponse.json(
        { error: 'Kategorie muss trocken, kuehlschrank oder gefrierfach sein' },
        { status: 400 }
      );
    }

    const id = addLebensmittel(data);
    return NextResponse.json({ id, message: 'Lebensmittel hinzugefügt' }, { status: 201 });
  } catch (error) {
    return NextResponse.json({ error: (error as Error).message }, { status: 500 });
  }
}
