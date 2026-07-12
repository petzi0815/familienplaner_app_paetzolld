import { NextRequest, NextResponse } from 'next/server';
import { getAllMarken } from '@/server/legacy/samu-db';
import { guard } from '@/server/legacy/compat';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(request: NextRequest) {
  const g = guard(request); if (g) return g;
  const marken = getAllMarken();
  return NextResponse.json(marken);
}
