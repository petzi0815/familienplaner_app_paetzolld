import { NextRequest, NextResponse } from 'next/server';
import { linkPflanzeDuenger, unlinkPflanzeDuenger } from '@/server/legacy/garten-db';
import { guard } from '@/server/legacy/compat';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function POST(req: NextRequest) {
  const g = guard(req, 'agent'); if (g) return g;
  try {
    const { pflanze_id, duenger_id, empfohlen, notizen } = await req.json();
    if (!pflanze_id || !duenger_id) return NextResponse.json({ error: 'pflanze_id and duenger_id required' }, { status: 400 });
    const id = linkPflanzeDuenger(pflanze_id, duenger_id, empfohlen ?? 1, notizen);
    return NextResponse.json({ id }, { status: 201 });
  } catch (e: any) {
    return NextResponse.json({ error: e.message }, { status: 500 });
  }
}

export async function DELETE(req: NextRequest) {
  const g = guard(req, 'agent'); if (g) return g;
  try {
    const { searchParams } = new URL(req.url);
    const id = Number(searchParams.get('id'));
    if (!id) return NextResponse.json({ error: 'id required' }, { status: 400 });
    unlinkPflanzeDuenger(id);
    return NextResponse.json({ ok: true });
  } catch (e: any) {
    return NextResponse.json({ error: e.message }, { status: 500 });
  }
}
