// Portiert aus dem Original (`lib/geschenkplaner-db.ts`, Geschenkplaner). Änderungen ggü. Original:
//  - Verbindung: shared `getDb()` (konsolidierte DB, Singleton) statt eigener better-sqlite3-Datei.
//  - KEIN `db.close()` (Singleton darf nicht geschlossen werden).
//  - KEINE lokale `getGeschenkDb()`/CREATE TABLE/Migrationen mehr (Tabellen sind seed-seitig konsolidiert).
//  - Tabellen präfixiert: kinder→geschenk_kinder, ereignisse→geschenk_ereignisse, geschenke→geschenk_geschenke,
//    anlass_config→geschenk_anlass_config, vergangene_geschenke→geschenk_vergangene_geschenke.
//  - `any`-Casts durch `unknown[]`/`Record<string, unknown>` ersetzt (strict TS), Logik/SQL/Signaturen 1:1.
import { getDb } from "@/server/db/connection";

/* ── Types ── */
export interface Kind {
  id: number;
  name: string;
  geburtsdatum: string | null;
  profil: string | null;
  negativliste: string | null;
  profil_bestaetigt_am: string | null;
  erstellt_am: string;
  aktualisiert_am: string;
}

export interface AnlassConfig {
  id: number;
  kind_id: number;
  anlass: string;
  aktiv: number;
  budget_min: number | null;
  budget_max: number | null;
}

export interface Ereignis {
  id: number;
  kind_id: number;
  anlass: string;
  datum: string;
  jahr: number;
  alter_zum_ereignis: number | null;
  profil_snapshot: string | null;
  profil_bestaetigung_angefragt: number;
  profil_bestaetigt: number;
  recherche_gestartet: number;
  recherche_abgeschlossen: number;
  erinnerungen_aktiv: number;
  erstellt_am: string;
  // Joined fields
  kind_name?: string;
  geburtsdatum?: string;
  profil?: string;
  budget_min?: number | null;
  budget_max?: number | null;
  geschenke?: Geschenk[];
  geschenke_count?: number;
  geschenke_ausgaben?: number;
  geschenke_status?: Record<string, number>;
}

export interface Geschenk {
  id: number;
  ereignis_id: number | null;
  kind_id: number;
  titel: string;
  beschreibung: string | null;
  preis: number | null;
  url: string | null;
  shop: string | null;
  status: string;
  ist_manuell: number;
  quelle: string | null;
  notizen: string | null;
  bild_url: string | null;
  ranking: number | null;
  begruendung: string | null;
  erstellt_am: string;
  aktualisiert_am: string;
  kind_name?: string;
}

export interface VergangeneGeschenk {
  id: number;
  kind_id: number;
  titel: string;
  anlass: string | null;
  jahr: number | null;
  notizen: string | null;
  erstellt_am: string;
  kind_name?: string;
}

