import { NextRequest, NextResponse } from 'next/server';
import { getAllRezepte, addRezept, deleteRezept } from '@/server/legacy/vorratskammer-db';
import { guard } from '@/server/legacy/compat';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(request: NextRequest) {
  const g = guard(request); if (g) return g;
  try {
    const { searchParams } = new URL(request.url);
    const limit = parseInt(searchParams.get('limit') || '50', 10);
    return NextResponse.json(getAllRezepte(limit));
  } catch (error) {
    return NextResponse.json({ error: (error as Error).message }, { status: 500 });
  }
}

export async function POST(request: NextRequest) {
  const g = guard(request, 'agent'); if (g) return g;
  try {
    const data = await request.json();
    if (!data.titel) {
      return NextResponse.json({ error: 'Titel ist Pflichtfeld' }, { status: 400 });
    }
    const id = addRezept(data);
    return NextResponse.json({ id, message: 'Rezept hinzugefügt' }, { status: 201 });
  } catch (error) {
    return NextResponse.json({ error: (error as Error).message }, { status: 500 });
  }
}

export async function DELETE(request: NextRequest) {
  const g = guard(request, 'agent'); if (g) return g;
  try {
    const { searchParams } = new URL(request.url);
    const id = parseInt(searchParams.get('id') || '0', 10);
    if (!id) return NextResponse.json({ error: 'ID fehlt' }, { status: 400 });
    const ok = deleteRezept(id);
    return ok
      ? NextResponse.json({ message: 'Rezept gelöscht' })
      : NextResponse.json({ error: 'Nicht gefunden' }, { status: 404 });
  } catch (error) {
    return NextResponse.json({ error: (error as Error).message }, { status: 500 });
  }
}
