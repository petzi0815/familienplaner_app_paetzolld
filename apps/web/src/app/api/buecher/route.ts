import { NextResponse } from 'next/server';
import { getAllBooks, addBook, getCategories, getYears } from '@/server/legacy/buecher-db';
import { guard } from '@/server/legacy/compat';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(request: Request) {
  const g = guard(request); if (g) return g;
  try {
    const { searchParams } = new URL(request.url);

    if (searchParams.get('categories') === 'true') {
      return NextResponse.json(getCategories());
    }
    if (searchParams.get('years') === 'true') {
      return NextResponse.json(getYears());
    }

    const filters = {
      status: searchParams.get('status') || undefined,
      year: searchParams.get('year') || undefined,
      category: searchParams.get('category') || undefined,
      q: searchParams.get('q') || undefined,
    };

    const books = getAllBooks(filters);
    return NextResponse.json(books);
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}

export async function POST(request: Request) {
  const g = guard(request, 'agent'); if (g) return g;
  try {
    const data = await request.json();

    if (!data.title) {
      return NextResponse.json({ error: 'title ist ein Pflichtfeld' }, { status: 400 });
    }

    const id = addBook(data);
    return NextResponse.json({ id, success: true });
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}
