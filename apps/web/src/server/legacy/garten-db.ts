// Portiert aus dem Original (`lib/garden-db.ts`, Garten). Änderungen ggü. Original:
//  - Verbindung: shared `getDb()` (konsolidierte DB, Singleton) statt eigener better-sqlite3-Datei.
//  - KEIN `db.close()` (Singleton darf nicht geschlossen werden).
//  - Tabellen präfixiert: pflanzen→garten_pflanzen, samen→garten_samen, duenger→garten_duenger,
//    aufgaben→garten_aufgaben, pflanze_duenger→garten_pflanze_duenger.
// Logik/Signaturen bleiben 1:1.
import { getDb } from "@/server/db/connection";

export interface Pflanze {
  id: number;
  name: string;
  art: string;
  sorte?: string;
  standort?: string;
  beschreibung?: string;
  bewaesserung: 'hunter' | 'manuell';
  status: 'aktiv' | 'entfernt';
  bild_pfade?: string;
  erfasst_am: string;
  aktualisiert_am: string;
  metadata?: string;
  notizen?: string;
}

export interface Samen {
  id: number;
  nummer: string;
  name: string;
  art?: string;
  sorte?: string;
  beschreibung?: string;
  pflanz_von?: number;
  pflanz_bis?: number;
  vorziehen_ab?: number;
  ernte_von?: number;
  ernte_bis?: number;
  aussaat_2_von?: number;
  aussaat_2_bis?: number;
  ernte_2_von?: number;
  ernte_2_bis?: number;
  standort_empfehlung?: string;
  abstand_cm?: number;
  tiefe_cm?: number;
  keimzeit_tage?: number;
  hersteller?: string;
  bio?: string;
  samenfest?: number;
  botanisch?: string;
  keimtemp?: string;
  keimfaehig_bis?: string;
  inhalt?: string;
  verwendung?: string;
  typ?: string;
  herkunft?: string;
  besonderheiten?: string;
  aktiv: number;
  bild_pfade?: string;
  erfasst_am: string;
  aktualisiert_am: string;
  metadata?: string;
  notizen?: string;
}

export interface Aufgabe {
  id: number;
  pflanze_id?: number;
  samen_id?: number;
  duenger_id?: number;
  titel: string;
  beschreibung?: string;
  kategorie: string;
  monat: number;
  geplant_monat?: number;
  jahr: number;
  erledigt: number;
  erledigt_am?: string;
  prioritaet: 'niedrig' | 'normal' | 'hoch';
  wiederholung?: string;
  notizen?: string;
}

// ── Pflanzen ──

export function getAllPflanzen(filters?: {
  status?: string;
  art?: string;
  bewaesserung?: string;
  search?: string;
}): Pflanze[] {
  const db = getDb();
  let sql = 'SELECT * FROM garten_pflanzen WHERE 1=1';
  const params: unknown[] = [];

  if (filters?.status) {
    sql += ' AND status = ?';
    params.push(filters.status);
  }
  if (filters?.art) {
    sql += ' AND art = ?';
    params.push(filters.art);
  }
  if (filters?.bewaesserung) {
    sql += ' AND bewaesserung = ?';
    params.push(filters.bewaesserung);
  }
  if (filters?.search) {
    sql += ' AND (name LIKE ? OR sorte LIKE ? OR standort LIKE ? OR beschreibung LIKE ?)';
    const searchTerm = `%${filters.search}%`;
    params.push(searchTerm, searchTerm, searchTerm, searchTerm);
  }

  sql += ' ORDER BY erfasst_am DESC';

  const pflanzen = db.prepare(sql).all(...params) as Pflanze[];
  return pflanzen;
}

export function getPflanze(id: number): Pflanze | undefined {
  const db = getDb();
  const pflanze = db.prepare('SELECT * FROM garten_pflanzen WHERE id = ?').get(id) as Pflanze | undefined;
  return pflanze;
}

