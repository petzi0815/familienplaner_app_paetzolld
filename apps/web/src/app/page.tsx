import Link from "next/link";
import { getDb } from "@/server/db/connection";
import { LogoutButton } from "@/components/LogoutButton";

// Lebensbereich-Key → Registry-Domain (fast identisch; nur „buecher" → „ebooks").
const DOMAIN_OF: Record<string, string> = { buecher: "ebooks" };
// Bespoke, originalgetreue Bereichsseiten (statt generischem Browser) — via Kompat-API-Layer 1:1 portiert.
const BESPOKE_HREF: Record<string, string> = {
  reisen: "/reisen",
  samu: "/samu",
  garten: "/garten",
  geschenkplaner: "/geschenkplaner",
  termine: "/termine",
  vorratskammer: "/vorratskammer",
  wunschliste: "/wunschliste",
  gypsi: "/gypsi",
  reiniger: "/reiniger",
  buecher: "/buecher",
  smarthome: "/smarthome",
  vertraege: "/vertraege",
};

// Datengetriebenes Portal: Kacheln aus der `lebensbereiche`-Registry + Tagesübersicht aus der DB.
// Domänen-spezifische UIs folgen in Phase 3; die REST-API (/api/v1/*) ist bereits vollständig.
export const dynamic = "force-dynamic";

// Gradient-Klassen als Map (Tailwind-JIT kann keine Klassen aus DB-Werten generieren).
const GRADIENTS: Record<string, string> = {
  samu: "from-[#FF9F0A] via-[#FF6B6B] to-[#AF52DE]",
  gypsi: "from-[#FF8C00] via-[#FF6600] to-[#FF4500]",
  smarthome: "from-[#007AFF] via-[#5856D6] to-[#AF52DE]",
  garten: "from-[#34C759] via-[#30D158] to-[#00C7BE]",
  vertraege: "from-[#5856D6] via-[#AF52DE] to-[#FF2D55]",
  buecher: "from-[#FF2D55] via-[#FF6B6B] to-[#FF9500]",
  wunschliste: "from-[#AF52DE] via-[#FF2D55] to-[#FF9500]",
  termine: "from-[#007AFF] via-[#5856D6] to-[#34C759]",
  reisen: "from-[#FF9500] via-[#FF6B6B] to-[#5856D6]",
  geschenkplaner: "from-[#F59E0B] via-[#EF4444] to-[#8B5CF6]",
  vorratskammer: "from-[#F97316] via-[#FB923C] to-[#FBBF24]",
  reiniger: "from-[#0EA5E9] via-[#14B8A6] to-[#84CC16]",
  elisbooks: "from-[#92400E] via-[#B45309] to-[#D97706]",
  foto: "from-[#5AC8FA] via-[#007AFF] to-[#5856D6]",
};
const DEFAULT_GRADIENT = "from-[#8E8E93] via-[#AEAEB2] to-[#C7C7CC]";

interface Bereich { key: string; titel: string; beschreibung: string; emoji: string; gradient: string; }

