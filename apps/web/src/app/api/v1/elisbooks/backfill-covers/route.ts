import { getDb } from "@/server/db/connection";
import { getAuth, hasRole } from "@/server/auth/auth";
import { ok, fail, unauthorized, forbidden } from "@/server/http/respond";

// Einmalig: echte Cover-URLs (Google Books) aus Elitas Supabase in unsere elisbooks_books.thumbnail
// zurückschreiben. Oles Migration hatte sie durch tote `/api/elisbooks/covers/<uuid>.jpg`-Pfade ersetzt.
// Matcht per ID (ID-erhaltend). Body: { supabaseUrl, anonKey }.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 60;

export async function POST(req: Request): Promise<Response> {
  const auth = getAuth(req);
  if (!hasRole(auth, "agent")) return auth ? forbidden() : unauthorized();
  let body: Record<string, unknown>;
  try { body = (await req.json()) as Record<string, unknown>; } catch { return fail("bad_json", "Ungültiger JSON-Body.", 400); }
  const supabaseUrl = String(body.supabaseUrl ?? "").replace(/\/+$/, "");
  const anonKey = String(body.anonKey ?? "");
  if (!supabaseUrl || !anonKey) return fail("missing", "supabaseUrl + anonKey erforderlich.", 400);

  // Supabase REST: alle Bücher mit id + thumbnail.
  let rows: { id: string; thumbnail: string | null }[] = [];
  try {
    const r = await fetch(`${supabaseUrl}/rest/v1/books?select=id,thumbnail&limit=2000`, {
      headers: { apikey: anonKey, authorization: `Bearer ${anonKey}` },
    });
    if (!r.ok) return fail("supabase_error", `Supabase ${r.status}`, 502, { detail: (await r.text()).slice(0, 200) });
    rows = (await r.json()) as { id: string; thumbnail: string | null }[];
  } catch (e) {
    return fail("fetch_error", "Supabase-Abruf fehlgeschlagen.", 502, { detail: String((e as Error)?.message ?? e) });
  }

  const db = getDb();
  const upd = db.prepare(
    "UPDATE elisbooks_books SET thumbnail=?, updated_at=datetime('now') WHERE id=? AND (thumbnail IS NULL OR thumbnail LIKE '/api/%' OR thumbnail='')",
  );
  let updated = 0, skipped = 0;
  const tx = db.transaction(() => {
    for (const b of rows) {
      const t = (b.thumbnail ?? "").trim();
      if (!t || !/^https?:\/\//i.test(t)) { skipped++; continue; }
      const https = t.replace(/^http:\/\//i, "https://");
      const info = upd.run(https, b.id);
      if (info.changes > 0) updated++; else skipped++;
    }
  });
  tx();
  return ok({ supabase_books: rows.length, updated, skipped });
}
