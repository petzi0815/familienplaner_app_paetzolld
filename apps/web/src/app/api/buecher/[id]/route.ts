import { NextResponse } from 'next/server';
import { getBook, updateBook, deleteBook } from '@/server/legacy/buecher-db';
import { guard } from '@/server/legacy/compat';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(
  request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  const g = guard(request); if (g) return g;
  try {
    const { id } = await params;
    const book = getBook(parseInt(id));
    if (!book) {
      return NextResponse.json({ error: 'Buch nicht gefunden' }, { status: 404 });
    }
    return NextResponse.json(book);
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}

export async function PATCH(
  request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  const g = guard(request, 'agent'); if (g) return g;
  try {
    const { id } = await params;
    const data = await request.json();
    const success = updateBook(parseInt(id), data);
    if (!success) {
      return NextResponse.json({ error: 'Buch nicht gefunden oder keine Änderungen' }, { status: 404 });
    }
    return NextResponse.json({ success: true });
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}

export async function DELETE(
  request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  const g = guard(request, 'agent'); if (g) return g;
  try {
    const { id } = await params;
    const success = deleteBook(parseInt(id));
    if (!success) {
      return NextResponse.json({ error: 'Buch nicht gefunden' }, { status: 404 });
    }
    return NextResponse.json({ success: true });
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}
