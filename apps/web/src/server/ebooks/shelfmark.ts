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

/** Download starten: das VOLLE Release-Objekt an Shelfmark POSTen. */
export async function startDownload(release: Record<string, unknown>): Promise<ShelfmarkResponse> {
  return shelfmarkRequest("/releases/download", { method: "POST", body: release });
}

/** Aktueller Download-Status (queued/downloading/complete/error …). */
export async function downloadStatus(): Promise<ShelfmarkResponse> {
  return shelfmarkRequest("/status");
}

/** Cover-URL absolut machen (Shelfmark liefert teils relative Pfade). */
export function absolutePreview(preview: string | null | undefined): string | null {
  if (!preview) return null;
  return preview.startsWith("http") ? preview : `${config.shelfmark.baseUrl}${preview}`;
}
