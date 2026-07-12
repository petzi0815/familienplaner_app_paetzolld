import type BetterSqlite3 from "better-sqlite3";

// Abfuhrkalender-Logik: Kategorien, ICS-Parser, nächster Termin je Kategorie.

export interface AbfuhrCategory { key: string; label: string; emoji: string; color: string }

export const ABFUHR_CATEGORIES: AbfuhrCategory[] = [
  { key: "restmuell", label: "Restmüll", emoji: "🗑️", color: "#6B7280" },
  { key: "gelbe_tonne", label: "Gelbe Tonne", emoji: "♻️", color: "#F59E0B" },
  { key: "bio", label: "Bio", emoji: "🌱", color: "#84CC16" },
  { key: "papier", label: "Papier", emoji: "📦", color: "#3B82F6" },
];
const CAT_BY_KEY = new Map(ABFUHR_CATEGORIES.map((c) => [c.key, c]));
export const abfuhrCategory = (key: string): AbfuhrCategory | undefined => CAT_BY_KEY.get(key);

/** SUMMARY (z.B. "Leichtverpackungen *") → Kategorie-Key. */
export function categoryFromSummary(summary: string): string {
  const s = summary.toLowerCase();
  if (s.includes("restabfall") || s.includes("restmüll") || s.includes("restmuell")) return "restmuell";
  if (s.includes("leichtverpackung") || s.includes("gelb") || s.includes("wertstoff") || s.includes("verpackung")) return "gelbe_tonne";
  if (s.includes("bio")) return "bio";
  if (s.includes("papier") || s.includes("pappe") || s.includes("karton")) return "papier";
  return "sonstige";
}

export interface ParsedEvent { uid: string; kategorie: string; datum: string; summary: string }

/** Parst eine ICS in Abfuhr-Events. DTSTART;VALUE=DATE:YYYYMMDD → datum YYYY-MM-DD. */
export function parseAbfuhrICS(ics: string): ParsedEvent[] {
  // Zeilen entfalten (RFC5545: fortgesetzte Zeilen beginnen mit Space/Tab).
  const unfolded = ics.replace(/\r?\n[ \t]/g, "");
  const out: ParsedEvent[] = [];
  const blocks = unfolded.split("BEGIN:VEVENT").slice(1);
  for (const b of blocks) {
    const body = b.split("END:VEVENT")[0];
    const uid = (body.match(/^UID:(.+)$/m)?.[1] ?? "").trim();
    const summaryRaw = (body.match(/^SUMMARY:(.+)$/m)?.[1] ?? "").trim();
    const dt = body.match(/^DTSTART(?:;[^:]*)?:(\d{8})/m)?.[1];
    if (!summaryRaw || !dt) continue;
    const datum = `${dt.slice(0, 4)}-${dt.slice(4, 6)}-${dt.slice(6, 8)}`;
    const summary = summaryRaw.replace(/\s*\*+\s*$/, "").trim(); // "Restabfall *" → "Restabfall"
    out.push({ uid: uid || `${summary}-${datum}`, kategorie: categoryFromSummary(summary), datum, summary });
  }
  return out;
}

export interface NextAbfuhr { kategorie: string; label: string; emoji: string; color: string; datum: string | null; days_until: number | null }

/** Nächster Termin je Kategorie (ab heute). */
export function nextPerCategory(db: BetterSqlite3.Database): NextAbfuhr[] {
  const stmt = db.prepare(
    "SELECT datum, CAST(julianday(datum) - julianday('now','localtime') AS INTEGER) AS days FROM abfuhr_termine WHERE kategorie=? AND datum >= date('now','localtime') ORDER BY datum ASC LIMIT 1",
  );
  return ABFUHR_CATEGORIES.map((c) => {
    const row = stmt.get(c.key) as { datum: string; days: number } | undefined;
    return { kategorie: c.key, label: c.label, emoji: c.emoji, color: c.color,
             datum: row?.datum ?? null, days_until: row ? Math.max(0, row.days) : null };
  });
}

// ── aha-region.de Online-Sync (3-Schritt-Formular: Straße → ladeort → ICS) ──
export interface AhaParams { gemeinde: string; von: string; strasse: string; hausnr: string; hausnraddon: string }
const AHA_BASE = "https://www.aha-region.de/abholtermine/abfuhrkalender";

/** Holt die Jahres-ICS von aha-region.de für die konfigurierte Adresse. */
export async function fetchAhaICS(p: AhaParams): Promise<string> {
  const ua = "Mozilla/5.0";
  const base = { gemeinde: p.gemeinde, jsaus: "", von: p.von, strasse: p.strasse, hausnr: p.hausnr, hausnraddon: p.hausnraddon };
  // Schritt 2: ladeort ermitteln (POST anzeigen=Suchen).
  const r2 = await fetch(AHA_BASE, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded", "user-agent": ua },
    body: new URLSearchParams({ ...base, anzeigen: "Suchen" }).toString(),
  });
  const cookie = (r2.headers.get("set-cookie") ?? "").split(";")[0];
  const h2 = await r2.text();
  let ladeort = h2.match(/name=["']ladeort["'][^>]*value=["']([^"']*)["']/i)?.[1];
  if (!ladeort) {
    const sel = h2.match(/<select[^>]*name=["']ladeort["'][^>]*>([\s\S]*?)<\/select>/i)?.[1];
    ladeort = sel?.match(/<option[^>]*value=["']([^"']+)["']/i)?.[1];
  }
  // Schritt 3: ICS (POST ical="ICAL Jahresübersicht").
  const r3 = await fetch(AHA_BASE, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded", "user-agent": ua, ...(cookie ? { cookie } : {}) },
    body: new URLSearchParams({ ...base, ladeort: ladeort ?? "", ical: "ICAL Jahresübersicht" }).toString(),
  });
  return await r3.text();
}

/** Alle kommenden Termine (flach, ab heute). */
export function upcoming(db: BetterSqlite3.Database, limit = 30): { kategorie: string; label: string; datum: string }[] {
  const rows = db.prepare(
    "SELECT kategorie, datum FROM abfuhr_termine WHERE datum >= date('now','localtime') ORDER BY datum ASC LIMIT ?",
  ).all(limit) as { kategorie: string; datum: string }[];
  return rows.map((r) => ({ ...r, label: abfuhrCategory(r.kategorie)?.label ?? r.kategorie }));
}
