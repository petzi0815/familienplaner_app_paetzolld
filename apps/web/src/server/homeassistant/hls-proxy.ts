import { createHmac, timingSafeEqual } from "node:crypto";
import { config } from "@/server/config";

// HLS-Proxy: der Client (AVPlayer) spielt NICHT direkt gegen Home Assistant (DuckDNS:8123 — von manchen
// Netzen/Geräten nicht erreichbar), sondern gegen das Backend (familienplaner.yagemi.app, wie die Snapshots).
// Das Backend holt Playlist/Segmente von HA und schreibt die relativen Referenzen auf signierte Proxy-URLs um.
// AVPlayer sendet KEINEN Auth-Header → die Proxy-URL trägt einen signierten Token (HA-Pfad + Ablauf, HMAC).

const HA_HLS_PREFIX = "/api/hls/";
const HLS_TTL_MS = 2 * 60 * 60 * 1000; // 2h — deckt eine Ansicht ab (der HA-Stream selbst läuft nach Idle ab).
const FETCH_TIMEOUT_MS = 20_000;

function sign(payload: string): string {
  return createHmac("sha256", config.sessionSecret || "hls-proxy").update(payload).digest("base64url");
}

function signedToken(haPath: string, expMs: number): string {
  const payload = Buffer.from(JSON.stringify({ p: haPath, e: expMs })).toString("base64url");
  return `${payload}.${sign(payload)}`;
}

/** Token prüfen → HA-Pfad (nur `/api/hls/…`, nicht abgelaufen) oder null. */
export function verifyHlsToken(token: string): string | null {
  const dot = token.lastIndexOf(".");
  if (dot < 0) return null;
  const payload = token.slice(0, dot);
  const sig = token.slice(dot + 1);
  const expected = sign(payload);
  if (sig.length !== expected.length || !timingSafeEqual(Buffer.from(sig), Buffer.from(expected))) return null;
  try {
    const obj = JSON.parse(Buffer.from(payload, "base64url").toString("utf8")) as { p: string; e: number };
    if (typeof obj.p !== "string" || !obj.p.startsWith(HA_HLS_PREFIX)) return null;
    if (typeof obj.e !== "number" || Date.now() > obj.e) return null;
    return obj.p;
  } catch {
    return null;
  }
}

function proxyUrlFor(haPath: string, expMs: number): string {
  return `${config.publicBaseUrl}/api/v1/smarthome/hls/${signedToken(haPath, expMs)}`;
}

/** Aus einer frisch geminteten HA-HLS-URL (relativer Pfad) die abspielbare Master-Proxy-URL bauen. */
export function hlsMasterProxyUrl(haRelPath: string): string {
  return proxyUrlFor(haRelPath, Date.now() + HLS_TTL_MS);
}

/** Referenz (relativ/absolut) gegen den aktuellen Playlist-Pfad auflösen → HA-Pfad (nur /api/hls/…) oder null. */
function resolveHaPath(ref: string, basePath: string): string | null {
  try {
    const haOrigin = new URL(config.homeAssistant.url).origin;
    const abs = new URL(ref, `${haOrigin}${basePath}`);
    if (abs.origin !== haOrigin) return null;
    if (!abs.pathname.startsWith(HA_HLS_PREFIX)) return null;
    return abs.pathname + abs.search;
  } catch {
    return null;
  }
}

function rewriteRef(ref: string, basePath: string, expMs: number): string {
  const haPath = resolveHaPath(ref, basePath);
  return haPath ? proxyUrlFor(haPath, expMs) : ref;
}

// Low-Latency-HLS-Tags: HA liefert LL-HLS (blockierende Playlist-Reloads via `_HLS_msn/_HLS_part`).
// Über den Proxy funktioniert das nicht zuverlässig (AVPlayer hängt) → diese Zeilen entfernen, damit
// eine STANDARD-HLS-Playlist übrig bleibt (normale Reloads, etwas höhere Latenz, dafür stabil).
const LL_HLS_TAGS = [
  "#EXT-X-PART", // deckt auch #EXT-X-PART-INF ab (Präfix)
  "#EXT-X-PRELOAD-HINT",
  "#EXT-X-SERVER-CONTROL",
  "#EXT-X-RENDITION-REPORT",
  "#EXT-X-SKIP",
];

/** Alle URIs einer m3u8 auf Proxy-URLs umschreiben (bare Zeilen + URI="…" in Tags); LL-HLS entfernen. */
function rewritePlaylist(text: string, basePath: string, expMs: number): string {
  const out: string[] = [];
  for (const line of text.split("\n")) {
    const t = line.trim();
    if (t === "") { out.push(line); continue; }
    if (t.startsWith("#")) {
      if (LL_HLS_TAGS.some((tag) => t.startsWith(tag))) continue; // LL-HLS → Standard-HLS
      out.push(line.replace(/URI="([^"]+)"/g, (_m, uri) => `URI="${rewriteRef(uri, basePath, expMs)}"`));
    } else {
      out.push(rewriteRef(t, basePath, expMs));
    }
  }
  return out.join("\n");
}

/** Einen HA-HLS-Pfad proxyn: Playlist → Referenzen umschreiben; Segment/Init → Bytes durchreichen. */
export async function proxyHls(haPath: string): Promise<Response> {
  const ctrl = new AbortController();
  // Timeout deckt AUCH den Body-Read ab (nicht nur die Header) → kein Hänger bei stockendem Segment.
  const timer = setTimeout(() => ctrl.abort(), FETCH_TIMEOUT_MS);
  try {
    const res = await fetch(`${config.homeAssistant.url}${haPath}`, {
      signal: ctrl.signal,
      cache: "no-store",
      redirect: "manual", // keine Redirects folgen (bliebe zwar im /api/hls-Rahmen, aber unnötig)
    });
    if (!res.ok) return new Response(null, { status: res.status });

    const ct = res.headers.get("content-type") ?? "";
    const isPlaylist = haPath.split("?")[0].endsWith(".m3u8") || ct.includes("mpegurl");
    if (!isPlaylist) {
      const buf = await res.arrayBuffer();
      return new Response(buf, {
        status: 200,
        headers: { "content-type": ct || "application/octet-stream", "cache-control": "no-store" },
      });
    }
    const rewritten = rewritePlaylist(await res.text(), haPath, Date.now() + HLS_TTL_MS);
    return new Response(rewritten, {
      status: 200,
      headers: { "content-type": "application/vnd.apple.mpegurl", "cache-control": "no-store" },
    });
  } finally {
    clearTimeout(timer);
  }
}
