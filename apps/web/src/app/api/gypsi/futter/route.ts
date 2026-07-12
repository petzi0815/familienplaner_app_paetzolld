import { NextResponse } from 'next/server';
import { getAllFutter, addFutter, getMarken, getGeschmacksrichtungen } from '@/server/legacy/gypsi-db';
import { guard } from '@/server/legacy/compat';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(request: Request) {
  const g = guard(request); if (g) return g;
  try {
    const { searchParams } = new URL(request.url);

    // Special: return filter options
    if (searchParams.get('marken') === 'true') {
      return NextResponse.json(getMarken());
    }
    if (searchParams.get('geschmacksrichtungen') === 'true') {
      return NextResponse.json(getGeschmacksrichtungen());
    }

    const filters = {
      marke: searchParams.get('marke') || undefined,
      geschmack: searchParams.get('geschmack') || undefined,
      status: searchParams.get('status') || undefined,
    };

    const futter = getAllFutter(filters);
    return NextResponse.json(futter);
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}

export async function POST(request: Request) {
  const g = guard(request, 'agent'); if (g) return g;
  try {
    const data = await request.json();

    if (!data.marke || !data.sorte) {
      return NextResponse.json({ error: 'marke und sorte sind Pflichtfelder' }, { status: 400 });
    }

    const id = addFutter(data);
    return NextResponse.json({ id, success: true });
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}
