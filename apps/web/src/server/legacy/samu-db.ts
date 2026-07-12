// Portiert aus dem Original (`lib/db.ts`, Samu-Inventar). Änderungen ggü. Original:
//  - Verbindung: shared `getDb()` (konsolidierte DB, Singleton) statt eigener better-sqlite3-Datei.
//  - KEIN `db.close()` (Singleton darf nicht geschlossen werden).
//  - Tabellen präfixiert: items→samu_items, marken→samu_marken, bedarfsliste→samu_bedarfsliste.
// Logik/Signaturen bleiben 1:1.
import { getDb } from "@/server/db/connection";

export interface Item {
  id: number;
  typ: 'kleidung' | 'spielzeug';
  kategorie: string;
  unterkategorie?: string;
  name?: string;
  marke?: string;
  beschreibung?: string;
  groesse?: string;
  altersgruppe?: string;
  passt_ab_groesse?: string;
  passt_ab_alter?: string;
  zustand?: string;
  verkaufswert?: number;
  farbe?: string;
  saison?: string;
  material?: string;
  status: string;
  verkaufskanal?: string;
  bild_pfade?: string;
  bild_telegram_ids?: string;
  erfasst_am: string;
  aktualisiert_am: string;
  aussortiert_am?: string;
  notizen?: string;
}

export function getAllItems(filters?: {
  status?: string;
  typ?: string;
  kategorie?: string;
  groesse?: string;
  search?: string;
}): Item[] {
  const db = getDb();
  let sql = 'SELECT * FROM samu_items WHERE 1=1';
  const params: unknown[] = [];

  if (filters?.status) {
    sql += ' AND status = ?';
    params.push(filters.status);
  }
  if (filters?.typ) {
    sql += ' AND typ = ?';
    params.push(filters.typ);
  }
  if (filters?.kategorie) {
    sql += ' AND kategorie = ?';
    params.push(filters.kategorie);
  }
  if (filters?.groesse) {
    sql += ' AND groesse = ?';
    params.push(filters.groesse);
  }
  if (filters?.search) {
    sql += ' AND (name LIKE ? OR marke LIKE ? OR beschreibung LIKE ? OR farbe LIKE ?)';
    const searchTerm = `%${filters.search}%`;
    params.push(searchTerm, searchTerm, searchTerm, searchTerm);
  }

  sql += ' ORDER BY erfasst_am DESC';

  return db.prepare(sql).all(...params) as Item[];
}

export function getItem(id: number): Item | undefined {
  const db = getDb();
  return db.prepare('SELECT * FROM samu_items WHERE id = ?').get(id) as Item | undefined;
}

export function updateItem(id: number, data: Partial<Item>): boolean {
  const db = getDb();
  const fields = Object.keys(data).filter((f) => f !== 'id');
  const setClause = fields.map(f => `${f} = ?`).join(', ');
  const values = [...fields.map(f => (data as Record<string, unknown>)[f]), id];

  const stmt = db.prepare(`UPDATE samu_items SET ${setClause}, aktualisiert_am = CURRENT_TIMESTAMP WHERE id = ?`);
  const result = stmt.run(...values);
  return result.changes > 0;
}

export function deleteItem(id: number): boolean {
  const db = getDb();
  const result = db.prepare('DELETE FROM samu_items WHERE id = ?').run(id);
  return result.changes > 0;
}

export function getStats() {
  const db = getDb();
  const stats = {
    gesamt: (db.prepare('SELECT COUNT(*) as count FROM samu_items').get() as { count: number }).count,
    nach_status: db.prepare('SELECT status, COUNT(*) as count FROM samu_items GROUP BY status').all(),
    nach_typ: db.prepare("SELECT typ, COUNT(*) as count FROM samu_items WHERE status != 'aussortiert' GROUP BY typ").all(),
    geschaetzter_wert: (db.prepare("SELECT SUM(verkaufswert) as summe FROM samu_items WHERE status IN ('aktiv', 'eingelagert')").get() as { summe: number | null })?.summe || 0,
  };
  return stats;
}

export function getMatrix(statusFilter?: string) {
  const db = getDb();
  let sql = "SELECT kategorie, groesse, COUNT(*) as count FROM samu_items WHERE typ = 'kleidung' AND kategorie IS NOT NULL AND groesse IS NOT NULL";
  const params: unknown[] = [];
  if (statusFilter) {
    sql += ' AND status = ?';
    params.push(statusFilter);
  } else {
    sql += " AND status IN ('aktiv', 'eingelagert')";
  }
  sql += ' GROUP BY kategorie, groesse ORDER BY kategorie, groesse';
  return db.prepare(sql).all(...params) as { kategorie: string; groesse: string; count: number }[];
}

export function getKategorien(filters?: { status?: string; typ?: string }): string[] {
  const db = getDb();
  let sql = "SELECT DISTINCT kategorie FROM samu_items WHERE kategorie IS NOT NULL AND kategorie != ''";
  const params: unknown[] = [];
  if (filters?.status) {
    sql += ' AND status = ?';
    params.push(filters.status);
  }
  if (filters?.typ) {
    sql += ' AND typ = ?';
    params.push(filters.typ);
  }
  sql += ' ORDER BY kategorie';
  const rows = db.prepare(sql).all(...params) as { kategorie: string }[];
  return rows.map(r => r.kategorie);
}