export function addPflanze(data: Omit<Pflanze, 'id' | 'erfasst_am' | 'aktualisiert_am'>): number {
  const db = getDb();
  const stmt = db.prepare(`
    INSERT INTO garten_pflanzen (name, art, sorte, standort, beschreibung, bewaesserung, status, bild_pfade, metadata, notizen)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);
  const result = stmt.run(
    data.name,
    data.art,
    data.sorte || null,
    data.standort || null,
    data.beschreibung || null,
    data.bewaesserung || 'hunter',
    data.status || 'aktiv',
    data.bild_pfade || null,
    data.metadata || null,
    data.notizen || null
  );
  return result.lastInsertRowid as number;
}

export function updatePflanze(id: number, data: Partial<Pflanze>): boolean {
  const db = getDb();
  const fields = Object.keys(data).filter(k => k !== 'id' && k !== 'erfasst_am' && k !== 'aktualisiert_am');
  const setClause = fields.map(f => `${f} = ?`).join(', ');
  const values = [...fields.map(f => (data as Record<string, unknown>)[f]), id];

  const stmt = db.prepare(`UPDATE garten_pflanzen SET ${setClause}, aktualisiert_am = CURRENT_TIMESTAMP WHERE id = ?`);
  const result = stmt.run(...values);
  return result.changes > 0;
}

export function deletePflanze(id: number): boolean {
  const db = getDb();
  const result = db.prepare('DELETE FROM garten_pflanzen WHERE id = ?').run(id);
  return result.changes > 0;
}

// ── Samen ──

export function getAllSamen(filters?: {
  aktiv?: number;
  art?: string;
  hersteller?: string;
  bio?: string;
  typ?: string;
  samenfest?: number;
  keimfaehig?: 'ok' | 'abgelaufen' | 'unbekannt';
  search?: string;
}): Samen[] {
  const db = getDb();
  let sql = 'SELECT * FROM garten_samen WHERE 1=1';
  const params: unknown[] = [];

  if (filters?.aktiv !== undefined) {
    sql += ' AND aktiv = ?';
    params.push(filters.aktiv);
  }
  if (filters?.art) {
    sql += ' AND art = ?';
    params.push(filters.art);
  }
  if (filters?.hersteller) {
    sql += ' AND hersteller = ?';
    params.push(filters.hersteller);
  }
  if (filters?.bio) {
    sql += ' AND bio IS NOT NULL AND bio LIKE ?';
    params.push(`%${filters.bio}%`);
  }
  if (filters?.typ) {
    sql += ' AND typ = ?';
    params.push(filters.typ);
  }
  if (filters?.samenfest !== undefined) {
    sql += ' AND samenfest = ?';
    params.push(filters.samenfest);
  }
  if (filters?.keimfaehig) {
    const currentYear = new Date().getFullYear();
    if (filters.keimfaehig === 'ok') {
      sql += ' AND (keimfaehig_bis IS NULL OR CAST(keimfaehig_bis AS INTEGER) >= ?)';
      params.push(currentYear);
    } else if (filters.keimfaehig === 'abgelaufen') {
      sql += ' AND keimfaehig_bis IS NOT NULL AND CAST(keimfaehig_bis AS INTEGER) < ?';
      params.push(currentYear);
    } else if (filters.keimfaehig === 'unbekannt') {
      sql += ' AND keimfaehig_bis IS NULL';
    }
  }
  if (filters?.search) {
    sql += ' AND (name LIKE ? OR nummer LIKE ? OR sorte LIKE ? OR beschreibung LIKE ?)';
    const searchTerm = `%${filters.search}%`;
    params.push(searchTerm, searchTerm, searchTerm, searchTerm);
  }

  sql += ' ORDER BY nummer ASC';

  const samen = db.prepare(sql).all(...params) as Samen[];
  return samen;
}

export function getSamen(id: number): Samen | undefined {
  const db = getDb();
  const samen = db.prepare('SELECT * FROM garten_samen WHERE id = ?').get(id) as Samen | undefined;
  return samen;
}

export function addSamen(data: Omit<Samen, 'id' | 'erfasst_am' | 'aktualisiert_am'>): number {
  const db = getDb();
  const stmt = db.prepare(`
    INSERT INTO garten_samen (nummer, name, art, sorte, beschreibung, pflanz_von, pflanz_bis, vorziehen_ab, ernte_von, ernte_bis,
                       standort_empfehlung, abstand_cm, tiefe_cm, keimzeit_tage, aktiv, bild_pfade, metadata, notizen)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);
  const result = stmt.run(
    data.nummer,
    data.name,
    data.art || null,
    data.sorte || null,
    data.beschreibung || null,
    data.pflanz_von || null,
    data.pflanz_bis || null,
    data.vorziehen_ab || null,
    data.ernte_von || null,
    data.ernte_bis || null,
    data.standort_empfehlung || null,
    data.abstand_cm || null,
    data.tiefe_cm || null,
    data.keimzeit_tage || null,
    data.aktiv !== undefined ? data.aktiv : 1,
    data.bild_pfade || null,
    data.metadata || null,
    data.notizen || null
  );
  return result.lastInsertRowid as number;
}

