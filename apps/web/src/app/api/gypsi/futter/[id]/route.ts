import { NextResponse } from 'next/server';
import { getFutter, updateFutterStatus, deleteFutter } from '@/server/legacy/gypsi-db';
import { guard } from '@/server/legacy/compat';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const g = guard(request); if (g) return g;
  try {
    const { id } = await params;
    const futter = getFutter(parseInt(id));
    if (!futter) {
      return NextResponse.json({ error: 'Futter nicht gefunden' }, { status: 404 });
    }
    return NextResponse.json(futter);
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}

export async function PATCH(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const g = guard(request, 'agent'); if (g) return g;
  try {
    const { id } = await params;
    const data = await request.json();

    if (!data.status || !['mag_er', 'mag_er_nicht_mehr'].includes(data.status)) {
      return NextResponse.json({ error: 'Ungültiger Status. Erlaubt: mag_er, mag_er_nicht_mehr' }, { status: 400 });
    }

    const success = updateFutterStatus(parseInt(id), data.status);
    if (!success) {
      return NextResponse.json({ error: 'Futter nicht gefunden' }, { status: 404 });
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
    const success = deleteFutter(parseInt(id));
    if (!success) {
      return NextResponse.json({ error: 'Futter nicht gefunden' }, { status: 404 });
    }
    return NextResponse.json({ success: true });
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}
