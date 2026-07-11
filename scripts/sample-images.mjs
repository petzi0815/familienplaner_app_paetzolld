import Database from "better-sqlite3";
const q = (f, sql) => {
  const db = new Database("_legacy/db/" + f, { readonly: true });
  try { return db.prepare(sql).all(); } catch (e) { return [String(e.message)]; } finally { db.close(); }
};
const show = (label, rows) => { console.log("== " + label + " =="); for (const r of rows) console.log(JSON.stringify(r)); };
show("samu items.bild_pfade", q("samu-inventar.db", "SELECT id,bild_pfade FROM items WHERE bild_pfade IS NOT NULL AND bild_pfade<>'' LIMIT 4"));
show("garten pflanzen.bild_pfade", q("garten.db", "SELECT id,bild_pfade FROM pflanzen WHERE bild_pfade IS NOT NULL AND bild_pfade<>'' LIMIT 3"));
show("garten samen.bild_pfade", q("garten.db", "SELECT id,bild_pfade FROM samen WHERE bild_pfade IS NOT NULL AND bild_pfade<>'' LIMIT 2"));
show("garten duenger.bild_pfade", q("garten.db", "SELECT id,bild_pfade FROM duenger WHERE bild_pfade IS NOT NULL AND bild_pfade<>'' LIMIT 2"));
show("gypsi futter.bild_pfad", q("gypsi.db", "SELECT id,bild_pfad FROM futter WHERE bild_pfad IS NOT NULL AND bild_pfad<>'' LIMIT 3"));
show("geschenke.bild_url", q("geschenkplaner.db", "SELECT id,bild_url FROM geschenke WHERE bild_url IS NOT NULL AND bild_url<>'' LIMIT 3"));
show("elisbooks books.thumbnail", q("elisbooks.db", "SELECT id,thumbnail FROM books WHERE thumbnail IS NOT NULL AND thumbnail<>'' LIMIT 2"));
show("ebook wishlist.cover_url", q("ebook-wishlist.db", "SELECT id,cover_url FROM wishlist WHERE cover_url IS NOT NULL AND cover_url<>'' LIMIT 2"));
show("vorrat lebensmittel.bild_pfad", q("vorratskammer.db", "SELECT id,bild_pfad FROM lebensmittel LIMIT 2"));
// Wieviele Datensätze haben Bilder?
const cnt = (f, t, c) => q(f, `SELECT COUNT(*) AS n FROM ${t} WHERE ${c} IS NOT NULL AND ${c}<>''`)[0];
console.log("\n== Bild-Zählungen ==");
console.log("samu items:", JSON.stringify(cnt("samu-inventar.db","items","bild_pfade")));
console.log("garten pflanzen:", JSON.stringify(cnt("garten.db","pflanzen","bild_pfade")));
console.log("garten samen:", JSON.stringify(cnt("garten.db","samen","bild_pfade")));
console.log("gypsi futter:", JSON.stringify(cnt("gypsi.db","futter","bild_pfad")));
console.log("reiniger:", JSON.stringify(cnt("reiniger.db","reiniger","bild_pfad")));
