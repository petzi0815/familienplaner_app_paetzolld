import { NextRequest, NextResponse } from 'next/server';
import { getItem, updateItem, deleteItem } from '@/server/legacy/samu-db';
import { guard } from '@/server/legacy/compat';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const g = guard(request); if (g) return g;
  const { id } = await params;
  const item = getItem(parseInt(id));
  if (!item) return NextResponse.json({ error: 'Item nicht gefunden' }, { status: 404 });
  return NextResponse.json(item);
}

export async function PUT(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const g = guard(request, 'agent'); if (g) return g;
  const { id } = await params;
  const data = await request.json();
  const success = updateItem(parseInt(id), data);
  if (!success) return NextResponse.json({ error: 'Update fehlgeschlagen' }, { status: 400 });
  return NextResponse.json({ success: true });
}

export async function DELETE(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const g = guard(request, 'agent'); if (g) return g;
  const { id } = await params;
  const success = deleteItem(parseInt(id));
  if (!success) return NextResponse.json({ error: 'Löschen fehlgeschlagen' }, { status: 400 });
  return NextResponse.json({ success: true });
}
