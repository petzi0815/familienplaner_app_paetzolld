import { NextResponse } from 'next/server';
import { getSmarthomeDb } from '@/server/legacy/smarthome-db';
import { guard } from '@/server/legacy/compat';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(request: Request) {
  const g = guard(request); if (g) return g;
  try {
    const db = getSmarthomeDb(true);

    const totalEntities = db.prepare('SELECT COUNT(*) as count FROM ha_entities').get() as { count: number };
    const totalRelationships = db.prepare('SELECT COUNT(*) as count FROM ha_relationships').get() as { count: number };
    const areas = db.prepare('SELECT COUNT(DISTINCT area_name) as count FROM ha_entities WHERE area_name IS NOT NULL').get() as { count: number };

    // Count unique parent entities (groups)
    const totalGroups = db.prepare('SELECT COUNT(DISTINCT parent_entity_id) as count FROM ha_relationships').get() as { count: number };

    const byDomain = db.prepare(`
      SELECT domain, COUNT(*) as count
      FROM ha_entities
      GROUP BY domain
      ORDER BY count DESC
      LIMIT 10
    `).all() as { domain: string; count: number }[];

    return NextResponse.json({
      totalEntities: totalEntities.count,
      totalRelationships: totalRelationships.count,
      totalAreas: areas.count,
      totalGroups: totalGroups.count,
      byDomain
    });
  } catch (error) {
    return NextResponse.json({ error: (error as Error).message }, { status: 500 });
  }
}