export function updateSamen(id: number, data: Partial<Samen>): boolean {
  const db = getDb();
  const fields = Object.keys(data).filter(k => k !== 'id' && k !== 'erfasst_am' && k !== 'aktualisiert_am');
  const setClause = fields.map(f => `${f} = ?`).join(', ');
  const values = [...fields.map(f => (data as Record<string, unknown>)[f]), id];

  const stmt = db.prepare(`UPDATE garten_samen SET ${setClause}, aktualisiert_am = CURRENT_TIMESTAMP WHERE id = ?`);
  const result = stmt.run(...values);
  return result.changes > 0;
}

export function deleteSamen(id: number): boolean {
  const db = getDb();
  const result = db.prepare('DELETE FROM garten_samen WHERE id = ?').run(id);
  return result.changes > 0;
}

// ── Aufgaben ──

export function getAufgaben(filters?: {
  monat?: number;
  jahr?: number;
  erledigt?: number;
  pflanze_id?: number;
  bereich?: 'alle' | 'rasen' | 'baeume' | 'anzucht';
}): Aufgabe[] {
  const db = getDb();
  let sql = 'SELECT a.*, p.name AS pflanze_name, p.art AS pflanze_art FROM garten_aufgaben a LEFT JOIN garten_pflanzen p ON a.pflanze_id = p.id WHERE (a.samen_id IS NULL OR a.samen_id IN (SELECT id FROM garten_samen WHERE aktiv = 1))';
  const params: unknown[] = [];

  if (filters?.monat) {
    sql += ' AND a.monat = ?';
    params.push(filters.monat);
  }
  if (filters?.jahr) {
    sql += ' AND a.jahr = ?';
    params.push(filters.jahr);
  }
  if (filters?.erledigt !== undefined) {
    sql += ' AND a.erledigt = ?';
    params.push(filters.erledigt);
  }
  if (filters?.pflanze_id) {
    sql += ' AND a.pflanze_id = ?';
    params.push(filters.pflanze_id);
  }

  // Bereich-Filter
  if (filters?.bereich === 'rasen') {
    sql += ' AND a.pflanze_id IS NOT NULL AND p.art IN (?, ?)';
    params.push('rasen', 'gras');
  } else if (filters?.bereich === 'baeume') {
    sql += ' AND a.pflanze_id IS NOT NULL AND p.art IN (?, ?, ?, ?)';
    params.push('baum', 'strauch', 'hecke', 'kuebelpflanze');
  } else if (filters?.bereich === 'anzucht') {
    sql += ' AND a.samen_id IS NOT NULL';
  }

  sql += ' ORDER BY COALESCE(a.geplant_monat, a.monat) ASC, a.prioritaet DESC';

  const aufgaben = db.prepare(sql).all(...params) as (Aufgabe & { duenger_name?: string; duenger_vorraetig?: number })[];
  // Join duenger info if column exists
  const withDuenger = aufgaben.map(a => {
    if (a.duenger_id) {
      try {
        const d = db.prepare('SELECT name, vorraetig FROM garten_duenger WHERE id = ?').get(a.duenger_id) as { name: string; vorraetig: number } | undefined;
        if (d) return { ...a, duenger_name: d.name, duenger_vorraetig: d.vorraetig };
      } catch {}
    }
    return a;
  });
  return withDuenger;
}

export function getAufgabe(id: number): Aufgabe | undefined {
  const db = getDb();
  const aufgabe = db.prepare('SELECT * FROM garten_aufgaben WHERE id = ?').get(id) as Aufgabe | undefined;
  return aufgabe;
}

