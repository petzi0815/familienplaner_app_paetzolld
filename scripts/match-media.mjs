import Database from "better-sqlite3";
import fs from "node:fs";
import path from "node:path";

// Sammelt alle lokalen Bild-Referenzen und prüft Existenz im Media-Verzeichnis.
const MEDIA = path.resolve("_legacy/media");
const basenamesInDir = (area) => {
  const dir = path.join(MEDIA, area, "images");
  if (!fs.existsSync(dir)) return new Set();
  return new Set(fs.readdirSync(dir));
};

const refsFromJsonArray = (val) => {
  if (!val) return [];
  try { const a = JSON.parse(val); return Array.isArray(a) ? a : []; } catch { return val ? [val] : []; }
};
const isExternal = (p) => /^https?:\/\//i.test(p) || p.startsWith("/api/");
const base = (p) => p.split("/").pop();

function analyze(area, file, table, col, multi) {
  const db = new Database("_legacy/db/" + file, { readonly: true });
  const rows = db.prepare(`SELECT id, ${col} AS v FROM ${table} WHERE ${col} IS NOT NULL AND ${col}<>''`).all();
  db.close();
  const files = basenamesInDir(area);
  let total = 0, ext = 0, hit = 0, miss = 0;
  const misses = [];
  for (const r of rows) {
    const refs = multi ? refsFromJsonArray(r.v) : [r.v];
    for (const ref of refs) {
      if (!ref) continue;
      total++;
      if (isExternal(ref)) { ext++; continue; }
      const b = base(ref);
      if (files.has(b)) hit++; else { miss++; if (misses.length < 5) misses.push(`${r.id}:${ref}`); }
    }
  }
  console.log(`\n[${area}] ${file} ${table}.${col} — refs:${total} extern:${ext} hit:${hit} MISS:${miss} / dateien-im-dir:${files.size}`);
  if (misses.length) console.log("   miss-bsp:", misses.join(" | "));
}

analyze("samu-inventar", "samu-inventar.db", "items", "bild_pfade", true);
analyze("garten", "garten.db", "pflanzen", "bild_pfade", true);
analyze("garten", "garten.db", "samen", "bild_pfade", true);
analyze("garten", "garten.db", "duenger", "bild_pfade", true);
analyze("gypsi", "gypsi.db", "futter", "bild_pfad", false);
analyze("reiniger", "reiniger.db", "reiniger", "bild_pfad", false);

// Wieviele Dateien im Dir werden NICHT referenziert (Waisen)?
console.log("\n== Datei-Namensbeispiele je Media-Dir ==");
for (const area of ["samu-inventar","garten","gypsi","reiniger"]) {
  const f = [...basenamesInDir(area)].slice(0, 4);
  console.log(area, "→", f.join(", "));
}
