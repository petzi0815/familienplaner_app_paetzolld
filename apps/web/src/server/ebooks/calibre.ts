import https from "node:https";
import { config } from "@/server/config";

// Proxy zur familieneigenen Calibre-Web-Instanz (Synology, selbst-signiert, Session-Login + CSRF).
// BEWUSST nur lesen + auf Regal legen/entfernen — kein Löschen/Ändern von Büchern/Metadaten.
// node:https (rejectUnauthorized:false) + manuelles Cookie/CSRF-Handling; Session wird gecacht.

const agent = new https.Agent({ rejectUnauthorized: false });

export function calibreEnabled(): boolean {
  return !!(config.calibre.username && config.calibre.password);
}

interface RawResp { status: number; headers: Record<string, string | string[] | undefined>; body: Buffer }

function raw(path: string, opts: { method?: string; headers?: Record<string, string>; body?: string } = {}): Promise<RawResp> {
  return new Promise((resolve, reject) => {
    const u = new URL(config.calibre.baseUrl + path);
    const r = https.request(u, { method: opts.method ?? "GET", agent, headers: opts.headers ?? {}, timeout: 20000 }, (x) => {
      const ch: Buffer[] = [];
      x.on("data", (c) => ch.push(c as Buffer));
      x.on("end", () => resolve({ status: x.statusCode ?? 0, headers: x.headers, body: Buffer.concat(ch) }));
    });
    r.on("error", reject);
    r.on("timeout", () => r.destroy(new Error("Calibre-Zeitüberschreitung")));
    if (opts.body) r.write(opts.body);
    r.end();
  });
}

function cookiesFrom(h: RawResp["headers"]): string {
  const sc = h["set-cookie"];
  if (!sc) return "";
  return (Array.isArray(sc) ? sc : [sc]).map((c) => String(c).split(";")[0]).join("; ");
}

let session: { cookie: string; csrf: string } | null = null;

async function login(): Promise<{ cookie: string; csrf: string }> {
  const g = await raw("/login");
  const loginCsrf = (g.body.toString().match(/name="csrf_token"[^>]*value="([^"]+)"/) || [])[1] ?? "";
  const c0 = cookiesFrom(g.headers);
  const form = new URLSearchParams({
    username: config.calibre.username, password: config.calibre.password,
    csrf_token: loginCsrf, next: "/", remember_me: "on",
  }).toString();
  const l = await raw("/login", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded", cookie: c0, "content-length": String(Buffer.byteLength(form)) },
    body: form,
  });
  if (l.status !== 302 && l.status !== 200) throw new Error(`Calibre-Login fehlgeschlagen (${l.status})`);
  const cookie = cookiesFrom(l.headers) || c0;
  const home = (await raw("/", { headers: { cookie } })).body.toString();
  const csrf = (home.match(/name="csrf-token"\s+content="([^"]+)"/) || home.match(/name="csrf_token"[^>]*value="([^"]+)"/) || [])[1] ?? loginCsrf;
  session = { cookie, csrf };
  return session;
}

async function ensure(): Promise<{ cookie: string; csrf: string }> {
  return session ?? login();
}

/** Authentifizierter Request; bei abgelaufener Session (Redirect auf /login oder 401) einmal neu einloggen.
 *  `csrf`: fügt das X-CSRFToken der AKTUELLEN Session hinzu — auch nach Re-Login mit frischem Token. */
async function authed(
  path: string,
  opts: { method?: string; headers?: Record<string, string>; body?: string; csrf?: boolean } = {},
  retry = true,
): Promise<RawResp> {
  const s = await ensure();
  const headers: Record<string, string> = { cookie: s.cookie, ...(opts.headers ?? {}) };
  if (opts.csrf) headers["x-csrftoken"] = s.csrf; // frisch je (Wiederhol-)Versuch
  const res = await raw(path, { method: opts.method, body: opts.body, headers });
  const loginRedirect = res.status === 302 && String(res.headers.location ?? "").includes("/login");
  if (retry && (res.status === 401 || loginRedirect)) {
    session = null;
    return authed(path, opts, false);
  }
  return res;
}

export interface CalibreBook {
  id: number;
  title: string;
  authors: string;
  series: string | null;
  tags: string[];
  has_cover: boolean;
  isbn: string | null;
  read_status: boolean;
  description: string | null;   // Calibre `comments` (HTML → Klartext)
  publisher: string | null;
  published: string | null;     // Erscheinungsjahr
  rating: string | null;
  languages: string | null;
}

const stripHtml = (s: string) => s.replace(/<[^>]+>/g, " ").replace(/&nbsp;/g, " ").replace(/&amp;/g, "&").replace(/\s+/g, " ").trim();

function mapBook(r: Record<string, unknown>): CalibreBook {
  const tags = typeof r.tags === "string" ? (r.tags as string).split(",").map((t) => t.trim()).filter(Boolean) : [];
  const comments = r.comments ? stripHtml(String(r.comments)) : "";
  const pub = r.pubdate ? String(r.pubdate) : "";
  const rawYear = /^\d{4}/.test(pub) ? pub.slice(0, 4) : null;
  const year = rawYear && rawYear >= "1000" ? rawYear : null; // Calibre-Sentinel (0101 / <1000) verwerfen
  return {
    id: Number(r.id),
    title: String(r.title ?? ""),
    authors: String(r.authors ?? ""),
    series: r.series ? String(r.series) : null,
    tags,
    has_cover: !!r.has_cover,
    isbn: r.isbn ? String(r.isbn) : null,
    read_status: !!r.read_status,
    description: comments || null,
    publisher: r.publishers ? String(r.publishers) : null,
    published: year,
    rating: r.ratings ? String(r.ratings) : null,
    languages: r.languages ? String(r.languages) : null,
  };
}

