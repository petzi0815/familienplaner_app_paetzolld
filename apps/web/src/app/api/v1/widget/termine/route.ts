import { agenda, type AgendaItem } from "@/server/domains/queries";
import { getAuth, hasRole } from "@/server/auth/auth";
import { unauthorized, ok } from "@/server/http/respond";
import { getCategoryInfo } from "@/server/legacy/termine-db";
import { abfuhrCategory } from "@/server/abfuhr/abfuhr";

// Schlanker, für WidgetKit optimierter Termin-Feed (Home-Screen + Sperrbildschirm + Live Activity).
// Baut auf dem generischen „Anstehendes"-Feed `agenda(days, owner)` auf und reichert jedes Element
// um Emoji + Farbe (Hex) an, damit das Widget nichts nachschlagen muss. Zähler (heute/morgen/woche)
// werden serverseitig gerechnet — das Widget rendert nur noch.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

// Die Termin-Kategorien (server/legacy/termine-db.ts, auch via `GET /api/termine?mode=categories`)
// führen Tailwind-Farbnamen. Für das Widget brauchen wir echte Hex-Werte → Tailwind-500-Töne.
const TAILWIND_HEX: Record<string, string> = {
  blue: "#3B82F6", red: "#EF4444", rose: "#F43F5E", purple: "#A855F7", indigo: "#6366F1",
  cyan: "#06B6D4", amber: "#F59E0B", orange: "#F97316", gray: "#6B7280", green: "#22C55E",
  pink: "#EC4899", violet: "#8B5CF6", slate: "#64748B",
};
const DEFAULT_EMOJI = "📅";
const DEFAULT_COLOR = "#3B82F6";

// Nicht-Termin-Quellen des Feeds bekommen sinnvolle Defaults (Abfuhr bringt eigene Hex-Farben mit).
const SOURCE_STYLE: Record<string, { emoji: string; color: string }> = {
  abfuhr: { emoji: "🗑️", color: "#6B7280" },
  reise: { emoji: "✈️", color: "#0EA5E9" },
  vorrat: { emoji: "🥫", color: "#F59E0B" },
  reminder: { emoji: "🔔", color: "#8B5CF6" },
};

/** Emoji + Farbe je Feed-Element — Quelle: Termin-Kategorien bzw. Abfuhr-Kategorien. */
function styleOf(it: AgendaItem): { emoji: string; color: string } {
  if (it.source === "termin") {
    const cat = getCategoryInfo(String(it.category ?? "allgemein"));
    return { emoji: cat.emoji || DEFAULT_EMOJI, color: TAILWIND_HEX[cat.color] ?? DEFAULT_COLOR };
  }
  if (it.source === "abfuhr") {
    const cat = it.category ? abfuhrCategory(String(it.category)) : undefined;
    return { emoji: cat?.emoji ?? SOURCE_STYLE.abfuhr.emoji, color: cat?.color ?? SOURCE_STYLE.abfuhr.color };
  }
  return SOURCE_STYLE[it.source] ?? { emoji: DEFAULT_EMOJI, color: DEFAULT_COLOR };
}

/** Der Abfuhr-Titel trägt im Feed bereits das Emoji („🗑️ Restmüll") — im Widget steht es separat. */
function titleOf(it: AgendaItem, emoji: string): string {
  const t = String(it.title ?? "").trim();
  return t.startsWith(emoji) ? t.slice(emoji.length).trim() : t;
}

export function GET(req: Request): Response {
  const auth = getAuth(req);
  if (!hasRole(auth, "readonly")) return unauthorized();
  const raw = Number(new URL(req.url).searchParams.get("days") ?? "14");
  const days = Number.isFinite(raw) ? Math.max(1, Math.min(Math.trunc(raw), 365)) : 14;
  const owner = auth?.owner ?? null;
  const now = Math.floor(Date.now() / 1000);

  // Exklusives Ende — MUSS der Client-Auslegung entsprechen (ios-app/Shared/WidgetTermin.swift):
  // bei ganztägigen/mehrtägigen Einträgen ist `end_at` = 00:00 des Endtages, dieser Tag zählt also
  // noch dazu. Ohne die Tagesaddition wäre die Route einen ganzen Tag strenger als das Widget und
  // ein laufender Mehrtages-Termin (z.B. „Zwergenstübchen Sommerferien" 09.07.–30.07.) fiele an
  // seinem LETZTEN Tag aus dem Feed. (+86400 statt Kalendertag: an den 2 Zeitumstellungen im Jahr
  // um eine Stunde ungenau — unkritisch für einen Sichtbarkeits-Filter.)
  const effEnd = (it: AgendaItem): number | null =>
    it.all_day ? (it.end_at ?? it.start_at ?? 0) + 86400 : (it.end_at ?? null);

  const items = agenda(days, owner)
    // Widgets zeigen nach vorn: alles ab heute, plus noch laufende (Ende in der Zukunft) Elemente.
    .filter((it) => {
      if ((it.days_until ?? 0) >= 0) return true;
      const e = effEnd(it);
      return e != null && e > now;
    })
    // Diese Projektionsschicht muss TOTAL sein: der Client decodiert `start_at`/`days_until` als
    // nicht-optionale Zahlen. Ein einziger Datensatz mit unparsbarem Datum (kein ableitbares
    // `start_at`) würde sonst den KOMPLETTEN Feed reißen — das Widget bliebe ohne erkennbare
    // Ursache leer. Solche Elemente fliegen hier raus, statt alles mitzunehmen.
    .filter((it): it is AgendaItem & { start_at: number } => Number.isFinite(it.start_at))
    .slice(0, 50) // Payload-Deckel — mehr zeigt kein Widget
    .map((it) => {
      const { emoji, color } = styleOf(it);
      return {
        id: it.id,
        source: it.source,
        ref_id: it.ref_id,
        title: titleOf(it, emoji),
        subtitle: it.subtitle ?? null,
        location: it.location ?? null,
        emoji,
        color,
        date: it.date,
        time: it.time ?? null,
        start_at: it.start_at,
        end_at: it.end_at ?? null,
        all_day: it.all_day ?? !it.time,
        days_until: it.days_until ?? 0,
        read: !!it.read,
        muted: !!it.muted,
      };
    });

  // Zähler nach BETROFFENEN TAGEN, nicht nach dem Startdatum: ein noch laufender Mehrtages-Eintrag
  // (Ferien, Reise) hat ein negatives `days_until`, belegt aber sehr wohl den heutigen Tag. Ohne diese
  // Regel stünde im Widget „Heute 0" über einer Liste, die zwei Einträge unter „Heute" zeigt.
  const DAY = 86400;
  const dayStart = Math.floor(now / DAY) * DAY; // grobe Tagesraster-Basis reicht für den Vergleich
  const coversDay = (i: { days_until: number; end_at: number | null; all_day: boolean }, n: number): boolean => {
    if (i.days_until === n) return true;
    if (i.days_until > n) return false;
    // Bereits begonnen: zählt, solange das (bei ganztägig inklusive) Ende den Tag noch abdeckt.
    if (i.end_at == null) return false;
    const effEnd = i.all_day ? i.end_at + DAY : i.end_at;
    return effEnd > dayStart + n * DAY;
  };
  const counts = {
    heute: items.filter((i) => coversDay(i, 0)).length,
    morgen: items.filter((i) => coversDay(i, 1)).length,
    woche: items.filter((i) => Array.from({ length: 7 }, (_, n) => n).some((n) => coversDay(i, n))).length,
  };

  return ok({ data: { now, owner, items, counts }, total: items.length });
}
