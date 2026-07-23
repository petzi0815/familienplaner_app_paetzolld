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
  location?: string | null;    // Ort (Freitext) — auf dem Dashboard antippbar → Google Maps
  date: string;                // YYYY-MM-DD
  time?: string | null;        // HH:MM (null = ganztägig)
  end_date?: string | null;
  days_until: number | null;
  owner?: string | null;
  done?: boolean;              // geteilter Erledigt-Status
  read?: boolean;              // persönliches „gelesen" (nur wenn owner)
  notify?: boolean;            // persönliches Push-Opt-in (nur wenn owner)
  // ── additiv (Widgets/Live Activity): absolute Zeitpunkte + Kategorie/Stummschaltung ──
  start_at?: number;           // Unix-Sekunden des Beginns (Wanduhrzeit Europe/Berlin → UTC)
  end_at?: number | null;      // Unix-Sekunden des Endes (null = unbekannt)
  all_day?: boolean;           // ganztägig (keine Uhrzeit) → start_at = 00:00 lokal
  category?: string | null;    // Quell-Kategorie (Termin-Kategorie, Abfuhr-Kategorie …) für Emoji/Farbe
  muted?: boolean;             // persönlich stummgeschaltet (nur wenn owner, nur Termine)
}

/** Datengetriebene KPI-Kachel fürs Home (iOS rendert sie generisch). */
export interface KpiTile { key: string; icon: string; label: string; value: number; domain: string; target: string }

/** Normalisiertes Element des Aufgaben-Feeds (Familien-Aufgaben + fällige Garten-Aufgaben). */
export interface TaskItem {
  source: "aufgabe" | "garten";
  domain: string;              // Gradient/Icon-Key ("aufgaben" | "garten")
  id: string;                  // stabile Feed-ID, z.B. "aufgabe-5" / "garten-12"
  ref_id: number;              // Original-Zeilen-ID (für /complete bzw. PATCH)
  title: string;
  description?: string | null;
  owner?: string | null;       // Zuständig: 'lars' | 'elita' | 'familie' (garten: null)
  due_date?: string | null;    // YYYY-MM-DD (aufgabe; garten ist monatsbasiert → null)
  due_label?: string | null;   // menschenlesbare Fälligkeit (garten: "März 2026")
  days_until?: number | null;
  overdue: boolean;
  status: string;              // offen | erledigt
  priority?: string | null;    // niedrig | normal | hoch
  recurring?: string | null;   // einmalig | taeglich | woechentlich | monatlich | jaehrlich (garten: wiederholung)
  project?: string | null;
  termin_id?: number | null;   // optionale Verknüpfung zu einem Termin
  done_at?: string | null;     // Erledigt-Zeitpunkt (nur im Erledigt-Feed gesetzt)
}

const MONTHS_DE = ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember"];
const monthLabel = (m: number, y: number): string => `${MONTHS_DE[Math.max(1, Math.min(12, m)) - 1]} ${y}`;

const DAY_MS = 86400000;

// ── Wanduhrzeit → Unix-Sekunden (Europe/Berlin) ────────────────────────────────────────────────
// ANNAHME zur Serverzeitzone: die DB hält AUSSCHLIESSLICH lokale Datums-/Zeitstrings der Familie
// (YYYY-MM-DD / HH:MM in Europe/Berlin), die Prozess-Zeitzone des Containers ist aber NICHT gesetzt
// (Coolify/Node ⇒ i.d.R. UTC). `new Date("2026-07-24T15:45:00")` würde also je nach Host anders
// auflösen. Darum rechnen wir explizit über `Intl` mit der IANA-Zone „Europe/Berlin" — unabhängig
// von der Prozess-Zeitzone, inkl. Sommer-/Winterzeit.
const BERLIN_TZ = "Europe/Berlin";
const BERLIN_FMT = new Intl.DateTimeFormat("en-US", {
  timeZone: BERLIN_TZ, hour12: false,
  year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", second: "2-digit",
});

/** UTC-Offset (Sekunden) von Europe/Berlin zum gegebenen absoluten Zeitpunkt. */
function berlinOffsetSeconds(utcMs: number): number {
  const parts = BERLIN_FMT.formatToParts(new Date(utcMs));
  const get = (t: string) => Number(parts.find((p) => p.type === t)?.value ?? 0);
  const hour = get("hour") % 24; // manche Engines liefern "24" für Mitternacht
  const asUtc = Date.UTC(get("year"), get("month") - 1, get("day"), hour, get("minute"), get("second"));
  return Math.round((asUtc - utcMs) / 1000);
}

