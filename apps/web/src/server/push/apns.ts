import http2 from "node:http2";
import crypto from "node:crypto";
import { config } from "@/server/config";
import { getDb } from "@/server/db/connection";
import { log } from "@/server/observability/logger";

// APNs-Push (token-basiert, .p8) an die native iOS-App. Ohne konfigurierten Auth-Key
// (APNS_KEY_P8 + APNS_KEY_ID + APPLE_TEAM_ID) sind alle Sends stille No-Ops.
// Provider-Token = ES256-JWT (kid=Key-ID, iss=Team-ID), ~40 min wiederverwendet.
const PROD_HOST = "https://api.push.apple.com";
const SANDBOX_HOST = "https://api.sandbox.push.apple.com";
const TOKEN_TTL_MS = 40 * 60 * 1000;

let tokenCache = { jwt: "", iat: 0 };

export function apnsEnabled(): boolean {
  const a = config.apns;
  return !!(a.keyP8 && a.keyId && a.teamId && a.bundleId);
}

function privateKeyPem(): string {
  const raw = (config.apns.keyP8 || "").trim();
  return raw.includes("BEGIN") ? raw : Buffer.from(raw, "base64").toString("utf8");
}

function b64url(input: Buffer | string): string {
  return Buffer.from(input).toString("base64url");
}

function providerToken(): string {
  const now = Date.now();
  if (tokenCache.jwt && now - tokenCache.iat < TOKEN_TTL_MS) return tokenCache.jwt;
  const header = b64url(JSON.stringify({ alg: "ES256", kid: config.apns.keyId }));
  const payload = b64url(JSON.stringify({ iss: config.apns.teamId, iat: Math.floor(now / 1000) }));
  const signingInput = `${header}.${payload}`;
  const key = crypto.createPrivateKey(privateKeyPem());
  // ieee-p1363 = rohe R||S-Signatur (JWT-ES256-Format, NICHT DER)
  const sig = crypto.sign(null, Buffer.from(signingInput), { key, dsaEncoding: "ieee-p1363" });
  const jwt = `${signingInput}.${b64url(sig)}`;
  tokenCache = { jwt, iat: now };
  return jwt;
}

interface DeviceRow { id: number; token: string; environment: string }

/** Ergebnis eines Sende-Durchlaufs: zugestellt + tote/lebende Token-IDs (Aufräumen macht der Aufrufer). */
interface DeliverResult { sent: number; dead: number[]; ok: number[] }

/**
 * Gemeinsamer HTTP/2-Sendecode für Alert- UND Live-Activity-Pushes.
 * Gruppiert die Tokens nach APNs-Host (sandbox/prod), öffnet je Host EINE Verbindung und
 * feuert alle Requests darauf ab. Best-effort: wirft nie, Timeout 10 s je Request,
 * 410/Unregistered/BadDeviceToken/DeviceTokenNotForTopic landen in `dead`.
 */
async function deliver(
  rows: DeviceRow[],
  jwt: string,
  headers: Record<string, string>,
  payload: string,
): Promise<DeliverResult> {
  const byHost = new Map<string, DeviceRow[]>();
  for (const r of rows) {
    const host = r.environment === "sandbox" ? SANDBOX_HOST : PROD_HOST;
    (byHost.get(host) ?? byHost.set(host, []).get(host)!).push(r);
  }

  let sent = 0;
  const dead: number[] = [];
  const ok: number[] = [];

  for (const [host, hostRows] of byHost) {
    await new Promise<void>((resolve) => {
      const client = http2.connect(host);
      let settled = false;
      const finish = () => { if (!settled) { settled = true; try { client.close(); } catch { /* */ } resolve(); } };
      client.on("error", finish);
      let pending = hostRows.length;
      const one = () => { if (--pending <= 0) finish(); };
      for (const r of hostRows) {
        const req = client.request({
          ":method": "POST",
          ":path": `/3/device/${r.token}`,
          authorization: `bearer ${jwt}`,
          ...headers,
          "content-type": "application/json",
        });
        let status = 0;
        let respBody = "";
        req.on("response", (h) => { status = Number(h[":status"]) || 0; });
        req.setEncoding("utf8");
        req.on("data", (c) => { respBody += c; });
        req.on("end", () => {
          if (status === 200) { sent++; ok.push(r.id); }
          else {
            let reason = "";
            try { reason = (JSON.parse(respBody) as { reason?: string }).reason ?? ""; } catch { /* */ }
            if (status === 410 || ["Unregistered", "BadDeviceToken", "DeviceTokenNotForTopic"].includes(reason)) dead.push(r.id);
            else log.warn("APNs Push abgelehnt", { status, reason });
          }
          one();
        });
        req.on("error", one);
        req.setTimeout(10000, () => { try { req.close(); } catch { /* */ } one(); });
        req.end(payload);
      }
    });
  }

  return { sent, dead, ok };
}

