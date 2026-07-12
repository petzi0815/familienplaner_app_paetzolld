import { NextResponse } from 'next/server';
import { getSmarthomeDb } from '@/server/legacy/smarthome-db';
import { guard } from '@/server/legacy/compat';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(request: Request) {
  const g = guard(request); if (g) return g;
  try {
    const { searchParams } = new URL(request.url);
    const type = searchParams.get('type'); // 'auto', 'manual', 'all'

    const db = getSmarthomeDb(true);

    let query = `
      SELECT
        r.*,
        p.friendly_name as parent_name,
        p.state as parent_state,
        p.domain as parent_domain,
        c.friendly_name as child_name
      FROM ha_relationships r
      LEFT JOIN ha_entities p ON p.entity_id = r.parent_entity_id
      LEFT JOIN ha_entities c ON c.entity_id = r.child_entity_id
      WHERE 1=1
    `;

    if (type === 'auto') {
      query += ' AND r.auto_discovered = 1 AND r.manually_verified = 0';
    } else if (type === 'manual') {
      query += ' AND (r.auto_discovered = 0 OR r.manually_verified = 1)';
    }
    // 'all' or null = no filter

    query += ' ORDER BY r.type, p.friendly_name';

    const relationships = db.prepare(query).all();

    return NextResponse.json({ relationships });
  } catch (error) {
    return NextResponse.json({ error: (error as Error).message }, { status: 500 });
  }
}

export async function POST(request: Request) {
  const g = guard(request, 'agent'); if (g) return g;
  try {
    const { parent_entity_id, child_entity_id, type } = await request.json();

    if (!parent_entity_id || !child_entity_id || !type) {
      return NextResponse.json({ error: 'parent_entity_id, child_entity_id and type are required' }, { status: 400 });
    }

    const db = getSmarthomeDb(false);
    db.prepare(`
      INSERT INTO ha_relationships (parent_entity_id, child_entity_id, type, auto_discovered, manually_verified)
      VALUES (?, ?, ?, 0, 1)
    `).run(parent_entity_id, child_entity_id, type);

    return NextResponse.json({ success: true });
  } catch (error) {
    return NextResponse.json({ error: (error as Error).message }, { status: 500 });
  }
}

export async function DELETE(request: Request) {
  const g = guard(request, 'agent'); if (g) return g;
  try {
    const { searchParams } = new URL(request.url);
    const id = searchParams.get('id');

    if (!id) {
      return NextResponse.json({ error: 'id is required' }, { status: 400 });
    }

    const db = getSmarthomeDb(false);
    db.prepare('DELETE FROM ha_relationships WHERE id = ?').run(id);

    return NextResponse.json({ success: true });
  } catch (error) {
    return NextResponse.json({ error: (error as Error).message }, { status: 500 });
  }
}

export async function PATCH(request: Request) {
  const g = guard(request, 'agent'); if (g) return g;
  try {
    const { searchParams } = new URL(request.url);
    const id = searchParams.get('id');
    const { manually_verified } = await request.json();

    if (!id) {
      return NextResponse.json({ error: 'id is required' }, { status: 400 });
    }

    const db = getSmarthomeDb(false);
    db.prepare('UPDATE ha_relationships SET manually_verified = ? WHERE id = ?').run(manually_verified ? 1 : 0, id);

    return NextResponse.json({ success: true });
  } catch (error) {
    return NextResponse.json({ error: (error as Error).message }, { status: 500 });
  }
}