/**
 * Lokale Wanduhrzeit (Europe/Berlin) → Unix-Sekunden. `time` leer/null ⇒ 00:00 (ganztägig).
 * Zwei Durchläufe, damit auch die DST-Umschalttage korrekt sind (Offset am Zieltag, nicht am Rohwert).
 */
function berlinEpoch(date?: string | null, time?: string | null): number | undefined {
  if (!date) return undefined;
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(date).slice(0, 10));
  if (!m) return undefined;
  const hm = /^(\d{1,2}):(\d{2})/.exec(String(time ?? "").trim());
  const naive = Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]), hm ? Number(hm[1]) : 0, hm ? Number(hm[2]) : 0, 0);
  if (isNaN(naive)) return undefined;
  let ts = Math.round(naive / 1000) - berlinOffsetSeconds(naive);
  ts = Math.round(naive / 1000) - berlinOffsetSeconds(ts * 1000);
  return ts;
}

/** Heutiges Datum ('YYYY-MM-DD') in Europe/Berlin — unabhängig von der Prozess-Zeitzone (Container = UTC). */
function berlinToday(utcMs: number = Date.now()): string {
  const parts = BERLIN_FMT.formatToParts(new Date(utcMs));
  const get = (t: string) => parts.find((p) => p.type === t)?.value ?? "";
  return `${get("year")}-${get("month")}-${get("day")}`;
}

/** Jahr + Monat (1–12) von HEUTE in Europe/Berlin — gemeinsame Basis für monatsbasierte Abfragen. */
function berlinYearMonth(utcMs: number = Date.now()): { y: number; mo: number } {
  const t = berlinToday(utcMs);
  return { y: Number(t.slice(0, 4)), mo: Number(t.slice(5, 7)) };
}

/** 'YYYY-MM-DD' → UTC-Mitternacht in ms (reiner Kalenderwert, KEIN Zeitzonenbezug). */
function calendarMs(dateStr: string): number | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(dateStr).slice(0, 10));
  if (!m) return null;
  const ms = Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
  return isNaN(ms) ? null : ms;
}

/**
 * Ganztägige Tages-Differenz zu HEUTE in Europe/Berlin (negativ = vergangen, null = unparsbar).
 * Bewusst reine UTC-Kalenderarithmetik auf beiden Seiten (⇒ DST-unabhängig) mit dem Berliner
 * Heute-Datum als Basis — sonst driften `days_until` und `start_at`/`berlinEpoch` zwischen
 * 00:00 und 02:00 Berliner Zeit um einen Tag auseinander (Container läuft in UTC).
 */
