import { push } from "./ringbuffer";

/**
 * Schlanker, dependency-freier strukturierter Logger:
 * - JSON-Zeile nach stdout/stderr (→ Coolify-Logs)
 * - kompakte Zeile in den In-Memory-Ringpuffer (→ /api/v1/debug/logs)
 *
 * Bewusst kein pino: vermeidet Worker-/Transport-Probleme im Next-standalone-Build.
 */
type Level = "debug" | "info" | "warn" | "error";
const LEVELS: Record<Level, number> = { debug: 10, info: 20, warn: 30, error: 40 };
const MIN = LEVELS[(process.env.LOG_LEVEL as Level) ?? "info"] ?? LEVELS.info;

function emit(level: Level, scope: string, msg: string, extra?: Record<string, unknown>): void {
  if (LEVELS[level] < MIN) return;
  const ts = new Date().toISOString();
  const record = { ts, level, scope, msg, ...(extra ?? {}) };
  const json = JSON.stringify(record);
  if (level === "error") console.error(json);
  else if (level === "warn") console.warn(json);
  else console.log(json);
  push(`${ts.slice(11, 23)} ${level.toUpperCase().padEnd(5)} ${scope}: ${msg}`);
}

export interface Logger {
  debug: (msg: string, extra?: Record<string, unknown>) => void;
  info: (msg: string, extra?: Record<string, unknown>) => void;
  warn: (msg: string, extra?: Record<string, unknown>) => void;
  error: (msg: string, extra?: Record<string, unknown>) => void;
}

export function createLogger(scope: string): Logger {
  return {
    debug: (msg, extra) => emit("debug", scope, msg, extra),
    info: (msg, extra) => emit("info", scope, msg, extra),
    warn: (msg, extra) => emit("warn", scope, msg, extra),
    error: (msg, extra) => emit("error", scope, msg, extra),
  };
}

export const log = createLogger("app");
