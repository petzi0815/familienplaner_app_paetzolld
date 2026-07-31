import { getDb } from "@/server/db/connection";
import { getAuth, hasRole } from "@/server/auth/auth";
import { unauthorized, forbidden, fail, ok } from "@/server/http/respond";
import {
  getWeinSettings, saveWeinSettings, type WeinSettings,
  INTERVALL_TAGE_MIN, INTERVALL_TAGE_MAX, RABATT_PROZENT_MIN, RABATT_PROZENT_MAX,
} from "@/server/wein/settings";

// Einstellungen der Wein-Preisüberwachung (persistiert in app_settings unter wein.preischeck.*):
// Prüfintervall in Tagen, Rabattschwelle in Prozent, Push an/aus.
//
// BEWUSST Rolle `agent` (nicht `admin` wie /api/v1/config): Lars und Elita haben Per-User-Keys mit
// Rolle agent — sie sollen ihre eigene Weinüberwachung aus der App heraus einstellen können, ohne
// das Admin-Passwort. Es sind drei Komfort-Werte, keine sicherheitsrelevante Konfiguration.
//
// Nach außen snake_case (wie alle v1-Felder), intern camelCase (WeinSettings) — die Umrechnung
// passiert hier an genau einer Stelle. Die Grenzen kommen aus dem Settings-Modul, damit 422-Meldung
// und Speicherung nie auseinanderlaufen.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/** Interne Settings → API-Form (snake_case). */
function nachAussen(s: WeinSettings): { intervall_tage: number; rabatt_prozent: number; push_aktiv: boolean } {
  return { intervall_tage: s.intervallTage, rabatt_prozent: s.rabattProzent, push_aktiv: s.pushAktiv };
}

export function GET(req: Request): Response {
  const auth = getAuth(req);
  if (!hasRole(auth, "agent")) return auth ? forbidden() : unauthorized();
  try {
    return ok(nachAussen(getWeinSettings(getDb())));
  } catch (e) {
    return fail("db_error", "Einstellungen konnten nicht gelesen werden.", 500, { detail: String((e as Error)?.message ?? e).slice(0, 200) });
  }
}

export async function PUT(req: Request): Promise<Response> {
  const auth = getAuth(req);
  if (!hasRole(auth, "agent")) return auth ? forbidden() : unauthorized();

  let body: Record<string, unknown>;
  try { body = (await req.json()) as Record<string, unknown>; } catch { return fail("bad_json", "Ungültiger JSON-Body.", 400); }

  const patch: Partial<WeinSettings> = {};

  if (body.intervall_tage !== undefined && body.intervall_tage !== null) {
    const n = Number(body.intervall_tage);
    if (!Number.isFinite(n) || n < INTERVALL_TAGE_MIN || n > INTERVALL_TAGE_MAX) {
      return fail("invalid_value", `Feld 'intervall_tage' erlaubt nur ${INTERVALL_TAGE_MIN}–${INTERVALL_TAGE_MAX} (Tage).`, 422,
        { column: "intervall_tage", min: INTERVALL_TAGE_MIN, max: INTERVALL_TAGE_MAX });
    }
    patch.intervallTage = Math.round(n);
  }

  if (body.rabatt_prozent !== undefined && body.rabatt_prozent !== null) {
    const n = Number(body.rabatt_prozent);
    if (!Number.isFinite(n) || n < RABATT_PROZENT_MIN || n > RABATT_PROZENT_MAX) {
      return fail("invalid_value", `Feld 'rabatt_prozent' erlaubt nur ${RABATT_PROZENT_MIN}–${RABATT_PROZENT_MAX} (Prozent).`, 422,
        { column: "rabatt_prozent", min: RABATT_PROZENT_MIN, max: RABATT_PROZENT_MAX });
    }
    patch.rabattProzent = Math.round(n);
  }

  if (body.push_aktiv !== undefined && body.push_aktiv !== null) {
    const v = body.push_aktiv;
    if (typeof v !== "boolean" && v !== 0 && v !== 1 && v !== "true" && v !== "false") {
      return fail("invalid_value", "Feld 'push_aktiv' erlaubt nur true oder false.", 422, { column: "push_aktiv", allowed: [true, false] });
    }
    patch.pushAktiv = v === true || v === 1 || v === "true";
  }

  if (!Object.keys(patch).length) {
    return fail("empty", "Keine Einstellung angegeben (erlaubt: intervall_tage, rabatt_prozent, push_aktiv).", 400);
  }

  const db = getDb();
  try {
    const aktuell = saveWeinSettings(db, patch);
    try {
      db.prepare("INSERT INTO event_log (actor, action, domain, detail) VALUES (?,?,?,?)")
        .run(auth.actor, "wein_einstellungen", "wein", JSON.stringify(nachAussen(aktuell)));
    } catch { /* Audit best effort */ }
    return ok(nachAussen(aktuell));
  } catch (e) {
    return fail("db_error", "Einstellungen konnten nicht gespeichert werden.", 500, { detail: String((e as Error)?.message ?? e).slice(0, 200) });
  }
}
