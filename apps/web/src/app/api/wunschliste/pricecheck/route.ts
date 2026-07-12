import { guard, notMigrated } from '@/server/legacy/compat';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

// Preisvergleich via idealo/Google-Shopping-Scrape → braucht externe Netzwerkzugriffe,
// in dieser Version (noch) nicht migriert.
export async function POST(request: Request) {
  const g = guard(request, 'agent'); if (g) return g;
  return notMigrated('Wunschliste-Preisvergleich');
}
