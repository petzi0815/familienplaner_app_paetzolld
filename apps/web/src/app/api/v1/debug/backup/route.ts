import fs from "node:fs";
import path from "node:path";
import { getDb } from "@/server/db/connection";
import { config } from "@/server/config";
import { getAuth, hasRole } from "@/server/auth/auth";
import { unauthorized, ok } from "@/server/http/respond";

// Container-freundliches DB-Backup (better-sqlite3 .backup()) nach $DATA_DIR/backups/. Admin.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const backupDir = () => path.join(config.dataDir, "backups");

export function GET(req: Request): Response {
  if (!hasRole(getAuth(req), "admin")) return unauthorized();
  const dir = backupDir();
  const files = fs.existsSync(dir)
    ? fs.readdirSync(dir).filter((f) => f.endsWith(".db")).map((f) => ({ file: f, bytes: fs.statSync(path.join(dir, f)).size })).sort((a, b) => b.file.localeCompare(a.file))
    : [];
  return ok({ dir, backups: files });
}

export async function POST(req: Request): Promise<Response> {
  if (!hasRole(getAuth(req), "admin")) return unauthorized();
  const dir = backupDir();
  fs.mkdirSync(dir, { recursive: true });
  const ts = new Date().toISOString().replace(/[:.]/g, "-");
  const dest = path.join(dir, `familienplaner-${ts}.db`);
  await getDb().backup(dest);
  return ok({ backup: path.basename(dest), path: dest, bytes: fs.statSync(dest).size });
}
