import { NextResponse } from 'next/server';
import { getSmarthomeDb } from '@/server/legacy/smarthome-db';
import { guard } from '@/server/legacy/compat';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(request: Request) {
  const g = guard(request); if (g) return g;
  try {
    const db = getSmarthomeDb(true);
    const aliases = db.prepare('SELECT * FROM ha_aliases ORDER BY entity_id, alias').all();
    return NextResponse.json({ aliases });
  } catch (error) {
    return NextResponse.json({ error: (error as Error).message }, { status: 500 });
  }
}

export async function POST(request: Request) {
  const g = guard(request, 'agent'); if (g) return g;
  try {
    const { entity_id, alias } = await request.json();

    if (!entity_id || !alias) {
      return NextResponse.json({ error: 'entity_id and alias are required' }, { status: 400 });
    }

    const db = getSmarthomeDb(false);
    db.prepare('INSERT INTO ha_aliases (entity_id, alias) VALUES (?, ?)').run(entity_id, alias);

    return NextResponse.json({ success: true });
  } catch (error) {
    return NextResponse.json({ error: (error as Error).message }, { status: 500 });
  }
}

export async function DELETE(request: Request) {
  const g = guard(request, 'agent'); if (g) return g;
  try {
    const { searchParams } = new URL(request.url);
    const entity_id = searchParams.get('entity_id');
    const alias = searchParams.get('alias');

    if (!entity_id || !alias) {
      return NextResponse.json({ error: 'entity_id and alias are required' }, { status: 400 });
    }

    const db = getSmarthomeDb(false);
    db.prepare('DELETE FROM ha_aliases WHERE entity_id = ? AND alias = ?').run(entity_id, alias);

    return NextResponse.json({ success: true });
  } catch (error) {
    return NextResponse.json({ error: (error as Error).message }, { status: 500 });
  }
}
