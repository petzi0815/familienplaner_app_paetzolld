import path from "path";

function env(key: string, fallback = ""): string {
  return process.env[key] ?? fallback;
}

/**
 * Zentrale, env-basierte Konfiguration. Secrets kommen ausschließlich aus der
 * Umgebung (Coolify / lokale .env), nie aus dem Code.
 */
export const config = {
  nodeEnv: env("NODE_ENV", "development"),
  // Trailing-Slashes entfernen (sonst doppelte Slashes in zusammengesetzten URLs).
  publicBaseUrl: env("PUBLIC_BASE_URL", "http://localhost:3000").replace(/\/+$/, ""),
  /** Persistentes Datenverzeichnis (Coolify-Volume). Lokal: apps/web/data. */
  dataDir: env("DATA_DIR", path.join(process.cwd(), "data")),
  gitSha: env("APP_GIT_SHA", "dev"),

  // Auth
  adminPassword: env("ADMIN_PASSWORD"),
  sessionSecret: env("SESSION_SECRET"),
  bootstrapAgentApiKey: env("BOOTSTRAP_AGENT_API_KEY"),
  /**
   * Per-User-Login-Keys (Lars & Elita) — eigener Key je Person statt Oles Shared-Key.
   * Beim Boot in `api_keys` gehasht angelegt (Rolle agent) mit gesetztem `owner` →
   * ermöglicht Geräte→Person-Zuordnung und gezielte Push (nur an den Foto-Uploader).
   * Werte kommen aus Coolify-ENV; ohne gesetzten Wert wird der jeweilige Key nicht angelegt.
   */
  bootstrapUserKeys: [
    { label: "lars", owner: "lars", role: "agent" as const, key: env("BOOTSTRAP_LARS_API_KEY") },
    { label: "elita", owner: "elita", role: "agent" as const, key: env("BOOTSTRAP_ELITA_API_KEY") },
  ].filter((k) => k.key),

  // Observability
  sentryDsn: env("SENTRY_DSN"),
  sentryEnvironment: env("SENTRY_ENVIRONMENT", "production"),

  // Jobs/Scheduler (Standard an; einzelne Notify-Sends sind zusätzlich token-gated)
  jobsEnabled: env("JOBS_ENABLED", "1") !== "0",

  // APNs-Push (native iOS-App, token-basiert .p8). Leer = deaktiviert (No-Op).
  // Der APNs-Auth-Key ist team-weit — aus dem Referenzprojekt wiederverwendbar,
  // nur APNS_BUNDLE_ID (= apns-topic) unterscheidet sich.
  apns: {
    keyP8: env("APNS_KEY_P8"),          // Inhalt der AuthKey_XXXX.p8 (PEM oder base64)
    keyId: env("APNS_KEY_ID"),          // 10-stellige Key-ID
    teamId: env("APPLE_TEAM_ID"),       // Developer-Team-ID
    bundleId: env("APNS_BUNDLE_ID", "app.yagemi.familienplaner"),
    useSandbox: env("APNS_USE_SANDBOX", "0") === "1",
  },

  // Shelfmark (familieneigene E-Book-Downloader-Instanz auf der Synology, selbst-signiertes Zertifikat).
  // Der Server proxyt Suche/Download dorthin. Basis-URL überschreibbar; Standard = bekannte DDNS.
  shelfmark: {
    baseUrl: env("SHELFMARK_BASE_URL", "https://bookdl.yagemi.synology.me:1443/api").replace(/\/+$/, ""),
  },

  // Integrationen (optional)
  openaiApiKey: env("OPENAI_API_KEY"),
  telegram: {
    botToken: env("TELEGRAM_BOT_TOKEN"),
    familyChatId: env("TELEGRAM_FAMILY_CHAT_ID"),
    larsChatId: env("TELEGRAM_LARS_CHAT_ID"),
  },

  get dbPath(): string {
    return path.join(this.dataDir, "familienplaner.db");
  },
  get mediaDir(): string {
    return path.join(this.dataDir, "media");
  },
};

export const isProd = (): boolean => config.nodeEnv === "production";