export default function Portal() {
  const db = getDb();
  const bereiche = db.prepare(
    "SELECT key, titel, beschreibung, emoji, gradient FROM lebensbereiche WHERE enabled=1 ORDER BY sort ASC",
  ).all() as Bereich[];

  const safe = <T,>(fn: () => T, fb: T): T => { try { return fn(); } catch { return fb; } };
  // Zeit über SQLite (date('now')/julianday) statt JS-Date — vermeidet impure Calls im Render.
  const termineNext = safe(() => (db.prepare("SELECT COUNT(*) c FROM termine WHERE date >= date('now') AND COALESCE(status,'')<>'erledigt'").get() as { c: number }).c, 0);
  const nextTrip = safe(() => db.prepare(
    "SELECT title, destination, start_date, CAST(julianday(start_date) - julianday('now') AS INTEGER) AS days_until FROM reisen_trips WHERE start_date >= date('now') ORDER BY start_date ASC LIMIT 1",
  ).get() as { title: string; destination: string; start_date: string; days_until: number } | undefined, undefined);
  const tripDays = nextTrip?.days_until ?? 0;

  return (
    <main className="min-h-[100dvh] bg-gradient-to-br from-[#F2F2F7] via-[#E5E5EA] to-[#F2F2F7]">
      <header className="pt-10 pb-3 px-4 safe-area-inset">
        <div className="max-w-3xl mx-auto flex items-start justify-between">
          <div>
            <h1 className="text-2xl font-extrabold text-[#1C1C1E] tracking-tight mb-0.5">Familie Paetzold-Stilke</h1>
            <p className="text-[#8E8E93] text-xs font-medium">Familienplaner</p>
          </div>
          <LogoutButton />
        </div>
      </header>

      {/* Tagesübersicht */}
      <div className="max-w-3xl mx-auto px-3 mb-1">
        <div className="grid grid-cols-2 gap-2.5">
          <div className="bg-white rounded-2xl border border-black/5 p-3 shadow-sm">
            <div className="text-[11px] text-[#8E8E93] font-semibold">Anstehende Termine</div>
            <div className="text-2xl font-extrabold text-[#1C1C1E]">{termineNext}</div>
          </div>
          <div className="bg-white rounded-2xl border border-black/5 p-3 shadow-sm">
            <div className="text-[11px] text-[#8E8E93] font-semibold">Nächste Reise</div>
            {nextTrip ? (
              <div className="text-[13px] font-extrabold text-[#1C1C1E] leading-tight">
                {nextTrip.destination || nextTrip.title}
                {tripDays > 0 && <span className="text-[#FF9500]"> · {tripDays}d</span>}
              </div>
            ) : (
              <div className="text-[13px] font-semibold text-[#C7C7CC]">—</div>
            )}
          </div>
        </div>
      </div>

      {/* Lebensbereiche */}
      <div className="max-w-3xl mx-auto px-3 pb-6 pt-2">
        <div className="grid grid-cols-2 gap-2.5">
          {bereiche.map((b) => (
            <Link key={b.key} href={BESPOKE_HREF[b.key] ?? `/bereich/${DOMAIN_OF[b.key] ?? b.key}`} className="group relative overflow-hidden bg-white rounded-2xl shadow-sm border border-black/5 h-full active:scale-[0.97] transition-transform">
              <div className={`absolute inset-0 bg-gradient-to-br ${GRADIENTS[b.key] ?? b.gradient ?? DEFAULT_GRADIENT} opacity-90`} />
              <div className="absolute inset-0"><div className="absolute -top-4 -right-4 w-16 h-16 bg-white rounded-full blur-2xl opacity-20" /></div>
              <div className="relative p-3 flex flex-col gap-1 min-h-[92px]">
                <div className="text-2xl drop-shadow-lg leading-none">{b.emoji}</div>
                <div>
                  <h2 className="text-[15px] font-extrabold text-white tracking-tight leading-tight">{b.titel}</h2>
                  <p className="text-white/70 text-[10px] font-medium leading-snug">{b.beschreibung}</p>
                </div>
                <div className="flex justify-end mt-auto">
                  <div className="flex items-center justify-center w-6 h-6 bg-white/20 backdrop-blur-md rounded-lg">
                    <svg className="w-3.5 h-3.5 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2.5}><path strokeLinecap="round" strokeLinejoin="round" d="M9 5l7 7-7 7" /></svg>
                  </div>
                </div>
              </div>
            </Link>
          ))}
        </div>
        <footer className="mt-6 text-center text-[#8E8E93] text-[11px] font-medium">
          {/* eslint-disable-next-line @next/next/no-html-link-for-pages */}
          <p>Phase 2 — API-first · <a href="/api/v1/docs" className="text-[#007AFF]">API-Docs</a></p>
        </footer>
      </div>
    </main>
  );
}
