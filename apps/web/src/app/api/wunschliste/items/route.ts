import { NextResponse } from 'next/server';
import { getItems, addItem } from '@/server/legacy/wunschliste-db';
import { guard } from '@/server/legacy/compat';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(request: Request) {
  const g = guard(request); if (g) return g;
  try {
    const { searchParams } = new URL(request.url);
    const eventId = searchParams.get('event_id') ? parseInt(searchParams.get('event_id')!) : undefined;
    const status = searchParams.get('status') || undefined;
    return NextResponse.json(getItems(eventId, status));
  } catch (error) {
    return NextResponse.json({ error: (error as Error).message }, { status: 500 });
  }
}

export async function POST(request: Request) {
  const g = guard(request, 'agent'); if (g) return g;
  try {
    const data = await request.json();
    if (!data.title || !data.event_id) {
      return NextResponse.json({ error: 'title und event_id sind Pflichtfelder' }, { status: 400 });
    }
    const id = addItem(data);
    return NextResponse.json({ id, success: true });
  } catch (error) {
    return NextResponse.json({ error: (error as Error).message }, { status: 500 });
  }
}