export interface PushOptions {
  title: string;
  body: string;
  data?: Record<string, unknown>;
  sound?: string | null; // null = lautlos
  badge?: number;
  /**
   * Zielperson ('lars' | 'elita'). Ist er gesetzt UND besitzt diese Person registrierte Geräte,
   * geht der Push NUR an deren Tokens; sonst Broadcast an alle (deckt Legacy-Tokens, Ole-Uploads
   * mit owner NULL und Personen ohne registriertes Gerät ab → niemand verpasst still Meldungen).
   */
  owner?: string | null;
  /**
   * Broadcast-Fallback abschalten: es werden NUR Geräte dieses `owner` plus Geräte ohne owner
   * (owner IS NULL = Ole-Shared-Key/Legacy-Registrierung) bedient — nie alle.
   * Nötig für Jobs, die dieselbe Meldung in einer Schleife an mehrere owner schicken —
   * sonst bekäme die einzige Person mit registriertem Gerät jeden Push mehrfach.
   * Default (nicht gesetzt) = bisheriges Verhalten mit Broadcast-Fallback.
   */
  strictOwner?: boolean;
  /**
   * Token-IDs, die dieser Send auslassen soll. Für Schleifen, die dieselbe Meldung an mehrere
   * owner schicken: owner-lose Geräte hängen an JEDEM Durchlauf und bekämen den Push sonst
   * mehrfach. Der Aufrufer sammelt dafür die zurückgegebenen `tokenIds` auf.
   */
  excludeTokens?: Iterable<number>;
  /** UNNotificationCategory-ID (z.B. "TERMIN") → Aktions-Buttons am Sperrbildschirm. */
  category?: string;
  /** aps["thread-id"] — gruppiert zusammengehörige Meldungen (z.B. "termin-42"). */
  threadId?: string;
  /** aps["interruption-level"] — Default "active". */
  interruptionLevel?: "passive" | "active" | "time-sensitive" | "critical";
  /** aps["relevance-score"] (0…1) — Default 1.0. */
  relevanceScore?: number;
}

/**
 * Alert-Push an registrierte Geräte (owner-gezielt mit Broadcast-Fallback). Best-effort, wirft nie.
 * `tokenIds` = die tatsächlich adressierten Token-IDs → Aufrufer können damit über mehrere Sends
 * derselben Meldung deduplizieren (siehe `excludeTokens`).
 */
