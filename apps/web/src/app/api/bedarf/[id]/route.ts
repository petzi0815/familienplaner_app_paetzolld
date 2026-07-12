import { NextRequest, NextResponse } from 'next/server';
import { getBedarfsItem, updateBedarfsItem, deleteBedarfsItem } from '@/server/legacy/samu-db';
import { guard } from '@/server/legacy/compat';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const g = guard(request); if (g) return g;
  const { id } = await params;
  const item = getBedarfsItem(parseInt(id));
  if (!item) return NextResponse.json({ error: 'Nicht gefunden' }, { status: 404 });
  return NextResponse.json(item);
}

export async function PATCH(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const g = guard(request, 'agent'); if (g) return g;
  try {
    const { id } = await params;
    const data = await request.json();
    if (data.erledigt === 1 && !data.erledigt_am) {
      data.erledigt_am = new Date().toISOString();
    }
    if (data.erledigt === 0) {
      data.erledigt_am = null;
    }
    const success = updateBedarfsItem(parseInt(id), data);
    if (!success) return NextResponse.json({ error: 'Update fehlgeschlagen' }, { status: 400 });
    return NextResponse.json({ success: true });
  } catch (err) {
    console.error('Fehler beim Update:', err);
    return NextResponse.json({ error: 'Fehler beim Update' }, { status: 500 });
  }
}

export async function DELETE(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const g = guard(request, 'agent'); if (g) return g;
  try {
    const { id } = await params;
    const success = deleteBedarfsItem(parseInt(id));
    if (!success) return NextResponse.json({ error: 'Löschen fehlgeschlagen' }, { status: 400 });
    return NextResponse.json({ success: true });
  } catch (err) {
    console.error('Fehler beim Löschen:', err);
    return NextResponse.json({ error: 'Fehler beim Löschen' }, { status: 500 });
  }
}
