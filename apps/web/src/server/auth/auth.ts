import { config } from "@/server/config";
import { getDb } from "@/server/db/connection";
import { sha256 } from "@/server/util/hash";
import { verifySession, SESSION_COOKIE } from "./session";

export type Role = "admin" | "agent" | "readonly";
const RANK: Record<Role, number> = { readonly: 1, agent: 2, admin: 3 };

export interface Auth {
  role: Role;
  actor: string;
  /** Zugeordnete Person eines Per-User-Keys ('lars' | 'elita'); NULL bei Ole/Admin/Session. */
  owner?: string | null;
}

export function readCookie(req: Request, name: string): string | null {
  const raw = req.headers.get("cookie");
  if (!raw) return null;
  for (const part of raw.split(";")) {
    const eq = part.indexOf("=");
    if (eq < 0) continue;
    if (part.slice(0, eq).trim() === name) return decodeURIComponent(part.slice(eq + 1).trim());
  }
  return null;
}

/** Löst die Authentifizierung auf: Bearer (Admin-Passwort ODER API-Key) oder Session-Cookie. */
export function getAuth(req: Request): Auth | null {
  const authz = req.headers.get("authorization") ?? "";
  const bearer = authz.toLowerCase().startsWith("bearer ") ? authz.slice(7).trim() : "";
  if (bearer) {
    if (config.adminPassword && bearer === config.adminPassword) return { role: "admin", actor: "admin-token", owner: null };
    try {
      const db = getDb();
      const row = db.prepare("SELECT id,label,role,revoked,owner FROM api_keys WHERE key_hash=?").get(sha256(bearer)) as
        | { id: number; label: string | null; role: Role; revoked: number; owner: string | null }
        | undefined;
      if (row && !row.revoked) {
        db.prepare("UPDATE api_keys SET last_used_at=datetime('now') WHERE id=?").run(row.id);
        return { role: row.role, actor: `key:${row.label ?? row.id}`, owner: row.owner };
      }
    } catch {
      /* DB evtl. nicht bereit — als nicht authentifiziert behandeln */
    }
  }
  const cookie = readCookie(req, SESSION_COOKIE);
  if (cookie) {
    const p = verifySession(cookie);
    if (p) return { role: "admin", actor: `session:${p.u}`, owner: null };
  }
  return null;
}

export function hasRole(auth: Auth | null, min: Role): auth is Auth {
  return !!auth && RANK[auth.role] >= RANK[min];
}
