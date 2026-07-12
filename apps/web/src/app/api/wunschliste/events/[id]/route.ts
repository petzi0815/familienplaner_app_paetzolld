import { NextResponse } from 'next/server';
import { getEvent, updateEvent, deleteEvent } from '@/server/legacy/wunschliste-db';
import { guard } from '@/server/legacy/compat';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const g = guard(request); if (g) return g;
  try {
    const { id } = await params;
    const event = getEvent(parseInt(id));
    if (!event) return NextResponse.json({ error: 'Event nicht gefunden' }, { status: 404 });
    return NextResponse.json(event);
  } catch (error) {
    return NextResponse.json({ error: (error as Error).message }, { status: 500 });
  }
}

export async function PATCH(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const g = guard(request, 'agent'); if (g) return g;
  try {
    const { id } = await params;
    const data = await request.json();
    const success = updateEvent(parseInt(id), data);
    if (!success) return NextResponse.json({ error: 'Nicht gefunden' }, { status: 404 });
    return NextResponse.json({ success: true });
  } catch (error) {
    return NextResponse.json({ error: (error as Error).message }, { status: 500 });
  }
}

export async function DELETE(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const g = guard(request, 'agent'); if (g) return g;
  try {
    const { id } = await params;
    const success = deleteEvent(parseInt(id));
    if (!success) return NextResponse.json({ error: 'Nicht gefunden' }, { status: 404 });
    return NextResponse.json({ success: true });
  } catch (error) {
    return NextResponse.json({ error: (error as Error).message }, { status: 500 });
  }
}
