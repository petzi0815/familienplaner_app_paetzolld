import { jobByName } from "@/server/jobs/registry";
import { runJob } from "@/server/jobs/runner";
import { getAuth, hasRole } from "@/server/auth/auth";
import { unauthorized, forbidden, notFound, ok } from "@/server/http/respond";

// Job manuell auslösen (Scheduler/Agent). ?dry_run=1 = Vorschau ohne Senden/Schreiben.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function POST(req: Request, { params }: { params: Promise<{ name: string }> }): Promise<Response> {
  const auth = getAuth(req);
  if (!hasRole(auth, "agent")) return auth ? forbidden() : unauthorized();
  const { name } = await params;
  if (!jobByName(name)) return notFound("Job");
  const dryRun = new URL(req.url).searchParams.get("dry_run") === "1";
  const outcome = await runJob(name, { dryRun });
  return ok(outcome);
}
