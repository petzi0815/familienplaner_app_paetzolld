import { NextResponse } from 'next/server';
import { bestaetigeProfil, getKind } from '@/server/legacy/geschenkplaner-db';
import { guard } from '@/server/legacy/compat';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function POST(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const g = guard(request, 'agent'); if (g) return g;
  try {
    const { id } = await params;
    const kind = getKind(parseInt(id));
    if (!kind) return NextResponse.json({ error: 'Kind nicht gefunden' }, { status: 404 });
    bestaetigeProfil(parseInt(id));
    return NextResponse.json({ success: true });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : String(error) }, { status: 500 });
  }
}