function daysUntil(dateStr: string): number | null {
  const target = calendarMs(dateStr);
  const today = calendarMs(berlinToday());
  if (target == null || today == null) return null;
  return Math.round((target - today) / DAY_MS);
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
  // Fenstergrenzen gegen das BERLINER Heute rechnen (nicht `date('now','localtime')` — die
  // Prozess-Zeitzone des Containers ist UTC, das Fenster läge zwischen 00:00 und 02:00 Berliner
  // Zeit sonst einen Tag daneben und driftete gegen `days_until`/`start_at`).
  const today = berlinToday();
  const items: AgendaItem[] = [];

  // ── Termine (offen; leicht rückwirkend für „vergessene") + optional per-User read/notify/muted ──
  const termineSql =
    "SELECT t.id,t.title,t.description,t.category,t.date,t.time,t.end_date,t.end_time,t.location,t.person,t.status" +
    (owner ? ", tus.read AS ustate_read, tus.notify AS ustate_notify, tus.muted AS ustate_muted" : "") +
    " FROM termine t" +
    (owner ? " LEFT JOIN termin_user_state tus ON tus.termin_id=t.id AND tus.owner=@owner" : "") +
    " WHERE t.date IS NOT NULL AND t.date<>'' AND COALESCE(t.status,'')<>'erledigt'" +
    // Im Fenster beginnend ODER bereits laufend: ein am 20. gestarteter, bis zum 25. laufender
    // Termin muss sichtbar bleiben, auch wenn sein Startdatum aus dem Rückwärts-Fenster fällt.
    " AND ((t.date >= date(@today,'-7 days') AND t.date <= date(@today,@win))" +
    "   OR (t.end_date IS NOT NULL AND t.end_date<>'' AND t.date <= date(@today,@win)" +
    "       AND t.end_date >= @today))" +
    " ORDER BY t.date ASC, t.time ASC";
  const termineParams = owner ? { owner, win, today } : { win, today };
  for (const t of safeDb(() => db.prepare(termineSql).all(termineParams) as Record<string, unknown>[], [])) {
    const time = t.time ? String(t.time).slice(0, 5) : null;
    const endTime = t.end_time ? String(t.end_time).slice(0, 5) : null;
    const endDate = t.end_date ? String(t.end_date) : null;
    // Ende: `end_time` gewinnt (am `end_date`, sonst am Starttag); ohne `end_time` bleibt es bei
    // 00:00 des Endtages — diesen Tag zählt der Client inklusive mit (WidgetTermin.swift::allDayEnd).
    // ENTSCHEIDEND ist die Absicherung danach: das iOS-Formular schreibt NUR ein End-DATUM (nie eine
    // End-ZEIT). Bei einem GETIMTEN Termin mit end_date = Starttag ergäbe die Formel 00:00 des
    // Starttages, also ein Ende VOR dem Beginn — der Termin gälte den ganzen Tag als vorbei und
    // verschwände aus allen Widgets (vgl. server/jobs/registry.ts::terminWindow, das `end` darum
    // ausschliesslich aus `end_time` ableitet).
    const startAt = berlinEpoch(String(t.date), time);
    const endRaw = endTime ? berlinEpoch(endDate ?? String(t.date), endTime)
      : (endDate ? berlinEpoch(endDate, null) : undefined);
    // Ein Ende, das nicht NACH dem Beginn liegt, ist kein Ende. Fängt genau den obigen Fall ab und
    // ausserdem den ganztägigen Ein-Tages-Termin (end == start ⇒ null, der Client fällt ohnehin auf
    // den Starttag zurück). Ein GETIMTER MEHRTÄGIGER Termin behält bewusst 00:00 des Endtages —
    // sonst wäre er im Widget nach einer Stunde am ersten Tag „vorbei".
    const endAt = endRaw != null && startAt != null && endRaw <= startAt ? null : (endRaw ?? null);
    items.push({
      source: "termin", domain: "termine", id: `termin-${t.id}`, ref_id: Number(t.id),
      title: String(t.title ?? ""),
      subtitle: (t.person ? String(t.person) : null),
      location: (t.location ? String(t.location) : null),
      date: String(t.date), time, end_date: (t.end_date ? String(t.end_date) : null),
      days_until: daysUntil(String(t.date)), done: false,
      read: owner ? !!Number(t.ustate_read ?? 0) : undefined,
      notify: owner ? !!Number(t.ustate_notify ?? 0) : undefined,
      start_at: startAt,
      end_at: endAt,
      all_day: !time,
      category: (t.category ? String(t.category) : null),
      muted: owner ? !!Number(t.ustate_muted ?? 0) : undefined,
    });
  }

  // ── Abfuhr ──
  for (const a of safeDb(() => db.prepare(
    "SELECT id,kategorie,summary,datum FROM abfuhr_termine WHERE datum >= @today AND datum <= date(@today,@win) ORDER BY datum ASC",
  ).all({ win, today }) as Record<string, unknown>[], [])) {
    const cat = abfuhrCategory(String(a.kategorie));
    items.push({
      source: "abfuhr", domain: "abfuhrkalender", id: `abfuhr-${a.id}`, ref_id: Number(a.id),
      title: `${cat?.emoji ?? "🗑️"} ${cat?.label ?? a.summary ?? a.kategorie}`,
      date: String(a.datum), time: null, days_until: daysUntil(String(a.datum)),
      start_at: berlinEpoch(String(a.datum), null), end_at: null, all_day: true,
      category: (a.kategorie ? String(a.kategorie) : null),
    });
  }

  // ── Reisen (Recherche-/Ideen-Trips status='idee' ausblenden) ──
  for (const r of safeDb(() => db.prepare(
    "SELECT id,title,destination,start_date,end_date FROM reisen_trips WHERE start_date IS NOT NULL AND start_date<>'' AND COALESCE(status,'')<>'idee' AND start_date >= @today AND start_date <= date(@today,@win) ORDER BY start_date ASC",
  ).all({ win, today }) as Record<string, unknown>[], [])) {
    items.push({
      source: "reise", domain: "reisen", id: `reise-${r.id}`, ref_id: Number(r.id),
      title: `${r.title}`, subtitle: (r.destination ? String(r.destination) : null),
      date: String(r.start_date), time: null, end_date: (r.end_date ? String(r.end_date) : null),
      days_until: daysUntil(String(r.start_date)),
      start_at: berlinEpoch(String(r.start_date), null),
      end_at: berlinEpoch(r.end_date ? String(r.end_date) : null, null) ?? null,
      all_day: true, category: null,
    });
  }

  // (Bald ablaufende Lebensmittel laufen NICHT mehr über die Agenda — sie haben auf dem Dashboard
  //  eine eigene „Bald ablaufend"-Sektion, sonst doppelt sichtbar. Siehe dashboardToday.vorrat_bald_ablaufend.)

  // ── Generische Erinnerungen (per API injizierbar); Familie (owner NULL) + eigene ──
  const remSql =
    "SELECT id,title,body,date,time,domain,owner FROM reminders WHERE status='offen' AND date IS NOT NULL AND date<>''" +
    " AND date >= date(@today,'-7 days') AND date <= date(@today,@win)" +
    (owner ? " AND (owner IS NULL OR owner=@owner)" : "") +
    " ORDER BY date ASC";
  for (const r of safeDb(() => db.prepare(remSql).all(owner ? { owner, win, today } : { win, today }) as Record<string, unknown>[], [])) {
    const time = r.time ? String(r.time) : null;
    items.push({
      source: "reminder", domain: (r.domain ? String(r.domain) : "termine"), id: `reminder-${r.id}`, ref_id: Number(r.id),
      title: String(r.title ?? ""), subtitle: (r.body ? String(r.body) : null),
      date: String(r.date), time,
      days_until: daysUntil(String(r.date)), owner: (r.owner ? String(r.owner) : null),
      start_at: berlinEpoch(String(r.date), time), end_at: null, all_day: !time,
      category: (r.domain ? String(r.domain) : null),
    });
  }

  return items.sort((a, b) => (a.date === b.date ? (a.time ?? "").localeCompare(b.time ?? "") : a.date.localeCompare(b.date)));
}

