import { NextResponse } from 'next/server';
import { getAllEvents, addEvent } from '@/server/legacy/wunschliste-db';
import { guard } from '@/server/legacy/compat';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(request: Request) {
  const g = guard(request); if (g) return g;
  try {
    const { searchParams } = new URL(request.url);
    const includeArchived = searchParams.get('archived') === 'true';
    return NextResponse.json(getAllEvents(includeArchived));
  } catch (error) {
    return NextResponse.json({ error: (error as Error).message }, { status: 500 });
  }
}

export async function POST(request: Request) {
  const g = guard(request, 'agent'); if (g) return g;
  try {
    const data = await request.json();
    if (!data.name) {
      return NextResponse.json({ error: 'Name ist Pflichtfeld' }, { status: 400 });
    }
    const id = addEvent(data);
    return NextResponse.json({ id, success: true });
  } catch (error) {
    return NextResponse.json({ error: (error as Error).message }, { status: 500 });
  }
}
