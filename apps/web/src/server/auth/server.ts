import { cookies } from "next/headers";
import { verifySession, SESSION_COOKIE } from "./session";

/** Session-User aus dem Cookie (für Server-Components / Layout-Guards). */
export async function getSessionUser(): Promise<string | null> {
  const store = await cookies();
  const token = store.get(SESSION_COOKIE)?.value;
  if (!token) return null;
  const p = verifySession(token);
  return p ? p.u : null;
}
