import { guard, notMigrated } from '@/server/legacy/compat';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

// Reichert Wunschlisten-Items via externem Scrape (Netzwerk) an → braucht externe Netzwerkzugriffe,
// in dieser Version (noch) nicht migriert.
export async function POST(request: Request) {
  const g = guard(request, 'agent'); if (g) return g;
  return notMigrated('Wunschliste-Anreicherung');
}
