import crypto from "node:crypto";
import { getDb } from "@/server/db/connection";

// Klartext-Token für abonnierbare ICS-Feeds. Kalender-Apps können keinen Bearer-Header senden →
// der Token steckt im URL-Pfad (nie Query-String, per Projekt-Datenschutzregel).

export interface FeedToken { id: number; token: string; scope: string; label: string | null; revoked: number }

const genToken = () => crypto.randomBytes(24).toString("base64url"); // ~32 URL-sichere Zeichen

/** Liefert den (bei Bedarf neu angelegten) Familien-Feed-Token. */
export function getOrCreateFamilyToken(): string {
  const db = getDb();
  const row = db.prepare("SELECT token FROM feed_tokens WHERE scope='family' AND revoked=0 ORDER BY id ASC LIMIT 1").get() as { token: string } | undefined;
  if (row) return row.token;
  const token = genToken();
  db.prepare("INSERT INTO feed_tokens (token, scope, label) VALUES (?, 'family', 'Familien-Kalender')").run(token);
  return token;
}

/** Rotiert den Familien-Token: alten revoken, neuen anlegen (Abo-Links müssen erneuert werden). */
export function rotateFamilyToken(): string {
  const db = getDb();
  db.prepare("UPDATE feed_tokens SET revoked=1 WHERE scope='family' AND revoked=0").run();
  const token = genToken();
  db.prepare("INSERT INTO feed_tokens (token, scope, label) VALUES (?, 'family', 'Familien-Kalender')").run(token);
  return token;
}

/** Token nachschlagen (nur gültige/nicht-widerrufene). Bumpt last_used_at. */
export function lookupToken(token: string): FeedToken | null {
  if (!token) return null;
  const db = getDb();
  const row = db.prepare("SELECT id,token,scope,label,revoked FROM feed_tokens WHERE token=? AND revoked=0").get(token) as FeedToken | undefined;
  if (!row) return null;
  db.prepare("UPDATE feed_tokens SET last_used_at=datetime('now') WHERE id=?").run(row.id);
  return row;
}
