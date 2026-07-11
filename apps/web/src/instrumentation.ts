/**
 * Next.js Instrumentation-Hook. Initialisiert Sentry so früh wie möglich —
 * aber NUR, wenn SENTRY_DSN gesetzt ist (sonst komplett deaktiviert).
 * Release = APP_GIT_SHA, kein Performance-Tracing, keine PII (Referenzmuster).
 */
export async function register(): Promise<void> {
  const dsn = process.env.SENTRY_DSN;
  if (!dsn) return;

  const runtime = process.env.NEXT_RUNTIME;
  if (runtime === "nodejs" || runtime === "edge") {
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

/**
 * Meldet Server-Fehler aus Route-Handlern/Server-Components an Sentry (wenn aktiv).
 */
export async function onRequestError(
  ...args: Parameters<
    NonNullable<
      Awaited<typeof import("@sentry/nextjs")>["captureRequestError"]
    >
  >
): Promise<void> {
  if (!process.env.SENTRY_DSN) return;
  const Sentry = await import("@sentry/nextjs");
  Sentry.captureRequestError(...args);
}