export function getGroessen(filters?: { status?: string; typ?: string }): string[] {
  const db = getDb();
  let sql = "SELECT DISTINCT groesse FROM samu_items WHERE groesse IS NOT NULL AND groesse != ''";
  const params: unknown[] = [];
  if (filters?.status) {
    sql += ' AND status = ?';
    params.push(filters.status);
  }
  if (filters?.typ) {
    sql += ' AND typ = ?';
    params.push(filters.typ);
  }
  sql += ' ORDER BY CAST(groesse AS INTEGER), groesse';
  const rows = db.prepare(sql).all(...params) as { groesse: string }[];
  return rows.map(r => r.groesse);
}

// ── Marken-Funktionen ──

export interface Marke {
  id: number;
  name: string;
  groessen_info?: string;
  herkunft?: string;
  material_fokus?: string;
  website?: string;
  preis_segment?: string;
  notizen?: string;
  angereichert_am?: string;
  erstellt_am: string;
}

export function getAllMarken(): Marke[] {
  const db = getDb();
  return db.prepare('SELECT * FROM samu_marken ORDER BY name').all() as Marke[];
}

export function getMarke(name: string): Marke | undefined {
  const db = getDb();
  return db.prepare('SELECT * FROM samu_marken WHERE name = ?').get(name) as Marke | undefined;
}

export function upsertMarke(data: {
  name: string;
  groessen_info?: string;
  herkunft?: string;
  material_fokus?: string;
  website?: string;
  preis_segment?: string;
  notizen?: string;
}): boolean {
  const db = getDb();
  try {
    const stmt = db.prepare(`
      INSERT INTO samu_marken (name, groessen_info, herkunft, material_fokus, website, preis_segment, notizen, angereichert_am)
      VALUES (?, ?, ?, ?, ?, ?, ?, datetime('now'))
      ON CONFLICT(name) DO UPDATE SET
        groessen_info = excluded.groessen_info,
        herkunft = excluded.herkunft,
        material_fokus = excluded.material_fokus,
        website = excluded.website,
        preis_segment = excluded.preis_segment,
        notizen = excluded.notizen,
        angereichert_am = datetime('now')
    `);
    stmt.run(
      data.name,
      data.groessen_info || null,
      data.herkunft || null,
      data.material_fokus || null,
      data.website || null,
      data.preis_segment || null,
      data.notizen || null
    );
    return true;
  } catch (err) {
    console.error('Fehler beim Speichern der Marke:', err);
    return false;
  }
}

export function getMarkenFromItems(): string[] {
  const db = getDb();
  const rows = db.prepare("SELECT DISTINCT marke FROM samu_items WHERE marke IS NOT NULL AND marke != '' ORDER BY marke").all() as { marke: string }[];
  return rows.map(r => r.marke);
}

// ── Bedarfsliste-Funktionen ──

export interface BedarfsItem {
  id: number;
  beschreibung: string;
  kategorie?: string;
  groesse?: string;
  prioritaet: 'hoch' | 'normal' | 'niedrig';
  notizen?: string;
  erledigt: number;
  erledigt_am?: string;
  erstellt_am: string;
  aktualisiert_am: string;
}

export function getAllBedarf(filters?: { erledigt?: number }): BedarfsItem[] {
  const db = getDb();
  let sql = 'SELECT * FROM samu_bedarfsliste WHERE 1=1';
  const params: unknown[] = [];

  if (filters?.erledigt !== undefined) {
    sql += ' AND erledigt = ?';
    params.push(filters.erledigt);
  }

  sql += " ORDER BY CASE prioritaet WHEN 'hoch' THEN 1 WHEN 'normal' THEN 2 WHEN 'niedrig' THEN 3 END, erstellt_am DESC";

  return db.prepare(sql).all(...params) as BedarfsItem[];
}

export function getBedarfsItem(id: number): BedarfsItem | undefined {
  const db = getDb();
  return db.prepare('SELECT * FROM samu_bedarfsliste WHERE id = ?').get(id) as BedarfsItem | undefined;
}

export function createBedarfsItem(data: {
  beschreibung: string;
  kategorie?: string;
  groesse?: string;
  prioritaet?: string;
  notizen?: string;
}): number {
  const db = getDb();
  const stmt = db.prepare(`
    INSERT INTO samu_bedarfsliste (beschreibung, kategorie, groesse, prioritaet, notizen)
    VALUES (?, ?, ?, ?, ?)
  `);
  const result = stmt.run(
    data.beschreibung,
    data.kategorie || null,
    data.groesse || null,
    data.prioritaet || 'normal',
    data.notizen || null
  );
  return Number(result.lastInsertRowid);
}

export function updateBedarfsItem(id: number, data: Partial<BedarfsItem>): boolean {
  const db = getDb();
  const fields = Object.keys(data).filter(f => f !== 'id');
  const setClause = fields.map(f => `${f} = ?`).join(', ');
  const values = [...fields.map(f => (data as Record<string, unknown>)[f]), id];

  const stmt = db.prepare(`UPDATE samu_bedarfsliste SET ${setClause}, aktualisiert_am = datetime('now') WHERE id = ?`);
  const result = stmt.run(...values);
  return result.changes > 0;
}

export function deleteBedarfsItem(id: number): boolean {
  const db = getDb();
  const result = db.prepare('DELETE FROM samu_bedarfsliste WHERE id = ?').run(id);
  return result.changes > 0;
}
