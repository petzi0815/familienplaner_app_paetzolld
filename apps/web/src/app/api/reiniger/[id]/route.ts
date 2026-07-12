import { NextRequest, NextResponse } from 'next/server';
import { deleteReiniger, getReiniger, updateReiniger } from '@/server/legacy/reiniger-db';
import { guard } from '@/server/legacy/compat';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const g = guard(request); if (g) return g;
  try {
    const { id } = await params;
    const item = getReiniger(Number(id));
    if (!item) {
      return NextResponse.json({ error: 'Nicht gefunden' }, { status: 404 });
    }
    return NextResponse.json(item);
  } catch (error) {
    return NextResponse.json({ error: (error as Error).message }, { status: 500 });
  }
}

export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const g = guard(request, 'agent'); if (g) return g;
  try {
    const { id } = await params;
    const success = updateReiniger(Number(id), await request.json());
    if (!success) {
      return NextResponse.json({ error: 'Nicht gefunden oder keine Änderung' }, { status: 404 });
    }
    return NextResponse.json({ message: 'Aktualisiert' });
  } catch (error) {
    return NextResponse.json({ error: (error as Error).message }, { status: 500 });
  }
}

export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const g = guard(request, 'agent'); if (g) return g;
  try {
    const { id } = await params;
    const success = deleteReiniger(Number(id));
    if (!success) {
      return NextResponse.json({ error: 'Nicht gefunden' }, { status: 404 });
    }
    return NextResponse.json({ message: 'Gelöscht' });
  } catch (error) {
    return NextResponse.json({ error: (error as Error).message }, { status: 500 });
  }
}
