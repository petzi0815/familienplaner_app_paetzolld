// Portiert aus dem Original (`lib/termine-db.ts`, Bereich Termine). Änderungen ggü. Original:
//  - Verbindung: shared `getDb()` (konsolidierte DB, Singleton) statt eigener better-sqlite3-Datei.
//  - KEIN `db.close()` (Singleton darf nicht geschlossen werden).
//  - KEINE Tabellen-Präfixe: die Tabelle heißt in beiden DBs `termine` (kein Rename nötig).
//  - Schema wird nicht mehr zur Laufzeit angelegt (`getTerminDb()` entfällt) — die konsolidierte DB
//    hat `termine` bereits per Migration.
// Logik/Signaturen/SQL bleiben 1:1.
import { getDb } from "@/server/db/connection";

/* ── Types ── */
export interface Termin {
  id: number;
  title: string;
  description: string | null;
  category: string;
  date: string;
  time: string | null;
  end_date: string | null;
  end_time: string | null;
  location: string | null;
  person: string | null;
  recurring: string | null;
  recurring_interval: string | null;
  reminder_days: number;
  reminder_sent: number;
  cron_job_id: string | null;
  status: string;
  notes: string | null;
  source: string;
  created_at: string;
  updated_at: string;
}

export const CATEGORIES = [
  { id: 'allgemein', label: 'Allgemein', emoji: '📅', color: 'blue' },
  { id: 'arzt_samu', label: 'Arzt Samu', emoji: '👶🏥', color: 'red' },
  { id: 'arzt_familie', label: 'Arzt Familie', emoji: '🏥', color: 'rose' },
  { id: 'impfung', label: 'Impfung', emoji: '💉', color: 'purple' },
  { id: 'u_untersuchung', label: 'U-Untersuchung', emoji: '📋', color: 'indigo' },
  { id: 'zahnarzt', label: 'Zahnarzt', emoji: '🦷', color: 'cyan' },
  { id: 'schliesszzeit', label: 'Schließzeit Kita', emoji: '🏫', color: 'amber' },
  { id: 'tierarzt', label: 'Tierarzt', emoji: '🐱', color: 'orange' },
  { id: 'wartung', label: 'Wartung/Haushalt', emoji: '🔧', color: 'gray' },
  { id: 'garten', label: 'Garten', emoji: '🌱', color: 'green' },
  { id: 'geburtstag', label: 'Geburtstag', emoji: '🎂', color: 'pink' },
  { id: 'friseur', label: 'Friseur', emoji: '💇', color: 'violet' },
  { id: 'auto', label: 'Auto/TÜV', emoji: '🚗', color: 'slate' },
];

export function getCategoryInfo(cat: string) {
  return CATEGORIES.find(c => c.id === cat) || CATEGORIES[0];
}

/* ── CRUD ── */
// `owner` (Per-User-Key) → LEFT JOIN termin_user_state, ergänzt read/notify/muted je Termin (0/1).
export function getAllTermine(opts?: { from?: string; to?: string; category?: string; status?: string; person?: string }, owner?: string | null): Termin[] {
  const db = getDb();
  const sel = owner ? "t.*, COALESCE(tus.read,0) AS read, COALESCE(tus.notify,0) AS notify, COALESCE(tus.muted,0) AS muted" : "t.*";
  let sql = `SELECT ${sel} FROM termine t`
    + (owner ? " LEFT JOIN termin_user_state tus ON tus.termin_id=t.id AND tus.owner=@owner" : "")
    + " WHERE 1=1";
  const params: Record<string, unknown> = {};
  if (owner) params.owner = owner;
  if (opts?.from) { sql += ' AND t.date >= @from'; params.from = opts.from; }
  if (opts?.to) { sql += ' AND t.date <= @to'; params.to = opts.to; }
  if (opts?.category) { sql += ' AND t.category = @category'; params.category = opts.category; }
  if (opts?.status) { sql += ' AND t.status = @status'; params.status = opts.status; }
  if (opts?.person) { sql += ' AND t.person = @person'; params.person = opts.person; }

  sql += ' ORDER BY t.date ASC, t.time ASC';
  return db.prepare(sql).all(params) as Termin[];
}

export function getTermin(id: number): Termin | undefined {
  const db = getDb();
  const result = db.prepare('SELECT * FROM termine WHERE id = ?').get(id) as Termin | undefined;
  return result;
}

