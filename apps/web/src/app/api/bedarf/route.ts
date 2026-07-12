import { NextRequest, NextResponse } from 'next/server';
import { getAllBedarf, createBedarfsItem } from '@/server/legacy/samu-db';
import { guard } from '@/server/legacy/compat';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(request: NextRequest) {
  const g = guard(request); if (g) return g;
  const searchParams = request.nextUrl.searchParams;
  const filters: { erledigt?: number } = {};
  if (searchParams.get('erledigt') !== null) {
    filters.erledigt = parseInt(searchParams.get('erledigt')!);
  }
  const items = getAllBedarf(filters);
  return NextResponse.json(items);
}

export async function POST(request: NextRequest) {
  const g = guard(request, 'agent'); if (g) return g;
  try {
    const data = await request.json();
    if (!data.beschreibung) {
      return NextResponse.json({ error: 'Beschreibung erforderlich' }, { status: 400 });
    }
    const id = createBedarfsItem(data);
    return NextResponse.json({ id, success: true }, { status: 201 });
  } catch (err) {
    console.error('Fehler beim Erstellen:', err);
    return NextResponse.json({ error: 'Fehler beim Erstellen' }, { status: 500 });
  }
}
