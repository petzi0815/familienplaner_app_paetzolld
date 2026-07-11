/**
 * Next.js Instrumentation-Hook — läuft einmalig beim Serverstart.
 * 1. DB seeden + migrieren (nodejs-Runtime, fail-soft).
 * 2. Sentry initialisieren, wenn SENTRY_DSN gesetzt ist (Release = APP_GIT_SHA,
 *    kein Perf-Tracing, keine PII). Ohne DSN komplett deaktiviert.
 */
export async function register(): Promise<void> {
  const runtime = process.env.NEXT_RUNTIME;

  // DB initialisieren (Seed ins DATA_DIR + Migrationen) + Job-Scheduler starten.
  if (runtime === "nodejs") {
    try {
      const { getDb } = await import("@/server/db/connection");
      getDb();
      const { startScheduler } = await import("@/server/jobs/scheduler");
      startScheduler();
    } catch (e) {
      const { log } = await import("@/server/observability/logger");
      log.error("Start-Init (DB/Scheduler) fehlgeschlagen", { error: String(e) });
    }
  }

  // Sentry (nur wenn DSN gesetzt).
  const dsn = process.env.SENTRY_DSN;
  if (dsn && (runtime === "nodejs" || runtime === "edge")) {
    const Sentry = await import("@sentry/nextjs");
    Sentry.init({
      dsn,
      environment: process.env.SENTRY_ENVIRONMENT || "production",
      release: process.env.APP_GIT_SHA || "dev",
      tracesSampleRate: 0,
      sendDefaultPii: false,
    });
  }
}

/** Meldet Server-Fehler aus Route-Handlern/Server-Components an Sentry (wenn aktiv). */
export async function onRequestError(
  ...args: Parameters<NonNullable<Awaited<typeof import("@sentry/nextjs")>["captureRequestError"]>>
): Promise<void> {
  if (!process.env.SENTRY_DSN) return;
  const Sentry = await import("@sentry/nextjs");
  Sentry.captureRequestError(...args);
}