export function addAufgabe(data: Omit<Aufgabe, 'id'>): number {
  const db = getDb();
  const stmt = db.prepare(`
    INSERT INTO garten_aufgaben (pflanze_id, samen_id, titel, beschreibung, kategorie, monat, jahr, erledigt, prioritaet, wiederholung, notizen)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);
  const result = stmt.run(
    data.pflanze_id || null,
    data.samen_id || null,
    data.titel,
    data.beschreibung || null,
    data.kategorie,
    data.monat,
    data.jahr,
    data.erledigt || 0,
    data.prioritaet || 'normal',
    data.wiederholung || null,
    data.notizen || null
  );
  return result.lastInsertRowid as number;
}

export function updateAufgabe(id: number, data: Partial<Aufgabe>): boolean {
  const db = getDb();
  const fields = Object.keys(data).filter(k => k !== 'id');

  // Wenn erledigt auf 1 gesetzt wird, füge erledigt_am hinzu
  if (data.erledigt === 1 && !data.erledigt_am) {
    fields.push('erledigt_am');
    (data as Record<string, unknown>).erledigt_am = new Date().toISOString();
  }

  const setClause = fields.map(f => `${f} = ?`).join(', ');
  const values = [...fields.map(f => (data as Record<string, unknown>)[f]), id];

  const stmt = db.prepare(`UPDATE garten_aufgaben SET ${setClause} WHERE id = ?`);
  const result = stmt.run(...values);
  return result.changes > 0;
}

export function deleteAufgabe(id: number): boolean {
  const db = getDb();
  const result = db.prepare('DELETE FROM garten_aufgaben WHERE id = ?').run(id);
  return result.changes > 0;
}

// ── Stats ──

export function getGardenStats() {
  const db = getDb();
  const stats = {
    pflanzen: {
      gesamt: (db.prepare('SELECT COUNT(*) as count FROM garten_pflanzen').get() as { count: number }).count,
      aktiv: (db.prepare("SELECT COUNT(*) as count FROM garten_pflanzen WHERE status = 'aktiv'").get() as { count: number }).count,
      nach_art: db.prepare("SELECT art, COUNT(*) as count FROM garten_pflanzen WHERE status = 'aktiv' GROUP BY art").all(),
    },
    samen: {
      gesamt: (db.prepare('SELECT COUNT(*) as count FROM garten_samen').get() as { count: number }).count,
      aktiv: (db.prepare('SELECT COUNT(*) as count FROM garten_samen WHERE aktiv = 1').get() as { count: number }).count,
    },
    aufgaben: {
      gesamt: (db.prepare('SELECT COUNT(*) as count FROM garten_aufgaben WHERE jahr = 2026').get() as { count: number }).count,
      offen: (db.prepare('SELECT COUNT(*) as count FROM garten_aufgaben WHERE jahr = 2026 AND erledigt = 0').get() as { count: number }).count,
      erledigt: (db.prepare('SELECT COUNT(*) as count FROM garten_aufgaben WHERE jahr = 2026 AND erledigt = 1').get() as { count: number }).count,
    },
    duenger: {
      gesamt: (db.prepare('SELECT COUNT(*) as count FROM garten_duenger').get() as { count: number }).count,
      vorraetig: (db.prepare('SELECT COUNT(*) as count FROM garten_duenger WHERE vorraetig = 1').get() as { count: number }).count,
      fehlend: (db.prepare('SELECT COUNT(*) as count FROM garten_pflanze_duenger WHERE duenger_id IS NULL').get() as { count: number }).count,
    },
  };
  return stats;
}

export function getArten(): string[] {
  const db = getDb();
  const rows = db.prepare("SELECT DISTINCT art FROM garten_pflanzen WHERE status = 'aktiv' ORDER BY art").all() as { art: string }[];
  return rows.map(r => r.art);
}

// ── Dünger ──

export interface Duenger {
  id: number;
  name: string;
  marke?: string;
  typ?: 'fluessig' | 'granulat' | 'staebchen' | 'pulver' | 'organisch' | 'kompost' | 'sonstig';
  beschreibung?: string;
  geeignet_fuer?: string;
  naehrstoffe?: string;
  dosierung?: string;
  intervall_wochen?: number;
  saison_von?: number;
  saison_bis?: number;
  vorraetig: number;
  kauflink?: string;
  bild_pfade?: string;
  erfasst_am: string;
  aktualisiert_am: string;
  metadata?: string;
  notizen?: string;
}

export interface PflanzeDuenger {
  id: number;
  pflanze_id: number;
  duenger_id?: number;
  duenger_typ_benoetigt?: string;
  empfohlen: number;
  notizen?: string;
}

type DuengerJoinRow = {
  id: number;
  pflanze_id: number;
  duenger_id?: number;
  duenger_typ_benoetigt?: string;
  empfohlen: number;
  notizen?: string;
  d_name?: string;
  d_marke?: string;
  d_typ?: Duenger['typ'];
  d_vorraetig?: number;
  d_naehrstoffe?: string;
  d_dosierung?: string;
};

type PflanzeJoinRow = {
  id: number;
  pflanze_id: number;
  duenger_id?: number;
  duenger_typ_benoetigt?: string;
  empfohlen: number;
  notizen?: string;
  p_name?: string;
  p_art?: string;
};

export function getAllDuenger(filters?: {
  typ?: string;
  vorraetig?: number;
  search?: string;
}): Duenger[] {
  const db = getDb();
  let sql = 'SELECT * FROM garten_duenger WHERE 1=1';
  const params: unknown[] = [];

  if (filters?.typ) {
    sql += ' AND typ = ?';
    params.push(filters.typ);
  }
  if (filters?.vorraetig !== undefined) {
    sql += ' AND vorraetig = ?';
    params.push(filters.vorraetig);
  }
  if (filters?.search) {
    sql += ' AND (name LIKE ? OR marke LIKE ? OR beschreibung LIKE ? OR geeignet_fuer LIKE ?)';
    const s = `%${filters.search}%`;
    params.push(s, s, s, s);
  }

  sql += ' ORDER BY name ASC';
  const result = db.prepare(sql).all(...params) as Duenger[];
  return result;
}

export function getDuenger(id: number): Duenger | undefined {
  const db = getDb();
  const d = db.prepare('SELECT * FROM garten_duenger WHERE id = ?').get(id) as Duenger | undefined;
  return d;
}

export function addDuenger(data: Omit<Duenger, 'id' | 'erfasst_am' | 'aktualisiert_am'>): number {
  const db = getDb();
  const stmt = db.prepare(`
    INSERT INTO garten_duenger (name, marke, typ, beschreibung, geeignet_fuer, naehrstoffe, dosierung, intervall_wochen,
      saison_von, saison_bis, vorraetig, kauflink, bild_pfade, metadata, notizen)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);
  const result = stmt.run(
    data.name, data.marke || null, data.typ || null, data.beschreibung || null,
    data.geeignet_fuer || null, data.naehrstoffe || null, data.dosierung || null,
    data.intervall_wochen || null, data.saison_von || null, data.saison_bis || null,
    data.vorraetig !== undefined ? data.vorraetig : 1,
    data.kauflink || null, data.bild_pfade || null, data.metadata || null, data.notizen || null
  );
  return result.lastInsertRowid as number;
}

