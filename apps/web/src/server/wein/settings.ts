import type BetterSqlite3 from "better-sqlite3";

// Einstellungen der Wein-Preisüberwachung.
//
// Persistenz bewusst in `app_settings` (dieselbe Tabelle wie `PUT /api/v1/config`) statt in einer
// eigenen Tabelle: es sind drei skalare Werte, sie brauchen keine Migration und bleiben nebenbei
// über die Admin-Config sicht- und änderbar.
//
// `app_settings.value` ist TEXT — Zahlen/Booleans kommen also immer als String zurück, und über die
// Config-Route landen sie als `JSON.stringify`-Form dort ("7", "true"). Deshalb liest das Modul
// bewusst tolerant: unlesbare oder aus dem Rahmen gelaufene Werte ergeben nie NaN, sondern den
// Standard bzw. den nächstgelegenen erlaubten Wert.

export interface WeinSettings {
  /** Abstand, in dem ein beobachteter Wein neu recherchiert wird (Tage). */
  intervallTage: number;
  /** Ab dieser Ersparnis gegenüber `referenzpreis` gilt ein Angebot als Schnäppchen (Prozent). */
  rabattProzent: number;
  /** Bei Schnäppchen einen Push an die Familie senden? */
  pushAktiv: boolean;
}

/** Schlüssel in `app_settings` — auch von der Config-Route aus lesbar. */
export const WEIN_SETTINGS_KEYS = {
  intervallTage: "wein.preischeck.intervall_tage",
  rabattProzent: "wein.preischeck.rabatt_prozent",
  pushAktiv: "wein.preischeck.push_aktiv",
} as const;

export const WEIN_SETTINGS_DEFAULTS: WeinSettings = { intervallTage: 7, rabattProzent: 20, pushAktiv: true };

// Grenzen zentral hier, damit Route (422-Meldung) und Speicherung dieselben Werte benutzen.
export const INTERVALL_TAGE_MIN = 1;
export const INTERVALL_TAGE_MAX = 90;
export const RABATT_PROZENT_MIN = 5;
export const RABATT_PROZENT_MAX = 80;

const clamp = (n: number, min: number, max: number): number => Math.min(Math.max(Math.round(n), min), max);

/**
 * Zahl aus einem beliebigen Wert (String aus `app_settings` oder Number aus einem Patch).
 * Fehlend/leer/unlesbar → null. WICHTIG: der Leerstring wird ausdrücklich vorher abgefangen —
 * `Number("")` ist 0 und würde sonst als gültige Einstellung durchgehen (und auf das Minimum
 * geklemmt), statt den Standardwert zu ziehen.
 */
function alsZahl(raw: unknown): number | null {
  if (raw === null || raw === undefined) return null;
  const s = String(raw).trim().replace(",", ".");
  if (!s) return null;
  const n = Number(s);
  return Number.isFinite(n) ? n : null;
}

/** Zahl aus einem gespeicherten Wert; unlesbar → `fallback`, außerhalb der Grenzen → geklemmt. */
function leseZahl(raw: string | undefined, fallback: number, min: number, max: number): number {
  const n = alsZahl(raw);
  return n === null ? fallback : clamp(n, min, max);
}

/** Boolean aus einem gespeicherten Wert. Akzeptiert "true"/"false" (JSON) genauso wie "1"/"0"/"ja". */
function leseBool(raw: string | undefined, fallback: boolean): boolean {
  const v = String(raw ?? "").trim().toLowerCase();
  if (["1", "true", "ja", "yes", "on", "an"].includes(v)) return true;
  if (["0", "false", "nein", "no", "off", "aus"].includes(v)) return false;
  return fallback;
}

/** Alle drei Werte in einem Rutsch lesen (eine Abfrage statt drei). */
function rohwerte(db: BetterSqlite3.Database): Record<string, string> {
  const rows = db
    .prepare("SELECT key, value FROM app_settings WHERE key IN (?,?,?)")
    .all(WEIN_SETTINGS_KEYS.intervallTage, WEIN_SETTINGS_KEYS.rabattProzent, WEIN_SETTINGS_KEYS.pushAktiv) as
    { key: string; value: string | null }[];
  const out: Record<string, string> = {};
  for (const r of rows) if (r.value != null) out[r.key] = r.value;
  return out;
}

/** Aktuelle Einstellungen (mit Standardwerten 7 Tage / 20 % / Push an). */
export function getWeinSettings(db: BetterSqlite3.Database): WeinSettings {
  const v = rohwerte(db);
  return {
    intervallTage: leseZahl(v[WEIN_SETTINGS_KEYS.intervallTage], WEIN_SETTINGS_DEFAULTS.intervallTage, INTERVALL_TAGE_MIN, INTERVALL_TAGE_MAX),
    rabattProzent: leseZahl(v[WEIN_SETTINGS_KEYS.rabattProzent], WEIN_SETTINGS_DEFAULTS.rabattProzent, RABATT_PROZENT_MIN, RABATT_PROZENT_MAX),
    pushAktiv: leseBool(v[WEIN_SETTINGS_KEYS.pushAktiv], WEIN_SETTINGS_DEFAULTS.pushAktiv),
  };
}

/**
 * Einstellungen teilweise ändern. Zahlen werden auf den erlaubten Bereich geklemmt
 * (1..90 bzw. 5..80), unlesbare Werte ignoriert. Gibt den Stand NACH dem Schreiben zurück.
 */
export function saveWeinSettings(db: BetterSqlite3.Database, patch: Partial<WeinSettings>): WeinSettings {
  const eintraege: [string, string][] = [];
  const intervall = alsZahl(patch.intervallTage);
  if (intervall !== null) {
    eintraege.push([WEIN_SETTINGS_KEYS.intervallTage, String(clamp(intervall, INTERVALL_TAGE_MIN, INTERVALL_TAGE_MAX))]);
  }
  const rabatt = alsZahl(patch.rabattProzent);
  if (rabatt !== null) {
    eintraege.push([WEIN_SETTINGS_KEYS.rabattProzent, String(clamp(rabatt, RABATT_PROZENT_MIN, RABATT_PROZENT_MAX))]);
  }
  if (patch.pushAktiv !== undefined && patch.pushAktiv !== null) {
    // "true"/"false" statt 1/0 — so ist der Wert identisch zu dem, was `PUT /api/v1/config`
    // (JSON.stringify) schreiben würde, und beide Wege bleiben austauschbar.
    eintraege.push([WEIN_SETTINGS_KEYS.pushAktiv, patch.pushAktiv ? "true" : "false"]);
  }
  if (eintraege.length) {
    const stmt = db.prepare(
      "INSERT INTO app_settings (key,value) VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value, updated_at=datetime('now')",
    );
    const tx = db.transaction(() => { for (const [k, v] of eintraege) stmt.run(k, v); });
    tx();
  }
  return getWeinSettings(db);
}
