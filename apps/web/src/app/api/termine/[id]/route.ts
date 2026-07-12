import { NextResponse } from 'next/server';
import { getTermin, updateTermin, deleteTermin } from '@/server/legacy/termine-db';
import { guard } from '@/server/legacy/compat';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const g = guard(request); if (g) return g;
  try {
    const { id } = await params;
    const termin = getTermin(parseInt(id));
    if (!termin) return NextResponse.json({ error: 'Termin nicht gefunden' }, { status: 404 });
    return NextResponse.json(termin);
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Fehler' }, { status: 500 });
  }
}

export async function PATCH(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const g = guard(request, 'agent'); if (g) return g;
  try {
    const { id } = await params;
    const data = await request.json();
    const success = updateTermin(parseInt(id), data);
    if (!success) return NextResponse.json({ error: 'Nicht gefunden' }, { status: 404 });
    return NextResponse.json({ success: true });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Fehler' }, { status: 500 });
  }
}

export async function DELETE(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const g = guard(request, 'agent'); if (g) return g;
  try {
    const { id } = await params;
    const success = deleteTermin(parseInt(id));
    if (!success) return NextResponse.json({ error: 'Nicht gefunden' }, { status: 404 });
    return NextResponse.json({ success: true });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Fehler' }, { status: 500 });
  }
}
