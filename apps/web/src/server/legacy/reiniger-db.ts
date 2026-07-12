// Portiert aus dem Original (`lib/reiniger-db.ts`, Reiniger & Putzmittel). Änderungen ggü. Original:
//  - Verbindung: shared `getDb()` (konsolidierte DB, Singleton) statt eigener better-sqlite3-Datei.
//  - KEIN `db.close()` (Singleton darf nicht geschlossen werden).
//  - KEINE Schema-DDL (CREATE/ALTER/UPDATE): die konsolidierte DB ist bereits migriert (getReinigerDb() entfällt).
//  - Tabellen präfixiert: reiniger→reiniger_produkte, anwendungen→reiniger_anwendungen.
// Logik/Signaturen bleiben 1:1.
import { getDb } from "@/server/db/connection";

export type ReinigerStatus = 'aktiv' | 'leer' | 'nachkaufen' | 'entsorgt';

export interface Reiniger {
  id: number;
  name: string;
  marke?: string;
  kategorie: string;
  einsatzorte?: string;
  geeignet_fuer?: string;
  nicht_geeignet_fuer?: string;
  flecken?: string;
  pflegehinweise?: string;
  sicherheit?: string;
  dosierung?: string;
  menge?: string;
  bild_pfad?: string;
  bild_mime?: string;
  bild_sha256?: string;
  status: ReinigerStatus;
  restock: number;
  quelle_url?: string;
  meta_json?: string;
  erfasst_am: string;
  aktualisiert_am?: string;
  notizen?: string;
}

export interface Anwendung {
  id: number;
  reiniger_id: number;
  problem: string;
  material?: string;
  oberflaeche?: string;
  fleck_art?: string;
  anwendungsfall?: string;
  anleitung: string;
  begruendung?: string;
  warnhinweise?: string;
  prioritaet: number;
  erstellt_am: string;
  produkt_name?: string;
  produkt_marke?: string;
  produkt_kategorie?: string;
  produkt_bild_pfad?: string;
  produkt_quelle_url?: string;
}

export function getAllReiniger(filters?: {
  status?: string;
  kategorie?: string;
  search?: string;
}): Reiniger[] {
  const db = getDb();
  let sql = 'SELECT * FROM reiniger_produkte WHERE 1=1';
  const params: unknown[] = [];

  if (filters?.status) {
    sql += ' AND status = ?';
    params.push(filters.status);
  }
  if (filters?.kategorie) {
    sql += ' AND kategorie = ?';
    params.push(filters.kategorie);
  }
  if (filters?.search) {
    sql += ` AND (
      name LIKE ? OR marke LIKE ? OR einsatzorte LIKE ? OR geeignet_fuer LIKE ?
      OR nicht_geeignet_fuer LIKE ? OR flecken LIKE ? OR pflegehinweise LIKE ? OR notizen LIKE ?
    )`;
    const term = `%${filters.search}%`;
    params.push(term, term, term, term, term, term, term, term);
  }

  sql += " ORDER BY CASE WHEN status = 'aktiv' THEN 0 WHEN status = 'nachkaufen' THEN 1 WHEN status = 'leer' THEN 2 ELSE 3 END, aktualisiert_am DESC, erfasst_am DESC";
  const rows = db.prepare(sql).all(...params) as Reiniger[];
  return rows;
}

export function getReiniger(id: number): Reiniger | undefined {
  const db = getDb();
  const row = db.prepare('SELECT * FROM reiniger_produkte WHERE id = ?').get(id) as Reiniger | undefined;
  return row;
}

export function addReiniger(data: Partial<Reiniger>): number {
  const db = getDb();
  const result = db.prepare(`
    INSERT INTO reiniger_produkte (
      name, marke, kategorie, einsatzorte, geeignet_fuer, nicht_geeignet_fuer,
      flecken, pflegehinweise, sicherheit, dosierung, menge, bild_pfad, bild_mime, bild_sha256,
      status, restock, quelle_url, meta_json, aktualisiert_am, notizen
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'), ?)
  `).run(
    data.name,
    data.marke || null,
    data.kategorie || 'allzweck',
    data.einsatzorte || null,
    data.geeignet_fuer || null,
    data.nicht_geeignet_fuer || null,
    data.flecken || null,
    data.pflegehinweise || null,
    data.sicherheit || null,
    data.dosierung || null,
    data.menge || null,
    data.bild_pfad || null,
    data.bild_mime || null,
    data.bild_sha256 || null,
    data.status || 'aktiv',
    data.restock ?? 1,
    data.quelle_url || null,
    data.meta_json || null,
    data.notizen || null
  );
  return result.lastInsertRowid as number;
}

