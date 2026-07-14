import { getDb } from "@/server/db/connection";
import { RESOURCES, pkOf, resourceByKey } from "./registry";
import { textColumns } from "@/server/db/introspect";
import { ftsAvailable, ftsSearch, ftsFuzzy } from "@/server/db/fts";
import { nextPerCategory, abfuhrCategory } from "@/server/abfuhr/abfuhr";

// Geteilte Query-Logik — von REST-Routen UND MCP-Tools genutzt (Single Source of Truth).

const DISPLAY = ["title", "titel", "name", "friendly_name", "bezeichnung", "anbieter", "beschreibung", "problem"];
const display = (row: Record<string, unknown>) => { for (const c of DISPLAY) if (row[c]) return String(row[c]); return ""; };

export interface SearchHit { resource: string; domain: string; label: string; id: unknown; display: string }

/** Normalisiertes Element des vereinheitlichten „Anstehendes"-Feeds (quellenübergreifend). */
export interface AgendaItem {
  source: "termin" | "abfuhr" | "reise" | "vorrat" | "reminder";
  domain: string;              // Gradient/Icon-Key (termine, abfuhrkalender, reisen, vorratskammer, …)
  id: string;                  // stabile Feed-ID, z.B. "termin-5"
  ref_id: number;              // Original-Zeilen-ID (für Aktionen)
  title: string;
  subtitle?: string | null;
  date: string;                // YYYY-MM-DD
  time?: string | null;        // HH:MM (null = ganztägig)
  end_date?: string | null;
  days_until: number | null;
  owner?: string | null;
  done?: boolean;              // geteilter Erledigt-Status
  read?: boolean;              // persönliches „gelesen" (nur wenn owner)
  notify?: boolean;            // persönliches Push-Opt-in (nur wenn owner)
}

/** Datengetriebene KPI-Kachel fürs Home (iOS rendert sie generisch). */
export interface KpiTile { key: string; icon: string; label: string; value: number; domain: string; target: string }

const DAY_MS = 86400000;
/** Ganztägige Tages-Differenz (negativ = vergangen, null = unparsbar). */
function daysUntil(dateStr: string): number | null {
  const d = new Date(dateStr.slice(0, 10) + "T00:00:00");
  if (isNaN(d.getTime())) return null;
  const t0 = new Date(); t0.setHours(0, 0, 0, 0);
  return Math.round((d.getTime() - t0.getTime()) / DAY_MS);
}

