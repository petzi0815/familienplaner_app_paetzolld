import { NextResponse } from 'next/server';
import { getSmarthomeDb } from '@/server/legacy/smarthome-db';
import { guard } from '@/server/legacy/compat';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(request: Request) {
  const g = guard(request); if (g) return g;
  try {
    const { searchParams } = new URL(request.url);
    const domain = searchParams.get('domain');
    const area = searchParams.get('area');
    const disabled = searchParams.get('disabled'); // '0', '1', 'all'
    const sort = searchParams.get('sort') || 'name'; // 'name', 'domain', 'usage', 'discovered'
    const discoveredSince = searchParams.get('discovered_since'); // ISO date string

    const db = getSmarthomeDb(true);

    let query = 'SELECT e.*';

    // Add usage count if sorting by usage
    if (sort === 'usage') {
      query += ', COALESCE(cmd.cmd_count, 0) as usage_count';
    }

    query += ' FROM ha_entities e';

    // Join with command_log for usage count
    if (sort === 'usage') {
      query += ' LEFT JOIN (SELECT matched_entity_id, COUNT(*) as cmd_count FROM ha_command_log GROUP BY matched_entity_id) cmd ON cmd.matched_entity_id = e.entity_id';
    }

    query += ' WHERE 1=1';
    const params: unknown[] = [];

    if (domain) {
      query += ' AND e.domain = ?';
      params.push(domain);
    }

    if (area) {
      query += ' AND e.area_name = ?';
      params.push(area);
    }

    // Filter by disabled status
    if (disabled === '0') {
      query += ' AND e.disabled = 0';
    } else if (disabled === '1') {
      query += ' AND e.disabled = 1';
    }
    // 'all' or null = no filter

    // Filter by discovered_at
    if (discoveredSince) {
      query += ' AND e.discovered_at >= ?';
      params.push(discoveredSince);
    }

    // Sorting
    if (sort === 'usage') {
      query += ' ORDER BY usage_count DESC, e.friendly_name';
    } else if (sort === 'domain') {
      query += ' ORDER BY e.domain, e.friendly_name';
    } else if (sort === 'discovered') {
      query += ' ORDER BY e.discovered_at DESC, e.friendly_name';
    } else {
      query += ' ORDER BY e.area_name, e.friendly_name';
    }

    const entities = db.prepare(query).all(...params);

    return NextResponse.json({ entities });
  } catch (error) {
    return NextResponse.json({ error: (error as Error).message }, { status: 500 });
  }
}
