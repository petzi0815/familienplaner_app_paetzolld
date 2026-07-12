import cron from "node-cron";
import { config } from "@/server/config";
import { log } from "@/server/observability/logger";
import { JOBS } from "./registry";
import { runJob } from "./runner";

let started = false;

/** Startet den In-Process-Scheduler (node-cron). Einmalig, guarded via JOBS_ENABLED. */
export function startScheduler(): void {
  if (started) return;
  started = true;
  if (!config.jobsEnabled) {
    log.info("Scheduler deaktiviert (JOBS_ENABLED=0)");
    return;
  }
  let n = 0;
  for (const job of JOBS) {
    if (!job.schedule || !cron.validate(job.schedule)) continue;
    cron.schedule(job.schedule, () => {
      runJob(job.name).catch((e) => log.error("Scheduled-Job-Absturz", { name: job.name, error: String(e) }));
    }, job.timezone ? { timezone: job.timezone } : undefined);
    n++;
  }
  log.info("Scheduler gestartet", { geplant: n });
}
