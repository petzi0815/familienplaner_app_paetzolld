import { getDb } from "@/server/db/connection";
import { getAuth, hasRole } from "@/server/auth/auth";
import { ok, fail, unauthorized, forbidden } from "@/server/http/respond";

// Cover-Backfill: schreibt die echten Cover-URLs (aus Elitas Supabase) in unsere elisbooks_books.thumbnail,
// wo Oles Migration tote /api/elisbooks/covers/-Pfade hinterlassen hat. Match per ID (ID-erhaltend).
// Body: { covers: [{ id, vid }] } — vid = Google-Books-Volume-ID (URL wird rekonstruiert),
//        ODER [{ id, thumbnail }] — vollständige URL (http→https). Nur wo aktuell kaputt.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 60;

const BROKEN = "(thumbnail IS NULL OR thumbnail='' OR thumbnail LIKE '/api/%')";

export async function POST(req: Request): Promise<Response> {
  const auth = getAuth(req);
  if (!hasRole(auth, "agent")) return auth ? forbidden() : unauthorized();
  let body: Record<string, unknown>;
  try { body = (await req.json()) as Record<string, unknown>; } catch { return fail("bad_json", "Ungültiger JSON-Body.", 400); }
  const covers = Array.isArray(body.covers) ? (body.covers as Record<string, unknown>[]) : [];
  if (!covers.length) return fail("empty", "Feld 'covers' (Array) erforderlich.", 400);

  const db = getDb();
  const upd = db.prepare(`UPDATE elisbooks_books SET thumbnail=?, updated_at=datetime('now') WHERE id=? AND ${BROKEN}`);
  let updated = 0, skipped = 0;
  const tx = db.transaction(() => {
    for (const c of covers) {
      const id = String(c.id ?? "");
      if (!id) { skipped++; continue; }
      let url = "";
      if (c.vid) url = `https://books.google.com/books/content?id=${String(c.vid)}&printsec=frontcover&img=1&zoom=1&source=gbs_api`;
      else if (c.thumbnail) url = String(c.thumbnail).replace(/^http:\/\//i, "https://");
      if (!/^https:\/\//i.test(url)) { skipped++; continue; }
      const info = upd.run(url, id);
      if (info.changes > 0) updated++; else skipped++;
    }
  });
  tx();
  const remaining = (db.prepare(
    `SELECT COUNT(*) c FROM elisbooks_books WHERE ${BROKEN}`,
  ).get() as { c: number }).c;
  return ok({ received: covers.length, updated, skipped, remaining });
}
