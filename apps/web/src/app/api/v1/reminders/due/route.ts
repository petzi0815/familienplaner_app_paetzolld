import { getDb } from "@/server/db/connection";
import { getAuth, hasRole } from "@/server/auth/auth";
import { unauthorized, ok } from "@/server/http/respond";

// Fällige Termin-Erinnerungen (aus `termine`): heute liegt im Fenster [date - reminder_days, date],
// noch nicht gesendet, nicht erledigt.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

interface Termin {
  id: number; title: string; date: string; time?: string; category?: string;
  reminder_days?: number; reminder_sent?: number; status?: string;
}

export function GET(req: Request): Response {
  if (!hasRole(getAuth(req), "readonly")) return unauthorized();
  const db = getDb();
  const rows = db.prepare(
    "SELECT * FROM termine WHERE COALESCE(reminder_sent,0)=0 AND COALESCE(status,'')<>'erledigt' AND date IS NOT NULL AND date<>''",
  ).all() as Termin[];
  const today = new Date(); today.setHours(0, 0, 0, 0);
  const due = rows.filter((t) => {
    const d = new Date(t.date + "T00:00:00");
    if (isNaN(d.getTime())) return false;
    const windowStart = new Date(d); windowStart.setDate(d.getDate() - (t.reminder_days ?? 0));
    return today >= windowStart && today <= d;
  }).sort((a, b) => a.date.localeCompare(b.date));
  return ok({ count: due.length, data: due });
}
