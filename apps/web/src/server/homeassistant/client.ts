import { config } from "@/server/config";

// Dünner Home-Assistant-REST-Client. Aktuell nur für die „Alarmo"-Alarmanlage genutzt
// (Status lesen + scharf/unscharf schalten). Token/URL kommen aus der ENV (Coolify).
// Das HA-Zertifikat (duckdns + Let's Encrypt) ist gültig → globales fetch reicht (kein node:https nötig).

const TIMEOUT_MS = 12_000;

/** True, wenn URL + Token gesetzt sind (sonst ist HA in dieser Instanz nicht konfiguriert). */
export function haConfigured(): boolean {
  return Boolean(config.homeAssistant.url && config.homeAssistant.token);
}

async function haFetch(path: string, init?: RequestInit): Promise<Response> {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), TIMEOUT_MS);
  try {
    return await fetch(`${config.homeAssistant.url}${path}`, {
      ...init,
      signal: ctrl.signal,
      cache: "no-store",
      headers: {
        Authorization: `Bearer ${config.homeAssistant.token}`,
        "Content-Type": "application/json",
        ...(init?.headers ?? {}),
      },
    });
  } finally {
    clearTimeout(timer);
  }
}

export interface HaState {
  entity_id: string;
  state: string;
  attributes: Record<string, unknown>;
  last_changed?: string;
  last_updated?: string;
}

/** Aktuellen Zustand einer Entität lesen (GET /api/states/<id>). */
export async function getEntityState(entityId: string): Promise<HaState> {
  const res = await haFetch(`/api/states/${encodeURIComponent(entityId)}`);
  if (!res.ok) throw new Error(`HA ${res.status}`);
  return (await res.json()) as HaState;
}

/** Einen HA-Service aufrufen (domain.service) mit beliebigem Datenobjekt. */
export async function callService(
  domain: string,
  service: string,
  data: Record<string, unknown>,
): Promise<void> {
  const res = await haFetch(`/api/services/${domain}/${service}`, {
    method: "POST",
    body: JSON.stringify(data),
  });
  if (!res.ok) {
    const body = await res.text().catch(() => "");
    throw new Error(`HA ${res.status}${body ? `: ${body.slice(0, 200)}` : ""}`);
  }
}
