import { getDb } from "@/server/db/connection";
import { RESOURCES, pkOf, resourceByKey } from "./registry";
import { textColumns } from "@/server/db/introspect";
import { ftsAvailable, ftsSearch } from "@/server/db/fts";

// Geteilte Query-Logik — von REST-Routen UND MCP-Tools genutzt (Single Source of Truth).

const DISPLAY = ["title", "titel", "name", "friendly_name", "bezeichnung", "anbieter", "beschreibung", "problem"];
const display = (row: Record<string, unknown>) => { for (const c of DISPLAY) if (row[c]) return String(row[c]); return ""; };

export interface SearchHit { resource: string; domain: string; label: string; id: unknown; display: string }

/** Cross-Domain-Volltextsuche (FTS5 mit LIKE-Fallback). */
export function searchAll(q: string, domains?: Set<string>): { query: string; engine: string; count: number; results: SearchHit[] } {
  const db = getDb();
  if (ftsAvailable(db)) {
    try {
      const hits = ftsSearch(db, q, 300);
      const results = hits
        .map((h) => ({ res: resourceByKey(h.resource), h }))
        .filter(({ res }) => res && (!domains || domains.has(res.domain)))
        .slice(0, 200)
        .map(({ res, h }) => ({ resource: h.resource, domain: res!.domain, label: res!.label, id: h.entity_id, display: h.title }));
      return { query: q, engine: "fts5", count: results.length, results };
    } catch { /* Fallback */ }
  }
  const results: SearchHit[] = [];
  for (const r of RESOURCES) {
    if (domains && !domains.has(r.domain)) continue;
    const cols = r.searchable ?? textColumns(db, r.table);
    if (!cols.length) continue;
    const whereSql = "(" + cols.map((c) => `"${c}" LIKE ?`).join(" OR ") + ")";
    const params = cols.map(() => `%${q}%`);
    try {
      const rows = db.prepare(`SELECT * FROM "${r.table}" WHERE ${whereSql} LIMIT 8`).all(...params) as Record<string, unknown>[];
      for (const row of rows) results.push({ resource: r.key, domain: r.domain, label: r.label, id: row[pkOf(r)], display: display(row) });
    } catch { /* skip */ }
    if (results.length >= 200) break;
  }
  return { query: q, engine: "like", count: results.length, results };
}

/** Kompakter Tageszustand. */
export function dashboardToday(): Record<string, unknown> {
  const db = getDb();
  const safe = <T>(fn: () => T, fb: T): T => { try { return fn(); } catch { return fb; } };
  const month = new Date().getMonth() + 1;
  const year = new Date().getFullYear();

  const termineUpcoming = safe(() => db.prepare(
    "SELECT id,title,date,time,category FROM termine WHERE date >= date('now') AND COALESCE(status,'')<>'erledigt' ORDER BY date ASC, time ASC LIMIT 15",
  ).all(), []);

  const remindersDueCount = remindersDue().count;

  const nextTrip = safe(() => {
    const trip = db.prepare("SELECT id,title,destination,start_date, CAST(julianday(start_date)-julianday('now') AS INTEGER) AS days_until FROM reisen_trips WHERE start_date>=date('now') ORDER BY start_date ASC LIMIT 1").get() as Record<string, unknown> | undefined;
    return trip ?? null;
  }, null);

  const gartenOffen = safe(() => (db.prepare("SELECT COUNT(*) c FROM garten_aufgaben WHERE COALESCE(erledigt,0)=0 AND monat=? AND (jahr=? OR jahr IS NULL)").get(month, year) as { c: number }).c, 0);
  const vorratBaldAb = safe(() => db.prepare("SELECT id,name,mhd FROM vorrat_lebensmittel WHERE mhd IS NOT NULL AND mhd<>'' AND mhd<=date('now','+14 days') ORDER BY mhd ASC LIMIT 10").all(), []);

  const counts = safe(() => ({
    samu_items: (db.prepare("SELECT COUNT(*) c FROM samu_items WHERE COALESCE(status,'')<>'aussortiert'").get() as { c: number }).c,
    geschenke_offen: (db.prepare("SELECT COUNT(*) c FROM geschenk_geschenke WHERE COALESCE(status,'')<>'vergeben'").get() as { c: number }).c,
    buecher: (db.prepare("SELECT COUNT(*) c FROM elisbooks_books").get() as { c: number }).c,
    vertraege: (db.prepare("SELECT COUNT(*) c FROM vertraege").get() as { c: number }).c,
    foto_inbox_neu: (db.prepare("SELECT COUNT(*) c FROM foto_inbox WHERE status='neu'").get() as { c: number }).c,
  }), { samu_items: 0, geschenke_offen: 0, buecher: 0, vertraege: 0, foto_inbox_neu: 0 });

  return { date: new Date().toISOString().slice(0, 10), termine_upcoming: termineUpcoming, reminders_due: remindersDueCount, next_trip: nextTrip, garten_offen: gartenOffen, vorrat_bald_ablaufend: vorratBaldAb, counts };
}

/** Fällige Termin-Erinnerungen (heute im Fenster [date - reminder_days, date]). */
export function remindersDue(): { count: number; data: Record<string, unknown>[] } {
  const db = getDb();
  const rows = db.prepare(
    "SELECT * FROM termine WHERE COALESCE(reminder_sent,0)=0 AND COALESCE(status,'')<>'erledigt' AND date IS NOT NULL AND date<>''",
  ).all() as { id: number; title: string; date: string; reminder_days?: number }[];
  const today = new Date(); today.setHours(0, 0, 0, 0);
  const due = rows.filter((t) => {
    const d = new Date(t.date + "T00:00:00");
    if (isNaN(d.getTime())) return false;
    const ws = new Date(d); ws.setDate(d.getDate() - (t.reminder_days ?? 0));
    return today >= ws && today <= d;
  }).sort((a, b) => a.date.localeCompare(b.date));
  return { count: due.length, data: due as unknown as Record<string, unknown>[] };
}