export function updateReiniger(id: number, data: Partial<Reiniger>): boolean {
  const db = getDb();
  const allowed = [
    'name', 'marke', 'kategorie', 'einsatzorte', 'geeignet_fuer', 'nicht_geeignet_fuer',
    'flecken', 'pflegehinweise', 'sicherheit', 'dosierung', 'menge', 'bild_pfad', 'bild_mime', 'bild_sha256',
    'status', 'restock', 'quelle_url', 'meta_json', 'notizen',
  ];
  const fields: string[] = [];
  const values: unknown[] = [];

  for (const key of allowed) {
    if (key in data) {
      fields.push(`${key} = ?`);
      values.push((data as Record<string, unknown>)[key] ?? null);
    }
  }

  if (fields.length === 0) {
    return false;
  }

  fields.push('aktualisiert_am = datetime("now")');
  values.push(id);
  const result = db.prepare(`UPDATE reiniger_produkte SET ${fields.join(', ')} WHERE id = ?`).run(...values);
  return result.changes > 0;
}

export function deleteReiniger(id: number): boolean {
  const db = getDb();
  const result = db.prepare('DELETE FROM reiniger_produkte WHERE id = ?').run(id);
  return result.changes > 0;
}

export function getAnwendungen(filters?: { search?: string; reiniger_id?: number }): Anwendung[] {
  const db = getDb();
  let sql = `
    SELECT
      a.*,
      r.name AS produkt_name,
      r.marke AS produkt_marke,
      r.kategorie AS produkt_kategorie,
      r.bild_pfad AS produkt_bild_pfad,
      r.quelle_url AS produkt_quelle_url
    FROM reiniger_anwendungen a
    LEFT JOIN reiniger_produkte r ON r.id = a.reiniger_id
    WHERE 1=1
  `;
  const params: unknown[] = [];

  if (filters?.reiniger_id) {
    sql += ' AND a.reiniger_id = ?';
    params.push(filters.reiniger_id);
  }
  if (filters?.search) {
    sql += ` AND (
      a.problem LIKE ? OR a.material LIKE ? OR a.oberflaeche LIKE ? OR a.fleck_art LIKE ?
      OR a.anwendungsfall LIKE ? OR a.anleitung LIKE ? OR a.begruendung LIKE ? OR a.warnhinweise LIKE ?
      OR r.name LIKE ? OR r.marke LIKE ? OR r.geeignet_fuer LIKE ? OR r.flecken LIKE ?
    )`;
    const term = `%${filters.search}%`;
    params.push(term, term, term, term, term, term, term, term, term, term, term, term);
  }

  sql += " ORDER BY COALESCE(a.oberflaeche, a.material, ''), a.prioritaet ASC, a.erstellt_am DESC";
  const rows = db.prepare(sql).all(...params) as Anwendung[];
  return rows;
}

export function addAnwendung(data: Partial<Anwendung>): number {
  const db = getDb();
  const result = db.prepare(`
    INSERT INTO reiniger_anwendungen (
      reiniger_id, problem, material, oberflaeche, fleck_art, anwendungsfall,
      anleitung, begruendung, warnhinweise, prioritaet
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(
    data.reiniger_id,
    data.problem,
    data.material || null,
    data.oberflaeche || data.material || null,
    data.fleck_art || data.problem || null,
    data.anwendungsfall || null,
    data.anleitung,
    data.begruendung || null,
    data.warnhinweise || null,
    data.prioritaet ?? 5
  );
  return result.lastInsertRowid as number;
}

export function getStats() {
  const db = getDb();
  const active = (db.prepare("SELECT COUNT(*) as c FROM reiniger_produkte WHERE status = 'aktiv'").get() as { c: number }).c;
  const restock = (db.prepare("SELECT COUNT(*) as c FROM reiniger_produkte WHERE status IN ('leer', 'nachkaufen') AND restock = 1").get() as { c: number }).c;
  const useCases = (db.prepare('SELECT COUNT(*) as c FROM reiniger_anwendungen').get() as { c: number }).c;
  const categories = db.prepare("SELECT kategorie, COUNT(*) as count FROM reiniger_produkte WHERE status != 'entsorgt' GROUP BY kategorie ORDER BY count DESC").all();
  return { active, restock, useCases, categories };
}
