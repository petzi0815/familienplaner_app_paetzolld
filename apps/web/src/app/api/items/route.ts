import { NextRequest, NextResponse } from 'next/server';
import { getAllItems, getStats, getKategorien, getGroessen, getMatrix } from '@/server/legacy/samu-db';
import { guard } from '@/server/legacy/compat';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(request: NextRequest) {
  const g = guard(request); if (g) return g;
  const searchParams = request.nextUrl.searchParams;

  if (searchParams.get('stats') === 'true') {
    return NextResponse.json(getStats());
  }

  if (searchParams.get('matrix') === 'true') {
    return NextResponse.json(getMatrix(searchParams.get('status') || undefined));
  }

  if (searchParams.get('kategorien') === 'true') {
    const filters = {
      status: searchParams.get('status') || undefined,
      typ: searchParams.get('typ') || undefined,
    };
    return NextResponse.json(getKategorien(filters));
  }

  if (searchParams.get('groessen') === 'true') {
    const filters = {
      status: searchParams.get('status') || undefined,
      typ: searchParams.get('typ') || undefined,
    };
    return NextResponse.json(getGroessen(filters));
  }

  const filters = {
    status: searchParams.get('status') || undefined,
    typ: searchParams.get('typ') || undefined,
    kategorie: searchParams.get('kategorie') || undefined,
    groesse: searchParams.get('groesse') || undefined,
    search: searchParams.get('search') || undefined,
  };

  const items = getAllItems(filters);
  return NextResponse.json(items);
}
