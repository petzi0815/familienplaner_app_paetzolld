import https from "node:https";
import { config } from "@/server/config";

// Proxy zur familieneigenen „Shelfmark"-Instanz (E-Book-Downloader auf der Synology, selbst-signiertes
// Zertifikat → rejectUnauthorized:false). node:https statt fetch, weil das native fetch die self-signed-CA
// nicht ohne Weiteres ignoriert. Suche (Anna's Archive), Download-Start und Status.

const agent = new https.Agent({ rejectUnauthorized: false });

interface ShelfmarkResponse { status: number; json: unknown }

function shelfmarkRequest(path: string, opts: { method?: string; body?: unknown; timeoutMs?: number } = {}): Promise<ShelfmarkResponse> {
  const url = new URL(config.shelfmark.baseUrl + path);
  const payload = opts.body != null ? JSON.stringify(opts.body) : undefined;
  return new Promise((resolve, reject) => {
    const req = https.request(
      url,
      {
        method: opts.method ?? "GET",
        agent,
        headers: {
          accept: "application/json",
          ...(payload ? { "content-type": "application/json", "content-length": Buffer.byteLength(payload) } : {}),
        },
        timeout: opts.timeoutMs ?? 20000,
      },
      (res) => {
        let data = "";
        res.setEncoding("utf8");
        res.on("data", (c) => (data += c));
        res.on("end", () => {
          let json: unknown = null;
          try { json = data ? JSON.parse(data) : null; } catch { json = data; }
          resolve({ status: res.statusCode ?? 0, json });
        });
      },
    );
    req.on("error", reject);
    req.on("timeout", () => req.destroy(new Error("Shelfmark-Zeitüberschreitung")));
    if (payload) req.write(payload);
    req.end();
  });
}

export interface ShelfmarkRelease {
  source_id: string | null;
  title: string;
  format: string | null;
  size: string | null;
  info_url: string | null;
  content_type: string | null;
  author: string | null;
  language: string | null;
  publisher: string | null;
  year: string | null;
  preview: string | null;
  description: string | null;
  _raw: Record<string, unknown>;
}

/** Bücher suchen (Anna's Archive über Shelfmark). Wirft bei Netz-/HTTP-Fehler. */
export async function searchReleases(query: string): Promise<{ query: string; count: number; results: ShelfmarkRelease[] }> {
  const { status, json } = await shelfmarkRequest(`/releases?source=direct_download&query=${encodeURIComponent(query)}`);
  if (status < 200 || status >= 300) throw new Error(`Shelfmark-API-Fehler ${status}`);
  const raw = Array.isArray(json) ? json : ((json as { releases?: unknown[] })?.releases ?? []);
  const results: ShelfmarkRelease[] = (raw as Record<string, unknown>[]).map((r) => {
    const extra = (r.extra ?? {}) as Record<string, unknown>;
    const s = (v: unknown): string | null => (v == null ? null : String(v));
    return {
      source_id: s(r.source_id ?? r.id),
      title: String(r.title ?? ""),
      format: s(r.format),
      size: s(r.size),
      info_url: s(r.info_url),
      content_type: s(r.content_type),
      author: s(extra.author),
      language: s(extra.language),
      publisher: s(extra.publisher),
      year: s(extra.year),
      preview: s(extra.preview),
      description: s(extra.description),
      _raw: r,
    };
  });
  return { query, count: results.length, results };
}

/**
 * Download in die Shelfmark-Warteschlange EINREIHEN. Antwort ist `200 {"priority":0,"status":"queued"}`
 * — das heißt NICHT „heruntergeladen": der Ablauf (queued → locating → resolving → downloading →
 * complete|error) passiert danach asynchron. Den Ausgang liefert erst `downloadStates()`.
 */
export async function startDownload(release: Record<string, unknown>): Promise<ShelfmarkResponse> {
  return shelfmarkRequest("/releases/download", { method: "POST", body: release });
}

/** Aktueller Download-Status (queued/downloading/complete/error …). */
export async function downloadStatus(): Promise<ShelfmarkResponse> {
  return shelfmarkRequest("/status");
}

// ── Download-Verfolgung ──────────────────────────────────────────────────────
// Zwei Quellen, weil Shelfmark seinen Zustand zweigeteilt hält:
//  • `GET /status`            — LIVE-Warteschlange, nach Buckets. Nur im Speicher (Neustart = weg).
//  • `GET /activity/history`  — persistierte Historie, aber nur der in der Shelfmark-Oberfläche
//                               weggeklickten („dismissed") Einträge.
// Ein Download kann also aus beiden verschwinden, ohne je fertig geworden zu sein → „unbekannt"
// ist ein eigener Zustand und wird NICHT als Erfolg gewertet.

