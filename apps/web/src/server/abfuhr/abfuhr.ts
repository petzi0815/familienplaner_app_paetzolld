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

/** Alle kommenden Termine (flach, ab heute). */
export function upcoming(db: BetterSqlite3.Database, limit = 30): { kategorie: string; label: string; datum: string }[] {
  const rows = db.prepare(
    "SELECT kategorie, datum FROM abfuhr_termine WHERE datum >= date('now','localtime') ORDER BY datum ASC LIMIT ?",
  ).all(limit) as { kategorie: string; datum: string }[];
  return rows.map((r) => ({ ...r, label: abfuhrCategory(r.kategorie)?.label ?? r.kategorie }));
}
