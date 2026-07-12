// Portiert aus dem Original (`lib/vorratskammer-db.ts`, Vorratskammer). Änderungen ggü. Original:
//  - Verbindung: shared `getDb()` (konsolidierte DB, Singleton) statt eigener better-sqlite3-Datei.
//  - KEIN `db.close()` (Singleton darf nicht geschlossen werden).
//  - Tabellen präfixiert: lebensmittel→vorrat_lebensmittel, rezepte→vorrat_rezepte.
// Logik/Signaturen bleiben 1:1.
import { getDb } from "@/server/db/connection";

export interface Lebensmittel {
  id: number;
  name: string;
  marke?: string;
  kategorie: 'trocken' | 'kuehlschrank' | 'gefrierfach';
  menge?: string;
  mhd?: string;
  bild_pfad?: string;
  status: 'aktiv' | 'verbraucht';
  restock: number;
  erfasst_am: string;
  verbraucht_am?: string;
  notizen?: string;
}

// ── CRUD ──

export function getAllLebensmittel(filters?: {
  kategorie?: string;
  status?: string;
  search?: string;
}): Lebensmittel[] {
  const db = getDb();
  let sql = 'SELECT * FROM vorrat_lebensmittel WHERE 1=1';
  const params: unknown[] = [];

  if (filters?.kategorie) {
    sql += ' AND kategorie = ?';
    params.push(filters.kategorie);
  }
  if (filters?.status) {
    sql += ' AND status = ?';
    params.push(filters.status);
  }
  if (filters?.search) {
    sql += ' AND (name LIKE ? OR marke LIKE ?)';
    const term = `%${filters.search}%`;
    params.push(term, term);
  }

  sql += ' ORDER BY erfasst_am DESC';

  const rows = db.prepare(sql).all(...params) as Lebensmittel[];
  return rows;
}

export function getLebensmittel(id: number): Lebensmittel | undefined {
  const db = getDb();
  const row = db.prepare('SELECT * FROM vorrat_lebensmittel WHERE id = ?').get(id) as Lebensmittel | undefined;
  return row;
}