export async function sendPush(opts: PushOptions): Promise<{ sent: number; total: number; tokenIds: number[] }> {
  if (!apnsEnabled()) {
    log.info("APNs deaktiviert — Push übersprungen", { title: opts.title.slice(0, 40) });
    return { sent: 0, total: 0, tokenIds: [] };
  }
  const db = getDb();
  let rows: DeviceRow[] = [];
  if (opts.owner) {
    // strictOwner = kein Broadcast, aber Geräte OHNE owner (Registrierung über den Shared-Key)
    // gehören zur Familie und müssen mitbedient werden — sonst bekämen sie gar nichts.
    // Doppelzustellung über mehrere owner-Durchläufe verhindert `excludeTokens`.
    rows = db.prepare(
      opts.strictOwner
        ? "SELECT id, token, environment FROM device_tokens WHERE owner=? OR owner IS NULL"
        : "SELECT id, token, environment FROM device_tokens WHERE owner=?",
    ).all(opts.owner) as DeviceRow[];
  }
  if (!rows.length && !opts.strictOwner) {
    rows = db.prepare("SELECT id, token, environment FROM device_tokens").all() as DeviceRow[];
  }
  const exclude = opts.excludeTokens ? new Set(opts.excludeTokens) : null;
  if (exclude?.size) rows = rows.filter((r) => !exclude.has(r.id));
  if (!rows.length) {
    if (opts.strictOwner) log.info("APNs: kein (neues) Gerät für owner — Push übersprungen (strictOwner)", { owner: opts.owner ?? null, title: opts.title.slice(0, 40) });
    return { sent: 0, total: 0, tokenIds: [] };
  }
  const tokenIds = rows.map((r) => r.id);

  let jwt: string;
  try { jwt = providerToken(); } catch (e) { log.error("APNs Provider-Token-Signatur fehlgeschlagen", { error: String(e) }); return { sent: 0, total: rows.length, tokenIds }; }

  const aps: Record<string, unknown> = {
    alert: { title: opts.title, body: opts.body },
    "interruption-level": opts.interruptionLevel ?? "active",
    "relevance-score": opts.relevanceScore ?? 1.0,
  };
  if (opts.sound !== null) aps.sound = opts.sound ?? "default";
  if (opts.badge != null) aps.badge = opts.badge;
  if (opts.category) aps.category = opts.category;
  if (opts.threadId) aps["thread-id"] = opts.threadId;
  const payload = JSON.stringify({ aps, ...(opts.data ?? {}) });

  const { sent, dead, ok } = await deliver(rows, jwt, {
    "apns-topic": config.apns.bundleId,
    "apns-push-type": "alert",
    "apns-priority": "10",
  }, payload);

  if (dead.length) {
    const stmt = db.prepare("DELETE FROM device_tokens WHERE id=?");
    for (const id of dead) stmt.run(id);
    log.info("APNs: tote Tokens entfernt", { count: dead.length });
  }
  if (ok.length) {
    const stmt = db.prepare("UPDATE device_tokens SET last_seen=datetime('now') WHERE id=?");
    for (const id of ok) stmt.run(id);
  }
  log.info("APNs Push gesendet", { title: opts.title.slice(0, 40), sent, total: rows.length });
  return { sent, total: rows.length, tokenIds };
}

// ── Live Activities (ActivityKit) ────────────────────────────────────────────
// Payload-/Header-Form laut Apple „Starting and updating Live Activities with ActivityKit
// push notifications":
//   Header: apns-push-type: liveactivity, apns-topic: <bundleId>.push-type.liveactivity,
//           apns-priority: 5|10 (wir: 10 — Start/Update sollen sofort erscheinen).
//   Payload: { "aps": { "timestamp": <unix s>, "event": "start"|"update"|"end",
//                       "content-state": {…},
//                       "attributes-type": "…", "attributes": {…}   // NUR bei event=start
//                       "alert": { title, body, sound },            // Pflicht bei start
//                       "stale-date": <unix s>, "dismissal-date": <unix s> } }
// „content-state" muss exakt die Swift-Property-Namen der ContentState-Struktur tragen
// (Codable-Default → camelCase), „attributes-type" den Namen des ActivityAttributes-Typs.
// dismissal-date: Zeitpunkt, ab dem das System die beendete Activity entfernt (Vergangenheit =
// sofort; ohne Angabe bzw. > 4 h → spätestens nach 4 h).

export type LiveActivityEvent = "start" | "update" | "end";

/** Zeile aus `live_activity_tokens` (Tabelle kommt aus Migration 0018). */
export interface LiveActivityTokenRow {
  id: number;
  token: string;
  environment?: string | null;
}