export function updateDuenger(id: number, data: Partial<Duenger>): boolean {
  const db = getDb();
  const fields = Object.keys(data).filter(k => k !== 'id' && k !== 'erfasst_am' && k !== 'aktualisiert_am');
  if (fields.length === 0) { return false; }
  const setClause = fields.map(f => `${f} = ?`).join(', ');
  const values = [...fields.map(f => (data as Record<string, unknown>)[f]), id];
  const result = db.prepare(`UPDATE garten_duenger SET ${setClause}, aktualisiert_am = CURRENT_TIMESTAMP WHERE id = ?`).run(...values);
  return result.changes > 0;
}

export function deleteDuenger(id: number): boolean {
  const db = getDb();
  const result = db.prepare('DELETE FROM garten_duenger WHERE id = ?').run(id);
  return result.changes > 0;
}

export function getDuengerFuerPflanze(pflanze_id: number): (PflanzeDuenger & { duenger?: Duenger })[] {
  const db = getDb();
  const rows = db.prepare(`
    SELECT pd.*, d.name as d_name, d.marke as d_marke, d.typ as d_typ, d.vorraetig as d_vorraetig,
           d.naehrstoffe as d_naehrstoffe, d.dosierung as d_dosierung
    FROM garten_pflanze_duenger pd
    LEFT JOIN garten_duenger d ON d.id = pd.duenger_id
    WHERE pd.pflanze_id = ?
  `).all(pflanze_id) as DuengerJoinRow[];
  return rows.map(r => ({
    id: r.id, pflanze_id: r.pflanze_id, duenger_id: r.duenger_id,
    duenger_typ_benoetigt: r.duenger_typ_benoetigt, empfohlen: r.empfohlen, notizen: r.notizen,
    duenger: r.duenger_id ? { id: r.duenger_id, name: r.d_name, marke: r.d_marke, typ: r.d_typ,
      vorraetig: r.d_vorraetig, naehrstoffe: r.d_naehrstoffe, dosierung: r.d_dosierung } as Duenger : undefined,
  }));
}