export function addLebensmittel(data: Partial<Lebensmittel>): number {
  const db = getDb();
  const stmt = db.prepare(`
    INSERT INTO vorrat_lebensmittel (name, marke, kategorie, menge, mhd, bild_pfad, status, restock, notizen)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);
  const result = stmt.run(
    data.name,
    data.marke || null,
    data.kategorie,
    data.menge || null,
    data.mhd || null,
    data.bild_pfad || null,
    data.status || 'aktiv',
    data.restock ?? 1,
    data.notizen || null
  );
  return Number(result.lastInsertRowid);
}

export function updateLebensmittel(id: number, data: Partial<Lebensmittel>): boolean {
  const db = getDb();

  // Auto-set verbraucht_am when status changes to verbraucht
  if (data.status === 'verbraucht' && !data.verbraucht_am) {
    data.verbraucht_am = new Date().toISOString().slice(0, 19).replace('T', ' ');
  }

  const fields: string[] = [];
  const values: unknown[] = [];

  const allowed = ['name', 'marke', 'kategorie', 'menge', 'mhd', 'bild_pfad', 'status', 'restock', 'verbraucht_am', 'notizen'];
  for (const key of allowed) {
    if (key in data) {
      fields.push(`${key} = ?`);
      values.push((data as Record<string, unknown>)[key] ?? null);
    }
  }

  if (fields.length === 0) {
    return false;
  }

  values.push(id);
  const result = db.prepare(`UPDATE vorrat_lebensmittel SET ${fields.join(', ')} WHERE id = ?`).run(...values);
  return result.changes > 0;
}

export function deleteLebensmittel(id: number): boolean {
  const db = getDb();
  const result = db.prepare('DELETE FROM vorrat_lebensmittel WHERE id = ?').run(id);
  return result.changes > 0;
}

// ── Spezial-Abfragen ──

export function getEinkaufsliste(): Lebensmittel[] {
  const db = getDb();
  const rows = db.prepare(
    "SELECT * FROM vorrat_lebensmittel WHERE status = 'verbraucht' AND restock = 1 ORDER BY name ASC"
  ).all() as Lebensmittel[];
  return rows;
}

export function getAblaufend(tage: number = 14): Lebensmittel[] {
  const db = getDb();
  const rows = db.prepare(`
    SELECT * FROM vorrat_lebensmittel
    WHERE status = 'aktiv'
      AND mhd IS NOT NULL
      AND mhd != ''
      AND date(mhd) <= date('now', '+' || ? || ' days')
    ORDER BY mhd ASC
  `).all(tage) as Lebensmittel[];
  return rows;
}

export function getStats(): {
  total: number;
  trocken: number;
  kuehlschrank: number;
  gefrierfach: number;
  ablaufend: number;
  einkaufsliste: number;
} {
  const db = getDb();

  const total = (db.prepare("SELECT COUNT(*) as c FROM vorrat_lebensmittel WHERE status = 'aktiv'").get() as { c: number }).c;
  const trocken = (db.prepare("SELECT COUNT(*) as c FROM vorrat_lebensmittel WHERE status = 'aktiv' AND kategorie = 'trocken'").get() as { c: number }).c;
  const kuehlschrank = (db.prepare("SELECT COUNT(*) as c FROM vorrat_lebensmittel WHERE status = 'aktiv' AND kategorie = 'kuehlschrank'").get() as { c: number }).c;
  const gefrierfach = (db.prepare("SELECT COUNT(*) as c FROM vorrat_lebensmittel WHERE status = 'aktiv' AND kategorie = 'gefrierfach'").get() as { c: number }).c;
  const ablaufend = (db.prepare(`
    SELECT COUNT(*) as c FROM vorrat_lebensmittel
    WHERE status = 'aktiv' AND mhd IS NOT NULL AND mhd != ''
    AND date(mhd) <= date('now', '+14 days')
  `).get() as { c: number }).c;
  const einkaufsliste = (db.prepare("SELECT COUNT(*) as c FROM vorrat_lebensmittel WHERE status = 'verbraucht' AND restock = 1").get() as { c: number }).c;

  return { total, trocken, kuehlschrank, gefrierfach, ablaufend, einkaufsliste };
}

export function getKategorien(): string[] {
  const db = getDb();
  const rows = db.prepare("SELECT DISTINCT kategorie FROM vorrat_lebensmittel ORDER BY kategorie").all() as { kategorie: string }[];
  return rows.map(r => r.kategorie);
}

// ── Rezepte ──

export interface Rezept {
  id: number;
  titel: string;
  url?: string;
  quelle?: string;
  beschreibung?: string;
  zutaten_match?: string;
  bild_url?: string;
  erstellt_am: string;
  notizen?: string;
}

export function getAllRezepte(limit: number = 50): Rezept[] {
  const db = getDb();
  const rows = db.prepare('SELECT * FROM vorrat_rezepte ORDER BY erstellt_am DESC LIMIT ?').all(limit) as Rezept[];
  return rows;
}

export function addRezept(data: Partial<Rezept>): number {
  const db = getDb();
  const stmt = db.prepare(`
    INSERT INTO vorrat_rezepte (titel, url, quelle, beschreibung, zutaten_match, bild_url, notizen)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `);
  const result = stmt.run(
    data.titel,
    data.url || null,
    data.quelle || null,
    data.beschreibung || null,
    data.zutaten_match || null,
    data.bild_url || null,
    data.notizen || null
  );
  return Number(result.lastInsertRowid);
}

export function deleteRezept(id: number): boolean {
  const db = getDb();
  const result = db.prepare('DELETE FROM vorrat_rezepte WHERE id = ?').run(id);
  return result.changes > 0;
}
