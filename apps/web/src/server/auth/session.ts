import crypto from "node:crypto";
import { config } from "@/server/config";

const SECRET = () => config.sessionSecret || "dev-insecure-secret";

export interface SessionPayload {
  u: string;   // user-label (Familie)
  exp: number; // Ablauf (ms epoch)
}

export const SESSION_COOKIE = "fp_session";
export const SESSION_TTL_MS = 1000 * 60 * 60 * 24 * 30; // 30 Tage

/** Signiertes, zustandsloses Session-Token (HMAC-SHA256). */
export function signSession(payload: SessionPayload): string {
  const body = Buffer.from(JSON.stringify(payload)).toString("base64url");
  const sig = crypto.createHmac("sha256", SECRET()).update(body).digest("base64url");
  return `${body}.${sig}`;
}

export function verifySession(token: string): SessionPayload | null {
  const dot = token.indexOf(".");
  if (dot < 0) return null;
  const body = token.slice(0, dot);
  const sig = token.slice(dot + 1);
  const expect = crypto.createHmac("sha256", SECRET()).update(body).digest("base64url");
  const a = Buffer.from(sig);
  const b = Buffer.from(expect);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return null;
  try {
    const payload = JSON.parse(Buffer.from(body, "base64url").toString()) as SessionPayload;
    if (payload.exp && Date.now() > payload.exp) return null;
    return payload;
  } catch {
    return null;
  }
}
