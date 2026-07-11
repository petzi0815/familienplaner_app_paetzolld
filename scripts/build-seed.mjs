// Baut seed/familienplaner.db + seed/media/ aus den Legacy-Daten (_legacy/).
// - wendet db/migrations/0001+0002 an (Infra + Domänen-Schema)
// - kopiert alle Domänen-Tabellen ID-erhaltend (ATTACH + INSERT SELECT, inkl. BLOBs)
// - zieht Media nach seed/media/<bereich>/<datei> um, baut media_assets, schreibt Bildpfade → storage_keys
// - importiert Verträge (vertraege.json) + seedet die Lebensbereiche-Registry
// - verifiziert Row-Counts (dst == src) und bricht bei Abweichung ab
import Database from "better-sqlite3";
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";

const ROOT = path.resolve(".");
const LEGACY_DB = path.join(ROOT, "_legacy/db");
const LEGACY_MEDIA = path.join(ROOT, "_legacy/media");
const SEED_DIR = path.join(ROOT, "seed");
const SEED_DB = path.join(SEED_DIR, "familienplaner.db");
const SEED_MEDIA = path.join(SEED_DIR, "media");
const MIGRATIONS = path.join(ROOT, "db/migrations");

// src-DB → { srcTable: dstTable } (identisch zu gen-domain-migration.mjs)
const MAP = {
  "termine.db": { termine: "termine" },
  "reisen.db": { trips: "reisen_trips", trip_activities: "reisen_trip_activities", trip_day_plans: "reisen_trip_day_plans", trip_diving: "reisen_trip_diving", trip_docs: "reisen_trip_docs", trip_emails: "reisen_trip_emails", trip_emergency: "reisen_trip_emergency", trip_flights: "reisen_trip_flights", trip_hotel: "reisen_trip_hotel", trip_links: "reisen_trip_links", trip_packing: "reisen_trip_packing", trip_phrases: "reisen_trip_phrases", trip_restaurants: "reisen_trip_restaurants", trip_samu_activities: "reisen_trip_samu_activities", trip_weather: "reisen_trip_weather", weekend_tips: "reisen_weekend_tips" },
  "samu-inventar.db": { items: "samu_items", marken: "samu_marken", bedarfsliste: "samu_bedarfsliste" },
  "wunschliste.db": { events: "wunschliste_events", items: "wunschliste_items" },
  "geschenkplaner.db": { kinder: "geschenk_kinder", ereignisse: "geschenk_ereignisse", geschenke: "geschenk_geschenke", anlass_config: "geschenk_anlass_config", vergangene_geschenke: "geschenk_vergangene_geschenke" },
  "garten.db": { pflanzen: "garten_pflanzen", samen: "garten_samen", duenger: "garten_duenger", aufgaben: "garten_aufgaben", pflanze_duenger: "garten_pflanze_duenger" },
  "vorratskammer.db": { lebensmittel: "vorrat_lebensmittel", rezepte: "vorrat_rezepte" },
  "gypsi.db": { futter: "gypsi_futter" },
  "reiniger.db": { reiniger: "reiniger_produkte", anwendungen: "reiniger_anwendungen" },
  "elisbooks.db": { books: "elisbooks_books", bookshelves: "elisbooks_bookshelves", wishlist: "elisbooks_wishlist", user_settings: "elisbooks_user_settings" },
  "ebook-wishlist.db": { wishlist: "ebook_wishlist" },
  "ha-voice.db": { entities: "ha_entities", relationships: "ha_relationships", aliases: "ha_aliases", command_log: "ha_command_log" },
};

