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

export interface PushOptions {
  title: string;
  body: string;
  data?: Record<string, unknown>;
  sound?: string | null; // null = lautlos
  badge?: number;
}

/** Alert-Push an alle registrierten Geräte. Best-effort, wirft nie. Tote Tokens werden entfernt. */
export async function sendPush(opts: PushOptions): Promise<{ sent: number; total: number }> {
  if (!apnsEnabled()) {
    log.info("APNs deaktiviert — Push übersprungen", { title: opts.title.slice(0, 40) });
    return { sent: 0, total: 0 };
  }
  const db = getDb();
  const rows = db.prepare("SELECT id, token, environment FROM device_tokens").all() as DeviceRow[];
  if (!rows.length) return { sent: 0, total: 0 };

  let jwt: string;
  try { jwt = providerToken(); } catch (e) { log.error("APNs Provider-Token-Signatur fehlgeschlagen", { error: String(e) }); return { sent: 0, total: rows.length }; }

  const aps: Record<string, unknown> = {
    alert: { title: opts.title, body: opts.body },
    "interruption-level": "active",
    "relevance-score": 1.0,
  };
  if (opts.sound !== null) aps.sound = opts.sound ?? "default";
  if (opts.badge != null) aps.badge = opts.badge;
  const payload = JSON.stringify({ aps, ...(opts.data ?? {}) });

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
          "apns-topic": config.apns.bundleId,
          "apns-push-type": "alert",
          "apns-priority": "10",
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
  return { sent, total: rows.length };
}
