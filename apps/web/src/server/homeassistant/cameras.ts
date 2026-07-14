import { config } from "@/server/config";
import { haConfigured } from "./client";

// Kameras der Familie über Home Assistant (UniFi Protect ist in HA integriert). HA liefert sowohl
// Schnappschüsse (`/api/camera_proxy/<entity>`) als auch Live-HLS (WebSocket `camera/stream`) —
// beides über die schon erreichbare HA-URL (DuckDNS), daher KEIN Tailscale/kein UniFi-Key nötig.
// Nur diese kuratierten Entitäten sind abrufbar (Allow-List).

export interface CameraDef { entity: string; name: string }

export const CAMERAS: CameraDef[] = [
  { entity: "camera.einfahrt_high", name: "Einfahrt" },
  { entity: "camera.g6_ptz_high_resolution_channel", name: "Eingang" },
  { entity: "camera.vorgarten_high", name: "Vorgarten" },
  { entity: "camera.garage_high", name: "Garage" },
  { entity: "camera.sudseite_high", name: "Südseite" },
  { entity: "camera.westseite_high", name: "Westseite" },
  { entity: "camera.wohnzimmer_high", name: "Wohnzimmer" },
  { entity: "camera.schlafzimmer_high_resolution_channel", name: "Schlafzimmer" },
  { entity: "camera.doorstation_live", name: "Türklingel" },
];

const CAMERA_ENTITIES = new Set(CAMERAS.map((c) => c.entity));
export function isKnownCamera(e: string): boolean { return CAMERA_ENTITIES.has(e); }

const TIMEOUT_MS = 15_000;

export function cameraList(): { configured: boolean; cameras: CameraDef[] } {
  const configured = haConfigured();
  return { configured, cameras: configured ? CAMERAS : [] };
}

/** Aktuellen Schnappschuss einer Kamera holen (Backend hält den HA-Token; der Client bekommt nur das Bild). */
export async function cameraSnapshot(entity: string): Promise<{ bytes: ArrayBuffer; contentType: string }> {
  if (!haConfigured()) throw new Error("Home Assistant ist nicht konfiguriert.");
  if (!isKnownCamera(entity)) throw new Error("Unbekannte Kamera.");
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), TIMEOUT_MS);
  try {
    const res = await fetch(`${config.homeAssistant.url}/api/camera_proxy/${encodeURIComponent(entity)}`, {
      headers: { Authorization: `Bearer ${config.homeAssistant.token}` },
      signal: ctrl.signal,
      cache: "no-store",
    });
    if (!res.ok) throw new Error(`HA ${res.status}`);
    const bytes = await res.arrayBuffer();
    return { bytes, contentType: res.headers.get("content-type") ?? "image/jpeg" };
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Live-HLS-URL einer Kamera minten. HA erzeugt via WebSocket `camera/stream` eine signierte,
 * öffentlich (Token im Pfad) abspielbare HLS-URL — AVPlayer spielt das nativ. Rückgabe = absolute URL.
 */
export async function cameraHlsUrl(entity: string): Promise<string> {
  if (!haConfigured()) throw new Error("Home Assistant ist nicht konfiguriert.");
  if (!isKnownCamera(entity)) throw new Error("Unbekannte Kamera.");
  const path = await haCameraStreamPath(entity);
  return `${config.homeAssistant.url}${path}`;
}

function haWebsocketUrl(): string {
  // config.homeAssistant.url hat keinen Trailing-Slash. http(s) → ws(s).
  return config.homeAssistant.url.replace(/^http/i, "ws") + "/api/websocket";
}

/** WebSocket-Handshake mit HA: auth → camera/stream(hls) → relativer HLS-Pfad. */
function haCameraStreamPath(entity: string): Promise<string> {
  return new Promise((resolve, reject) => {
    let settled = false;
    const finish = (fn: () => void) => { if (settled) return; settled = true; clearTimeout(timer); try { ws.close(); } catch { /* egal */ } fn(); };
    const ws = new WebSocket(haWebsocketUrl());
    const reqId = 1;
    const timer = setTimeout(() => finish(() => reject(new Error("HA WebSocket Timeout"))), TIMEOUT_MS);
    ws.onmessage = (ev: MessageEvent) => {
      let m: { type?: string; id?: number; success?: boolean; result?: { url?: string } };
      try { m = JSON.parse(String(ev.data)); } catch { return; }
      if (m.type === "auth_required") {
        ws.send(JSON.stringify({ type: "auth", access_token: config.homeAssistant.token }));
      } else if (m.type === "auth_invalid") {
        finish(() => reject(new Error("HA WebSocket Auth ungültig")));
      } else if (m.type === "auth_ok") {
        ws.send(JSON.stringify({ id: reqId, type: "camera/stream", entity_id: entity, format: "hls" }));
      } else if (m.type === "result" && m.id === reqId) {
        if (m.success && m.result?.url) finish(() => resolve(m.result!.url!));
        else finish(() => reject(new Error("HA Stream fehlgeschlagen")));
      }
    };
    ws.onerror = () => finish(() => reject(new Error("HA WebSocket Fehler")));
    ws.onclose = () => finish(() => reject(new Error("HA WebSocket geschlossen")));
  });
}
