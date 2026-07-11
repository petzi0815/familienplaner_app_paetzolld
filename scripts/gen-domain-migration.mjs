// Generiert db/migrations/0002_domains.sql aus den echten Legacy-Schemata.
// Präfixiert Tabellennamen (Kollisionen: items/wishlist/events/user_settings) und
// schreibt domänen-interne FK-REFERENCES mit um. FTS/Shadow/Trigger werden bewusst
// ausgelassen (FTS wird in einer späteren Migration/Unified-Search neu aufgebaut).
import fs from "node:fs";
import path from "node:path";

const schemas = JSON.parse(fs.readFileSync(path.resolve("_legacy/schemas.json"), "utf8"));

// src-DB → { srcTable: dstTable }
const MAP = {
  "termine.db": { termine: "termine" },
  "reisen.db": {
    trips: "reisen_trips",
    trip_activities: "reisen_trip_activities",
    trip_day_plans: "reisen_trip_day_plans",
    trip_diving: "reisen_trip_diving",
    trip_docs: "reisen_trip_docs",
    trip_emails: "reisen_trip_emails",
    trip_emergency: "reisen_trip_emergency",
    trip_flights: "reisen_trip_flights",
    trip_hotel: "reisen_trip_hotel",
    trip_links: "reisen_trip_links",
    trip_packing: "reisen_trip_packing",
    trip_phrases: "reisen_trip_phrases",
    trip_restaurants: "reisen_trip_restaurants",
    trip_samu_activities: "reisen_trip_samu_activities",
    trip_weather: "reisen_trip_weather",
    weekend_tips: "reisen_weekend_tips",
  },
  "samu-inventar.db": { items: "samu_items", marken: "samu_marken", bedarfsliste: "samu_bedarfsliste" },
  "wunschliste.db": { events: "wunschliste_events", items: "wunschliste_items" },
  "geschenkplaner.db": {
    kinder: "geschenk_kinder",
    ereignisse: "geschenk_ereignisse",
    geschenke: "geschenk_geschenke",
    anlass_config: "geschenk_anlass_config",
    vergangene_geschenke: "geschenk_vergangene_geschenke",
  },
  "garten.db": {
    pflanzen: "garten_pflanzen",
    samen: "garten_samen",
    duenger: "garten_duenger",
    aufgaben: "garten_aufgaben",
    pflanze_duenger: "garten_pflanze_duenger",
  },
  "vorratskammer.db": { lebensmittel: "vorrat_lebensmittel", rezepte: "vorrat_rezepte" },
  "gypsi.db": { futter: "gypsi_futter" },
  "reiniger.db": { reiniger: "reiniger_produkte", anwendungen: "reiniger_anwendungen" },
  "elisbooks.db": {
    books: "elisbooks_books",
    bookshelves: "elisbooks_bookshelves",
    wishlist: "elisbooks_wishlist",
    user_settings: "elisbooks_user_settings",
  },
  "ebook-wishlist.db": { wishlist: "ebook_wishlist" },
  "ha-voice.db": {
    entities: "ha_entities",
    relationships: "ha_relationships",
    aliases: "ha_aliases",
    command_log: "ha_command_log",
  },
};

const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

function transform(sql, src, dst, domainMap) {
  // 1. Führenden Tabellennamen ersetzen → CREATE TABLE IF NOT EXISTS "dst"
  //    \b nach dem Namen verhindert, dass z.B. "books" auch "bookshelves" trifft.
  let out = sql.replace(
    new RegExp('CREATE\\s+TABLE\\s+(?:IF\\s+NOT\\s+EXISTS\\s+)?["\'`\\[]?' + esc(src) + '\\b["\'`\\]]?', 'i'),
    'CREATE TABLE IF NOT EXISTS "' + dst + '"',
  );
  // 2. domänen-interne FK-REFERENCES umschreiben (mit Wortgrenze)
  for (const [s, d] of Object.entries(domainMap)) {
    out = out.replace(
      new RegExp('REFERENCES\\s+["\'`\\[]?' + esc(s) + '\\b["\'`\\]]?', 'gi'),
      'REFERENCES "' + d + '"',
    );
  }
  return out.trim();
}

const parts = [
  "-- 0002_domains — Domänen-Tabellen (aus Legacy-SQLite konsolidiert, präfixiert, FK umgeschrieben).",
  "-- GENERIERT von scripts/gen-domain-migration.mjs — nicht von Hand editieren.",
  "",
];

for (const [db, map] of Object.entries(MAP)) {
  const info = schemas[db];
  if (!info) { console.error("FEHLT schemas:", db); continue; }
  parts.push(`-- ── ${db} ──`);
  for (const [src, dst] of Object.entries(map)) {
    const t = info.tables.find((x) => x.name === src);
    if (!t) { console.error(`  FEHLT Tabelle ${db}.${src}`); continue; }
    if (/VIRTUAL\s+TABLE/i.test(t.sql)) { console.error(`  SKIP virtual ${src}`); continue; }
    parts.push(transform(t.sql, src, dst, map) + ";");
    parts.push("");
  }
}

const dst = path.resolve("db/migrations/0002_domains.sql");
fs.writeFileSync(dst, parts.join("\n"));
console.log("Geschrieben:", dst);
console.log("Tabellen gesamt:", Object.values(MAP).reduce((n, m) => n + Object.keys(m).length, 0));
