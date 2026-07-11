import Link from "next/link";

// Phase 0 — Portal-Shell im bestehenden iOS-Design. Die Kacheln werden ab Phase 2
// datengetrieben aus der `lebensbereiche`-Registry gerendert; die Ziel-Seiten je
// Bereich kommen in Phase 3 (bis dahin sind die Kacheln als „in Migration" markiert).
export const dynamic = "force-dynamic";

type Card = {
  key: string;
  gradient: string;
  emoji: string;
  title: string;
  desc: string;
  countdown?: { dest: string; date: string };
};

const cards: Card[] = [
  { key: "samu", gradient: "from-[#FF9F0A] via-[#FF6B6B] to-[#AF52DE]", emoji: "👶🧸", title: "Samu", desc: "Kleidung, Spielzeug & mehr" },
  { key: "gypsi", gradient: "from-[#FF8C00] via-[#FF6600] to-[#FF4500]", emoji: "🐱", title: "Gypsi", desc: "Futter-Vorlieben & Tracking" },
  { key: "smarthome", gradient: "from-[#007AFF] via-[#5856D6] to-[#AF52DE]", emoji: "🏠💡", title: "Smart Home", desc: "Geräte, Lichter & Sensoren" },
  { key: "garten", gradient: "from-[#34C759] via-[#30D158] to-[#00C7BE]", emoji: "🌱🌳", title: "Garten", desc: "Pflanzen, Samen & Pflege" },
  { key: "vertraege", gradient: "from-[#5856D6] via-[#AF52DE] to-[#FF2D55]", emoji: "📋💰", title: "Verträge", desc: "Versicherungen & Kosten" },
  { key: "buecher", gradient: "from-[#FF2D55] via-[#FF6B6B] to-[#FF9500]", emoji: "📚✨", title: "Bücher", desc: "Elitas Wishlist" },
  { key: "wunschliste", gradient: "from-[#AF52DE] via-[#FF2D55] to-[#FF9500]", emoji: "🎁🎀", title: "Wunschliste", desc: "Geschenke für Samu" },
  { key: "termine", gradient: "from-[#007AFF] via-[#5856D6] to-[#34C759]", emoji: "📅🗓️", title: "Termine", desc: "Kalender & Erinnerungen" },
  { key: "reisen", gradient: "from-[#FF9500] via-[#FF6B6B] to-[#5856D6]", emoji: "✈️🌍", title: "Reisen", desc: "Urlaube & Wochenend-Tipps", countdown: { dest: "Korfu", date: "2026-06-23" } },
  { key: "geschenkplaner", gradient: "from-[#F59E0B] via-[#EF4444] to-[#8B5CF6]", emoji: "🎁🎀", title: "Geschenkplaner", desc: "Geschenke für jeden Anlass" },
  { key: "vorratskammer", gradient: "from-[#F97316] via-[#FB923C] to-[#FBBF24]", emoji: "🍕🗄️", title: "Vorratskammer", desc: "Lebensmittel & Einkaufsliste" },
  { key: "reiniger", gradient: "from-[#0EA5E9] via-[#14B8A6] to-[#84CC16]", emoji: "🧽🧴", title: "Reiniger", desc: "Putzmittel & Fleckenhilfe" },
  { key: "elisbooks", gradient: "from-[#92400E] via-[#B45309] to-[#D97706]", emoji: "📖", title: "Büchersammlung", desc: "Elitas physische Bücher" },
];

function daysUntil(date: string): number {
  return Math.ceil((new Date(date + "T00:00:00").getTime() - Date.now()) / 86400000);
}

export default function Portal() {
  return (
    <main className="min-h-[100dvh] bg-gradient-to-br from-[#F2F2F7] via-[#E5E5EA] to-[#F2F2F7]">
      <header className="pt-10 pb-4 px-4 safe-area-inset">
        <div className="max-w-3xl mx-auto">
          <h1 className="text-2xl font-extrabold text-[#1C1C1E] tracking-tight mb-0.5">
            Familie Paetzold-Stilke
          </h1>
          <p className="text-[#8E8E93] text-xs font-medium">Familienplaner</p>
        </div>
      </header>

      <div className="max-w-3xl mx-auto px-3 pb-4">
        <div className="grid grid-cols-2 gap-2.5">
          {cards.map((card) => {
            const d = card.countdown ? daysUntil(card.countdown.date) : 0;
            return (
              <div
                key={card.key}
                className="group relative overflow-hidden bg-white rounded-2xl shadow-sm border border-black/5 h-full"
              >
                <div className={`absolute inset-0 bg-gradient-to-br ${card.gradient} opacity-90`} />
                <div className="absolute inset-0">
                  <div className="absolute -top-4 -right-4 w-16 h-16 bg-white rounded-full blur-2xl opacity-20" />
                </div>
                <div className="relative p-3 flex flex-col gap-1">
                  <div className="text-2xl drop-shadow-lg leading-none">{card.emoji}</div>
                  <div>
                    <h2 className="text-[15px] font-extrabold text-white tracking-tight leading-tight">
                      {card.title}
                    </h2>
                    <p className="text-white/70 text-[10px] font-medium leading-snug">{card.desc}</p>
                    {card.countdown && d > 0 && (
                      <p className="text-white text-[10px] font-black mt-0.5">
                        ✈️ {card.countdown.dest} in {d} Tagen!
                      </p>
                    )}
                  </div>
                  <div className="flex justify-end">
                    <span className="text-[9px] font-semibold text-white/80 bg-white/20 backdrop-blur-md rounded-md px-1.5 py-0.5">
                      🚧 wird migriert
                    </span>
                  </div>
                </div>
              </div>
            );
          })}
        </div>

        <footer className="mt-6 text-center text-[#8E8E93] text-[11px] font-medium space-y-1">
          <p>Phase 0 — Fundament · API-first Familienplaner</p>
          <p>
            <Link href="/api/v1/docs" className="text-[#007AFF]">API-Docs</Link>
            <span className="mx-1.5">·</span>
            <Link href="/version" className="text-[#007AFF]">Version</Link>
          </p>
        </footer>
      </div>
    </main>
  );
}
