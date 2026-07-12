import { NextResponse } from 'next/server';
import { generiereEreignisse } from '@/server/legacy/geschenkplaner-db';
import { guard } from '@/server/legacy/compat';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function POST(request: Request) {
  const g = guard(request, 'agent'); if (g) return g;
  try {
    const ereignisse = generiereEreignisse();
    return NextResponse.json({ generated: true, ereignisse });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : String(error) }, { status: 500 });
  }
}
