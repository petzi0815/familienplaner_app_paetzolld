import type BetterSqlite3 from "better-sqlite3";
import { apnsEnabled, sendLiveActivity, sendPush } from "@/server/push/apns";
import { abfuhrCategory, fetchAhaICS, parseAbfuhrICS } from "@/server/abfuhr/abfuhr";
import { enrichMissingCovers, countMissingCovers } from "@/server/ebooks/covers";
import { retryAll, pendingCount } from "@/server/ebooks/wishlist";
import { getCategoryInfo } from "@/server/legacy/termine-db";

export interface JobCtx {
  db: BetterSqlite3.Database;
  dryRun: boolean;
  notify: (topic: string, message: string) => Promise<void>;
}
export interface JobResult { messages: string[]; affected: number }
export interface JobDef {
  name: string;
  schedule: string; // Cron (leer = nur manuell)
  timezone?: string; // z.B. "Europe/Berlin" (sonst Server-Zeit)
  description: string;
  topic: string;
  run: (ctx: JobCtx) => Promise<JobResult>;
}

const todayStart = () => new Date(new Date().toISOString().slice(0, 10) + "T00:00:00");

// ── Zeit-Helfer (Europe/Berlin) ──────────────────────────────────────────────
// Die Termin-Jobs rechnen mit Wandkalender-Werten ('YYYY-MM-DD' + 'HH:MM') in deutscher
// Ortszeit, der Container läuft aber in UTC. Deshalb bewusst alles über `Intl` statt über
// die lokale Server-Zeitzone (die Cron-Timezone gilt nur für die Auslösung, nicht für `Date`).
const BERLIN_TZ = "Europe/Berlin";

const berlinFmt = new Intl.DateTimeFormat("en-CA", {
  timeZone: BERLIN_TZ,
  hourCycle: "h23",
  year: "numeric", month: "2-digit", day: "2-digit",
  hour: "2-digit", minute: "2-digit", second: "2-digit",
});

function berlinParts(ms: number): { y: number; m: number; d: number; h: number; mi: number; s: number } {
  const p: Record<string, string> = {};
  for (const part of berlinFmt.formatToParts(new Date(ms))) if (part.type !== "literal") p[part.type] = part.value;
  return { y: +p.year, m: +p.month, d: +p.day, h: +p.hour, mi: +p.minute, s: +p.second };
}

const pad2 = (n: number) => String(n).padStart(2, "0");

/** Aktuelles Datum ('YYYY-MM-DD') + Stunde/Minute in Berliner Ortszeit. */
function berlinNow(ms: number = Date.now()): { date: string; hour: number; minute: number } {
  const p = berlinParts(ms);
  return { date: `${p.y}-${pad2(p.m)}-${pad2(p.d)}`, hour: p.h, minute: p.mi };
}

