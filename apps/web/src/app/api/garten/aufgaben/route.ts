import { NextResponse } from 'next/server';
import { getAufgaben, addAufgabe } from '@/server/legacy/garten-db';
import { guard } from '@/server/legacy/compat';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(request: Request) {
  const g = guard(request); if (g) return g;
  try {
    const { searchParams } = new URL(request.url);

    const bereichParam = searchParams.get('bereich');
    const bereich: 'alle' | 'rasen' | 'baeume' | 'anzucht' =
      bereichParam === 'rasen' || bereichParam === 'baeume' || bereichParam === 'anzucht' ? bereichParam : 'alle';

    const filters = {
      monat: searchParams.get('monat') ? parseInt(searchParams.get('monat')!) : undefined,
      jahr: searchParams.get('jahr') ? parseInt(searchParams.get('jahr')!) : undefined,
      erledigt: searchParams.get('erledigt') !== null ? parseInt(searchParams.get('erledigt')!) : undefined,
      pflanze_id: searchParams.get('pflanze_id') ? parseInt(searchParams.get('pflanze_id')!) : undefined,
      bereich: bereich,
    };

    const aufgaben = getAufgaben(filters);
    return NextResponse.json(aufgaben);
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}

export async function POST(request: Request) {
  const g = guard(request, 'agent'); if (g) return g;
  try {
    const data = await request.json();
    const id = addAufgabe(data);
    return NextResponse.json({ id, success: true });
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}
