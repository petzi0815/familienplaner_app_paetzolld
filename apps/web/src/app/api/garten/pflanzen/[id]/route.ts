import { NextResponse } from 'next/server';
import { getPflanze, updatePflanze, deletePflanze } from '@/server/legacy/garten-db';
import { guard } from '@/server/legacy/compat';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const g = guard(request); if (g) return g;
  try {
    const { id } = await params;
    const pflanze = getPflanze(parseInt(id));
    if (!pflanze) {
      return NextResponse.json({ error: 'Pflanze nicht gefunden' }, { status: 404 });
    }
    return NextResponse.json(pflanze);
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}

export async function PUT(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const g = guard(request, 'agent'); if (g) return g;
  try {
    const { id } = await params;
    const data = await request.json();
    const success = updatePflanze(parseInt(id), data);
    if (!success) {
      return NextResponse.json({ error: 'Update fehlgeschlagen' }, { status: 404 });
    }
    return NextResponse.json({ success: true });
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}

export async function DELETE(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const g = guard(request, 'agent'); if (g) return g;
  try {
    const { id } = await params;
    const success = deletePflanze(parseInt(id));
    if (!success) {
      return NextResponse.json({ error: 'Löschen fehlgeschlagen' }, { status: 404 });
    }
    return NextResponse.json({ success: true });
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}