/** Verschiebt ein 'YYYY-MM-DD' um n Tage (reine Kalenderarithmetik, DST-unabhängig). */
function addDays(date: string, n: number): string {
  const d = new Date(date + "T00:00:00Z");
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

/**
 * 'YYYY-MM-DD' + 'HH:MM' als Berliner Ortszeit → Unix-Sekunden.
 * Zwei Offset-Durchläufe, damit auch die beiden DST-Umschalttage exakt stimmen.
 * NaN, wenn die Eingabe kein gültiges Datum ergibt (Aufrufer prüfen das).
 */
function berlinEpoch(date: string, time: string): number {
  const naive = Date.parse(`${date}T${time.slice(0, 5)}:00Z`);
  if (isNaN(naive)) return NaN;
  let ms = naive;
  for (let i = 0; i < 2; i++) {
    const p = berlinParts(ms);
    const asUtc = Date.UTC(p.y, p.m - 1, p.d, p.h, p.mi, p.s);
    ms = naive - (asUtc - ms); // (asUtc - ms) = UTC-Offset der Zone zu diesem Zeitpunkt
  }
  return Math.floor(ms / 1000);
}

/** 'HH:MM' aus einem Zeitfeld ('15:45' oder '15:45:00'); leer/NULL → null. */
const hhmm = (t?: string | null): string | null => (t && t.trim() ? t.trim().slice(0, 5) : null);

/** Beide Familienmitglieder mit eigenem Login-Key = Standard-Empfänger der Termin-Pushes. */
const TERMIN_OWNERS = ["lars", "elita"] as const;

/**
 * Live Activities dürfen nie nachts starten: der Job läuft alle 15 min rund um die Uhr und ab
 * 00:00 Ortszeit sind bereits alle Termine des Tages in der Auswahl. Frühester Start = 07:00
 * Berliner Ortszeit, sonst Vorlauf `LA_LEAD_SECONDS` vor Beginn. Der kurze Vorlauf ist auch
 * technisch richtig: iOS beendet eine Live Activity nach spätestens 8 h automatisch — mit 12 h
 * Vorlauf wäre sie zum Termin schon wieder weg.
 */
const LA_EARLIEST_LOCAL = "07:00";
const LA_LEAD_SECONDS = 2 * 3600;
/**
 * iOS beendet eine Live Activity nach ~8 h von selbst. Ein ganztägiger Termin läuft aber bis 23:00
 * (ab 07:00 = 16 h), also muss die Activity zwischendurch NEU gestartet werden. Der Neustart hängt
 * an `started_at` und zieht es mit — dadurch ist höchstens ein Neustart pro Fenster möglich
 * (kein Neustart-Karussell). Lohnt sich nur, wenn danach noch spürbar Restlaufzeit übrig ist.
 */
const LA_RESTART_AFTER_SECONDS = Math.round(7.5 * 3600);
const LA_MIN_REMAINING_SECONDS = 30 * 60;

/** 'YYYY-MM-DD HH:MM:SS' aus SQLite-`datetime('now')` (UTC) → Unix-Sekunden; NaN wenn unparsbar. */
function sqliteEpoch(s?: string | null): number {
  if (!s) return NaN;
  const ms = Date.parse(s.trim().replace(" ", "T") + "Z");
  return isNaN(ms) ? NaN : Math.floor(ms / 1000);
}

/**
 * Fehlversuche der Live-Activity-Updates je Activity-Zeile (In-Memory, Reset bei Erfolg/Ende/
 * Prozessneustart). Ohne Update-Token (App hat nie eins gemeldet) liefe sonst derselbe Versuch
 * alle 15 min bis zum Terminende ins Leere — reines Log-Rauschen mit affected=0.
 */
const laUpdateFails = new Map<number, { status: string; tries: number }>();
const LA_MAX_UPDATE_TRIES = 3;

const tableExists = (db: BetterSqlite3.Database, name: string): boolean =>
  !!db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?").get(name);

/** Termin-Zeile, soweit die Termin-Jobs sie brauchen. */
interface TerminJobRow {
  id: number;
  title: string;
  category: string | null;
  date: string;
  time: string | null;
  end_date: string | null;
  end_time: string | null;
  location: string | null;
  person: string | null;
  status: string | null;
}

const TERMIN_JOB_COLS = "id,title,category,date,time,end_date,end_time,location,person,status";

/**
 * Zeitfenster eines Termins in Unix-Sekunden.
 * - ganztägig (keine Uhrzeit): 06:00 … 23:00 Ortszeit
 * - ohne Endzeit: Start + 2 h
 * `dismissAt` = Zeitpunkt, ab dem eine Live Activity beendet werden soll
 * (30 min nach dem Ende; ganztägig exakt 23:00).
 */
function terminWindow(t: TerminJobRow): { allDay: boolean; start: number; end: number | null; effEnd: number; dismissAt: number } {
  const time = hhmm(t.time);
  const allDay = !time;
  const start = berlinEpoch(t.date, time ?? "06:00");
  const endTime = hhmm(t.end_time);
  const endDate = t.end_date && t.end_date.trim() ? t.end_date.trim() : t.date;
  const end = endTime ? berlinEpoch(endDate, endTime) : null;
  const effEnd = allDay ? berlinEpoch(t.date, "23:00") : (end != null && !isNaN(end) && end > start ? end : start + 2 * 3600);
  return { allDay, start, end: end != null && !isNaN(end) ? end : null, effEnd, dismissAt: allDay ? effEnd : effEnd + 30 * 60 };
}

/**
 * Owner, die diesen Termin quittiert haben — füttert `ackedBy`.
 * Nur `ack_at` zählt: `read` ist der ältere, davon unabhängige Gelesen-Marker (Augen-Button in der
 * Terminliste, `/mystate`) — er würde die Live Activity sofort als „quittiert" starten lassen.
 * Verlustfrei, denn die Ack-Route setzt `read` und `ack_at` gemeinsam.
 */
function ackedOwners(db: BetterSqlite3.Database, terminId: number): string[] {
  const rows = db.prepare(
    "SELECT owner FROM termin_user_state WHERE termin_id=? AND ack_at IS NOT NULL ORDER BY owner",
  ).all(terminId) as { owner: string }[];
  return rows.map((r) => r.owner);
}

export const JOBS: JobDef[] = [
  {
    name: "termine-reminders",
    schedule: "0 8 * * *",
    topic: "termine",
    description: "Fällige Termin-Erinnerungen senden und als gesendet markieren (idempotent).",
    async run(ctx) {
      const rows = ctx.db.prepare(
        "SELECT id,title,date,time,reminder_days FROM termine WHERE COALESCE(reminder_sent,0)=0 AND COALESCE(status,'')<>'erledigt' AND date IS NOT NULL AND date<>''",
      ).all() as { id: number; title: string; date: string; time?: string; reminder_days?: number }[];
      const t0 = todayStart();
      const messages: string[] = [];
      let affected = 0;
      for (const t of rows) {
        const d = new Date(t.date + "T00:00:00");
        if (isNaN(d.getTime())) continue;
        const ws = new Date(d); ws.setDate(d.getDate() - (t.reminder_days ?? 0));
        if (t0 < ws || t0 > d) continue;
        const msg = `📅 Erinnerung: ${t.title} am ${t.date}${t.time ? ` um ${t.time}` : ""}`;
        messages.push(msg);
        if (!ctx.dryRun) {
          await ctx.notify("termine", msg);
          ctx.db.prepare("UPDATE termine SET reminder_sent=1 WHERE id=?").run(t.id);
          affected++;
        }
      }
      return { messages, affected };
    },
  },
  {
    name: "termine-user-reminders",
    schedule: "0 7,18 * * *",
    timezone: "Europe/Berlin",
    topic: "termine",
    description:
      "Termin-Push je Person: 18 Uhr für morgen und 7 Uhr für heute (Standard an lars+elita, außer stumm), " +
      "dazu 7 Uhr „in 2 Tagen“ für Termine mit persönlichem Benachrichtigungs-Opt-in.",
    async run(ctx) {
      // Ohne APNs-Keys ginge kein Push raus, die reminder_*_sent-Marker würden aber gesetzt —
      // die Erinnerung wäre dann für immer verloren. Also gar nicht erst anfangen.
      if (!apnsEnabled()) return { messages: ["APNs nicht konfiguriert — übersprungen"], affected: 0 };
      const now = berlinNow();
      // Der Cron feuert um 07:00 und 18:00 (Berlin), der Job ist aber auch manuell auslösbar
      // (POST /api/v1/jobs/termine-user-reminders/run). Statt auf die exakte Stunde zu prüfen,
      // arbeiten wir ALLE Slots ab, deren Uhrzeit heute bereits erreicht ist — die
      // reminder_*_sent-Marker machen jeden Nachlauf idempotent. Vor 07:00 ist nichts fällig:
      // ein „Morgen"-Push um 02:00 würde sonst den übernächsten Tag ankündigen.
      const morningDue = now.hour >= 7;   // 07:00-Slot: heute (+ „in 2 Tagen" für notify=1)
      const eveningDue = now.hour >= 18;  // 18:00-Slot: morgen (Standard für beide)
      if (!morningDue && !eveningDue) return { messages: [`vor 07:00 Uhr (Berlin, ${now.date}) — nichts fällig`], affected: 0 };

      const today = now.date;
      const tomorrow = addDays(today, 1);
      const inTwoDays = addDays(today, 2);

      const termine = ctx.db.prepare(
        "SELECT id, title, date, time, location, category FROM termine " +
        "WHERE COALESCE(status,'')<>'erledigt' AND date IN (?,?,?) ORDER BY date, COALESCE(NULLIF(time,''),'99:99')",
      ).all(today, tomorrow, inTwoDays) as
        { id: number; title: string; date: string; time: string | null; location: string | null; category: string | null }[];

      const selState = ctx.db.prepare(
        "SELECT read, notify, muted, reminder_2d_sent, reminder_1d_sent, reminder_0d_sent FROM termin_user_state WHERE termin_id=? AND owner=?",
      );
      // Die State-Zeile existiert bisher NUR, wenn der User mal read/notify gesetzt hat — ohne
      // dieses INSERT OR IGNORE bekäme für die neuen Standard-Pushes also niemand etwas.
      const ensureState = ctx.db.prepare("INSERT OR IGNORE INTO termin_user_state (termin_id, owner) VALUES (?,?)");
      const markCols = ["reminder_0d_sent", "reminder_1d_sent", "reminder_2d_sent"] as const;
      type MarkCol = (typeof markCols)[number];
      const mark = {} as Record<MarkCol, BetterSqlite3.Statement>;
      for (const c of markCols) {
        mark[c] = ctx.db.prepare(`UPDATE termin_user_state SET ${c}=1, updated_at=datetime('now') WHERE termin_id=? AND owner=?`);
      }

      const messages: string[] = [];
      let affected = 0;
      for (const t of termine) {
        const time = hhmm(t.time);
        const cat = getCategoryInfo(t.category ?? "allgemein");
        // Geräte OHNE owner (Registrierung über den Shared-Key) hängen an BEIDEN owner-Durchläufen.
        // Je Meldung (= Termin + Slot) dürfen sie genau einen Push bekommen — analog `usedStartTokens`
        // in der Live-Activity-Schleife. Pro Termin/Slot zurückgesetzt, denn ein anderer Slot ist
        // eine andere Meldung und gehört zugestellt.
        const usedTokens = new Map<MarkCol, Set<number>>();
        for (const owner of TERMIN_OWNERS) {
          const st = selState.get(t.id, owner) as
            | { read: number; notify: number; muted: number; reminder_2d_sent: number; reminder_1d_sent: number; reminder_0d_sent: number }
            | undefined;
          if (st?.muted) continue; // „Nicht mehr erinnern" für genau diesen Termin
          let slot: { when: string; col: MarkCol } | null = null;
          if (eveningDue && t.date === tomorrow && !st?.reminder_1d_sent) slot = { when: "Morgen", col: "reminder_1d_sent" };
          else if (morningDue && t.date === today && !st?.reminder_0d_sent) slot = { when: "Heute", col: "reminder_0d_sent" };
          else if (morningDue && t.date === inTwoDays && st?.notify && !st.reminder_2d_sent) slot = { when: "In 2 Tagen", col: "reminder_2d_sent" };
          if (!slot) continue;

          const title = `${cat.emoji} ${slot.when}${time ? `: ${time}` : ""}`;
          const body = `${t.title}${t.location ? ` — ${t.location}` : ""}`;
          messages.push(`${title} (${owner}): ${body}`);
          if (!ctx.dryRun) {
            let used = usedTokens.get(slot.col);
            if (!used) { used = new Set<number>(); usedTokens.set(slot.col, used); }
            const res = await sendPush({
              title,
              body,
              data: { kind: "termin", id: t.id, date: t.date, time },
              owner,
              // Der Job schickt dieselbe Meldung an BEIDE owner — ohne strictOwner würde der
              // Broadcast-Fallback sie auf den Geräten der Person mit Login doppelt zustellen.
              // strictOwner nimmt owner-lose Geräte mit; `excludeTokens` hält sie bei einmal.
              strictOwner: true,
              excludeTokens: used,
              category: "TERMIN",
              threadId: `termin-${t.id}`,
            }).catch(() => null);
            for (const id of res?.tokenIds ?? []) used.add(id);
            ensureState.run(t.id, owner);
            mark[slot.col].run(t.id, owner);
            affected++;
          }
        }
      }
      if (!messages.length) messages.push("keine fälligen Termin-Erinnerungen");
      return { messages, affected };
    },
  },
  {
    name: "termine-live-activity",
    schedule: "*/15 * * * *",
    timezone: "Europe/Berlin",
    topic: "termine",
    description: "Live Activities für die Termine des Tages starten, aktualisieren und beenden (Sperrbildschirm + Dynamic Island).",
    async run(ctx) {
      // Ohne APNs-Keys (bzw. vor Migration 0018) sauberer No-Op statt Fehler.
      if (!apnsEnabled()) return { messages: ["APNs nicht konfiguriert — Live Activities übersprungen"], affected: 0 };
      if (!tableExists(ctx.db, "live_activity_tokens") || !tableExists(ctx.db, "termin_live_activities")) {
        return { messages: ["Migration 0018 noch nicht angewandt — Live Activities übersprungen"], affected: 0 };
      }

      const nowMs = Date.now();
      const nowSec = Math.floor(nowMs / 1000);
      const today = berlinNow(nowMs).date;
      const messages: string[] = [];
      let affected = 0;

      const statusOf = (t: TerminJobRow, w: ReturnType<typeof terminWindow>, acked: boolean): string => {
        if (nowSec >= w.effEnd) return "vorbei";
        if (acked || (t.status ?? "") === "erledigt") return "quittiert";
        if (nowSec >= w.start) return "laeuft";
        return "bevorstehend";
      };
      const contentStateOf = (t: TerminJobRow, w: ReturnType<typeof terminWindow>, status: string, acked: string[]) => {
        const cat = getCategoryInfo(t.category ?? "allgemein");
        // Keys = exakt die Swift-Property-Namen aus Shared/TerminActivityAttributes.swift.
        return {
          title: t.title,
          subtitle: t.person && t.person.trim() ? t.person.trim() : cat.label,
          location: t.location && t.location.trim() ? t.location.trim() : null,
          startAtEpoch: w.start,
          endAtEpoch: w.end,
          allDay: w.allDay,
          status,
          emoji: cat.emoji,
          ackedBy: acked,
        };
      };

      // ── 1) Start: Termine von heute, deren Beginn ≤ jetzt+12 h liegt (ganztägig ab 06:00) ──
      const todays = ctx.db.prepare(
        `SELECT ${TERMIN_JOB_COLS} FROM termine WHERE date=? AND COALESCE(status,'')<>'erledigt' ORDER BY COALESCE(NULLIF(time,''),'00:00')`,
      ).all(today) as TerminJobRow[];
      const selUserState = ctx.db.prepare("SELECT read, muted, ack_at FROM termin_user_state WHERE termin_id=? AND owner=?");
      const selActivity = ctx.db.prepare(
        "SELECT id, activity_id, started_at FROM termin_live_activities WHERE termin_id=? AND owner=?",
      );
      const selStartTokens = ctx.db.prepare(
        "SELECT id, token, environment FROM live_activity_tokens WHERE kind='start' AND (owner=? OR owner IS NULL)",
      );
      const insActivity = ctx.db.prepare("INSERT OR IGNORE INTO termin_live_activities (termin_id, owner, status) VALUES (?,?,?)");
      // Neustart nach dem iOS-8-h-Fenster: neue Activity, also alte activity_id verwerfen und
      // `started_at` mitziehen (⇒ frühestens LA_RESTART_AFTER_SECONDS später wieder).
      const restartActivity = ctx.db.prepare(
        "UPDATE termin_live_activities SET status=?, activity_id=NULL, started_at=datetime('now'), updated_at=datetime('now'), ended_at=NULL WHERE id=?",
      );
      const delStaleUpdateTokens = ctx.db.prepare("DELETE FROM live_activity_tokens WHERE kind='update' AND activity_id=?");

      // Frühester Start-Zeitpunkt heute (Berliner Ortszeit) — hält den Job aus der Nachtruhe raus.
      const earliestToday = berlinEpoch(today, LA_EARLIEST_LOCAL);

      for (const t of todays) {
        const w = terminWindow(t);
        if (isNaN(w.start) || isNaN(w.effEnd)) continue;
        if (nowSec >= w.dismissAt) continue;                                   // schon vorbei
        // Ganztägig: ab 07:00. Sonst 2 h vor Beginn, aber nie vor 07:00 Ortszeit.
        const earliest = isNaN(earliestToday) ? w.start : Math.max(w.start - LA_LEAD_SECONDS, earliestToday);
        const due = w.allDay ? (isNaN(earliestToday) || nowSec >= earliestToday) : nowSec >= earliest;
        if (!due) continue;
        const acked = ackedOwners(ctx.db, t.id);
        // Ein Gerät ohne bekannten owner (owner IS NULL) darf für DENSELBEN Termin nur einen
        // Start-Push bekommen, sonst liefen dort zwei identische Activities (lars + elita).
        // Bewusst pro Termin zurückgesetzt — für einen anderen Termin ist ein zweiter Push richtig.
        const usedStartTokens = new Set<number>();
        for (const owner of TERMIN_OWNERS) {
          const st = selUserState.get(t.id, owner) as { read: number; muted: number; ack_at: string | null } | undefined;
          if (st?.muted) continue;
          const existing = selActivity.get(t.id, owner) as
            | { id: number; activity_id: string | null; started_at: string | null }
            | undefined;
          // Zeile da = die Activity läuft — ODER iOS hat sie nach ~8 h stillschweigend beendet.
          // Im zweiten Fall (und nur wenn danach noch genug Restlaufzeit bleibt) neu starten;
          // sonst gäbe es für ganztägige Termine ab ~15:00 nichts mehr auf dem Sperrbildschirm.
          // Der Neustart zieht `started_at` mit und setzt `ended_at` zurück ⇒ maximal ein
          // Neustart je ~7,5 h, unabhängig davon, ob die Zeile offen oder geschlossen war.
          let restart: { id: number; activityId: string | null } | null = null;
          if (existing) {
            const startedSec = sqliteEpoch(existing.started_at);
            const stale = !isNaN(startedSec) && nowSec - startedSec >= LA_RESTART_AFTER_SECONDS;
            if (!stale || w.dismissAt - nowSec <= LA_MIN_REMAINING_SECONDS) continue;
            restart = { id: existing.id, activityId: existing.activity_id };
          }
          const tokens = (selStartTokens.all(owner) as { id: number; token: string; environment: string }[])
            .filter((tk) => !usedStartTokens.has(tk.id));
          if (!tokens.length) continue;                                        // kein Gerät → auch keine Zeile anlegen
          for (const tk of tokens) usedStartTokens.add(tk.id);

          const status = statusOf(t, w, acked.includes(owner));
          const time = hhmm(t.time);
          const cat = getCategoryInfo(t.category ?? "allgemein");
          messages.push(`${restart ? "🔁 Live Activity Neustart" : "▶️ Live Activity Start"}: ${t.title} (${owner}, ${tokens.length} Gerät(e))`);
          if (!ctx.dryRun) {
            await sendLiveActivity({
              event: "start",
              tokens,
              contentState: contentStateOf(t, w, status, acked),
              attributes: { terminId: t.id, category: t.category ?? "allgemein" },
              attributesType: "TerminActivityAttributes",
              alert: {
                // APNs verlangt bei event=start einen alert; er soll aber NICHT klingeln —
                // eine Live Activity ist eine Anzeige, kein Alarm (der Alarm ist der 07-Uhr-Push).
                // sound: null lässt sendLiveActivity das sound-Feld weglassen = lautlos.
                title: `${cat.emoji} ${t.title}`,
                body: `${time ? `${time} Uhr` : "Ganztägig"}${t.location ? ` · ${t.location}` : ""}`,
                sound: null,
              },
              staleDate: w.dismissAt,
            }).catch(() => ({ sent: 0, total: 0 }));
            if (restart) {
              // Die Tokens der abgelaufenen Activity sind tot — sonst würde der Update-Zweig
              // weiter dagegen pushen, statt auf das neue Token der Neustart-Activity zu warten.
              if (restart.activityId) delStaleUpdateTokens.run(restart.activityId);
              restartActivity.run(status, restart.id);
              laUpdateFails.delete(restart.id);
            } else {
              insActivity.run(t.id, owner, status);
            }
            affected++;
          }
        }
      }

      // ── 2) Update / Ende der laufenden Activities ──
      const open = ctx.db.prepare(
        "SELECT id, termin_id, owner, activity_id, status FROM termin_live_activities WHERE ended_at IS NULL",
      ).all() as { id: number; termin_id: number; owner: string; activity_id: string | null; status: string }[];
      const selTermin = ctx.db.prepare(`SELECT ${TERMIN_JOB_COLS} FROM termine WHERE id=?`);
      const selTokensByActivity = ctx.db.prepare("SELECT id, token, environment FROM live_activity_tokens WHERE kind='update' AND activity_id=?");
      const selTokensByTermin = ctx.db.prepare(
        "SELECT id, token, environment FROM live_activity_tokens WHERE kind='update' AND termin_id=? AND (owner=? OR owner IS NULL)",
      );
      const updActivity = ctx.db.prepare("UPDATE termin_live_activities SET status=?, updated_at=datetime('now') WHERE id=?");
      const endActivity = ctx.db.prepare("UPDATE termin_live_activities SET status='vorbei', ended_at=datetime('now'), updated_at=datetime('now') WHERE id=?");
      const delTokensByActivity = ctx.db.prepare("DELETE FROM live_activity_tokens WHERE kind='update' AND activity_id=?");
      const delTokensByTermin = ctx.db.prepare("DELETE FROM live_activity_tokens WHERE kind='update' AND termin_id=? AND (owner=? OR owner IS NULL)");

      for (const row of open) {
        const t = selTermin.get(row.termin_id) as TerminJobRow | undefined;
        let tokens = row.activity_id ? (selTokensByActivity.all(row.activity_id) as { id: number; token: string; environment: string }[]) : [];
        if (!tokens.length) tokens = selTokensByTermin.all(row.termin_id, row.owner) as { id: number; token: string; environment: string }[];

        // `null`, wenn der Termin gelöscht wurde oder sein Datum unparsbar ist.
        const w = t ? terminWindow(t) : null;
        const cur = t && w && !isNaN(w.start) && !isNaN(w.effEnd) ? { t, w } : null;

        // Termin vorbei ODER gelöscht → Activity beenden. Der end-Push MUSS auch beim gelöschten
        // Termin raus: hier werden Zeile geschlossen und Tokens entfernt, danach erreicht uns die
        // Activity nie wieder und sie bliebe bis zum System-Timeout auf dem Sperrbildschirm.
        if (!cur || nowSec >= cur.w.dismissAt) {
          messages.push(`⏹️ Live Activity Ende: Termin ${row.termin_id} (${row.owner})`);
          if (!ctx.dryRun) {
            if (tokens.length) {
              const contentState = cur
                ? contentStateOf(cur.t, cur.w, "vorbei", ackedOwners(ctx.db, cur.t.id))
                : {
                    // Termin existiert nicht mehr → Fallback-Anzeige fürs saubere Ausblenden.
                    title: "Termin entfernt",
                    subtitle: null,
                    location: null,
                    startAtEpoch: nowSec,
                    endAtEpoch: null,
                    allDay: false,
                    status: "vorbei",
                    emoji: "📅",
                    ackedBy: [] as string[],
                  };
              await sendLiveActivity({
                event: "end",
                tokens,
                contentState,
                dismissalDate: nowSec + 60,
              }).catch(() => ({ sent: 0, total: 0 }));
            }
            // Zeile in JEDEM Fall schließen — sonst liefe der Ende-Zweig endlos weiter.
            endActivity.run(row.id);
            laUpdateFails.delete(row.id);
            if (row.activity_id) delTokensByActivity.run(row.activity_id);
            else delTokensByTermin.run(row.termin_id, row.owner);
            affected++;
          }
          continue;
        }

        const acked = ackedOwners(ctx.db, cur.t.id);
        const status = statusOf(cur.t, cur.w, acked.includes(row.owner));
        if (status === row.status) continue;                                   // nichts Neues → kein Push
        // Ohne Update-Token (App hat nie eins gemeldet) schlägt derselbe Übergang alle 15 min fehl.
        // Nach LA_MAX_UPDATE_TRIES Fehlversuchen für DIESEN Zielstatus aufgeben; ein neuer Status
        // (oder ein zugestelltes Update) fängt wieder bei 0 an.
        const prevFail = laUpdateFails.get(row.id);
        const tries = prevFail && prevFail.status === status ? prevFail.tries : 0;
        if (tries >= LA_MAX_UPDATE_TRIES) continue;
        messages.push(`🔄 Live Activity Update: ${cur.t.title} (${row.owner}) → ${status}`);
        if (!ctx.dryRun) {
          // Den Übergang erst verbuchen, wenn er auch zugestellt wurde: sonst gilt er oben als
          // erledigt (`status === row.status`) und würde nie nachgeholt.
          const res = tokens.length
            ? await sendLiveActivity({
                event: "update",
                tokens,
                contentState: contentStateOf(cur.t, cur.w, status, acked),
                staleDate: cur.w.dismissAt,
              }).catch(() => ({ sent: 0, total: 0 }))
            : { sent: 0, total: 0 };
          if (res.sent > 0) {
            updActivity.run(status, row.id);
            laUpdateFails.delete(row.id);
            affected++;
          } else {
            const n = tries + 1;
            laUpdateFails.set(row.id, { status, tries: n });
            messages.push(
              n >= LA_MAX_UPDATE_TRIES
                ? `⚠️ Update nicht zustellbar (Termin ${row.termin_id}, ${row.owner}, ${n}/${LA_MAX_UPDATE_TRIES}) — kein weiterer Versuch für Status „${status}“`
                : `⚠️ Update nicht zugestellt (Termin ${row.termin_id}, ${row.owner}, ${n}/${LA_MAX_UPDATE_TRIES}) — Wiederholung beim nächsten Lauf`,
            );
          }
        }
      }

      if (!messages.length) messages.push("keine Live-Activity-Änderungen");
      return { messages, affected };
    },
  },
  {
    name: "aufgaben-reminders",
    schedule: "0 8 * * *",
    timezone: "Europe/Berlin",
    topic: "aufgaben",
    description: "Aufgaben-Push: 1 Tag vor Fälligkeit an die/den Zuständige(n) (owner-gezielt, familie=Broadcast).",
    async run(ctx) {
      // Wie bei den Termin-Erinnerungen: ohne APNs würde nur der Marker gesetzt und die
      // Erinnerung wäre dauerhaft verloren.
      if (!apnsEnabled()) return { messages: ["APNs nicht konfiguriert — übersprungen"], affected: 0 };
      const rows = ctx.db.prepare(
        "SELECT id, owner, title, due_date, reminder_1d_sent FROM aufgaben " +
        "WHERE status='offen' AND owner IS NOT NULL AND due_date IS NOT NULL AND due_date<>''",
      ).all() as { id: number; owner: string; title: string; due_date: string; reminder_1d_sent: number }[];
      const t0 = todayStart();
      const messages: string[] = [];
      let affected = 0;
      for (const r of rows) {
        const d = new Date(r.due_date + "T00:00:00");
        if (isNaN(d.getTime())) continue;
        const days = Math.round((d.getTime() - t0.getTime()) / 86400000);
        if (days !== 1 || r.reminder_1d_sent) continue;
        messages.push(`📋 Morgen fällig (${r.owner}): ${r.title}`);
        if (!ctx.dryRun) {
          await sendPush({ title: "📋 Aufgabe morgen fällig", body: `${r.title} — fällig ${r.due_date}`, data: { kind: "aufgabe", id: r.id }, owner: r.owner }).catch(() => {});
          ctx.db.prepare("UPDATE aufgaben SET reminder_1d_sent=1, updated_at=datetime('now') WHERE id=?").run(r.id);
          affected++;
        }
      }
      return { messages, affected };
    },
  },
  {
    name: "buecher-wishlist-retry",
    schedule: "0 5 * * 1",
    timezone: "Europe/Berlin",
    topic: "ebooks",
    description: "Gesuchte E-Book-Wunschbücher wöchentlich via Shelfmark prüfen + herunterladen.",
    async run(ctx) {
      const pending = pendingCount();
      if (ctx.dryRun) return { messages: [`${pending} gesuchte Bücher`], affected: 0 };
      if (pending === 0) return { messages: ["keine gesuchten Bücher"], affected: 0 };
      const { checked, downloaded } = await retryAll();
      return { messages: [`Wunschliste-Retry: ${checked} geprüft, ${downloaded} heruntergeladen`], affected: downloaded };
    },
  },
  {
    name: "buecher-cover-enrich",
    schedule: "30 4 * * *",
    topic: "ebooks",
    description: "Fehlende/kaputte E-Book-Wunschlisten-Cover aus Google Books nachladen (ISBN/Titel).",
    async run(ctx) {
      const pending = countMissingCovers(ctx.db);
      if (ctx.dryRun) return { messages: [`${pending} Bücher ohne (valides) Cover`], affected: 0 };
      if (pending === 0) return { messages: ["keine fehlenden Cover"], affected: 0 };
      const { processed, updated } = await enrichMissingCovers(ctx.db);
      return { messages: [`Cover-Enrich: ${processed} geprüft, ${updated} nachgeladen (${pending} offen)`], affected: updated };
    },
  },
  {
    name: "vorrat-mhd-check",
    schedule: "0 9 * * 1",
    topic: "vorratskammer",
    description: "Lebensmittel mit MHD in den nächsten 7 Tagen melden.",
    async run(ctx) {
      const soon = ctx.db.prepare(
        "SELECT name,mhd FROM vorrat_lebensmittel WHERE mhd IS NOT NULL AND mhd<>'' AND mhd<=date('now','+7 days') AND COALESCE(status,'')<>'verbraucht' ORDER BY mhd ASC",
      ).all() as { name: string; mhd: string }[];
      const messages = soon.map((l) => `🍽️ MHD bald: ${l.name} (${l.mhd})`);
      if (soon.length && !ctx.dryRun) await ctx.notify("vorratskammer", "Bald ablaufend:\n" + messages.join("\n"));
      return { messages, affected: soon.length };
    },
  },
  {
    name: "garten-aufgaben-check",
    schedule: "0 9 * * 1",
    topic: "garten",
    description: "Offene Garten-Aufgaben des aktuellen Monats melden.",
    async run(ctx) {
      const rows = ctx.db.prepare(
        "SELECT titel FROM garten_aufgaben WHERE COALESCE(erledigt,0)=0 AND monat=CAST(strftime('%m','now') AS INTEGER) ORDER BY prioritaet",
      ).all() as { titel: string }[];
      const messages = rows.map((r) => `🌱 ${r.titel}`);
      if (rows.length && !ctx.dryRun) await ctx.notify("garten", "Garten diesen Monat:\n" + messages.join("\n"));
      return { messages, affected: rows.length };
    },
  },
  {
    name: "abfuhr-reminder",
    schedule: "0 19 * * *",
    timezone: "Europe/Berlin",
    topic: "abfuhrkalender",
    description: "Am Vorabend (19 Uhr) an die Abfuhr morgen erinnern (iOS-Push + Notify).",
    async run(ctx) {
      const rows = ctx.db.prepare(
        "SELECT id, kategorie, summary FROM abfuhr_termine WHERE datum = date('now','+1 day')",
      ).all() as { id: number; kategorie: string; summary: string }[];
      if (!rows.length) return { messages: [], affected: 0 };
      const labels = [...new Set(rows.map((r) => abfuhrCategory(r.kategorie)?.label ?? r.summary))];
      const body = `Morgen wird abgeholt: ${labels.join(", ")}. Tonnen heute Abend rausstellen!`;
      if (!ctx.dryRun) {
        const res = await sendPush({ title: "🗑️ Abfuhr morgen", body, data: { kind: "abfuhr" } })
          .catch(() => ({ sent: 0, total: 0, tokenIds: [] as number[] }));
        // Telegram läuft über ctx.notify mit eigenem env-Gate und ist von APNs unabhängig —
        // deshalb KEIN apnsEnabled()-Gate über dem ganzen Job.
        await ctx.notify("abfuhrkalender", body);
        // `push_gesendet` protokolliert genau den APNs-Versand: ohne konfigurierte Keys bzw. ohne
        // erreichtes Gerät wäre die 1 gelogen. (Der Marker unterdrückt nichts — der Job filtert
        // nicht darauf —, taugt aber sonst nicht als Beleg dafür, ob der Push wirklich rausging.)
        if (res.sent > 0) ctx.db.prepare("UPDATE abfuhr_termine SET push_gesendet=1 WHERE datum=date('now','+1 day')").run();
      }
      return { messages: [body], affected: rows.length };
    },
  },
  {
    name: "abfuhr-aha-sync",
    schedule: "17 3 1 * *",
    timezone: "Europe/Berlin",
    topic: "abfuhrkalender",
    description: "Abfuhrtermine monatlich von aha-region.de synchronisieren (nächstes Jahr automatisch).",
    async run(ctx) {
      const cfg = ctx.db.prepare("SELECT aha_gemeinde, aha_von, aha_strasse, aha_hausnr, aha_hausnraddon FROM abfuhr_config WHERE id=1").get() as
        | { aha_gemeinde: string | null; aha_von: string | null; aha_strasse: string | null; aha_hausnr: string | null; aha_hausnraddon: string | null }
        | undefined;
      if (!cfg?.aha_gemeinde || !cfg?.aha_strasse) return { messages: ["keine aha-Adresse konfiguriert"], affected: 0 };
      if (ctx.dryRun) return { messages: ["würde aha synchronisieren"], affected: 0 };
      const ics = await fetchAhaICS({ gemeinde: cfg.aha_gemeinde, von: cfg.aha_von ?? "", strasse: cfg.aha_strasse, hausnr: cfg.aha_hausnr ?? "", hausnraddon: cfg.aha_hausnraddon ?? "" });
      const events = parseAbfuhrICS(ics);
      const upsert = ctx.db.prepare(
        "INSERT INTO abfuhr_termine (kategorie,datum,summary,uid,quelle) VALUES (?,?,?,?,'aha') ON CONFLICT(uid) DO UPDATE SET kategorie=excluded.kategorie, datum=excluded.datum, summary=excluded.summary",
      );
      let n = 0;
      for (const e of events) if (upsert.run(e.kategorie, e.datum, e.summary, e.uid).changes > 0) n++;
      ctx.db.prepare("UPDATE abfuhr_config SET letzter_sync=datetime('now') WHERE id=1").run();
      return { messages: [`aha-Sync: ${events.length} Termine, ${n} neu/aktualisiert`], affected: n };
    },
  },
];

export const jobByName = (name: string): JobDef | undefined => JOBS.find((j) => j.name === name);
