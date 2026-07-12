import { NextResponse } from 'next/server';
import { schonGeschenkt } from '@/server/legacy/geschenkplaner-db';
import { guard } from '@/server/legacy/compat';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function POST(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const g = guard(request, 'agent'); if (g) return g;
  try {
    const { id } = await params;
    const success = schonGeschenkt(parseInt(id));
    if (!success) return NextResponse.json({ error: 'Geschenk nicht gefunden' }, { status: 404 });
    return NextResponse.json({ success: true });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : String(error) }, { status: 500 });
  }
}
