// Dumpt Schema + Row-Counts aller Legacy-SQLite nach _legacy/schemas.json
import Database from "better-sqlite3";
import fs from "node:fs";
import path from "node:path";

const DBDIR = path.resolve("_legacy/db");
const files = fs.readdirSync(DBDIR).filter((f) => f.endsWith(".db"));
const out = {};

for (const file of files) {
  const db = new Database(path.join(DBDIR, file), { readonly: true });
  const objs = db
    .prepare("SELECT type, name, tbl_name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name")
    .all();
  const tables = [];
  const indexes = [];
  const triggers = [];
  for (const o of objs) {
    if (o.type === "table") {
      let rows = null;
      try {
        rows = db.prepare(`SELECT COUNT(*) AS c FROM "${o.name}"`).get().c;
      } catch {
        rows = "n/a";
      }
      let cols = [];
      try {
        cols = db.prepare(`PRAGMA table_info("${o.name}")`).all().map((c) => ({
          name: c.name, type: c.type, notnull: c.notnull, pk: c.pk, dflt: c.dflt_value,
        }));
      } catch { /* fts virtual */ }
      tables.push({ name: o.name, rows, sql: o.sql, cols });
    } else if (o.type === "index") {
      indexes.push({ name: o.name, tbl: o.tbl_name, sql: o.sql });
    } else if (o.type === "trigger") {
      triggers.push({ name: o.name, tbl: o.tbl_name, sql: o.sql });
    }
  }
  out[file] = { tables, indexes, triggers };
  db.close();
}

fs.writeFileSync(path.resolve("_legacy/schemas.json"), JSON.stringify(out, null, 2));
// Kompakte Übersicht auf stdout
for (const [file, info] of Object.entries(out)) {
  console.log(`\n### ${file}`);
  for (const t of info.tables) {
    const virt = /VIRTUAL TABLE/i.test(t.sql || "") ? " [FTS/virtual]" : "";
    console.log(`  - ${t.name} (${t.rows} rows)${virt}: ${t.cols.map((c) => c.name).join(", ")}`);
  }
}
console.log("\nGeschrieben: _legacy/schemas.json");
