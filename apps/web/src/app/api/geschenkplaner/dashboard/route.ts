import { NextResponse } from 'next/server';
import { getDashboard } from '@/server/legacy/geschenkplaner-db';
import { guard } from '@/server/legacy/compat';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(request: Request) {
  const g = guard(request); if (g) return g;
  try {
    return NextResponse.json(getDashboard());
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : String(error) }, { status: 500 });
  }
}
