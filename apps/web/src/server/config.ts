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

  // Observability
  sentryDsn: env("SENTRY_DSN"),
  sentryEnvironment: env("SENTRY_ENVIRONMENT", "production"),

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
