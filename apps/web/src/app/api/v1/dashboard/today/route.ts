import { getDb } from "@/server/db/connection";
import { getAuth, hasRole } from "@/server/auth/auth";
import { unauthorized, ok } from "@/server/http/respond";

// Kompakter Tageszustand für „Ole" + Dashboard.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export function GET(req: Request): Response {
  if (!hasRole(getAuth(req), "readonly")) return unauthorized();
  const db = getDb();
  const now = new Date();
  const today = now.toISOString().slice(0, 10);
  const in14 = new Date(now.getTime() + 14 * 86400000).toISOString().slice(0, 10);
  const month = now.getMonth() + 1;
  const year = now.getFullYear();

  const safe = <T>(fn: () => T, fallback: T): T => { try { return fn(); } catch { return fallback; } };

  const termineUpcoming = safe(() => db.prepare(
    "SELECT id,title,date,time,category FROM termine WHERE date>=? AND COALESCE(status,'')<>'erledigt' ORDER BY date ASC, time ASC LIMIT 15",
  ).all(today), []);

  const remindersDue = safe(() => {
    const rows = db.prepare("SELECT date,reminder_days FROM termine WHERE COALESCE(reminder_sent,0)=0 AND COALESCE(status,'')<>'erledigt' AND date IS NOT NULL AND date<>''").all() as { date: string; reminder_days?: number }[];
    const t0 = new Date(today + "T00:00:00");
    return rows.filter((t) => {
      const d = new Date(t.date + "T00:00:00");
      const ws = new Date(d); ws.setDate(d.getDate() - (t.reminder_days ?? 0));
      return t0 >= ws && t0 <= d;
    }).length;
  }, 0);

  const nextTrip = safe(() => {
    const trip = db.prepare("SELECT id,title,destination,start_date FROM reisen_trips WHERE start_date>=? ORDER BY start_date ASC LIMIT 1").get(today) as { id: number; title: string; destination: string; start_date: string } | undefined;
    if (!trip) return null;
    const days = Math.ceil((new Date(trip.start_date + "T00:00:00").getTime() - now.getTime()) / 86400000);
    return { ...trip, days_until: days };
  }, null);

  const gartenOffen = safe(() => (db.prepare("SELECT COUNT(*) c FROM garten_aufgaben WHERE COALESCE(erledigt,0)=0 AND monat=? AND (jahr=? OR jahr IS NULL)").get(month, year) as { c: number }).c, 0);
  const vorratBaldAb = safe(() => db.prepare("SELECT id,name,mhd FROM vorrat_lebensmittel WHERE mhd IS NOT NULL AND mhd<>'' AND mhd<=? ORDER BY mhd ASC LIMIT 10").all(in14), []);

  const counts = safe(() => ({
    samu_items: (db.prepare("SELECT COUNT(*) c FROM samu_items WHERE COALESCE(status,'')<>'aussortiert'").get() as { c: number }).c,
    geschenke_offen: (db.prepare("SELECT COUNT(*) c FROM geschenk_geschenke WHERE COALESCE(status,'')<>'vergeben'").get() as { c: number }).c,
    buecher: (db.prepare("SELECT COUNT(*) c FROM elisbooks_books").get() as { c: number }).c,
    vertraege: (db.prepare("SELECT COUNT(*) c FROM vertraege").get() as { c: number }).c,
  }), { samu_items: 0, geschenke_offen: 0, buecher: 0, vertraege: 0 });

  return ok({ date: today, termine_upcoming: termineUpcoming, reminders_due: remindersDue, next_trip: nextTrip, garten_offen: gartenOffen, vorrat_bald_ablaufend: vorratBaldAb, counts });
}
