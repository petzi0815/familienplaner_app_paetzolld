import { NextResponse } from 'next/server';
import { getEreignisse } from '@/server/legacy/geschenkplaner-db';
import { guard } from '@/server/legacy/compat';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(request: Request) {
  const g = guard(request); if (g) return g;
  try {
    const { searchParams } = new URL(request.url);
    const kindId = searchParams.get('kind_id') ? parseInt(searchParams.get('kind_id')!) : undefined;
    return NextResponse.json(getEreignisse(kindId));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : String(error) }, { status: 500 });
  }
}
