import { getDb } from "@/server/db/connection";
import { jobByName } from "@/server/jobs/registry";
import { getAuth, hasRole } from "@/server/auth/auth";
import { unauthorized, notFound, ok } from "@/server/http/respond";

// Job-Detail + letzte Läufe.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET(req: Request, { params }: { params: Promise<{ name: string }> }): Promise<Response> {
  if (!hasRole(getAuth(req), "agent")) return unauthorized();
  const { name } = await params;
  const job = jobByName(name);
  if (!job) return notFound("Job");
  const runs = getDb().prepare("SELECT id,started_at,finished_at,status,error,affected_rows,messages,dry_run FROM job_runs WHERE name=? ORDER BY id DESC LIMIT 20").all(name);
  return ok({ name: job.name, schedule: job.schedule, description: job.description, topic: job.topic, runs });
}
