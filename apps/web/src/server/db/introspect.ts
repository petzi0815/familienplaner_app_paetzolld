import type BetterSqlite3 from "better-sqlite3";

export interface ColumnInfo {
  name: string;
  type: string;
  notnull: number;
  pk: number;
  dflt: unknown;
}

const cache = new Map<string, ColumnInfo[]>();

/** Spalten einer Tabelle (gecacht). */
export function getColumns(db: BetterSqlite3.Database, table: string): ColumnInfo[] {
  const hit = cache.get(table);
  if (hit) return hit;
  const cols = (db.prepare(`PRAGMA table_info("${table}")`).all() as {
    name: string; type: string; notnull: number; pk: number; dflt_value: unknown;
  }[]).map((r) => ({ name: r.name, type: r.type, notnull: r.notnull, pk: r.pk, dflt: r.dflt_value }));
  cache.set(table, cols);
  return cols;
}

export function columnNames(db: BetterSqlite3.Database, table: string): string[] {
  return getColumns(db, table).map((c) => c.name);
}

/** Text-Spalten (für Default-Suche), ohne große JSON/BLOB-Felder. */
export function textColumns(db: BetterSqlite3.Database, table: string): string[] {
  const skip = new Set(["metadata", "attributes", "file_data", "profil", "profil_snapshot", "bild_pfade", "meta_json", "price_comparison"]);
  return getColumns(db, table)
    .filter((c) => /TEXT|CHAR|CLOB/i.test(c.type) && !skip.has(c.name))
    .map((c) => c.name);
}

export function hasColumn(db: BetterSqlite3.Database, table: string, col: string): boolean {
  return getColumns(db, table).some((c) => c.name === col);
}
