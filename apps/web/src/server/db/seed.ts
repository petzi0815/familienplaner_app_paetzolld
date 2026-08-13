import fs from "node:fs";
import path from "node:path";
import { config } from "@/server/config";
import { log } from "@/server/observability/logger";
import { resolveSeedDir } from "./paths";

let done = false;

/**
 * Kopiert beim ersten Start die vorgebaute Seed-DB + Media ins persistente
 * DATA_DIR (Coolify-Volume `/data`), sofern dort noch nichts liegt. Danach
 * lebt der State auf dem Volume und übersteht Redeploys.
 */
export function ensureSeeded(): void {
  if (done) return;
  done = true;
  fs.mkdirSync(config.dataDir, { recursive: true });
  const seedDir = resolveSeedDir();
  if (!seedDir) {
    log.warn("Kein Seed-Verzeichnis gefunden — DB startet leer (nur Migrationen).");
    return;
  }

  if (!fs.existsSync(config.dbPath)) {
    const seedDb = path.join(seedDir, "familienplaner.db");
    if (fs.existsSync(seedDb)) {
      fs.copyFileSync(seedDb, config.dbPath);
      log.info("Seed-DB nach DATA_DIR kopiert", { to: config.dbPath });
    }
  }

  const seedMedia = path.join(seedDir, "media");
  if (!fs.existsSync(config.mediaDir)) {
    if (fs.existsSync(seedMedia)) {
      fs.cpSync(seedMedia, config.mediaDir, { recursive: true });
      log.info("Seed-Media nach DATA_DIR kopiert", { to: config.mediaDir });
    }
  }

  // Nachträglich hinzugekommene Bereichs-Medien (z. B. trauerkarten) auch auf bereits geseedete
  // Volumes nachziehen — pro Unterordner, idempotent (nur wenn Ziel fehlt).
  for (const sub of ["trauerkarten"]) {
    const src = path.join(seedMedia, sub);
    const dst = path.join(config.mediaDir, sub);
    if (fs.existsSync(src) && !fs.existsSync(dst)) {
      fs.cpSync(src, dst, { recursive: true });
      log.info("Bereichs-Media nachgezogen", { sub, to: dst });
    }
  }

  ersetzeLeereMedien(seedMedia);
}

/**
 * Ersetzt Mediendateien im DATA_DIR, die 0 Byte gross sind, durch die Fassung aus dem Seed.
 *
 * Warum das nötig ist: die beiden Kopierschritte oben überspringen alles, was am Ziel schon
 * existiert — richtig so, sonst überschriebe jeder Neustart die vom Nutzer hochgeladenen Bilder.
 * Eine 0-Byte-Datei ist aber nie ein gültiger Inhalt, sondern immer ein abgebrochener Download
 * oder Upload. Ohne diese Ausnahme bliebe sie für immer stehen: das Seed brächte die reparierte
 * Datei mit, und das Volume zeigte weiter die leere (so geschehen bei `garten/samen_7_ref.jpg`,
 * dessen Download bei der ursprünglichen Migration fehlschlug).
 *
 * Bewusst NUR die Länge 0 als Kriterium: alles andere — etwa „Datei sieht nicht nach einem Bild
 * aus" — wäre eine Vermutung über fremde Inhalte und könnte echte Nutzerdaten überschreiben.
 * Läuft still und best effort; ein Fehler hier darf den Boot nicht aufhalten.
 */
function ersetzeLeereMedien(seedMedia: string): void {
  if (!fs.existsSync(seedMedia) || !fs.existsSync(config.mediaDir)) return;
  let ersetzt = 0;
  const durchlaufen = (relativ: string): void => {
    const quelle = path.join(seedMedia, relativ);
    for (const eintrag of fs.readdirSync(quelle, { withFileTypes: true })) {
      const rel = relativ ? path.join(relativ, eintrag.name) : eintrag.name;
      if (eintrag.isDirectory()) { durchlaufen(rel); continue; }
      const ziel = path.join(config.mediaDir, rel);
      try {
        if (!fs.existsSync(ziel) || fs.statSync(ziel).size > 0) continue;
        if (fs.statSync(path.join(seedMedia, rel)).size === 0) continue; // Seed selbst leer: nichts zu holen
        fs.copyFileSync(path.join(seedMedia, rel), ziel);
        ersetzt++;
      } catch { /* einzelne Datei nicht lesbar — der Rest laeuft weiter */ }
    }
  };
  try {
    durchlaufen("");
    if (ersetzt) log.info("Leere Mediendateien aus dem Seed ersetzt", { anzahl: ersetzt });
  } catch (e) {
    log.warn("Prüfung auf leere Mediendateien fehlgeschlagen", { error: String(e) });
  }
}
