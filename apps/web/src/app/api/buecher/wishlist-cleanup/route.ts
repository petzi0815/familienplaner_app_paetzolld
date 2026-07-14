import { NextResponse } from 'next/server';
import { guard } from '@/server/legacy/compat';
import { cleanupDownloaded } from '@/server/ebooks/wishlist';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

// Erfolgreich heruntergeladene Bücher aus der Wunschliste entfernen.
export async function POST(request: Request) {
  const g = guard(request, 'agent'); if (g) return g;
  try {
    const deleted = cleanupDownloaded();
    return NextResponse.json({ success: true, deleted });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Fehler' }, { status: 500 });
  }
}
