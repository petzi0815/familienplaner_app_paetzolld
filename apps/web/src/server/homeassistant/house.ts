import { getEntityState, callService, haConfigured } from "./client";

// Kuratierte Haus-Steuerung der Familie (Home Assistant): Raffstore-Cover (Höhe + Lamellen-Neigung)
// und die Szenen-Scripts. Nur diese explizit erlaubten Entitäten sind steuerbar (Allow-List →
// keine beliebige HA-Entität über die App fernsteuerbar).

export interface RaffstoreDef { entity: string; name: string }
export interface ScriptDef { entity: string; name: string; icon: string }

/** Raffstores im Haus (kurze Familien-Namen, nicht die HA-Friendly-Names). */
export const RAFFSTORE: RaffstoreDef[] = [
  { entity: "cover.raffstore_esstisch_sud_invert", name: "Esstisch" },
  { entity: "cover.raffstore_kueche_invert", name: "Küche" },
  { entity: "cover.raffstore_kratzbaum_invert", name: "Kratzbaum" },
  { entity: "cover.raffstore_esstisch_west_invert", name: "Glaskasten" },
  { entity: "cover.raffstore_fernseher_invert", name: "TV" },
];

/** Szenen-Scripts, die alle Raffstores in eine Position fahren. */
export const RAFFSTORE_SCRIPTS: ScriptDef[] = [
  { entity: "script.raffstore_putzen", name: "Putzen", icon: "sparkles" },
  { entity: "script.raffstore_verdunkeln", name: "Dunkel", icon: "moon.fill" },
  { entity: "script.raffstore_sichtschutz", name: "Sicht", icon: "eye.slash.fill" },
];

const COVER_ENTITIES = new Set(RAFFSTORE.map((r) => r.entity));
const SCRIPT_ENTITIES = new Set(RAFFSTORE_SCRIPTS.map((s) => s.entity));

export function isKnownCover(e: string): boolean { return COVER_ENTITIES.has(e); }
export function isKnownScript(e: string): boolean { return SCRIPT_ENTITIES.has(e); }

export interface CoverState {
  entity: string;
  name: string;
  reachable: boolean;
  state: string | null;      // open | closed | opening | closing
  position: number | null;   // 0..100 (100 = offen)
  tilt: number | null;       // 0..100 (Lamellen-Neigung)
}

export interface HouseData {
  configured: boolean;
  covers: CoverState[];
  scripts: ScriptDef[];
}

/** Aktueller Zustand aller Raffstores (parallel gelesen; einzelner Fehler → reachable:false für dieses Cover). */
export async function houseState(): Promise<HouseData> {
  // Ohne HA nichts Steuerbares zeigen (weder Cover noch Szenen — sonst laufen Script-Taps ins 502).
  if (!haConfigured()) return { configured: false, covers: [], scripts: [] };
  const covers = await Promise.all(
    RAFFSTORE.map(async (r): Promise<CoverState> => {
      try {
        const s = await getEntityState(r.entity);
        const a = s.attributes ?? {};
        return {
          entity: r.entity,
          name: r.name,
          reachable: true,
          state: s.state ?? null,
          position: typeof a.current_position === "number" ? a.current_position : null,
          tilt: typeof a.current_tilt_position === "number" ? a.current_tilt_position : null,
        };
      } catch {
        return { entity: r.entity, name: r.name, reachable: false, state: null, position: null, tilt: null };
      }
    }),
  );
  return { configured: true, covers, scripts: RAFFSTORE_SCRIPTS };
}

export type CoverAction =
  | "open" | "close" | "stop"
  | "set_position" | "set_tilt"
  | "open_tilt" | "close_tilt" | "stop_tilt";

const COVER_SERVICE: Record<CoverAction, string> = {
  open: "open_cover",
  close: "close_cover",
  stop: "stop_cover",
  set_position: "set_cover_position",
  set_tilt: "set_cover_tilt_position",
  open_tilt: "open_cover_tilt",
  close_tilt: "close_cover_tilt",
  stop_tilt: "stop_cover_tilt",
};

export const COVER_ACTIONS = Object.keys(COVER_SERVICE) as CoverAction[];

function clampPct(v: number | undefined): number {
  const n = Math.round(Number(v));
  if (!Number.isFinite(n)) throw new Error("Wert 0–100 erwartet.");
  return Math.max(0, Math.min(100, n));
}

/** Ein Raffstore-Kommando ausführen (nur Allow-List-Entitäten). */
export async function coverDispatch(entity: string, action: CoverAction, value?: number): Promise<void> {
  if (!haConfigured()) throw new Error("Home Assistant ist nicht konfiguriert.");
  if (!isKnownCover(entity)) throw new Error("Unbekannte Entität.");
  const data: Record<string, unknown> = { entity_id: entity };
  if (action === "set_position") data.position = clampPct(value);
  else if (action === "set_tilt") data.tilt_position = clampPct(value);
  await callService("cover", COVER_SERVICE[action], data);
}

/** Ein Szenen-Script starten (nur Allow-List-Scripts). */
export async function scriptDispatch(entity: string): Promise<void> {
  if (!haConfigured()) throw new Error("Home Assistant ist nicht konfiguriert.");
  if (!isKnownScript(entity)) throw new Error("Unbekanntes Script.");
  await callService("script", "turn_on", { entity_id: entity });
}
