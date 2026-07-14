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
}
