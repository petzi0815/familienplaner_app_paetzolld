import { getDb } from "@/server/db/connection";
import { lookupToken } from "@/server/feed/tokens";
import { buildICS, type IcsEvent } from "@/server/ics/generate";
import { abfuhrCategory } from "@/server/abfuhr/abfuhr";

// Öffentlicher, abonnierbarer Familien-Kalender-Feed (Termine + Abfuhr + Reisen).
// BEWUSST OHNE getAuth: Kalender-Apps (Apple/Google, webcal://) senden keinen Bearer —
// authentifiziert wird über den Token im Pfad. Der Middleware-Matcher schließt /api bereits aus.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

interface TerminRow { id: number; title: string; description: string | null; category: string | null; date: string; time: string | null; end_date: string | null; end_time: string | null; location: string | null; person: string | null; notes: string | null; status: string | null }
interface AbfuhrRow { id: number; kategorie: string; summary: string | null; datum: string }
interface ReiseRow { id: number; title: string; destination: string | null; start_date: string; end_date: string | null }

export async function GET(_req: Request, { params }: { params: Promise<{ token: string }> }): Promise<Response> {
  const { token } = await params;
  if (!lookupToken(token)) return new Response("Not found", { status: 404 });

  const db = getDb();
  const events: IcsEvent[] = [];
  const safe = <T>(fn: () => T, fb: T): T => { try { return fn(); } catch { return fb; } };

  // ── Termine (bis 90 Tage rückwirkend, damit der Kalender Kontext behält) ──
  const termine = safe(() => db.prepare(
    "SELECT id,title,description,category,date,time,end_date,end_time,location,person,notes,status FROM termine WHERE date >= date('now','-90 days') AND date IS NOT NULL AND date<>'' ORDER BY date ASC",
  ).all() as TerminRow[], []);
  for (const t of termine) {
    const done = String(t.status ?? "") === "erledigt";
    const desc = [t.description, t.person ? `Für: ${t.person}` : null, t.notes].filter(Boolean).join("\n");
    events.push({
      uid: `termin-${t.id}@familienplaner`,
      summary: (done ? "✅ " : "") + t.title,
      description: desc || null,
      location: t.location,
      start: t.date,
      startTime: t.time,
      end: t.end_date,
      endTime: t.end_time,
      allDay: !t.time || t.time.trim() === "",
      categories: t.category,
    });
  }

  // ── Abfuhrtermine (bis 30 Tage rückwirkend) ──
  const abfuhr = safe(() => db.prepare(
    "SELECT id,kategorie,summary,datum FROM abfuhr_termine WHERE datum >= date('now','-30 days') ORDER BY datum ASC",
  ).all() as AbfuhrRow[], []);
  for (const a of abfuhr) {
    const cat = abfuhrCategory(a.kategorie);
    events.push({
      uid: `abfuhr-${a.id}@familienplaner`,
      summary: `${cat?.emoji ?? "🗑️"} ${cat?.label ?? a.summary ?? a.kategorie}`,
      start: a.datum,
      allDay: true,
      categories: "Abfuhr",
    });
  }

  // ── Reisen (ganztägig, Start→Ende) ──
  const reisen = safe(() => db.prepare(
    "SELECT id,title,destination,start_date,end_date FROM reisen_trips WHERE start_date IS NOT NULL AND start_date<>'' AND COALESCE(NULLIF(end_date,''), start_date) >= date('now','-90 days') ORDER BY start_date ASC",
  ).all() as ReiseRow[], []);
  for (const r of reisen) {
    events.push({
      uid: `reise-${r.id}@familienplaner`,
      summary: `✈️ ${r.title}${r.destination ? ` – ${r.destination}` : ""}`,
      location: r.destination,
      start: r.start_date,
      end: r.end_date || r.start_date,
      allDay: true,
      categories: "Reise",
    });
  }

  const ics = buildICS("Familienplaner", events);
  return new Response(ics, {
    headers: {
      "content-type": "text/calendar; charset=utf-8",
      "cache-control": "public, max-age=3600",
      "content-disposition": 'inline; filename="familienplaner.ics"',
    },
  });
}