export function getPflanzenFuerDuenger(duenger_id: number): (PflanzeDuenger & { pflanze?: Pflanze })[] {
  const db = getDb();
  const rows = db.prepare(`
    SELECT pd.*, p.name as p_name, p.art as p_art
    FROM garten_pflanze_duenger pd
    LEFT JOIN garten_pflanzen p ON p.id = pd.pflanze_id
    WHERE pd.duenger_id = ?
  `).all(duenger_id) as PflanzeJoinRow[];
  return rows.map(r => ({
    id: r.id, pflanze_id: r.pflanze_id, duenger_id: r.duenger_id,
    duenger_typ_benoetigt: r.duenger_typ_benoetigt, empfohlen: r.empfohlen, notizen: r.notizen,
    pflanze: r.pflanze_id ? { id: r.pflanze_id, name: r.p_name, art: r.p_art } as Pflanze : undefined,
  }));
}

export function linkPflanzeDuenger(pflanze_id: number, duenger_id: number, empfohlen = 1, notizen?: string): number {
  const db = getDb();
  const result = db.prepare(`
    INSERT INTO garten_pflanze_duenger (pflanze_id, duenger_id, empfohlen, notizen) VALUES (?, ?, ?, ?)
  `).run(pflanze_id, duenger_id, empfohlen, notizen || null);
  return result.lastInsertRowid as number;
}

export function unlinkPflanzeDuenger(id: number): boolean {
  const db = getDb();
  const result = db.prepare('DELETE FROM garten_pflanze_duenger WHERE id = ?').run(id);
  return result.changes > 0;
}

export function getFehlendeDuenger(): (PflanzeDuenger & { pflanze?: Pflanze })[] {
  const db = getDb();
  const rows = db.prepare(`
    SELECT pd.*, p.name as p_name, p.art as p_art
    FROM garten_pflanze_duenger pd
    LEFT JOIN garten_pflanzen p ON p.id = pd.pflanze_id
    WHERE pd.duenger_id IS NULL
  `).all() as PflanzeJoinRow[];
  return rows.map(r => ({
    id: r.id, pflanze_id: r.pflanze_id, duenger_id: undefined,
    duenger_typ_benoetigt: r.duenger_typ_benoetigt, empfohlen: r.empfohlen, notizen: r.notizen,
    pflanze: r.pflanze_id ? { id: r.pflanze_id, name: r.p_name, art: r.p_art } as Pflanze : undefined,
  }));
}

export function addDuengerBedarf(pflanze_id: number, duenger_typ_benoetigt: string): number {
  const db = getDb();
  const result = db.prepare(`
    INSERT INTO garten_pflanze_duenger (pflanze_id, duenger_typ_benoetigt, empfohlen) VALUES (?, ?, 1)
  `).run(pflanze_id, duenger_typ_benoetigt);
  return result.lastInsertRowid as number;
}

// Extend getGardenStats already defined above — add a separate export for duenger stats
export function getDuengerStats() {
  const db = getDb();
  const stats = {
    gesamt: (db.prepare('SELECT COUNT(*) as count FROM garten_duenger').get() as { count: number }).count,
    vorraetig: (db.prepare('SELECT COUNT(*) as count FROM garten_duenger WHERE vorraetig = 1').get() as { count: number }).count,
    nicht_vorraetig: (db.prepare('SELECT COUNT(*) as count FROM garten_duenger WHERE vorraetig = 0').get() as { count: number }).count,
    fehlend: (db.prepare('SELECT COUNT(*) as count FROM garten_pflanze_duenger WHERE duenger_id IS NULL').get() as { count: number }).count,
    nach_typ: db.prepare('SELECT typ, COUNT(*) as count FROM garten_duenger GROUP BY typ').all(),
  };
  return stats;
}
