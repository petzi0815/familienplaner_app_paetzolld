import { getDb } from "@/server/db/connection";
import { log } from "@/server/observability/logger";
import { notify } from "./notify";
import { jobByName } from "./registry";

export interface RunOutcome {
  run_id: number;
  status: "ok" | "error";
  dry_run: boolean;
  messages?: string[];
  affected?: number;
  error?: string;
}

/** Führt einen Job aus und protokolliert den Lauf in job_runs (idempotent, mit Run-Log). */
export async function runJob(name: string, opts: { dryRun?: boolean } = {}): Promise<RunOutcome | null> {
  const job = jobByName(name);
  if (!job) return null;
  const dryRun = !!opts.dryRun;
  const db = getDb();
  const info = db.prepare("INSERT INTO job_runs (name, schedule, status, dry_run) VALUES (?,?, 'running', ?)").run(name, job.schedule, dryRun ? 1 : 0);
  const runId = Number(info.lastInsertRowid);
  try {
    const result = await job.run({ db, dryRun, notify });
    db.prepare("UPDATE job_runs SET finished_at=datetime('now'), status='ok', messages=?, affected_rows=? WHERE id=?")
      .run(JSON.stringify(result.messages), result.affected, runId);
    log.info("Job ok", { name, dryRun, affected: result.affected, messages: result.messages.length });
    return { run_id: runId, status: "ok", dry_run: dryRun, messages: result.messages, affected: result.affected };
  } catch (e) {
    const msg = String((e as Error).message ?? e);
    db.prepare("UPDATE job_runs SET finished_at=datetime('now'), status='error', error=? WHERE id=?").run(msg, runId);
    log.error("Job fehlgeschlagen", { name, error: msg });
    return { run_id: runId, status: "error", dry_run: dryRun, error: msg };
  }
}