/**
 * Aufgaben-Feed fürs Home: mergt die generische `aufgaben`-Tabelle (offen; per API/Ole befüllbar) mit
 * den FÄLLIGEN offenen Garten-Aufgaben (aktueller Monat oder überfällig). Überfällige zuerst, dann nach
 * Fälligkeit. Garten-Aufgaben sind monatsbasiert (kein Tagesdatum) → `due_label` „Monat Jahr".
 */
export function aufgabenFeed(): TaskItem[] {
  const db = getDb();
  const items: TaskItem[] = [];
  const { y, mo } = berlinYearMonth(); // Monatswechsel nach Berliner Kalender, nicht nach UTC

  // ── Familien-Aufgaben (offen) ──
  for (const a of safeDb(() => db.prepare(
    "SELECT id,title,description,owner,due_date,termin_id,project,priority,recurring FROM aufgaben WHERE status='offen'",
  ).all() as Record<string, unknown>[], [])) {
    const due = a.due_date ? String(a.due_date) : null;
    const du = due ? daysUntil(due) : null;
    items.push({
      source: "aufgabe", domain: "aufgaben", id: `aufgabe-${a.id}`, ref_id: Number(a.id),
      title: String(a.title ?? ""),
      description: (a.description ? String(a.description) : null),
      owner: (a.owner ? String(a.owner) : null),
      due_date: due, due_label: null,
      days_until: du, overdue: du != null && du < 0,
      status: "offen",
      priority: (a.priority ? String(a.priority) : null),
      recurring: (a.recurring ? String(a.recurring) : null),
      project: (a.project ? String(a.project) : null),
      termin_id: (a.termin_id != null ? Number(a.termin_id) : null),
    });
  }

  // ── Garten-Aufgaben des AKTUELLEN Monats (offen). Ältere Monate bewusst NICHT, sonst flutet der
  //    nie-abgehakte Jahresplan das Dashboard (Pflanzfenster sind ohnehin vorbei). „Diesen Monat im Garten". ──
  for (const g of safeDb(() => db.prepare(
    "SELECT id,titel,beschreibung,monat,jahr,prioritaet,wiederholung FROM garten_aufgaben WHERE COALESCE(erledigt,0)=0 AND jahr = @y AND monat = @mo",
  ).all({ y, mo }) as Record<string, unknown>[], [])) {
    items.push({
      source: "garten", domain: "garten", id: `garten-${g.id}`, ref_id: Number(g.id),
      title: String(g.titel ?? ""),
      description: (g.beschreibung ? String(g.beschreibung) : null),
      owner: null,
      due_date: null, due_label: monthLabel(mo, y),
      days_until: null, overdue: false,
      status: "offen",
      priority: (g.prioritaet ? String(g.prioritaet) : null),
      recurring: (g.wiederholung ? String(g.wiederholung) : null),
      project: "Garten",
      termin_id: null,
    });
  }

  // Reihenfolge: überfällig zuerst, dann Familien-Aufgaben vor Garten (Garten = hilfreiche Beigabe),
  // dann nach Priorität (hoch→niedrig), dann datierte nach Fälligkeit.
  const prioRank = (p?: string | null) => (p === "hoch" ? 0 : p === "niedrig" ? 2 : 1);
  const srcRank = (s: string) => (s === "aufgabe" ? 0 : 1);
  return items.sort((a, b) => {
    if (a.overdue !== b.overdue) return a.overdue ? -1 : 1;
    if (srcRank(a.source) !== srcRank(b.source)) return srcRank(a.source) - srcRank(b.source);
    if (prioRank(a.priority) !== prioRank(b.priority)) return prioRank(a.priority) - prioRank(b.priority);
    return (a.due_date ?? "9999-99-99").localeCompare(b.due_date ?? "9999-99-99");
  });
}