/* ── Easter Calculation (Gauss) ── */
export function osterSonntag(year: number): string {
  const a = year % 19;
  const b = Math.floor(year / 100);
  const c = year % 100;
  const d = Math.floor(b / 4);
  const e = b % 4;
  const f = Math.floor((b + 8) / 25);
  const g = Math.floor((b - f + 1) / 3);
  const h = (19 * a + b - d - g + 15) % 30;
  const i = Math.floor(c / 4);
  const k = c % 4;
  const l = (32 + 2 * e + 2 * i - h - k) % 7;
  const m = Math.floor((a + 11 * h + 22 * l) / 451);
  const month = Math.floor((h + l - 7 * m + 114) / 31);
  const day = ((h + l - 7 * m + 114) % 31) + 1;
  return `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
}

export function berechneAlter(geburtsdatum: string, ereignisDatum: string): number {
  const geb = new Date(geburtsdatum);
  const erg = new Date(ereignisDatum);
  let alter = erg.getFullYear() - geb.getFullYear();
  const monthDiff = erg.getMonth() - geb.getMonth();
  if (monthDiff < 0 || (monthDiff === 0 && erg.getDate() < geb.getDate())) {
    alter--;
  }
  return alter;
}

/* ── Kinder ── */
export function getAllKinder(): (Kind & { naechste_ereignisse: Ereignis[]; anlaesse: AnlassConfig[] })[] {
  const db = getDb();
  const kinder = db.prepare('SELECT * FROM geschenk_kinder ORDER BY name').all() as Kind[];
  const result = kinder.map(k => {
    const naechste_ereignisse = db.prepare(
      "SELECT * FROM geschenk_ereignisse WHERE kind_id = ? AND datum >= date('now') ORDER BY datum LIMIT 3"
    ).all(k.id) as Ereignis[];
    const anlaesse = db.prepare('SELECT * FROM geschenk_anlass_config WHERE kind_id = ?').all(k.id) as AnlassConfig[];
    return { ...k, naechste_ereignisse, anlaesse };
  });
  return result;
}

export function getKind(id: number): Kind | undefined {
  const db = getDb();
  const kind = db.prepare('SELECT * FROM geschenk_kinder WHERE id = ?').get(id) as Kind | undefined;
  return kind;
}

export function addKind(data: { name: string; geburtsdatum?: string | null; profil?: string | null; negativliste?: string | null }): number {
  const db = getDb();
  const result = db.prepare(
    'INSERT INTO geschenk_kinder (name, geburtsdatum, profil, negativliste) VALUES (?, ?, ?, ?)'
  ).run(data.name, data.geburtsdatum || null, data.profil || null, data.negativliste || null);

  const kindId = result.lastInsertRowid as number;
  const insertConfig = db.prepare('INSERT INTO geschenk_anlass_config (kind_id, anlass) VALUES (?, ?)');
  for (const anlass of ['geburtstag', 'ostern', 'weihnachten']) {
    insertConfig.run(kindId, anlass);
  }
  return kindId;
}

export function updateKind(id: number, data: Partial<Kind>): boolean {
  const db = getDb();
  const fields: string[] = [];
  const values: unknown[] = [];
  const allowed = ['name', 'geburtsdatum', 'profil', 'negativliste'];
  for (const key of allowed) {
    if (key in data) {
      fields.push(`${key} = ?`);
      values.push((data as Record<string, unknown>)[key]);
    }
  }
  if (fields.length === 0) { return false; }
  fields.push("aktualisiert_am = datetime('now')");
  values.push(id);
  const result = db.prepare(`UPDATE geschenk_kinder SET ${fields.join(', ')} WHERE id = ?`).run(...values);
  return result.changes > 0;
}

export function deleteKind(id: number): boolean {
  const db = getDb();
  const result = db.prepare('DELETE FROM geschenk_kinder WHERE id = ?').run(id);
  return result.changes > 0;
}

export function bestaetigeProfil(id: number): boolean {
  const db = getDb();
  db.prepare(
    "UPDATE geschenk_kinder SET profil_bestaetigt_am = datetime('now'), aktualisiert_am = datetime('now') WHERE id = ?"
  ).run(id);
  db.prepare(
    'UPDATE geschenk_ereignisse SET profil_bestaetigt = 1, profil_snapshot = (SELECT profil FROM geschenk_kinder WHERE id = ?) WHERE kind_id = ? AND profil_bestaetigung_angefragt = 1 AND profil_bestaetigt = 0'
  ).run(id, id);
  return true;
}

/* ── Anlass Config ── */
export function getAnlaesse(kindId: number): AnlassConfig[] {
  const db = getDb();
  const anlaesse = db.prepare('SELECT * FROM geschenk_anlass_config WHERE kind_id = ?').all(kindId) as AnlassConfig[];
  return anlaesse;
}

export function setAnlaesse(kindId: number, configs: { anlass: string; aktiv?: number; budget_min?: number | null; budget_max?: number | null }[]): AnlassConfig[] {
  const db = getDb();
  const upsert = db.prepare(`
    INSERT INTO geschenk_anlass_config (kind_id, anlass, aktiv, budget_min, budget_max)
    VALUES (?, ?, ?, ?, ?)
    ON CONFLICT(kind_id, anlass) DO UPDATE SET
      aktiv = excluded.aktiv,
      budget_min = excluded.budget_min,
      budget_max = excluded.budget_max
  `);
  const transaction = db.transaction(() => {
    for (const c of configs) {
      upsert.run(kindId, c.anlass, c.aktiv ?? 1, c.budget_min ?? null, c.budget_max ?? null);
    }
  });
  transaction();
  const result = db.prepare('SELECT * FROM geschenk_anlass_config WHERE kind_id = ?').all(kindId) as AnlassConfig[];
  return result;
}

/* ── Ereignisse ── */
export function getEreignisse(kindId?: number): Ereignis[] {
  const db = getDb();
  let sql = `
    SELECT e.*, k.name as kind_name, k.geburtsdatum,
      ac.budget_min, ac.budget_max
    FROM geschenk_ereignisse e
    JOIN geschenk_kinder k ON e.kind_id = k.id
    LEFT JOIN geschenk_anlass_config ac ON ac.kind_id = e.kind_id AND ac.anlass = e.anlass
    WHERE e.datum >= date('now', '-30 days')
  `;
  const params: unknown[] = [];
  if (kindId) { sql += ' AND e.kind_id = ?'; params.push(kindId); }
  sql += ' ORDER BY e.datum ASC';

  const ereignisse = db.prepare(sql).all(...params) as Ereignis[];
  const getGeschenke = db.prepare('SELECT * FROM geschenk_geschenke WHERE ereignis_id = ? ORDER BY status, titel');
  const result = ereignisse.map(e => ({
    ...e,
    geschenke: getGeschenke.all(e.id) as Geschenk[],
  }));
  return result;
}

export function getEreignis(id: number): Ereignis | undefined {
  const db = getDb();
  const ereignis = db.prepare(`
    SELECT e.*, k.name as kind_name, k.geburtsdatum, k.profil,
      ac.budget_min, ac.budget_max
    FROM geschenk_ereignisse e
    JOIN geschenk_kinder k ON e.kind_id = k.id
    LEFT JOIN geschenk_anlass_config ac ON ac.kind_id = e.kind_id AND ac.anlass = e.anlass
    WHERE e.id = ?
  `).get(id) as Ereignis | undefined;

  if (ereignis) {
    ereignis.geschenke = db.prepare(
      'SELECT * FROM geschenk_geschenke WHERE ereignis_id = ? ORDER BY status, titel'
    ).all(ereignis.id) as Geschenk[];
  }
  return ereignis;
}

export function generiereEreignisse(): Ereignis[] {
  const db = getDb();
  const now = new Date();
  const currentYear = now.getFullYear();
  const years = [currentYear, currentYear + 1];

  const kinder = db.prepare('SELECT * FROM geschenk_kinder').all() as Kind[];
  const insertEreignis = db.prepare(
    'INSERT INTO geschenk_ereignisse (kind_id, anlass, datum, jahr, alter_zum_ereignis) VALUES (?, ?, ?, ?, ?)'
  );
  const checkExists = db.prepare(
    'SELECT id FROM geschenk_ereignisse WHERE kind_id = ? AND anlass = ? AND jahr = ?'
  );

  const transaction = db.transaction(() => {
    for (const kind of kinder) {
      const configs = db.prepare(
        'SELECT * FROM geschenk_anlass_config WHERE kind_id = ? AND aktiv = 1'
      ).all(kind.id) as AnlassConfig[];

      for (const config of configs) {
        for (const jahr of years) {
          const existing = checkExists.get(kind.id, config.anlass, jahr);
          if (existing) continue;

          // Skip birthday events if the child has no birth date
          if (config.anlass === 'geburtstag' && !kind.geburtsdatum) continue;

          let datum: string;
          if (config.anlass === 'geburtstag') {
            const gebParts = kind.geburtsdatum!.split('-');
            datum = `${jahr}-${gebParts[1]}-${gebParts[2]}`;
          } else if (config.anlass === 'weihnachten') {
            datum = `${jahr}-12-24`;
          } else {
            datum = osterSonntag(jahr);
          }

          const alter = kind.geburtsdatum ? berechneAlter(kind.geburtsdatum, datum) : null;
          insertEreignis.run(kind.id, config.anlass, datum, jahr, alter);
        }
      }
    }
  });
  transaction();

  const ereignisse = db.prepare(
    "SELECT * FROM geschenk_ereignisse WHERE datum >= date('now') ORDER BY datum"
  ).all() as Ereignis[];
  return ereignisse;
}

/* ── Geschenke ── */
export function getGeschenke(ereignisId?: number, kindId?: number, status?: string | string[]): Geschenk[] {
  const db = getDb();
  let sql = 'SELECT g.*, k.name as kind_name, e.anlass, e.jahr, e.datum FROM geschenk_geschenke g JOIN geschenk_kinder k ON g.kind_id = k.id LEFT JOIN geschenk_ereignisse e ON g.ereignis_id = e.id';
  const params: unknown[] = [];
  const conditions: string[] = [];
  if (ereignisId) { conditions.push('g.ereignis_id = ?'); params.push(ereignisId); }
  if (kindId) { conditions.push('g.kind_id = ?'); params.push(kindId); }
  if (status) {
    if (Array.isArray(status)) {
      conditions.push(`g.status IN (${status.map(() => '?').join(',')})`);
      params.push(...status);
    } else {
      conditions.push('g.status = ?'); params.push(status);
    }
  }
  if (conditions.length) sql += ' WHERE ' + conditions.join(' AND ');
  sql += ' ORDER BY g.erstellt_am DESC';
  const result = db.prepare(sql).all(...params) as Geschenk[];
  return result;
}

export function addGeschenk(data: Partial<Geschenk>): number {
  const db = getDb();
  let kindId = data.kind_id;
  if (!kindId && data.ereignis_id) {
    const erg = db.prepare('SELECT kind_id FROM geschenk_ereignisse WHERE id = ?').get(data.ereignis_id) as { kind_id: number } | undefined;
    if (erg) kindId = erg.kind_id;
  }
  const result = db.prepare(`
    INSERT INTO geschenk_geschenke (ereignis_id, kind_id, titel, beschreibung, preis, url, shop, status, ist_manuell, quelle, notizen, bild_url, ranking, begruendung)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(
    data.ereignis_id || null, kindId, data.titel,
    data.beschreibung || null, data.preis || null, data.url || null, data.shop || null,
    data.status || 'vorschlag', data.ist_manuell ? 1 : 0, data.quelle || null, data.notizen || null,
    data.bild_url || null, data.ranking || null, data.begruendung || null
  );
  return result.lastInsertRowid as number;
}

