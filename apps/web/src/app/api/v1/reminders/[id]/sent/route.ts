import { getDb } from "@/server/db/connection";
import { getAuth, hasRole } from "@/server/auth/auth";
import { unauthorized, forbidden, notFound, ok } from "@/server/http/respond";

// Markiert eine Termin-Erinnerung als gesendet.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }): Promise<Response> {
  const auth = getAuth(req);
  if (!hasRole(auth, "agent")) return auth ? forbidden() : unauthorized();
  const { id } = await params;
  const db = getDb();
  const info = db.prepare("UPDATE termine SET reminder_sent=1 WHERE id=?").run(id);
  if (info.changes === 0) return notFound("Termin");
  db.prepare("INSERT INTO event_log (actor, action, domain, entity_id) VALUES (?,?,?,?)").run(auth.actor, "reminder_sent", "termine", String(id));
  return ok({ ok: true, id });
}