export interface LiveActivityOptions {
  event: LiveActivityEvent;
  /** Empfänger-Tokens (push-to-start bei event=start, sonst die Activity-Update-Tokens). */
  tokens: LiveActivityTokenRow[];
  /** Dynamischer Teil — Keys = Swift-Property-Namen der ContentState-Struktur. */
  contentState: Record<string, unknown>;
  /** Statischer Teil (nur bei event=start ausgewertet). */
  attributes?: Record<string, unknown>;
  /** Name des ActivityAttributes-Typs, z.B. "TerminActivityAttributes" (nur bei event=start). */
  attributesType?: string;
  /** Optionaler Alert (bei event=start von APNs verlangt, damit der Nutzer informiert wird). */
  alert?: { title: string; body: string; sound?: string | null };
  /** Unix-Sekunden, ab wann der Inhalt als veraltet gilt. */
  staleDate?: number;
  /** Unix-Sekunden, wann die beendete Activity verschwinden soll (nur sinnvoll bei event=end). */
  dismissalDate?: number;
  /** Überschreibt den aps-Zeitstempel (Unix-Sekunden); Default = jetzt. */
  timestamp?: number;
}

/**
 * Live-Activity-Push (start/update/end) an die übergebenen Tokens. Best-effort, wirft nie.
 * Ohne konfigurierte APNs-Keys stiller No-Op — wie sendPush.
 */
export async function sendLiveActivity(opts: LiveActivityOptions): Promise<{ sent: number; total: number }> {
  if (!apnsEnabled()) {
    log.info("APNs deaktiviert — Live Activity übersprungen", { event: opts.event });
    return { sent: 0, total: 0 };
  }
  const rows: DeviceRow[] = (opts.tokens ?? [])
    .filter((t) => !!t.token)
    .map((t) => ({ id: t.id, token: t.token, environment: t.environment ?? "production" }));
  if (!rows.length) return { sent: 0, total: 0 };

  let jwt: string;
  try { jwt = providerToken(); } catch (e) { log.error("APNs Provider-Token-Signatur fehlgeschlagen", { error: String(e) }); return { sent: 0, total: rows.length }; }

  const aps: Record<string, unknown> = {
    timestamp: opts.timestamp ?? Math.floor(Date.now() / 1000),
    event: opts.event,
    "content-state": opts.contentState ?? {},
  };
  if (opts.event === "start") {
    if (opts.attributesType) aps["attributes-type"] = opts.attributesType;
    if (opts.attributes) aps.attributes = opts.attributes;
    if (!opts.attributesType || !opts.attributes || !opts.alert) {
      // APNs weist Start-Pushes ohne attributes-type/attributes/alert ab.
      log.warn("Live Activity start ohne attributes/alert — APNs wird das ablehnen", { attributesType: opts.attributesType ?? null });
    }
  }
  if (opts.alert) {
    const alert: Record<string, unknown> = { title: opts.alert.title, body: opts.alert.body };
    if (opts.alert.sound !== null) alert.sound = opts.alert.sound ?? "default";
    aps.alert = alert;
  }
  if (opts.staleDate != null) aps["stale-date"] = Math.floor(opts.staleDate);
  if (opts.dismissalDate != null) aps["dismissal-date"] = Math.floor(opts.dismissalDate);
  const payload = JSON.stringify({ aps });

  const { sent, dead } = await deliver(rows, jwt, {
    "apns-topic": `${config.apns.bundleId}.push-type.liveactivity`,
    "apns-push-type": "liveactivity",
    "apns-priority": "10",
  }, payload);

  if (dead.length) {
    // Defensiv: die Tabelle stammt aus Migration 0018 — fehlt sie (noch), darf das nichts brechen.
    try {
      const db = getDb();
      const stmt = db.prepare("DELETE FROM live_activity_tokens WHERE id=?");
      for (const id of dead) stmt.run(id);
      log.info("APNs: tote Live-Activity-Tokens entfernt", { count: dead.length });
    } catch (e) {
      log.warn("Live-Activity-Tokens konnten nicht aufgeräumt werden", { error: String(e) });
    }
  }
  log.info("APNs Live Activity gesendet", { event: opts.event, sent, total: rows.length });
  return { sent, total: rows.length };
}
