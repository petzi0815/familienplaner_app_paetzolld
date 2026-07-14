import { guard, notMigrated } from '@/server/legacy/compat';
import { calibreEnabled, cover } from '@/server/ebooks/calibre';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

// Cover-Proxy: Calibre-Web-Cover auth-bewusst durchreichen (AuthImage lädt es mit Bearer).
export async function GET(request: Request, { params }: { params: Promise<{ id: string }> }): Promise<Response> {
  const g = guard(request); if (g) return g;
  if (!calibreEnabled()) return notMigrated('Calibre-Web');
  const { id } = await params;
  try {
    const c = await cover(parseInt(id));
    if (!c) return new Response('Not found', { status: 404 });
    return new Response(new Uint8Array(c.bytes), {
      headers: { 'content-type': c.contentType, 'cache-control': 'private, max-age=86400' },
    });
  } catch {
    return new Response('Bad gateway', { status: 502 });
  }
}