/** Bücher listen/suchen (Volltext über `search`). */
export async function listBooks(p: { offset?: number; limit?: number; search?: string; sort?: string; order?: string }): Promise<{ total: number; rows: CalibreBook[] }> {
  const q = new URLSearchParams({ offset: String(p.offset ?? 0), limit: String(p.limit ?? 30), sort: p.sort ?? "id", order: p.order ?? "desc" });
  if (p.search) q.set("search", p.search);
  const res = await authed(`/ajax/listbooks?${q.toString()}`, { headers: { "x-requested-with": "XMLHttpRequest" } });
  const j = JSON.parse(res.body.toString()) as { total?: number; rows?: Record<string, unknown>[] };
  return { total: j.total ?? 0, rows: (j.rows ?? []).map(mapBook) };
}

/** Regale (id + Name) aus der eingeloggten Startseiten-Navigation. */
export async function shelves(): Promise<{ id: number; name: string }[]> {
  const html = (await authed("/")).body.toString();
  const out = new Map<number, string>();
  for (const m of html.matchAll(/href="\/shelf\/(\d+)"[^>]*>\s*(?:<[^>]*>\s*)*([^<]+)/g)) {
    const id = Number(m[1]);
    const name = m[2].trim();
    if (id && name && !out.has(id)) out.set(id, name);
  }
  return [...out].map(([id, name]) => ({ id, name })).sort((a, b) => a.name.localeCompare(b.name));
}

/** Bücher eines Regals (aus der Regal-Seite geparst: id + Titel; Cover über /cover/<id>). */
export async function shelfBooks(shelfId: number): Promise<CalibreBook[]> {
  const html = (await authed(`/shelf/${shelfId}`)).body.toString();
  const books: CalibreBook[] = [];
  const seen = new Set<number>();
  const push = (id: number, title: string) => {
    if (!id || seen.has(id)) return;
    seen.add(id);
    books.push({ id, title: title || `#${id}`, authors: "", series: null, tags: [], has_cover: true, isbn: null, read_status: false, description: null, publisher: null, published: null, rating: null, languages: null });
  };
  // CWA-Regal-Karte: <a href="/book/<id>" …> <span class="img" title="<Titel>">
  for (const m of html.matchAll(/\/book\/(\d+)"[\s\S]{0,300}?class="img"\s+title="([^"]*)"/g)) push(Number(m[1]), m[2].trim());
  if (!books.length) for (const m of html.matchAll(/\/book\/(\d+)/g)) push(Number(m[1]), "");
  return books;
}

/** Detail eines Buchs: aktuell zugeordnete Regal-IDs (data-shelf-action="remove") + Voll-Metadaten.
 *  Metadaten via Titel-Suche in listbooks (CWA-Web-Suche kennt kein `id:`), nach id gefiltert. */
export async function bookDetail(id: number, title?: string): Promise<{ shelfIds: number[]; book: CalibreBook | null; formats: string[] }> {
  const html = (await authed(`/book/${id}`)).body.toString();
  const shelfIds = new Set<number>();
  for (const m of html.matchAll(/\/shelf\/add\/(\d+)\/\d+"[\s\S]{0,160}?data-shelf-action="(add|remove)"/g)) {
    if (m[2] === "remove") shelfIds.add(Number(m[1]));
  }
  // Herunterladbare Formate aus den Download-Links der Detailseite (/download/<id>/<format>/…).
  const formats = new Set<string>();
  for (const m of html.matchAll(/\/download\/\d+\/([a-z0-9]+)\//gi)) formats.add(m[1].toLowerCase());
  let book: CalibreBook | null = null;
  if (title && title.trim()) {
    try {
      const res = await listBooks({ search: title.trim(), limit: 25 });
      book = res.rows.find((b) => b.id === id) ?? null;
    } catch { /* Metadaten optional */ }
  }
  return { shelfIds: [...shelfIds], book, formats: [...formats] };
}

/** Buch-Datei in einem Format herunterladen (CWA: /download/<id>/<format>/<name>). Bytes + Dateiname. */
export async function downloadBook(
  id: number,
  format: string,
): Promise<{ contentType: string; bytes: Buffer; filename: string } | null> {
  const fmt = format.toLowerCase().replace(/[^a-z0-9]/g, "");
  if (!fmt) return null;
  const res = await authed(`/download/${id}/${fmt}/${id}.${fmt}`);
  if (res.status !== 200) return null;
  // Dateiname bewusst ASCII-sicher (`<id>.<fmt>`) — CWAs Content-Disposition kann typografische/Nicht-Latin1-
  // Zeichen enthalten, die als HTTP-Header werfen würden. Der Client benennt die Datei ohnehin nach dem Titel.
  return {
    contentType: String(res.headers["content-type"] ?? "application/octet-stream"),
    bytes: res.body,
    filename: `${id}.${fmt}`,
  };
}

/** Buch auf ein Regal legen/entfernen (POST mit CSRF — Token wird in authed() frisch gesetzt). */
export async function shelfAction(action: "add" | "remove", shelfId: number, bookId: number): Promise<boolean> {
  const res = await authed(`/shelf/${action}/${shelfId}/${bookId}`, {
    method: "POST",
    headers: { "x-requested-with": "XMLHttpRequest" },
    csrf: true,
  });
  return res.status === 200 || res.status === 204 || res.status === 302;
}

/** Cover-Bytes eines Buchs (für den Backend-Proxy). */
export async function cover(bookId: number): Promise<{ contentType: string; bytes: Buffer } | null> {
  const res = await authed(`/cover/${bookId}`);
  if (res.status !== 200) return null;
  return { contentType: String(res.headers["content-type"] ?? "image/jpeg"), bytes: res.body };
}
