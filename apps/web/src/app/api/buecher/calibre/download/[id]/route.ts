import { NextResponse } from 'next/server';
import { guard, notMigrated } from '@/server/legacy/compat';
import { calibreEnabled, downloadBook } from '@/server/ebooks/calibre';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

// Buch-Datei (epub/…) aus Calibre durchreichen — der Client lädt sie und öffnet sie z.B. in Apple Books.
export async function GET(request: Request, { params }: { params: Promise<{ id: string }> }): Promise<Response> {
  const g = guard(request); if (g) return g;
  if (!calibreEnabled()) return notMigrated('Calibre-Web');
  const { id } = await params;
  const format = new URL(request.url).searchParams.get('format') || 'epub';
  try {
    const file = await downloadBook(parseInt(id), format);
    if (!file) return NextResponse.json({ error: 'Download in diesem Format nicht verfügbar.' }, { status: 404 });
    return new Response(new Uint8Array(file.bytes), {
      status: 200,
      headers: {
        'content-type': file.contentType,
        'content-disposition': `attachment; filename="${file.filename.replace(/["\r\n]/g, '')}"`,
        'cache-control': 'no-store',
      },
    });
  } catch (error) {
    return NextResponse.json(
      { error: `Calibre nicht erreichbar: ${error instanceof Error ? error.message : 'Fehler'}` },
      { status: 502 },
    );
  }
}