export function addTermin(data: Partial<Termin>): number {
  const db = getDb();
  const result = db.prepare(`
    INSERT INTO termine (title, description, category, date, time, end_date, end_time, location, person, recurring, recurring_interval, reminder_days, status, notes, source, cron_job_id)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(
    data.title,
    data.description || null,
    data.category || 'allgemein',
    data.date,
    data.time || null,
    data.end_date || null,
    data.end_time || null,
    data.location || null,
    data.person || null,
    data.recurring || null,
    data.recurring_interval || null,
    data.reminder_days ?? 2,
    data.status || 'offen',
    data.notes || null,
    data.source || 'manuell',
    data.cron_job_id || null,
  );
  return result.lastInsertRowid as number;
}

export function updateTermin(id: number, data: Partial<Termin>): boolean {
  const db = getDb();
  const fields: string[] = [];
  const params: unknown[] = [];
  const allowed = ['title', 'description', 'category', 'date', 'time', 'end_date', 'end_time', 'location', 'person', 'recurring', 'recurring_interval', 'reminder_days', 'reminder_sent', 'cron_job_id', 'status', 'notes', 'source'];
  for (const key of allowed) {
    if (key in data) {
      fields.push(`${key} = ?`);
      params.push((data as Record<string, unknown>)[key]);
    }
  }
  if (fields.length === 0) { return false; }
  // Altes Datum VOR dem Update merken — der Marker-Reset unten darf nur bei einer echten
  // Verschiebung greifen. Das iOS-Bearbeiten-Formular (TermineForm) schickt `date` IMMER mit,
  // auch wenn nur der Titel geändert wurde; ohne diesen Vergleich würde jedes Speichern die
  // Quittierungen aller Personen löschen und den 07-Uhr-Push erneut scharf schalten.
  const dayOf = (v: unknown) => (typeof v === 'string' ? v.trim().slice(0, 10) : '');
  const prevDate = 'date' in data
    ? dayOf((db.prepare('SELECT date FROM termine WHERE id = ?').get(id) as { date?: string } | undefined)?.date)
    : '';
  fields.push("updated_at = datetime('now')");
  params.push(id);
  const result = db.prepare(`UPDATE termine SET ${fields.join(', ')} WHERE id = ?`).run(...params);
  // Datum geändert → Per-User-Push-Marker zurücksetzen (sonst würde der Push fälschlich unterdrückt).
  // `reminder_0d_sent` MUSS mit zurück: der 07-Uhr-Slot („Heute") feuert ausschließlich, solange er 0 ist —
  // ohne Reset bekäme ein verschobener Termin nie wieder eine Erinnerung. `ack_at` ebenfalls, denn eine
  // Quittierung galt dem ALTEN Termin; sonst startet die Live Activity des neuen Datums sofort als erledigt.
  if ('date' in data && dayOf((data as Record<string, unknown>).date) !== prevDate) {
    db.prepare(
      "UPDATE termin_user_state SET reminder_2d_sent=0, reminder_1d_sent=0, reminder_0d_sent=0, ack_at=NULL," +
      " updated_at=datetime('now') WHERE termin_id=?",
    ).run(id);
  }
  return result.changes > 0;
}

/* ── Per-User-Zustand (owner = 'lars' | 'elita') ── */
export interface TerminUserState { read: boolean; notify: boolean; muted: boolean; ack_at: string | null }

/**
 * Setzt/aktualisiert den Per-User-Zustand. Nur übergebene Felder werden geändert (Weglassen = unverändert).
 * `muted` = dieser User will für DIESEN Termin keine Erinnerung mehr (Migration 0018).
 * `ack_at` = Quittier-Zeitpunkt; `'now'` als Kürzel für datetime('now').
 *   undefined/null → unverändert (gleiche COALESCE-Semantik wie read/notify)
 *   `''`           → Quittierung ZURÜCKNEHMEN (ack_at = NULL), z.B. Ack-Aktion 'laut'.
 * Ohne diesen Sentinel wäre einmal quittiert = dauerhaft quittiert (Live Activity/statusOf).
 */
export function setTerminUserState(terminId: number, owner: string, patch: { read?: boolean; notify?: boolean; muted?: boolean; ack_at?: string | null }): void {
  const db = getDb();
  const read = patch.read === undefined ? null : (patch.read ? 1 : 0);
  const notify = patch.notify === undefined ? null : (patch.notify ? 1 : 0);
  const muted = patch.muted === undefined ? null : (patch.muted ? 1 : 0);
  const clearAck = patch.ack_at === '';
  const ackAt = patch.ack_at === undefined || patch.ack_at === null || clearAck
    ? null
    : (patch.ack_at === 'now' ? new Date().toISOString().slice(0, 19).replace('T', ' ') : patch.ack_at);
  db.prepare(
    `INSERT INTO termin_user_state (termin_id, owner, read, notify, muted, ack_at)
     VALUES (@id, @owner, COALESCE(@read,0), COALESCE(@notify,0), COALESCE(@muted,0), @ack_at)
     ON CONFLICT(termin_id, owner) DO UPDATE SET
       read   = COALESCE(@read, read),
       notify = COALESCE(@notify, notify),
       muted  = COALESCE(@muted, muted),
       ack_at = CASE WHEN @clear_ack = 1 THEN NULL ELSE COALESCE(@ack_at, ack_at) END,
       updated_at = datetime('now')`,
  ).run({ id: terminId, owner, read, notify, muted, ack_at: ackAt, clear_ack: clearAck ? 1 : 0 });
}

/** Liest den Per-User-Zustand (fehlende Zeile = alles false/null — der Default vor der ersten Aktion). */
export function getTerminUserState(terminId: number, owner: string): TerminUserState {
  const db = getDb();
  const row = db.prepare(
    'SELECT read, notify, muted, ack_at FROM termin_user_state WHERE termin_id = ? AND owner = ?',
  ).get(terminId, owner) as { read?: number; notify?: number; muted?: number; ack_at?: string | null } | undefined;
  return {
    read: !!Number(row?.read ?? 0),
    notify: !!Number(row?.notify ?? 0),
    muted: !!Number(row?.muted ?? 0),
    ack_at: row?.ack_at ?? null,
  };
}

export function deleteTermin(id: number): boolean {
  const db = getDb();
  const result = db.prepare('DELETE FROM termine WHERE id = ?').run(id);
  return result.changes > 0;
}

/* ── Helpers ── */
export function getUpcomingTermine(days: number = 14, owner?: string | null): Termin[] {
  const today = new Date().toISOString().split('T')[0];
  const future = new Date(Date.now() + days * 86400000).toISOString().split('T')[0];
  return getAllTermine({ from: today, to: future, status: 'offen' }, owner);
}

export function getTermineForMonth(year: number, month: number, owner?: string | null): Termin[] {
  const from = `${year}-${String(month).padStart(2, '0')}-01`;
  const lastDay = new Date(year, month, 0).getDate();
  const to = `${year}-${String(month).padStart(2, '0')}-${lastDay}`;
  return getAllTermine({ from, to }, owner);
}

export function searchTermine(query: string, owner?: string | null): Termin[] {
  const db = getDb();
  const q = `%${query}%`;
  const sel = owner ? "t.*, COALESCE(tus.read,0) AS read, COALESCE(tus.notify,0) AS notify, COALESCE(tus.muted,0) AS muted" : "t.*";
  const join = owner ? " LEFT JOIN termin_user_state tus ON tus.termin_id=t.id AND tus.owner=@owner" : "";
  const results = db.prepare(
    `SELECT ${sel} FROM termine t${join}
     WHERE t.title LIKE @q OR t.description LIKE @q OR t.location LIKE @q OR t.person LIKE @q OR t.notes LIKE @q OR t.category LIKE @q
     ORDER BY t.date DESC`,
  ).all(owner ? { q, owner } : { q }) as Termin[];
  return results;
}

export function getConflicts(date: string, excludeId?: number): Termin[] {
  const db = getDb();
  const results = db.prepare(`
    SELECT * FROM termine
    WHERE status = 'offen'
      AND (
        date = ?
        OR (end_date IS NOT NULL AND date <= ? AND end_date >= ?)
      )
      ${excludeId ? 'AND id != ?' : ''}
    ORDER BY time ASC
  `).all(...(excludeId ? [date, date, date, excludeId] : [date, date, date])) as Termin[];
  return results;
}

export function getDueReminders(): Termin[] {
  const db = getDb();
  const results = db.prepare(`
    SELECT * FROM termine
    WHERE status = 'offen'
      AND reminder_sent = 0
      AND date(date, '-' || reminder_days || ' days') <= date('now')
      AND date >= date('now')
    ORDER BY date ASC
  `).all() as Termin[];
  return results;
}

export function markReminderSent(id: number): void {
  const db = getDb();
  db.prepare("UPDATE termine SET reminder_sent = 1, updated_at = datetime('now') WHERE id = ?").run(id);
}
