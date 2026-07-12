import { NextResponse } from 'next/server';
import { getSmarthomeDb } from '@/server/legacy/smarthome-db';
import { guard } from '@/server/legacy/compat';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(request: Request) {
  const g = guard(request); if (g) return g;
  try {
    const { searchParams } = new URL(request.url);
    const limit = parseInt(searchParams.get('limit') || '50');

    const db = getSmarthomeDb(true);

    const logs = db.prepare(`
      SELECT
        l.*,
        e.friendly_name
      FROM ha_command_log l
      LEFT JOIN ha_entities e ON e.entity_id = l.matched_entity_id
      ORDER BY l.timestamp DESC
      LIMIT ?
    `).all(limit);

    return NextResponse.json({ logs });
  } catch (error) {
    return NextResponse.json({ error: (error as Error).message }, { status: 500 });
  }
}