// Bildspalten je Ziel-Tabelle → { col, multi(JSON-Array?), area(Media-Quelle) }
const IMAGE_COLS = [
  { table: "samu_items", col: "bild_pfade", multi: true, area: "samu", srcDir: "samu-inventar" },
  { table: "garten_pflanzen", col: "bild_pfade", multi: true, area: "garten", srcDir: "garten" },
  { table: "garten_samen", col: "bild_pfade", multi: true, area: "garten", srcDir: "garten" },
  { table: "garten_duenger", col: "bild_pfade", multi: true, area: "garten", srcDir: "garten" },
  { table: "gypsi_futter", col: "bild_pfad", multi: false, area: "gypsi", srcDir: "gypsi" },
  { table: "reiniger_produkte", col: "bild_pfad", multi: false, area: "reiniger", srcDir: "reiniger" },
  { table: "vorrat_lebensmittel", col: "bild_pfad", multi: false, area: "vorrat", srcDir: "vorratskammer" },
];
// Media-Quelle je area → Bereichsordner unter _legacy/media/<srcDir>/images
const MEDIA_AREAS = { samu: "samu-inventar", garten: "garten", gypsi: "gypsi", reiniger: "reiniger", vorrat: "vorratskammer" };

const mime = (f) => ({ ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png", ".webp": "image/webp", ".gif": "image/gif" }[path.extname(f).toLowerCase()] || "application/octet-stream");
const isExternal = (p) => /^https?:\/\//i.test(p) || p.startsWith("/api/");
const base = (p) => String(p).split("/").pop();

function applyMigrations(db) {
  db.exec("CREATE TABLE IF NOT EXISTS schema_migrations (version TEXT PRIMARY KEY, applied_at TEXT NOT NULL DEFAULT (datetime('now')))");
  const applied = new Set(db.prepare("SELECT version FROM schema_migrations").all().map((r) => r.version));
  const files = fs.readdirSync(MIGRATIONS).filter((f) => f.endsWith(".sql")).sort();
  for (const f of files) {
    const version = f.replace(/\.sql$/, "");
    if (applied.has(version)) continue;
    db.exec(fs.readFileSync(path.join(MIGRATIONS, f), "utf8"));
    db.prepare("INSERT INTO schema_migrations (version) VALUES (?)").run(version);
    console.log("  migration:", version);
  }
}

function main() {
  fs.mkdirSync(SEED_DIR, { recursive: true });
  for (const p of [SEED_DB, SEED_DB + "-wal", SEED_DB + "-shm"]) if (fs.existsSync(p)) fs.rmSync(p);
  fs.rmSync(SEED_MEDIA, { recursive: true, force: true });

  const db = new Database(SEED_DB);
  db.pragma("journal_mode = WAL");
  db.pragma("foreign_keys = OFF");

  console.log("→ Migrationen anwenden");
  applyMigrations(db);

  console.log("→ Domänen-Daten kopieren (ID-erhaltend)");
  const counts = [];
  for (const [dbFile, map] of Object.entries(MAP)) {
    const src = path.join(LEGACY_DB, dbFile);
    db.exec(`ATTACH DATABASE '${src.replace(/\\/g, "/")}' AS src`);
    for (const [srcT, dstT] of Object.entries(map)) {
      db.exec(`DELETE FROM "${dstT}"`);
      db.exec(`INSERT INTO "${dstT}" SELECT * FROM src."${srcT}"`);
      const dstN = db.prepare(`SELECT COUNT(*) c FROM "${dstT}"`).get().c;
      const srcN = db.prepare(`SELECT COUNT(*) c FROM src."${srcT}"`).get().c;
      counts.push({ dstT, srcN, dstN, ok: srcN === dstN });
    }
    db.exec("DETACH DATABASE src");
  }

  console.log("→ Media umziehen + media_assets + Pfad-Rewrite");
  fs.mkdirSync(SEED_MEDIA, { recursive: true });
  const insAsset = db.prepare("INSERT OR IGNORE INTO media_assets (bereich, storage_key, original_name, mime, bytes, sha256) VALUES (?,?,?,?,?,?)");
  let assetCount = 0;
  for (const [area, srcDir] of Object.entries(MEDIA_AREAS)) {
    const dir = path.join(LEGACY_MEDIA, srcDir, "images");
    if (!fs.existsSync(dir)) continue;
    const outDir = path.join(SEED_MEDIA, area);
    fs.mkdirSync(outDir, { recursive: true });
    for (const file of fs.readdirSync(dir)) {
      const buf = fs.readFileSync(path.join(dir, file));
      fs.writeFileSync(path.join(outDir, file), buf);
      insAsset.run(area, `${area}/${file}`, file, mime(file), buf.length, crypto.createHash("sha256").update(buf).digest("hex"));
      assetCount++;
    }
  }
  // Bildpfad-Spalten → storage_keys
  let rewritten = 0, missing = 0;
  const availByArea = {};
  for (const area of Object.keys(MEDIA_AREAS)) {
    const d = path.join(SEED_MEDIA, area);
    availByArea[area] = fs.existsSync(d) ? new Set(fs.readdirSync(d)) : new Set();
  }
  for (const spec of IMAGE_COLS) {
    const rows = db.prepare(`SELECT id, "${spec.col}" AS v FROM "${spec.table}" WHERE "${spec.col}" IS NOT NULL AND "${spec.col}" <> ''`).all();
    const upd = db.prepare(`UPDATE "${spec.table}" SET "${spec.col}" = ? WHERE id = ?`);
    for (const r of rows) {
      const mapRef = (ref) => {
        if (!ref) return ref;
        if (isExternal(ref)) return ref;
        const b = base(ref);
        if (!availByArea[spec.area].has(b)) missing++;
        return `${spec.area}/${b}`;
      };
      let next;
      if (spec.multi) {
        let arr; try { arr = JSON.parse(r.v); } catch { arr = [r.v]; }
        if (!Array.isArray(arr)) arr = [arr];
        next = JSON.stringify(arr.map(mapRef));
      } else {
        next = mapRef(r.v);
      }
      if (next !== r.v) { upd.run(next, r.id); rewritten++; }
    }
  }

  console.log("→ Verträge importieren (vertraege.json)");
  const vj = JSON.parse(fs.readFileSync(path.join(ROOT, "_legacy/vertraege.json"), "utf8"));
  const insV = db.prepare(`INSERT INTO vertraege (kategorie, anbieter, bezeichnung, kundennummer, vertragsnummer, kosten, kosten_intervall, beginn, laufzeit_bis, kuendigungsfrist, verlaengerung, status, notizen, metadata) VALUES (@kategorie,@anbieter,@bezeichnung,@kundennummer,@vertragsnummer,@kosten,@kosten_intervall,@beginn,@laufzeit_bis,@kuendigungsfrist,@verlaengerung,@status,@notizen,@metadata)`);
  let vCount = 0;
  for (const cat of vj.categories || []) {
    for (const c of cat.contracts || []) {
      insV.run({
        kategorie: cat.name ?? null,
        anbieter: c.provider ?? null,
        bezeichnung: c.type ?? c.name ?? null,
        kundennummer: c.customerNr ?? c.kundennummer ?? null,
        vertragsnummer: c.contractNr ?? null,
        kosten: typeof c.amount === "number" ? c.amount : (c.amount ? Number(String(c.amount).replace(",", ".")) || null : null),
        kosten_intervall: c.interval ?? null,
        beginn: c.start ?? c.beginn ?? null,
        laufzeit_bis: c.until ?? c.laufzeit_bis ?? null,
        kuendigungsfrist: c.cancellation ?? c.kuendigungsfrist ?? null,
        verlaengerung: c.renewal ?? null,
        status: c.status ?? "aktiv",
        notizen: c.details ?? c.notes ?? null,
        metadata: JSON.stringify({ ...c, _category: { name: cat.name, icon: cat.icon, color: cat.color } }),
      });
      vCount++;
    }
  }

  console.log("→ Lebensbereiche-Registry seeden");
  const LB = [
    ["samu", "Samu", "Kleidung, Spielzeug & mehr", "👶🧸", "from-[#FF9F0A] via-[#FF6B6B] to-[#AF52DE]", "/api/v1/samu"],
    ["gypsi", "Gypsi", "Futter-Vorlieben & Tracking", "🐱", "from-[#FF8C00] via-[#FF6600] to-[#FF4500]", "/api/v1/gypsi"],
    ["smarthome", "Smart Home", "Geräte, Lichter & Sensoren", "🏠💡", "from-[#007AFF] via-[#5856D6] to-[#AF52DE]", "/api/v1/smarthome"],
    ["garten", "Garten", "Pflanzen, Samen & Pflege", "🌱🌳", "from-[#34C759] via-[#30D158] to-[#00C7BE]", "/api/v1/garten"],
    ["vertraege", "Verträge", "Versicherungen & Kosten", "📋💰", "from-[#5856D6] via-[#AF52DE] to-[#FF2D55]", "/api/v1/vertraege"],
    ["buecher", "Bücher", "Elitas Wishlist", "📚✨", "from-[#FF2D55] via-[#FF6B6B] to-[#FF9500]", "/api/v1/ebooks"],
    ["wunschliste", "Wunschliste", "Geschenke für Samu", "🎁🎀", "from-[#AF52DE] via-[#FF2D55] to-[#FF9500]", "/api/v1/wunschliste"],
    ["termine", "Termine", "Kalender & Erinnerungen", "📅🗓️", "from-[#007AFF] via-[#5856D6] to-[#34C759]", "/api/v1/termine"],
    ["reisen", "Reisen", "Urlaube & Wochenend-Tipps", "✈️🌍", "from-[#FF9500] via-[#FF6B6B] to-[#5856D6]", "/api/v1/reisen"],
    ["geschenkplaner", "Geschenkplaner", "Geschenke für jeden Anlass", "🎁🎀", "from-[#F59E0B] via-[#EF4444] to-[#8B5CF6]", "/api/v1/geschenke"],
    ["vorratskammer", "Vorratskammer", "Lebensmittel & Einkaufsliste", "🍕🗄️", "from-[#F97316] via-[#FB923C] to-[#FBBF24]", "/api/v1/vorrat"],
    ["reiniger", "Reiniger", "Putzmittel & Fleckenhilfe", "🧽🧴", "from-[#0EA5E9] via-[#14B8A6] to-[#84CC16]", "/api/v1/reiniger"],
    ["elisbooks", "Büchersammlung", "Elitas physische Bücher", "📖", "from-[#92400E] via-[#B45309] to-[#D97706]", "/api/v1/elisbooks"],
  ];
  const insLB = db.prepare("INSERT OR IGNORE INTO lebensbereiche (key, titel, beschreibung, emoji, gradient, api_base, sort) VALUES (?,?,?,?,?,?,?)");
  LB.forEach((r, i) => insLB.run(r[0], r[1], r[2], r[3], r[4], r[5], i));

  db.pragma("wal_checkpoint(TRUNCATE)");
  db.close();

  // ── Verifikation ──
  console.log("\n=== VERIFIKATION (dst == src) ===");
  let fail = 0, totalRows = 0;
  for (const c of counts) {
    totalRows += c.dstN;
    if (!c.ok) { fail++; console.log(`  ✗ ${c.dstT}: src=${c.srcN} dst=${c.dstN}`); }
  }
  console.log(`Tabellen: ${counts.length} · Zeilen gesamt: ${totalRows} · Verträge: ${vCount}`);
  console.log(`Media-Assets: ${assetCount} · Pfade umgeschrieben: ${rewritten} · fehlende Dateien (referenziert, nicht im Export): ${missing}`);
  if (fail) { console.error(`\n❌ ${fail} Tabellen mit Row-Count-Abweichung!`); process.exit(1); }
  console.log("\n✅ Alle Row-Counts stimmen. Seed geschrieben:", path.relative(ROOT, SEED_DB));
}

main();