/**
 * Kürzlich ERLEDIGTE Aufgaben (Familie + Garten) — für die „Erledigt"-Ansicht auf dem Dashboard, damit
 * man versehentlich Abgehaktes wieder öffnen kann. Nur die letzten `days` Tage, neueste zuerst, gedeckelt.
 */
export function aufgabenErledigt(days = 30, limit = 25): TaskItem[] {
  const db = getDb();
  const items: TaskItem[] = [];
  const cut = `-${Math.max(1, Math.min(days, 365))} days`;
  const { y, mo } = berlinYearMonth(); // konsistent zu aufgabenFeed()

  for (const a of safeDb(() => db.prepare(
    "SELECT id,title,description,owner,due_date,termin_id,project,priority,recurring,done_at FROM aufgaben WHERE status='erledigt' AND done_at IS NOT NULL AND done_at >= date('now',@cut) ORDER BY done_at DESC LIMIT @limit",
  ).all({ cut, limit }) as Record<string, unknown>[], [])) {
    items.push({
      source: "aufgabe", domain: "aufgaben", id: `aufgabe-${a.id}`, ref_id: Number(a.id),
      title: String(a.title ?? ""), description: (a.description ? String(a.description) : null),
      owner: (a.owner ? String(a.owner) : null),
      due_date: (a.due_date ? String(a.due_date) : null), due_label: null,
      days_until: null, overdue: false, status: "erledigt",
      priority: (a.priority ? String(a.priority) : null),
      recurring: (a.recurring ? String(a.recurring) : null),
      project: (a.project ? String(a.project) : null),
      termin_id: (a.termin_id != null ? Number(a.termin_id) : null),
      done_at: (a.done_at ? String(a.done_at) : null),
    });
  }
  // Nur Garten-Aufgaben des AKTUELLEN Monats — konsistent mit dem Offen-Feed (der auch nur den aktuellen
  // Monat zeigt), damit das Wieder-Öffnen sie zuverlässig zurück in „Offen" bringt (kein Verschwinden).
  for (const g of safeDb(() => db.prepare(
    "SELECT id,titel,beschreibung,monat,jahr,prioritaet,wiederholung,erledigt_am FROM garten_aufgaben WHERE COALESCE(erledigt,0)=1 AND jahr=@y AND monat=@mo ORDER BY erledigt_am DESC LIMIT @limit",
  ).all({ y, mo, limit }) as Record<string, unknown>[], [])) {
    items.push({
      source: "garten", domain: "garten", id: `garten-${g.id}`, ref_id: Number(g.id),
      title: String(g.titel ?? ""), description: (g.beschreibung ? String(g.beschreibung) : null),
      owner: null, due_date: null, due_label: monthLabel(Number(g.monat), Number(g.jahr)),
      days_until: null, overdue: false, status: "erledigt",
      priority: (g.prioritaet ? String(g.prioritaet) : null),
      recurring: (g.wiederholung ? String(g.wiederholung) : null),
      project: "Garten", termin_id: null,
      done_at: (g.erledigt_am ? String(g.erledigt_am) : null),
    });
  }
  // Nach Erledigt-Zeitpunkt absteigend (Formate 'YYYY-MM-DD HH:MM:SS' vs. ISO 'YYYY-MM-DDT…Z' vereinheitlichen).
  const key = (s?: string | null) => (s ?? "").slice(0, 19).replace("T", " ");
  return items.sort((a, b) => key(b.done_at).localeCompare(key(a.done_at))).slice(0, limit);
}