export type ShelfmarkPhase = "queued" | "locating" | "resolving" | "downloading" | "complete" | "error" | "cancelled";

const TERMINAL_PHASES = new Set<ShelfmarkPhase>(["complete", "error", "cancelled"]);

export interface ShelfmarkDownloadInfo {
  phase: ShelfmarkPhase;
  terminal: boolean;
  message: string | null;
  title: string | null;
  source: "queue" | "history";
}

export interface ShelfmarkHistoryEntry {
  sourceId: string | null;
  finalStatus: string | null;
  title: string | null;
  author: string | null;
  message: string | null;
  addedAt: number | null;
}

const str = (v: unknown): string | null => (v == null || v === "" ? null : String(v));

/** Live-Warteschlange: Bucket-Name → { id → Eintrag }. */
async function queueStates(): Promise<Map<string, ShelfmarkDownloadInfo>> {
  const { status, json } = await shelfmarkRequest("/status");
  if (status < 200 || status >= 300) throw new Error(`Shelfmark-Status-Fehler ${status}`);
  const out = new Map<string, ShelfmarkDownloadInfo>();
  for (const [bucket, items] of Object.entries((json ?? {}) as Record<string, unknown>)) {
    const phase = bucket as ShelfmarkPhase;
    for (const [id, item] of Object.entries((items ?? {}) as Record<string, Record<string, unknown>>)) {
      out.set(String(id), {
        phase,
        terminal: TERMINAL_PHASES.has(phase),
        message: str(item?.status_message),
        title: str(item?.title),
        source: "queue",
      });
    }
  }
  return out;
}

/** Persistierte Historie (die in Shelfmark weggeklickten Downloads), neueste zuerst. */
export async function activityHistory(limit = 500): Promise<ShelfmarkHistoryEntry[]> {
  const { status, json } = await shelfmarkRequest(`/activity/history?limit=${limit}&offset=0`);
  if (status < 200 || status >= 300) throw new Error(`Shelfmark-Historie-Fehler ${status}`);
  const rows = Array.isArray(json) ? json : Object.values((json ?? {}) as Record<string, unknown>);
  return (rows as Record<string, unknown>[])
    .filter((r) => r && typeof r === "object")
    .map((r) => {
      const dl = ((r.snapshot as Record<string, unknown>)?.download ?? {}) as Record<string, unknown>;
      return {
        sourceId: str(r.source_id ?? dl.id),
        finalStatus: str(r.final_status),
        title: str(dl.title),
        author: str(dl.author),
        message: str(dl.status_message),
        addedAt: typeof dl.added_time === "number" ? dl.added_time : null,
      };
    });
}

/**
 * Zustand aller Shelfmark bekannten Downloads (Live-Queue hat Vorrang vor der Historie —
 * ein erneut angestoßener Download soll nicht am alten Endzustand hängenbleiben).
 * Wirft, wenn Shelfmark nicht erreichbar ist (Aufrufer entscheidet dann bewusst „unbekannt").
 */
export async function downloadStates(): Promise<Map<string, ShelfmarkDownloadInfo>> {
  const [queue, history] = await Promise.all([
    queueStates(),
    activityHistory().catch(() => [] as ShelfmarkHistoryEntry[]),
  ]);
  const out = new Map<string, ShelfmarkDownloadInfo>();
  for (const h of history) {
    if (!h.sourceId || !h.finalStatus) continue;
    const phase = h.finalStatus as ShelfmarkPhase;
    out.set(h.sourceId, {
      phase,
      terminal: TERMINAL_PHASES.has(phase),
      message: h.message,
      title: h.title,
      source: "history",
    });
  }
  for (const [id, info] of queue) out.set(id, info); // Live gewinnt
  return out;
}

/** Cover-URL absolut machen (Shelfmark liefert teils relative Pfade). */
export function absolutePreview(preview: string | null | undefined): string | null {
  if (!preview) return null;
  if (preview.startsWith("http")) return preview;
  // `baseUrl` endet bereits auf „/api", Shelfmark liefert den Pfad aber ebenfalls als „/api/covers/…"
  // → sonst entsteht „…/api/api/covers/…" (404). Doppeltes Präfix abschneiden.
  const base = config.shelfmark.baseUrl;
  const path = base.endsWith("/api") && preview.startsWith("/api/") ? preview.slice(4) : preview;
  return `${base}${path}`;
}
