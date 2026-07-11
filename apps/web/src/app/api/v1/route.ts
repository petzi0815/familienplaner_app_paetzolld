import { config } from "@/server/config";
import { getDb } from "@/server/db/connection";

// API-Wurzel: kurzer, maschinenlesbarer Einstieg + DB-Liveness. Offen.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export function GET(): Response {
  let db: {
    ok: boolean; tables?: number; migrations?: string[];
    seeded_at?: string | null; boot_count?: string | null; last_boot_at?: string | null;
    error?: string;
  };
  try {
    const conn = getDb();
    const tables = (conn.prepare("SELECT COUNT(*) AS c FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'").get() as { c: number }).c;
    const migrations = (conn.prepare("SELECT version FROM schema_migrations ORDER BY version").all() as { version: string }[]).map((r) => r.version);
    const setting = (k: string) => (conn.prepare("SELECT value FROM app_settings WHERE key=?").get(k) as { value: string } | undefined)?.value ?? null;
    // seeded_at + boot_count belegen Persistenz: bleibt seeded_at über Redeploys gleich und
    // wächst boot_count, ist das /data-Volume persistent.
    db = { ok: true, tables, migrations, seeded_at: setting("seeded_at"), boot_count: setting("boot_count"), last_boot_at: setting("last_boot_at") };
  } catch (e) {
    db = { ok: false, error: String(e) };
  }

  return Response.json(
    {
      name: "Familienplaner API",
      version: "v1",
      status: "phase-1",
      db,
      docs: `${config.publicBaseUrl}/api/v1/docs`,
      openapi: `${config.publicBaseUrl}/api/v1/openapi.json`,
      capabilities: `${config.publicBaseUrl}/api/v1/agent/capabilities`,
      health: `${config.publicBaseUrl}/healthz`,
      versionEndpoint: `${config.publicBaseUrl}/version`,
    },
    { headers: { "cache-control": "no-store" } },
  );
}
