import { config } from "@/server/config";
import { getEntityState, callService, haConfigured } from "./client";

// „Alarmo"-Alarmanlage über Home Assistant. Der PIN liegt serverseitig (config.homeAssistant.alarmoCode)
// → die App/Clients senden NUR die Aktion, nie den Code (Wunsch Lars: kein PIN-Tippen).

export type AlarmoAction = "arm_away" | "arm_home" | "arm_night" | "arm_vacation" | "disarm";

export const ALARMO_ACTIONS: AlarmoAction[] = ["arm_away", "arm_home", "arm_night", "arm_vacation", "disarm"];

const SERVICE: Record<AlarmoAction, string> = {
  arm_away: "alarm_arm_away",
  arm_home: "alarm_arm_home",
  arm_night: "alarm_arm_night",
  arm_vacation: "alarm_arm_vacation",
  disarm: "alarm_disarm",
};

// Antwort-Shape der API — snake_case (wie die übrige v1-API; iOS mappt via convertFromSnakeCase).
export interface AlarmoStatus {
  configured: boolean;
  reachable: boolean;
  /** disarmed | arming | pending | triggered | armed_away | armed_home | armed_night | armed_vacation | unavailable … */
  state: string | null;
  arm_mode: string | null;
  next_state: string | null;
  changed_by: string | null;
  friendly_name: string | null;
  open_sensors: unknown;
  error?: string;
}

function offline(configured: boolean, error?: string): AlarmoStatus {
  return {
    configured,
    reachable: false,
    state: null,
    arm_mode: null,
    next_state: null,
    changed_by: null,
    friendly_name: null,
    open_sensors: null,
    ...(error ? { error } : {}),
  };
}

/** Aktuellen Alarmo-Status lesen. Fehlt HA oder ist es nicht erreichbar → `reachable:false` (kein Throw). */
export async function alarmoStatus(): Promise<AlarmoStatus> {
  if (!haConfigured()) return offline(false);
  try {
    const s = await getEntityState(config.homeAssistant.alarmoEntity);
    const a = s.attributes ?? {};
    return {
      configured: true,
      reachable: true,
      state: s.state ?? null,
      arm_mode: (a.arm_mode as string) ?? null,
      next_state: (a.next_state as string) ?? null,
      changed_by: (a.changed_by as string) ?? null,
      friendly_name: (a.friendly_name as string) ?? null,
      open_sensors: a.open_sensors ?? null,
    };
  } catch (e) {
    return offline(true, (e as Error).message);
  }
}

/** Scharf/unscharf schalten (mit serverseitigem PIN) und danach den frischen Status zurückgeben. */
export async function alarmoDispatch(action: AlarmoAction): Promise<AlarmoStatus> {
  if (!haConfigured()) throw new Error("Home Assistant ist nicht konfiguriert.");
  await callService("alarm_control_panel", SERVICE[action], {
    entity_id: config.homeAssistant.alarmoEntity,
    code: config.homeAssistant.alarmoCode,
  });
  // Kurz warten, dann frisch lesen — Alarmo hat evtl. eine Ausgangs-Verzögerung („arming").
  await new Promise((r) => setTimeout(r, 800));
  return alarmoStatus();
}
