import type BetterSqlite3 from "better-sqlite3";

// Liest CHECK(col IN ('a','b',...))-Constraints je Tabelle aus dem CREATE-SQL,
// damit die API erlaubte Werte kennt (Validierung + Schema-Ausgabe).
const cache = new Map<string, Record<string, string[]>>();

export function enumConstraints(db: BetterSqlite3.Database, table: string): Record<string, string[]> {
  const hit = cache.get(table);
  if (hit) return hit;
  const row = db.prepare("SELECT sql FROM sqlite_master WHERE type='table' AND name=?").get(table) as { sql?: string } | undefined;
  const sql = row?.sql ?? "";
  const result: Record<string, string[]> = {};
  const re = /CHECK\s*\(\s*["'`]?([a-z0-9_]+)["'`]?\s+IN\s*\(([^)]*)\)/gi;
  let m: RegExpExecArray | null;
  while ((m = re.exec(sql))) {
    const col = m[1];
    const vals = [...m[2].matchAll(/'([^']*)'/g)].map((x) => x[1]);
    if (vals.length) result[col] = vals;
  }
  cache.set(table, result);
  return result;
}

/** Prüft die Werte gegen die Enum-CHECKs. Gibt den ersten Verstoß zurück (oder null). */
export function checkEnums(db: BetterSqlite3.Database, table: string, values: Record<string, unknown>): { column: string; value: unknown; allowed: string[] } | null {
  const enums = enumConstraints(db, table);
  for (const [col, allowed] of Object.entries(enums)) {
    const v = values[col];
    if (v == null || v === "") continue; // NULL/leer erlaubt die CHECK-Klausel
    if (!allowed.includes(String(v))) return { column: col, value: v, allowed };
  }
  return null;
}
