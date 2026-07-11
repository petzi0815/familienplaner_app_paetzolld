import { getDb } from "@/server/db/connection";
import { config } from "@/server/config";
import { JOBS } from "@/server/jobs/registry";
import { getAuth, hasRole } from "@/server/auth/auth";
import { unauthorized, ok } from "@/server/http/respond";

// Liste aller Jobs + letzter Lauf.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export function GET(req: Request): Response {
  if (!hasRole(getAuth(req), "agent")) return unauthorized();
  const db = getDb();
  const jobs = JOBS.map((j) => ({
    name: j.name,
    schedule: j.schedule,
    description: j.description,
    topic: j.topic,
    run_endpoint: `/api/v1/jobs/${j.name}/run`,
    last_run: db.prepare("SELECT id,started_at,finished_at,status,affected_rows,dry_run FROM job_runs WHERE name=? ORDER BY id DESC LIMIT 1").get(j.name) ?? null,
  }));
  return ok({ scheduler_enabled: config.jobsEnabled, jobs });
}