export function getGeschenk(id: number): Geschenk | undefined {
  const db = getDb();
  const geschenk = db.prepare('SELECT * FROM geschenk_geschenke WHERE id = ?').get(id) as Geschenk | undefined;
  return geschenk;
}

export function updateGeschenk(id: number, data: Partial<Geschenk>): boolean {
  const db = getDb();
  const allowed = ['ereignis_id', 'titel', 'beschreibung', 'preis', 'url', 'shop', 'status', 'quelle', 'notizen', 'bild_url', 'ranking', 'begruendung'];
  const fields: string[] = [];
  const values: unknown[] = [];
  for (const key of allowed) {
    if (key in data) {
      fields.push(`${key} = ?`);
      values.push((data as Record<string, unknown>)[key]);
    }
  }
  if (fields.length === 0) { return false; }
  fields.push("aktualisiert_am = datetime('now')");
  values.push(id);
  const result = db.prepare(`UPDATE geschenk_geschenke SET ${fields.join(', ')} WHERE id = ?`).run(...values);
  return result.changes > 0;
}

export function deleteGeschenk(id: number): boolean {
  const db = getDb();
  const result = db.prepare('DELETE FROM geschenk_geschenke WHERE id = ?').run(id);
  return result.changes > 0;
}

export function vergebeGeschenk(id: number): boolean {
  const db = getDb();
  const geschenk = db.prepare('SELECT * FROM geschenk_geschenke WHERE id = ?').get(id) as Geschenk | undefined;
  if (!geschenk) { return false; }

  const ereignis = geschenk.ereignis_id
    ? db.prepare('SELECT * FROM geschenk_ereignisse WHERE id = ?').get(geschenk.ereignis_id) as Ereignis | undefined
    : null;

  const transaction = db.transaction(() => {
    db.prepare(
      'INSERT INTO geschenk_vergangene_geschenke (kind_id, titel, anlass, jahr, notizen) VALUES (?, ?, ?, ?, ?)'
    ).run(
      geschenk.kind_id, geschenk.titel,
      ereignis ? ereignis.anlass : null,
      ereignis ? ereignis.jahr : new Date().getFullYear(),
      geschenk.notizen
    );
    db.prepare("UPDATE geschenk_geschenke SET status = 'vergeben', aktualisiert_am = datetime('now') WHERE id = ?").run(id);
  });
  transaction();
  return true;
}