/** Kompakter Tageszustand (KPI-Kacheln + Agenda). `owner` = Per-User-Sicht (aus dem API-Key). */
export function dashboardToday(owner?: string | null): Record<string, unknown> {
  const db = getDb();
  const safe = safeDb;
  // Heute/Monat/Jahr immer aus `berlinToday()` (einzige Heute-Quelle) — die Prozess-Zeitzone ist UTC.
  // ANMERKUNG: die reinen Zähl-Abfragen unten arbeiten weiterhin mit dem SQLite-`date('now')`
  // (= UTC-Datum). Zwischen 00:00 und 02:00 Berliner Zeit zählen sie darum noch mit dem Vortag.
  // Bewusst nicht umgebaut: `num()` bindet positionell, ein Mischen mit benannten Parametern ist in
  // better-sqlite3 nicht erlaubt — der Umbau träfe ~10 breit genutzte Kennzahlen auf einmal.
  const { y: year, mo: month } = berlinYearMonth();
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
  const vorratBaldAb = safe(() => db.prepare("SELECT id,name,mhd,kategorie,bild_pfad FROM vorrat_lebensmittel WHERE mhd IS NOT NULL AND mhd<>'' AND mhd<=date('now','+14 days') AND COALESCE(status,'')<>'verbraucht' ORDER BY mhd ASC LIMIT 12").all(), []);
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
    date: berlinToday(),
    kpis,
    agenda: safe(() => agenda(30, owner), []),
    aufgaben: safe(() => aufgabenFeed(), []),
    aufgaben_erledigt: safe(() => aufgabenErledigt(), []),
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
  // Heute-Basis = Berliner Kalendertag (einzige Heute-Quelle); Vergleich als reine UTC-Kalender-
  // arithmetik ⇒ DST-unabhängig und deckungsgleich mit `daysUntil()`.
  const today = berlinToday();
  const todayMs = calendarMs(today);
  const dueTermine = rows.filter((t) => {
    const d = calendarMs(String(t.date));
    if (d == null || todayMs == null) return false;
    const ws = d - Number(t.reminder_days ?? 0) * DAY_MS;
    return todayMs >= ws && todayMs <= d;
  }).map((t) => ({ ...t, source: "termin" }));
  const remSql = "SELECT id,title,body,date,time,domain,owner FROM reminders WHERE status='offen' AND date IS NOT NULL AND date<>'' AND date<=@today"
    + (owner ? " AND (owner IS NULL OR owner=@owner)" : "");
  const dueReminders = safeDb(() => (owner ? db.prepare(remSql).all({ owner, today }) : db.prepare(remSql).all({ today })) as Record<string, unknown>[], [])
    .map((r) => ({ ...r, source: "reminder" }));
  const data = [...dueTermine, ...dueReminders] as unknown as Record<string, unknown>[];
  data.sort((a, b) => String(a.date).localeCompare(String(b.date)));
  return { count: data.length, data };
}
