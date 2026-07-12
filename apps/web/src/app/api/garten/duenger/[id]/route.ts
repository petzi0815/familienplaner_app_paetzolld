import { NextRequest, NextResponse } from 'next/server';
import { getDuenger, getPflanzenFuerDuenger } from '@/server/legacy/garten-db';
import { guard } from '@/server/legacy/compat';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const g = guard(req); if (g) return g;
  try {
    const { id } = await params;
    const duenger = getDuenger(Number(id));
    if (!duenger) return NextResponse.json({ error: 'Not found' }, { status: 404 });
    const pflanzen = getPflanzenFuerDuenger(Number(id));
    return NextResponse.json({ ...duenger, pflanzen });
  } catch (e: any) {
    return NextResponse.json({ error: e.message }, { status: 500 });
  }
}
