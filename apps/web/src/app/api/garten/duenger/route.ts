import { NextRequest, NextResponse } from 'next/server';
import { getAllDuenger, addDuenger, updateDuenger, deleteDuenger } from '@/server/legacy/garten-db';
import { guard } from '@/server/legacy/compat';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(req: NextRequest) {
  const g = guard(req); if (g) return g;
  try {
    const { searchParams } = new URL(req.url);
    const filters: any = {};
    if (searchParams.get('typ')) filters.typ = searchParams.get('typ');
    if (searchParams.get('vorraetig') !== null && searchParams.get('vorraetig') !== '')
      filters.vorraetig = Number(searchParams.get('vorraetig'));
    if (searchParams.get('search')) filters.search = searchParams.get('search');
    return NextResponse.json(getAllDuenger(filters));
  } catch (e: any) {
    return NextResponse.json({ error: e.message }, { status: 500 });
  }
}

export async function POST(req: NextRequest) {
  const g = guard(req, 'agent'); if (g) return g;
  try {
    const data = await req.json();
    const id = addDuenger(data);
    return NextResponse.json({ id }, { status: 201 });
  } catch (e: any) {
    return NextResponse.json({ error: e.message }, { status: 500 });
  }
}

export async function PUT(req: NextRequest) {
  const g = guard(req, 'agent'); if (g) return g;
  try {
    const { id, ...data } = await req.json();
    if (!id) return NextResponse.json({ error: 'id required' }, { status: 400 });
    updateDuenger(id, data);
    return NextResponse.json({ ok: true });
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
    deleteDuenger(id);
    return NextResponse.json({ ok: true });
  } catch (e: any) {
    return NextResponse.json({ error: e.message }, { status: 500 });
  }
}
