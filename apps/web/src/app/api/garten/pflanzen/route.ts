import { NextResponse } from 'next/server';
import { getAllPflanzen, addPflanze, getArten } from '@/server/legacy/garten-db';
import { guard } from '@/server/legacy/compat';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(request: Request) {
  const g = guard(request); if (g) return g;
  try {
    const { searchParams } = new URL(request.url);

    // Special case: return available arten
    if (searchParams.get('arten') === 'true') {
      const arten = getArten();
      return NextResponse.json(arten);
    }

    const filters = {
      status: searchParams.get('status') || undefined,
      art: searchParams.get('art') || undefined,
      bewaesserung: searchParams.get('bewaesserung') || undefined,
      search: searchParams.get('search') || undefined,
    };

    const pflanzen = getAllPflanzen(filters);
    return NextResponse.json(pflanzen);
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}

export async function POST(request: Request) {
  const g = guard(request, 'agent'); if (g) return g;
  try {
    const data = await request.json();
    const id = addPflanze(data);
    return NextResponse.json({ id, success: true });
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}
