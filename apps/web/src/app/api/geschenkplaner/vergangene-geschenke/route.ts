import { NextResponse } from 'next/server';
import { getVergangeneGeschenke, addVergangeneGeschenk } from '@/server/legacy/geschenkplaner-db';
import { guard } from '@/server/legacy/compat';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(request: Request) {
  const g = guard(request); if (g) return g;
  try {
    const { searchParams } = new URL(request.url);
    const kindId = searchParams.get('kind_id') ? parseInt(searchParams.get('kind_id')!) : undefined;
    return NextResponse.json(getVergangeneGeschenke(kindId));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : String(error) }, { status: 500 });
  }
}

export async function POST(request: Request) {
  const g = guard(request, 'agent'); if (g) return g;
  try {
    const data = await request.json();
    if (!data.kind_id || !data.titel) {
      return NextResponse.json({ error: 'kind_id und titel erforderlich' }, { status: 400 });
    }
    const id = addVergangeneGeschenk(data);
    return NextResponse.json({ id, success: true }, { status: 201 });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : String(error) }, { status: 500 });
  }
}
