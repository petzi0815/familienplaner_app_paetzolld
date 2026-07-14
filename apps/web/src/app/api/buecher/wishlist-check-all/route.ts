import { NextResponse } from 'next/server';
import { guard } from '@/server/legacy/compat';
import { retryAll, pendingCount } from '@/server/ebooks/wishlist';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

// Alle „gesucht"-Bücher via Shelfmark prüfen + laden. Läuft im Hintergrund (kann dauern),
// die App lädt danach neu. Antwort kommt sofort.
export async function POST(request: Request) {
  const g = guard(request, 'agent'); if (g) return g;
  const pending = pendingCount();
  // Fire-and-forget: der persistente Node-Server (Coolify) arbeitet nach der Antwort weiter.
  void retryAll().catch(() => {});
  return NextResponse.json({ started: true, pending });
}