export function schonGeschenkt(id: number): boolean {
  const db = getDb();
  const geschenk = db.prepare('SELECT * FROM geschenk_geschenke WHERE id = ?').get(id) as Geschenk | undefined;
  if (!geschenk) { return false; }

  const ereignis = geschenk.ereignis_id
    ? db.prepare('SELECT * FROM geschenk_ereignisse WHERE id = ?').get(geschenk.ereignis_id) as Ereignis | undefined
    : null;

  const transaction = db.transaction(() => {
    // Move to vergangene_geschenke
    db.prepare(
      'INSERT INTO geschenk_vergangene_geschenke (kind_id, titel, anlass, jahr, notizen) VALUES (?, ?, ?, ?, ?)'
    ).run(
      geschenk.kind_id, geschenk.titel,
      ereignis ? ereignis.anlass : null,
      ereignis ? ereignis.jahr : new Date().getFullYear(),
      'Schon geschenkt (aus Bewertung markiert)'
    );
    // Delete the suggestion so it doesn't reappear
    db.prepare('DELETE FROM geschenk_geschenke WHERE id = ?').run(id);
  });
  transaction();
  return true;
}

/* ── Vergangene Geschenke ── */
export function getVergangeneGeschenke(kindId?: number): VergangeneGeschenk[] {
  const db = getDb();
  let sql = 'SELECT vg.*, k.name as kind_name FROM geschenk_vergangene_geschenke vg JOIN geschenk_kinder k ON vg.kind_id = k.id';
  const params: unknown[] = [];
  if (kindId) { sql += ' WHERE vg.kind_id = ?'; params.push(kindId); }
  sql += ' ORDER BY vg.jahr DESC, vg.anlass';
  const result = db.prepare(sql).all(...params) as VergangeneGeschenk[];
  return result;
}

