import { getDb } from "@/server/db/connection";
import { getAuth, hasRole } from "@/server/auth/auth";
import { ok, fail, unauthorized, forbidden } from "@/server/http/respond";

// Bulk-Operationen für die native ElisBooks-App (Tempo bei vielen Büchern). Liegt unter /elisbooks/,
// damit die generische /elisbooks-books-CRUD (via [domain]) NICHT von einem statischen Ordner beschattet wird.
// POST /api/v1/elisbooks/books-bulk { op: "move"|"delete"|"read"|"picklist", ids: [...], bookshelf_id?, is_read?, is_on_picklist? }
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function POST(req: Request): Promise<Response> {
  const auth = getAuth(req);
  if (!hasRole(auth, "agent")) return auth ? forbidden() : unauthorized();
  let body: Record<string, unknown>;
  try { body = (await req.json()) as Record<string, unknown>; } catch { return fail("bad_json", "Ungültiger JSON-Body.", 400); }

  const op = String(body.op ?? "");
  const ids = Array.isArray(body.ids) ? (body.ids as unknown[]).map(String).filter(Boolean) : [];
  if (!ids.length) return fail("empty", "Keine IDs angegeben.", 400);
  const ph = ids.map(() => "?").join(",");
  const db = getDb();

  try {
    let changes = 0;
    if (op === "move") {
      const shelf = body.bookshelf_id == null || body.bookshelf_id === "" ? null : String(body.bookshelf_id);
      changes = db.prepare(`UPDATE elisbooks_books SET bookshelf_id=?, updated_at=datetime('now') WHERE id IN (${ph})`).run(shelf, ...ids).changes;
    } else if (op === "delete") {
      changes = db.prepare(`DELETE FROM elisbooks_books WHERE id IN (${ph})`).run(...ids).changes;
    } else if (op === "read") {
      changes = db.prepare(`UPDATE elisbooks_books SET is_read=?, updated_at=datetime('now') WHERE id IN (${ph})`).run(body.is_read ? 1 : 0, ...ids).changes;
    } else if (op === "picklist") {
      changes = db.prepare(`UPDATE elisbooks_books SET is_on_picklist=?, updated_at=datetime('now') WHERE id IN (${ph})`).run(body.is_on_picklist ? 1 : 0, ...ids).changes;
    } else {
      return fail("bad_op", "op muss move|delete|read|picklist sein.", 400);
    }
    db.prepare("INSERT INTO event_log (actor, action, domain, entity_id, detail) VALUES (?,?,?,?,?)")
      .run(auth.actor, `bulk_${op}`, "elisbooks", null, JSON.stringify({ count: ids.length }));
    return ok({ op, affected: changes });
  } catch (e) {
    return fail("db_error", "Bulk-Operation fehlgeschlagen.", 500, { sqlite: String((e as Error)?.message ?? e) });
  }
}
