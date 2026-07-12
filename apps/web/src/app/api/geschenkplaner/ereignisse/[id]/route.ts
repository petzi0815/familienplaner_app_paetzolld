import { NextResponse } from 'next/server';
import { getEreignis } from '@/server/legacy/geschenkplaner-db';
import { guard, getDb } from '@/server/legacy/compat';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const g = guard(request); if (g) return g;
  try {
    const { id } = await params;
    const ereignis = getEreignis(parseInt(id));
    if (!ereignis) return NextResponse.json({ error: 'Ereignis nicht gefunden' }, { status: 404 });
    return NextResponse.json(ereignis);
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : String(error) }, { status: 500 });
  }
}

export async function PATCH(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const g = guard(request, 'agent'); if (g) return g;
  try {
    const { id } = await params;
    const body = await request.json();
    const db = getDb();
    const allowed = ['erinnerungen_aktiv'];
    const fields: string[] = [];
    const values: unknown[] = [];
    for (const key of allowed) {
      if (key in body) {
        fields.push(`${key} = ?`);
        values.push(body[key]);
      }
    }
    if (fields.length === 0) { return NextResponse.json({ error: 'Keine Felder zum Aktualisieren' }, { status: 400 }); }
    values.push(parseInt(id));
    db.prepare(`UPDATE geschenk_ereignisse SET ${fields.join(', ')} WHERE id = ?`).run(...values);
    const updated = getEreignis(parseInt(id));
    return NextResponse.json(updated);
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : String(error) }, { status: 500 });
  }
}
