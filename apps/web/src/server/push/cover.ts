import { createHmac, timingSafeEqual } from "node:crypto";
import https from "node:https";
import { config } from "@/server/config";

// Cover-Bilder für Push-Mitteilungen öffentlich (aber signiert) ausliefern.
//
// WARUM: Die iOS-Notification-Service-Extension lädt das Bild eines Rich-Push selbst herunter und
// schickt dabei KEINEN Bearer-Token mit. Die vorhandenen Cover-Quellen taugen dafür nicht:
//   • Shelfmark-Cover liegen auf der Synology (self-signed Zertifikat, von außen nicht erreichbar),
//   • Calibre-Cover brauchen eine Session,
//   • Google-Books-Cover sind zwar öffentlich, aber längst nicht für jedes Buch vorhanden.
// Deshalb spiegelt das Backend das Bild unter einer signierten, kurzlebigen URL — gleiches Muster
// wie der HLS-Proxy (`server/homeassistant/hls-proxy.ts`): HMAC über Quelle + Ablauf mit
// SESSION_SECRET, 24 h gültig, nur http(s)-Quellen.

const TTL_MS = 24 * 3600 * 1000;
const agent = new https.Agent({ rejectUnauthorized: false }); // Synology-Cover: self-signed

function sign(payload: string): string {
  return createHmac("sha256", config.sessionSecret || "push-cover").update(payload).digest("base64url");
}

/** Signierte, öffentlich abrufbare Cover-URL (absolut) — oder null, wenn keine Quelle bekannt ist. */
export function signedCoverUrl(source: string | null | undefined): string | null {
  if (!source || !/^https?:\/\//i.test(source)) return null;
  const payload = Buffer.from(JSON.stringify({ u: source, e: Date.now() + TTL_MS })).toString("base64url");
  return `${config.publicBaseUrl}/api/v1/push/cover/${payload}.${sign(payload)}`;
}

/** Token prüfen → Quell-URL (nicht abgelaufen, http(s)) oder null. */
export function verifyCoverToken(token: string): string | null {
  const dot = token.lastIndexOf(".");
  if (dot < 0) return null;
  const payload = token.slice(0, dot);
  const sig = token.slice(dot + 1);
  const expected = sign(payload);
  if (sig.length !== expected.length || !timingSafeEqual(Buffer.from(sig), Buffer.from(expected))) return null;
  try {
    const obj = JSON.parse(Buffer.from(payload, "base64url").toString("utf8")) as { u: string; e: number };
    if (!obj?.u || typeof obj.e !== "number" || Date.now() > obj.e) return null;
    return /^https?:\/\//i.test(obj.u) ? obj.u : null;
  } catch {
    return null;
  }
}

/** Bild von der Quelle holen (folgt keinen Weiterleitungen ins Ungewisse; max. 3 MB). */
export function fetchImage(url: string): Promise<{ contentType: string; bytes: Buffer } | null> {
  return new Promise((resolve) => {
    const u = new URL(url);
    const mod = u.protocol === "http:" ? require("node:http") : https;
    const req = mod.request(
      u,
      { agent: u.protocol === "https:" ? agent : undefined, timeout: 15000, headers: { accept: "image/*" } },
      (res: import("node:http").IncomingMessage) => {
        const ct = String(res.headers["content-type"] ?? "");
        if ((res.statusCode ?? 0) !== 200 || !ct.startsWith("image/")) { res.resume(); resolve(null); return; }
        const chunks: Buffer[] = [];
        let size = 0;
        res.on("data", (c: Buffer) => {
          size += c.length;
          if (size > 3_000_000) { req.destroy(); resolve(null); return; }
          chunks.push(c);
        });
        res.on("end", () => resolve({ contentType: ct, bytes: Buffer.concat(chunks) }));
      },
    );
    req.on("error", () => resolve(null));
    req.on("timeout", () => { req.destroy(); resolve(null); });
    req.end();
  });
}
