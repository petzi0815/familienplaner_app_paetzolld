import { getDb } from "@/server/db/connection";
import { getAuth, hasRole } from "@/server/auth/auth";
import { unauthorized, forbidden, notFound, ok } from "@/server/http/respond";

// Hakt eine Aufgabe ab. Einmalige Aufgaben → status='erledigt'. Wiederholende (recurring != 'einmalig')
// werden NICHT geschlossen, sondern auf die nächste Fälligkeit vorgerückt (Anker = spätere von
// due_date/heute, damit überfällige Wiederholungen nicht in der Vergangenheit landen). done_at merkt
// die letzte Erledigung. Agent-Rolle nötig (Schreibzugriff) — auch für Ole/externe Tools.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/**
 * Nächste Fälligkeit ab `base` (YYYY-MM-DD). Monat/Jahr TAG-GECLAMPT (der 31. → letzter Tag des
 * Zielmonats), damit KEIN Zeitraum übersprungen wird — anders als SQLites `date(x,'+1 month')`
 * (31.01.→03.03. lässt den Februar aus). Alles in UTC, um TZ-Drift zu vermeiden.
 */
function nextDue(base: string, interval: string): string | null {
  const [y, m, d] = base.split("-").map(Number);
  if (!y || !m || !d) return null;
  if (interval === "taeglich" || interval === "woechentlich") {
    const dt = new Date(Date.UTC(y, m - 1, d + (interval === "taeglich" ? 1 : 7)));
    return dt.toISOString().slice(0, 10);
  }
  if (interval !== "monatlich" && interval !== "jaehrlich") return null;
  const idx = m - 1 + (interval === "jaehrlich" ? 12 : 1);
  const ty = y + Math.floor(idx / 12);
  const tm = ((idx % 12) + 12) % 12; // 0-basierter Zielmonat
  const daysInTarget = new Date(Date.UTC(ty, tm + 1, 0)).getUTCDate();
  const td = Math.min(d, daysInTarget);
  return `${ty}-${String(tm + 1).padStart(2, "0")}-${String(td).padStart(2, "0")}`;
}

export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }): Promise<Response> {
  const auth = getAuth(req);
  if (!hasRole(auth, "agent")) return auth ? forbidden() : unauthorized();
  const { id } = await params;
  const db = getDb();
  const row = db.prepare("SELECT id,due_date,recurring FROM aufgaben WHERE id=?").get(id) as
    { id: number; due_date?: string | null; recurring?: string | null } | undefined;
  if (!row) return notFound("Aufgabe");

  const recurring = String(row.recurring ?? "einmalig");
  const today = new Date().toISOString().slice(0, 10);
  const base = row.due_date && String(row.due_date) > today ? String(row.due_date) : today;
  const next = recurring === "einmalig" ? null : nextDue(base, recurring);
  if (next) {
    db.prepare("UPDATE aufgaben SET due_date=?, status='offen', done_at=datetime('now'), updated_at=datetime('now') WHERE id=?").run(next, id);
  } else {
    db.prepare("UPDATE aufgaben SET status='erledigt', done_at=datetime('now'), updated_at=datetime('now') WHERE id=?").run(id);
  }
  db.prepare("INSERT INTO event_log (actor, action, domain, entity_id) VALUES (?,?,?,?)").run(auth.actor, "aufgabe_complete", "aufgaben", String(id));
  const updated = db.prepare("SELECT * FROM aufgaben WHERE id=?").get(id);
  return ok(updated);
}