export function addVergangeneGeschenk(data: { kind_id: number; titel: string; anlass?: string; jahr?: number; notizen?: string }): number {
  const db = getDb();
  const result = db.prepare(
    'INSERT INTO geschenk_vergangene_geschenke (kind_id, titel, anlass, jahr, notizen) VALUES (?, ?, ?, ?, ?)'
  ).run(data.kind_id, data.titel, data.anlass || null, data.jahr || null, data.notizen || null);
  return result.lastInsertRowid as number;
}

export function deleteVergangeneGeschenk(id: number): boolean {
  const db = getDb();
  const result = db.prepare('DELETE FROM geschenk_vergangene_geschenke WHERE id = ?').run(id);
  return result.changes > 0;
}

/* ── Dashboard ── */
export function getDashboard() {
  const db = getDb();

  const anstehende = db.prepare(`
    SELECT e.*, k.name as kind_name, ac.budget_min, ac.budget_max
    FROM geschenk_ereignisse e
    JOIN geschenk_kinder k ON e.kind_id = k.id
    LEFT JOIN geschenk_anlass_config ac ON ac.kind_id = e.kind_id AND ac.anlass = e.anlass
    WHERE e.datum >= date('now')
      AND (
        (SELECT COUNT(*) FROM geschenk_geschenke g WHERE g.ereignis_id = e.id) > 0
        OR julianday(e.datum) - julianday('now') <= 61
      )
    ORDER BY e.datum ASC LIMIT 10
  `).all() as Ereignis[];

  for (const e of anstehende) {
    const geschenke = db.prepare('SELECT * FROM geschenk_geschenke WHERE ereignis_id = ?').all(e.id) as Geschenk[];
    e.geschenke_count = geschenke.length;
    e.geschenke_ausgaben = geschenke
      .filter(g => ['ausgewaehlt', 'bestellt', 'verpackt', 'vergeben'].includes(g.status))
      .reduce((sum, g) => sum + (g.preis || 0), 0);
    e.geschenke_status = {
      vorschlag: geschenke.filter(g => g.status === 'vorschlag').length,
      ausgewaehlt: geschenke.filter(g => g.status === 'ausgewaehlt').length,
      bestellt: geschenke.filter(g => g.status === 'bestellt').length,
      verpackt: geschenke.filter(g => g.status === 'verpackt').length,
      vergeben: geschenke.filter(g => g.status === 'vergeben').length,
    };
  }

  const offeneBestaetigung = db.prepare(`
    SELECT e.*, k.name as kind_name
    FROM geschenk_ereignisse e JOIN geschenk_kinder k ON e.kind_id = k.id
    WHERE e.profil_bestaetigung_angefragt = 1 AND e.profil_bestaetigt = 0
  `).all() as Ereignis[];

  const kinderCount = (db.prepare('SELECT COUNT(*) as c FROM geschenk_kinder').get() as { c: number }).c;
  const ereignisseCount = (db.prepare("SELECT COUNT(*) as c FROM geschenk_ereignisse WHERE datum >= date('now')").get() as { c: number }).c;

  return {
    anstehende,
    offene_bestaetigung: offeneBestaetigung,
    stats: { kinder: kinderCount, anstehende_ereignisse: ereignisseCount },
  };
}
