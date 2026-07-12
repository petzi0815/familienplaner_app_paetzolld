import { NextResponse } from 'next/server';
import { getGeschenke, addGeschenk } from '@/server/legacy/geschenkplaner-db';
import { guard } from '@/server/legacy/compat';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(request: Request) {
  const g = guard(request); if (g) return g;
  try {
    const { searchParams } = new URL(request.url);
    const ereignisId = searchParams.get('ereignis_id') ? parseInt(searchParams.get('ereignis_id')!) : undefined;
    const kindId = searchParams.get('kind_id') ? parseInt(searchParams.get('kind_id')!) : undefined;
    const status = searchParams.getAll('status');
    return NextResponse.json(getGeschenke(ereignisId, kindId, status.length > 0 ? status : undefined));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : String(error) }, { status: 500 });
  }
}

export async function POST(request: Request) {
  const g = guard(request, 'agent'); if (g) return g;
  try {
    const data = await request.json();
    if (!data.titel) {
      return NextResponse.json({ error: 'Titel ist erforderlich' }, { status: 400 });
    }
    if (!data.kind_id && !data.ereignis_id) {
      return NextResponse.json({ error: 'kind_id oder ereignis_id erforderlich' }, { status: 400 });
    }
    const id = addGeschenk(data);
    return NextResponse.json({ id, success: true }, { status: 201 });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : String(error) }, { status: 500 });
  }
}
