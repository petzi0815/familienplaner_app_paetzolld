// Portiert aus dem Original (`lib/gypsi-db.ts`, Gypsi-Katzenfutter). Änderungen ggü. Original:
//  - Verbindung: shared `getDb()` (konsolidierte DB, Singleton) statt eigener better-sqlite3-Datei.
//  - KEIN `db.close()` (Singleton darf nicht geschlossen werden).
//  - Tabelle präfixiert: futter→gypsi_futter.
// Logik/Signaturen bleiben 1:1.
import { getDb } from "@/server/db/connection";

export interface Futter {
  id: number;
  marke: string;
  sorte: string;
  geschmack?: string;
  bild_pfad?: string;
  status: 'mag_er' | 'mag_er_nicht_mehr';
  erfasst_am: string;
  status_geaendert_am?: string;
  notizen?: string;
}

// ── Futter ──

export function getAllFutter(filters?: {
  marke?: string;
  geschmack?: string;
  status?: string;
}): Futter[] {
  const db = getDb();
  let sql = 'SELECT * FROM gypsi_futter WHERE 1=1';
  const params: unknown[] = [];

  if (filters?.marke) {
    sql += ' AND marke = ?';
    params.push(filters.marke);
  }
  if (filters?.geschmack) {
    sql += ' AND geschmack = ?';
    params.push(filters.geschmack);
  }
  if (filters?.status) {
    sql += ' AND status = ?';
    params.push(filters.status);
  }

  sql += ' ORDER BY erfasst_am DESC';

  const futter = db.prepare(sql).all(...params) as Futter[];
  return futter;
}

export function getFutter(id: number): Futter | undefined {
  const db = getDb();
  const futter = db.prepare('SELECT * FROM gypsi_futter WHERE id = ?').get(id) as Futter | undefined;
  return futter;
}

export function addFutter(data: Omit<Futter, 'id' | 'erfasst_am' | 'status_geaendert_am'>): number {
  const db = getDb();
  const stmt = db.prepare(`
    INSERT INTO gypsi_futter (marke, sorte, geschmack, bild_pfad, status, notizen)
    VALUES (?, ?, ?, ?, ?, ?)
  `);
  const result = stmt.run(
    data.marke,
    data.sorte,
    data.geschmack || null,
    data.bild_pfad || null,
    data.status || 'mag_er',
    data.notizen || null
  );
  return result.lastInsertRowid as number;
}

export function updateFutterStatus(id: number, status: 'mag_er' | 'mag_er_nicht_mehr'): boolean {
  const db = getDb();
  const stmt = db.prepare(`
    UPDATE gypsi_futter SET status = ?, status_geaendert_am = datetime('now') WHERE id = ?
  `);
  const result = stmt.run(status, id);
  return result.changes > 0;
}

export function deleteFutter(id: number): boolean {
  const db = getDb();
  const result = db.prepare('DELETE FROM gypsi_futter WHERE id = ?').run(id);
  return result.changes > 0;
}

// ── Filter options ──

export function getMarken(): string[] {
  const db = getDb();
  const rows = db.prepare('SELECT DISTINCT marke FROM gypsi_futter ORDER BY marke').all() as { marke: string }[];
  return rows.map(r => r.marke);
}

export function getGeschmacksrichtungen(): string[] {
  const db = getDb();
  const rows = db.prepare('SELECT DISTINCT geschmack FROM gypsi_futter WHERE geschmack IS NOT NULL ORDER BY geschmack').all() as { geschmack: string }[];
  return rows.map(r => r.geschmack);
}