/** Cross-Domain-Volltextsuche (FTS5 mit LIKE-Fallback). */
export function searchAll(q: string, domains?: Set<string>): { query: string; engine: string; count: number; results: SearchHit[] } {
  const db = getDb();
  if (ftsAvailable(db)) {
    try {
      const seen = new Set<string>();
      const mapHit = (h: { resource: string; entity_id: string; title: string }): SearchHit | null => {
        const res = resourceByKey(h.resource);
        if (!res || (domains && !domains.has(res.domain))) return null;
        const key = `${h.resource}#${h.entity_id}`;
        if (seen.has(key)) return null;
        seen.add(key);
        return { resource: h.resource, domain: res.domain, label: res.label, id: h.entity_id, display: h.title };
      };
      const exact = ftsSearch(db, q, 300).map(mapHit).filter((x): x is SearchHit => x !== null);
      const fuzzy = ftsFuzzy(db, q, 300).map(mapHit).filter((x): x is SearchHit => x !== null);
      const results = [...exact, ...fuzzy].slice(0, 200);
      return { query: q, engine: fuzzy.length ? "fts5+fuzzy" : "fts5", count: results.length, results };
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

const safeDb = <T>(fn: () => T, fb: T): T => { try { return fn(); } catch { return fb; } };

/**
 * Vereinheitlichter, generischer „Anstehendes"-Feed: mergt Termine (+ per-User-Zustand),
 * Abfuhr, Reisen, bald ablaufende Lebensmittel und die generische `reminders`-Tabelle
 * (per API befüllbar) in eine nach Datum/Zeit sortierte Liste. Fenster: heute .. +`days`
 * (plus wenige Tage rückwirkend, um vergessene offene Punkte sichtbar zu halten).
 */
export function agenda(days = 21, owner?: string | null): AgendaItem[] {
  const db = getDb();
  const win = `+${Math.max(1, Math.min(days, 365))} days`;
  const items: AgendaItem[] = [];

  // ── Termine (offen; leicht rückwirkend für „vergessene") + optional per-User read/notify ──
  const termineSql =
    "SELECT t.id,t.title,t.description,t.category,t.date,t.time,t.end_date,t.person,t.status" +
    (owner ? ", tus.read AS ustate_read, tus.notify AS ustate_notify" : "") +
    " FROM termine t" +
    (owner ? " LEFT JOIN termin_user_state tus ON tus.termin_id=t.id AND tus.owner=@owner" : "") +
    " WHERE t.date IS NOT NULL AND t.date<>'' AND t.date >= date('now','localtime','-7 days')" +
    " AND t.date <= date('now','localtime',@win) AND COALESCE(t.status,'')<>'erledigt'" +
    " ORDER BY t.date ASC, t.time ASC";
  const termineParams = owner ? { owner, win } : { win };
  for (const t of safeDb(() => db.prepare(termineSql).all(termineParams) as Record<string, unknown>[], [])) {
    items.push({
      source: "termin", domain: "termine", id: `termin-${t.id}`, ref_id: Number(t.id),
      title: String(t.title ?? ""),
      subtitle: (t.person ? String(t.person) : null),
      date: String(t.date), time: (t.time ? String(t.time) : null), end_date: (t.end_date ? String(t.end_date) : null),
      days_until: daysUntil(String(t.date)), done: false,
      read: owner ? !!Number(t.ustate_read ?? 0) : undefined,
      notify: owner ? !!Number(t.ustate_notify ?? 0) : undefined,
    });
  }

  // ── Abfuhr ──
  for (const a of safeDb(() => db.prepare(
    "SELECT id,kategorie,summary,datum FROM abfuhr_termine WHERE datum >= date('now','localtime') AND datum <= date('now','localtime',@win) ORDER BY datum ASC",
  ).all({ win }) as Record<string, unknown>[], [])) {
    const cat = abfuhrCategory(String(a.kategorie));
    items.push({
      source: "abfuhr", domain: "abfuhrkalender", id: `abfuhr-${a.id}`, ref_id: Number(a.id),
      title: `${cat?.emoji ?? "🗑️"} ${cat?.label ?? a.summary ?? a.kategorie}`,
      date: String(a.datum), time: null, days_until: daysUntil(String(a.datum)),
    });
  }

  // ── Reisen (Recherche-/Ideen-Trips status='idee' ausblenden) ──
  for (const r of safeDb(() => db.prepare(
    "SELECT id,title,destination,start_date,end_date FROM reisen_trips WHERE start_date IS NOT NULL AND start_date<>'' AND COALESCE(status,'')<>'idee' AND start_date >= date('now','localtime') AND start_date <= date('now','localtime',@win) ORDER BY start_date ASC",
  ).all({ win }) as Record<string, unknown>[], [])) {
    items.push({
      source: "reise", domain: "reisen", id: `reise-${r.id}`, ref_id: Number(r.id),
      title: `${r.title}`, subtitle: (r.destination ? String(r.destination) : null),
      date: String(r.start_date), time: null, end_date: (r.end_date ? String(r.end_date) : null),
      days_until: daysUntil(String(r.start_date)),
    });
  }

  // ── Bald ablaufende Lebensmittel (MHD) ──
  for (const v of safeDb(() => db.prepare(
    "SELECT id,name,mhd FROM vorrat_lebensmittel WHERE mhd IS NOT NULL AND mhd<>'' AND mhd >= date('now','localtime','-3 days') AND mhd <= date('now','localtime',@win) AND COALESCE(status,'')<>'verbraucht' ORDER BY mhd ASC",
  ).all({ win }) as Record<string, unknown>[], [])) {
    items.push({
      source: "vorrat", domain: "vorratskammer", id: `vorrat-${v.id}`, ref_id: Number(v.id),
      title: String(v.name ?? ""), subtitle: "MHD", date: String(v.mhd), time: null,
      days_until: daysUntil(String(v.mhd)),
    });
  }

  // ── Generische Erinnerungen (per API injizierbar); Familie (owner NULL) + eigene ──
  const remSql =
    "SELECT id,title,body,date,time,domain,owner FROM reminders WHERE status='offen' AND date IS NOT NULL AND date<>''" +
    " AND date >= date('now','localtime','-7 days') AND date <= date('now','localtime',@win)" +
    (owner ? " AND (owner IS NULL OR owner=@owner)" : "") +
    " ORDER BY date ASC";
  for (const r of safeDb(() => db.prepare(remSql).all(owner ? { owner, win } : { win }) as Record<string, unknown>[], [])) {
    items.push({
      source: "reminder", domain: (r.domain ? String(r.domain) : "termine"), id: `reminder-${r.id}`, ref_id: Number(r.id),
      title: String(r.title ?? ""), subtitle: (r.body ? String(r.body) : null),
      date: String(r.date), time: (r.time ? String(r.time) : null),
      days_until: daysUntil(String(r.date)), owner: (r.owner ? String(r.owner) : null),
    });
  }

  return items.sort((a, b) => (a.date === b.date ? (a.time ?? "").localeCompare(b.time ?? "") : a.date.localeCompare(b.date)));
}

/** Kompakter Tageszustand (KPI-Kacheln + Agenda). `owner` = Per-User-Sicht (aus dem API-Key). */
export function dashboardToday(owner?: string | null): Record<string, unknown> {
  const db = getDb();
  const safe = safeDb;
  const month = new Date().getMonth() + 1;
  const year = new Date().getFullYear();
  const num = (sql: string, ...p: unknown[]) => safe(() => (db.prepare(sql).get(...p) as { c: number }).c, 0);

  const termineUpcoming = safe(() => db.prepare(
    "SELECT id,title,date,time,category FROM termine WHERE date >= date('now') AND COALESCE(status,'')<>'erledigt' ORDER BY date ASC, time ASC LIMIT 15",
  ).all(), []);

  const remindersDueCount = remindersDue(owner).count;

  const nextTrip = safe(() => {
    const trip = db.prepare("SELECT id,title,destination,start_date, CAST(julianday(start_date)-julianday('now') AS INTEGER) AS days_until FROM reisen_trips WHERE start_date>=date('now') AND COALESCE(status,'')<>'idee' ORDER BY start_date ASC LIMIT 1").get() as Record<string, unknown> | undefined;
    return trip ?? null;
  }, null);

  const gartenOffen = num("SELECT COUNT(*) c FROM garten_aufgaben WHERE COALESCE(erledigt,0)=0 AND monat=? AND (jahr=? OR jahr IS NULL)", month, year);
  const vorratBaldAb = safe(() => db.prepare("SELECT id,name,mhd FROM vorrat_lebensmittel WHERE mhd IS NOT NULL AND mhd<>'' AND mhd<=date('now','+14 days') AND COALESCE(status,'')<>'verbraucht' ORDER BY mhd ASC LIMIT 10").all(), []);
  const abfuhrNext = safe(() => nextPerCategory(db).filter((n) => n.datum), [] as unknown[]);

  // KPI-Rohwerte
  const termine7d = num("SELECT COUNT(*) c FROM termine WHERE date BETWEEN date('now') AND date('now','+7 days') AND COALESCE(status,'')<>'erledigt'");
  const vorratAblaufend = num("SELECT COUNT(*) c FROM vorrat_lebensmittel WHERE mhd IS NOT NULL AND mhd<>'' AND mhd<=date('now','+14 days') AND COALESCE(status,'')<>'verbraucht'");
  const reinigerNachkauf = num("SELECT COUNT(*) c FROM reiniger_produkte WHERE status IN ('leer','nachkaufen')");
  const vorratNachkauf = num("SELECT COUNT(*) c FROM vorrat_lebensmittel WHERE COALESCE(restock,0)=1");
  // Geschenke-KPI: anstehende Anlässe der nächsten 3 Monate (aussagekräftiger als die reine Ideen-Zahl).
  const geschenkAnlaesse3M = num(
    "SELECT COUNT(*) c FROM geschenk_ereignisse WHERE datum>=date('now') AND datum<=date('now','+3 months')",
  );
  // Offene Geschenk-Ideen für zukünftige Anlässe (nur noch für counts.geschenke_offen; keine KPI-Kachel mehr).
  const geschenkeZukunft = num(
    "SELECT COUNT(*) c FROM geschenk_geschenke g JOIN geschenk_ereignisse e ON g.ereignis_id=e.id WHERE COALESCE(g.status,'')<>'vergeben' AND e.datum>=date('now')",
  );
  const fotoInboxNeu = num("SELECT COUNT(*) c FROM foto_inbox WHERE status='neu'");

  const counts = safe(() => ({
    samu_items: num("SELECT COUNT(*) c FROM samu_items WHERE COALESCE(status,'')<>'aussortiert'"),
    geschenke_offen: geschenkeZukunft, // konsistent mit KPI (WidgetKit zeigt sinnvolle Zahl)
    buecher: num("SELECT COUNT(*) c FROM elisbooks_books"),
    vertraege: num("SELECT COUNT(*) c FROM vertraege"),
    foto_inbox_neu: fotoInboxNeu,
  }), { samu_items: 0, geschenke_offen: 0, buecher: 0, vertraege: 0, foto_inbox_neu: 0 });

  // „Aktions-Fokus (6)" — datengetrieben; iOS rendert die Kacheln generisch und macht sie antippbar.
  const kpis: KpiTile[] = [
    { key: "foto", icon: "tray.full.fill", label: "Neue Fotos", value: fotoInboxNeu, domain: "foto", target: "inbox" },
    { key: "termine", icon: "calendar", label: "Anstehende Termine", value: termine7d, domain: "termine", target: "bereich:termine" },
    { key: "reminders", icon: "bell.badge.fill", label: "Erinnerungen", value: remindersDueCount, domain: "termine", target: "heute" },
    { key: "vorrat", icon: "clock.badge.exclamationmark", label: "Bald ablaufend", value: vorratAblaufend, domain: "vorratskammer", target: "bereich:vorratskammer" },
    { key: "nachkaufen", icon: "cart.fill", label: "Nachkaufen", value: reinigerNachkauf + vorratNachkauf, domain: "reiniger", target: "bereich:reiniger" },
    { key: "geschenke", icon: "gift.fill", label: "Geschenk-Anlässe", value: geschenkAnlaesse3M, domain: "geschenkplaner", target: "bereich:geschenkplaner" },
  ];

  return {
    date: new Date().toISOString().slice(0, 10),
    kpis,
    agenda: safe(() => agenda(30, owner), []),
    // Legacy-Keys (WidgetKit / ältere Clients) unverändert beibehalten:
    termine_upcoming: termineUpcoming,
    reminders_due: remindersDueCount,
    next_trip: nextTrip,
    garten_offen: gartenOffen,
    vorrat_bald_ablaufend: vorratBaldAb,
    abfuhr_next: abfuhrNext,
    counts,
  };
}

/** Fällige Erinnerungen: Termine (Fenster [date - reminder_days, date]) + generische reminders (heute fällig).
 *  `owner` (Per-User-Key) → generische reminders auf Familie (owner NULL) + eigene beschränken (Termine bleiben geteilt). */
export function remindersDue(owner?: string | null): { count: number; data: Record<string, unknown>[] } {
  const db = getDb();
  const rows = db.prepare(
    "SELECT * FROM termine WHERE COALESCE(reminder_sent,0)=0 AND COALESCE(status,'')<>'erledigt' AND date IS NOT NULL AND date<>''",
  ).all() as { id: number; title: string; date: string; reminder_days?: number }[];
  const today = new Date(); today.setHours(0, 0, 0, 0);
  const dueTermine = rows.filter((t) => {
    const d = new Date(t.date + "T00:00:00");
    if (isNaN(d.getTime())) return false;
    const ws = new Date(d); ws.setDate(d.getDate() - (t.reminder_days ?? 0));
    return today >= ws && today <= d;
  }).map((t) => ({ ...t, source: "termin" }));
  const remSql = "SELECT id,title,body,date,time,domain,owner FROM reminders WHERE status='offen' AND date IS NOT NULL AND date<>'' AND date<=date('now','localtime')"
    + (owner ? " AND (owner IS NULL OR owner=@owner)" : "");
  const dueReminders = safeDb(() => (owner ? db.prepare(remSql).all({ owner }) : db.prepare(remSql).all()) as Record<string, unknown>[], [])
    .map((r) => ({ ...r, source: "reminder" }));
  const data = [...dueTermine, ...dueReminders] as unknown as Record<string, unknown>[];
  data.sort((a, b) => String(a.date).localeCompare(String(b.date)));
  return { count: data.length, data };
}
