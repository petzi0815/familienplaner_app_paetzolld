import { NextRequest, NextResponse } from 'next/server';
import { addAnwendung, addReiniger, getAllReiniger, getAnwendungen, getStats } from '@/server/legacy/reiniger-db';
import { guard } from '@/server/legacy/compat';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(request: NextRequest) {
  const g = guard(request); if (g) return g;
  try {
    const { searchParams } = new URL(request.url);

    if (searchParams.get('stats') === 'true') {
      return NextResponse.json(getStats());
    }

    if (searchParams.get('anwendungen') === 'true') {
      return NextResponse.json(getAnwendungen({
        search: searchParams.get('search') || undefined,
        reiniger_id: searchParams.get('reiniger_id') ? Number(searchParams.get('reiniger_id')) : undefined,
      }));
    }

    return NextResponse.json(getAllReiniger({
      status: searchParams.get('status') || undefined,
      kategorie: searchParams.get('kategorie') || undefined,
      search: searchParams.get('search') || undefined,
    }));
  } catch (error) {
    return NextResponse.json({ error: (error as Error).message }, { status: 500 });
  }
}

export async function POST(request: NextRequest) {
  const g = guard(request, 'agent'); if (g) return g;
  try {
    const data = await request.json();

    if (data.type === 'anwendung') {
      if (!data.reiniger_id || !data.problem || !data.anleitung) {
        return NextResponse.json({ error: 'reiniger_id, problem und anleitung sind Pflichtfelder' }, { status: 400 });
      }
      const id = addAnwendung(data);
      return NextResponse.json({ id, message: 'Anwendung hinzugefügt' }, { status: 201 });
    }

    if (!data.name) {
      return NextResponse.json({ error: 'Name ist ein Pflichtfeld' }, { status: 400 });
    }

    const id = addReiniger(data);
    return NextResponse.json({ id, message: 'Reiniger hinzugefügt' }, { status: 201 });
  } catch (error) {
    return NextResponse.json({ error: (error as Error).message }, { status: 500 });
  }
}
