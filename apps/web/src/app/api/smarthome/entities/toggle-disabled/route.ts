import { NextResponse } from 'next/server';
import { getSmarthomeDb } from '@/server/legacy/smarthome-db';
import { guard } from '@/server/legacy/compat';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function POST(request: Request) {
  const g = guard(request, 'agent'); if (g) return g;
  try {
    const { entity_id } = await request.json();

    if (!entity_id) {
      return NextResponse.json({ error: 'entity_id required' }, { status: 400 });
    }

    const db = getSmarthomeDb(false);

    const current = db.prepare('SELECT disabled FROM ha_entities WHERE entity_id = ?').get(entity_id) as { disabled: number } | undefined;

    if (!current) {
      return NextResponse.json({ error: 'Entity not found' }, { status: 404 });
    }

    const newState = current.disabled ? 0 : 1;
    db.prepare('UPDATE ha_entities SET disabled = ? WHERE entity_id = ?').run(newState, entity_id);

    return NextResponse.json({ success: true, entity_id, disabled: newState === 1 });
  } catch (error) {
    return NextResponse.json({ error: (error as Error).message }, { status: 500 });
  }
}
