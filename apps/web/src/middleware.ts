import { NextResponse, type NextRequest } from "next/server";

// UI-Login-Gate: ohne Session-Cookie → Redirect auf /login. Nur UX/Präsenzprüfung —
// die eigentliche Validierung passiert serverseitig (API getAuth + Server-Component-Guard).
// Bewusst KEINE node-Imports (Edge-Runtime): Cookie-Name als Literal.
const SESSION_COOKIE = "fp_session";

export function middleware(req: NextRequest): NextResponse {
  const { pathname } = req.nextUrl;
  if (pathname === "/login") return NextResponse.next();
  if (req.cookies.get(SESSION_COOKIE)) return NextResponse.next();
  const url = req.nextUrl.clone();
  url.pathname = "/login";
  url.searchParams.set("next", pathname);
  return NextResponse.redirect(url);
}

// Läuft nicht für: /api, /_next, /healthz, /version und Dateien mit Endung (Assets).
export const config = {
  matcher: ["/((?!api|_next|healthz|version|.*\\.).*)"],
};
