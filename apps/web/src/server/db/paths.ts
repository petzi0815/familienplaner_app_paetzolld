import fs from "node:fs";
import path from "node:path";

/** Sucht `rel` ausgehend vom cwd nach oben (Monorepo: dev-cwd=apps/web, prod-cwd=/app). */
function findUp(rel: string): string | null {
  let dir = process.cwd();
  for (let i = 0; i < 6; i++) {
    const cand = path.join(dir, rel);
    if (fs.existsSync(cand)) return cand;
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  return null;
}

/** Migrations-Verzeichnis (Docker: DB_MIGRATIONS_DIR; lokal: findUp db/migrations). */
export function resolveMigrationsDir(): string | null {
  return process.env.DB_MIGRATIONS_DIR || findUp(path.join("db", "migrations"));
}

/** Seed-Verzeichnis (Docker: DB_SEED_DIR; lokal: findUp seed). */
export function resolveSeedDir(): string | null {
  return process.env.DB_SEED_DIR || findUp("seed");
}
