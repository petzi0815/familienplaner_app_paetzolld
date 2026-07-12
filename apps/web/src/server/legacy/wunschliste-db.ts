// Portiert aus dem Original (`lib/wunschliste-db.ts`, Wunschliste). Änderungen ggü. Original:
//  - Verbindung: shared `getDb()` (konsolidierte DB, Singleton) statt eigener better-sqlite3-Datei.
//  - KEIN `db.close()` (Singleton darf nicht geschlossen werden).
//  - KEINE lokale `getWunschDb()`-Factory mehr (Tabellen existieren bereits in der konsolidierten DB).
//  - Tabellen präfixiert: events→wunschliste_events, items→wunschliste_items.
// Logik/Signaturen/SQL bleiben 1:1.
import { getDb } from "@/server/db/connection";

/* ── Event Types ── */
export interface WunschEvent {
  id: number;
  name: string;
  emoji: string;
  date: string | null;
  type: string;
  recurring_month: number | null;
  recurring_day: number | null;
  notes: string | null;
  archived: number;
  erinnerungen_aktiv: number;
  created_at: string;
  updated_at: string;
  item_count?: number;
  open_count?: number;
}

export interface WunschItem {
  id: number;
  event_id: number;
  title: string;
  description: string | null;
  price: string | null;
  url: string | null;
  image_url: string | null;
  category: string | null;
  priority: number;
  status: string;
  purchased_by: string | null;
  notes: string | null;
  ean: string | null;
  price_comparison: string | null;
  created_at: string;
  updated_at: string;
  event_name?: string;
  event_emoji?: string;
}

/* ── Events ── */
export function getAllEvents(includeArchived = false): WunschEvent[] {
  const db = getDb();
  const where = includeArchived ? '' : 'WHERE e.archived = 0';
  const events = db.prepare(`
    SELECT e.*,
      COUNT(i.id) as item_count,
      SUM(CASE WHEN i.status = 'offen' THEN 1 ELSE 0 END) as open_count
    FROM wunschliste_events e
    LEFT JOIN wunschliste_items i ON i.event_id = e.id
    ${where}
    GROUP BY e.id
    ORDER BY e.date ASC, e.created_at ASC
  `).all() as WunschEvent[];
  return events;
}

export function getEvent(id: number): WunschEvent | undefined {
  const db = getDb();
  const event = db.prepare(`
    SELECT e.*,
      COUNT(i.id) as item_count,
      SUM(CASE WHEN i.status = 'offen' THEN 1 ELSE 0 END) as open_count
    FROM wunschliste_events e
    LEFT JOIN wunschliste_items i ON i.event_id = e.id
    WHERE e.id = ?
    GROUP BY e.id
  `).get(id) as WunschEvent | undefined;
  return event;
}

export function addEvent(data: Partial<WunschEvent>): number {
  const db = getDb();
  const result = db.prepare(`
    INSERT INTO wunschliste_events (name, emoji, date, type, recurring_month, recurring_day, notes)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `).run(
    data.name,
    data.emoji || '🎁',
    data.date || null,
    data.type || 'einmalig',
    data.recurring_month || null,
    data.recurring_day || null,
    data.notes || null,
  );
  return result.lastInsertRowid as number;
}

export function updateEvent(id: number, data: Partial<WunschEvent>): boolean {
  const db = getDb();
  const fields: string[] = [];
  const params: unknown[] = [];
  const allowed = ['name', 'emoji', 'date', 'type', 'recurring_month', 'recurring_day', 'notes', 'archived', 'erinnerungen_aktiv'];
  for (const key of allowed) {
    if (key in data) {
      fields.push(`${key} = ?`);
      params.push((data as Record<string, unknown>)[key]);
    }
  }
  if (fields.length === 0) { return false; }
  fields.push("updated_at = datetime('now')");
  params.push(id);
  const result = db.prepare(`UPDATE wunschliste_events SET ${fields.join(', ')} WHERE id = ?`).run(...params);
  return result.changes > 0;
}

export function deleteEvent(id: number): boolean {
  const db = getDb();
  db.prepare('DELETE FROM wunschliste_items WHERE event_id = ?').run(id);
  const result = db.prepare('DELETE FROM wunschliste_events WHERE id = ?').run(id);
  return result.changes > 0;
}

/* ── Items ── */
export function getItems(eventId?: number, status?: string): WunschItem[] {
  const db = getDb();
  let sql = `SELECT i.*, e.name as event_name, e.emoji as event_emoji
    FROM wunschliste_items i JOIN wunschliste_events e ON i.event_id = e.id WHERE 1=1`;
  const params: unknown[] = [];
  if (eventId) { sql += ' AND i.event_id = ?'; params.push(eventId); }
  if (status) { sql += ' AND i.status = ?'; params.push(status); }
  sql += ' ORDER BY i.priority DESC, i.created_at ASC';
  const items = db.prepare(sql).all(...params) as WunschItem[];
  return items;
}

export function getItem(id: number): WunschItem | undefined {
  const db = getDb();
  const item = db.prepare(`
    SELECT i.*, e.name as event_name, e.emoji as event_emoji
    FROM wunschliste_items i JOIN wunschliste_events e ON i.event_id = e.id
    WHERE i.id = ?
  `).get(id) as WunschItem | undefined;
  return item;
}

export function addItem(data: Partial<WunschItem>): number {
  const db = getDb();
  const result = db.prepare(`
    INSERT INTO wunschliste_items (event_id, title, description, price, url, image_url, category, priority, status, purchased_by, notes, ean, price_comparison)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(
    data.event_id,
    data.title,
    data.description || null,
    data.price || null,
    data.url || null,
    data.image_url || null,
    data.category || null,
    data.priority || 0,
    data.status || 'offen',
    data.purchased_by || null,
    data.notes || null,
    data.ean || null,
    data.price_comparison || null,
  );
  return result.lastInsertRowid as number;
}

export function updateItem(id: number, data: Partial<WunschItem>): boolean {
  const db = getDb();
  const fields: string[] = [];
  const params: unknown[] = [];
  const allowed = ['event_id', 'title', 'description', 'price', 'url', 'image_url', 'category', 'priority', 'status', 'purchased_by', 'notes', 'ean', 'price_comparison'];
  for (const key of allowed) {
    if (key in data) {
      fields.push(`${key} = ?`);
      params.push((data as Record<string, unknown>)[key]);
    }
  }
  if (fields.length === 0) { return false; }
  fields.push("updated_at = datetime('now')");
  params.push(id);
  const result = db.prepare(`UPDATE wunschliste_items SET ${fields.join(', ')} WHERE id = ?`).run(...params);
  return result.changes > 0;
}

export function deleteItem(id: number): boolean {
  const db = getDb();
  const result = db.prepare('DELETE FROM wunschliste_items WHERE id = ?').run(id);
  return result.changes > 0;
}
