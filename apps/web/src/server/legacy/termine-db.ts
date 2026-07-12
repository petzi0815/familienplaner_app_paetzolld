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
export function getAllTermine(opts?: { from?: string; to?: string; category?: string; status?: string; person?: string }): Termin[] {
  const db = getDb();
  let sql = 'SELECT * FROM termine WHERE 1=1';
  const params: unknown[] = [];

  if (opts?.from) { sql += ' AND date >= ?'; params.push(opts.from); }
  if (opts?.to) { sql += ' AND date <= ?'; params.push(opts.to); }
  if (opts?.category) { sql += ' AND category = ?'; params.push(opts.category); }
  if (opts?.status) { sql += ' AND status = ?'; params.push(opts.status); }
  if (opts?.person) { sql += ' AND person = ?'; params.push(opts.person); }

  sql += ' ORDER BY date ASC, time ASC';
  const result = db.prepare(sql).all(...params) as Termin[];
  return result;
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
  fields.push("updated_at = datetime('now')");
  params.push(id);
  const result = db.prepare(`UPDATE termine SET ${fields.join(', ')} WHERE id = ?`).run(...params);
  return result.changes > 0;
}

export function deleteTermin(id: number): boolean {
  const db = getDb();
  const result = db.prepare('DELETE FROM termine WHERE id = ?').run(id);
  return result.changes > 0;
}

/* ── Helpers ── */
export function getUpcomingTermine(days: number = 14): Termin[] {
  const today = new Date().toISOString().split('T')[0];
  const future = new Date(Date.now() + days * 86400000).toISOString().split('T')[0];
  return getAllTermine({ from: today, to: future, status: 'offen' });
}

export function getTermineForMonth(year: number, month: number): Termin[] {
  const from = `${year}-${String(month).padStart(2, '0')}-01`;
  const lastDay = new Date(year, month, 0).getDate();
  const to = `${year}-${String(month).padStart(2, '0')}-${lastDay}`;
  return getAllTermine({ from, to });
}

export function searchTermine(query: string): Termin[] {
  const db = getDb();
  const q = `%${query}%`;
  const results = db.prepare(`
    SELECT * FROM termine
    WHERE title LIKE ? OR description LIKE ? OR location LIKE ? OR person LIKE ? OR notes LIKE ? OR category LIKE ?
    ORDER BY date DESC
  `).all(q, q, q, q, q, q) as Termin[];
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
