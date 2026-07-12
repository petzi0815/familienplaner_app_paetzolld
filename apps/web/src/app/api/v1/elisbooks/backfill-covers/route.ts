import { getDb } from "@/server/db/connection";
import { getAuth, hasRole } from "@/server/auth/auth";
import { ok, fail, unauthorized, forbidden } from "@/server/http/respond";

// Cover-Backfill: für elisbooks_books mit kaputtem/fehlendem Cover (Oles tote /api/elisbooks/covers/-Pfade)
// das echte Google-Books-Cover per ISBN nachladen (dieselbe Quelle wie die Original-App). Server-seitig,
// in Batches (limit). Mehrfach aufrufen, bis remaining=0. POST /api/v1/elisbooks/backfill-covers { limit? }
export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 60;

const BROKEN = "(thumbnail IS NULL OR thumbnail='' OR thumbnail LIKE '/api/%')";

async function googleCover(isbn: string): Promise<string | null> {
  try {
    const r = await fetch(`https://www.googleapis.com/books/v1/volumes?q=isbn:${encodeURIComponent(isbn)}&country=DE&maxResults=1`);
    if (!r.ok) return null;
    const d = (await r.json()) as { items?: { volumeInfo?: { imageLinks?: Record<string, string> } }[] };
    const links = d.items?.[0]?.volumeInfo?.imageLinks;
    const t = links?.thumbnail ?? links?.smallThumbnail;
    return t ? t.replace(/^http:\/\//i, "https://") : null;
  } catch { return null; }
}

export async function POST(req: Request): Promise<Response> {
  const auth = getAuth(req);
  if (!hasRole(auth, "agent")) return auth ? forbidden() : unauthorized();
  let body: Record<string, unknown> = {};
  try { body = (await req.json()) as Record<string, unknown>; } catch { /* leerer Body ok */ }
  const limit = Math.min(Math.max(Number(body.limit ?? 80) || 80, 1), 200);

  const db = getDb();
  const rows = db.prepare(
    `SELECT id, isbn FROM elisbooks_books WHERE ${BROKEN} AND isbn IS NOT NULL AND isbn<>'' LIMIT ?`,
  ).all(limit) as { id: string; isbn: string }[];
  const upd = db.prepare("UPDATE elisbooks_books SET thumbnail=?, updated_at=datetime('now') WHERE id=?");

  let updated = 0, tried = 0;
  for (const r of rows) {
    tried++;
    const cover = await googleCover(r.isbn.trim());
    if (cover) { upd.run(cover, r.id); updated++; }
    await new Promise((res) => setTimeout(res, 80)); // sanft gegen Rate-Limits
  }
  const remaining = (db.prepare(
    `SELECT COUNT(*) c FROM elisbooks_books WHERE ${BROKEN} AND isbn IS NOT NULL AND isbn<>''`,
  ).get() as { c: number }).c;
  return ok({ tried, updated, remaining });
}
