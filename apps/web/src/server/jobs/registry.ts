import type BetterSqlite3 from "better-sqlite3";
import { sendPush } from "@/server/push/apns";
import { abfuhrCategory, fetchAhaICS, parseAbfuhrICS } from "@/server/abfuhr/abfuhr";
import { enrichMissingCovers, countMissingCovers } from "@/server/ebooks/covers";
import { retryAll, pendingCount } from "@/server/ebooks/wishlist";

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
    schedule: "0 8 * * *",
    timezone: "Europe/Berlin",
    topic: "termine",
    description: "Per-User-Termin-Push: 2 Tage und 1 Tag vor dem Termin an das Gerät des Users (owner-gezielt).",
    async run(ctx) {
      const rows = ctx.db.prepare(
        "SELECT s.termin_id, s.owner, s.reminder_2d_sent, s.reminder_1d_sent, t.title, t.date, t.time " +
        "FROM termin_user_state s JOIN termine t ON t.id = s.termin_id " +
        "WHERE s.notify=1 AND COALESCE(t.status,'')<>'erledigt' AND t.date IS NOT NULL AND t.date<>''",
      ).all() as { termin_id: number; owner: string; reminder_2d_sent: number; reminder_1d_sent: number; title: string; date: string; time: string | null }[];
      const t0 = todayStart();
      const messages: string[] = [];
      let affected = 0;
      for (const r of rows) {
        const d = new Date(r.date + "T00:00:00");
        if (isNaN(d.getTime())) continue;
        const days = Math.round((d.getTime() - t0.getTime()) / 86400000);
        let offset: 2 | 1 | null = null;
        if (days === 2 && !r.reminder_2d_sent) offset = 2;
        else if (days === 1 && !r.reminder_1d_sent) offset = 1;
        if (!offset) continue;
        const when = offset === 2 ? "In 2 Tagen" : "Morgen";
        const body = `${r.title} am ${r.date}${r.time ? ` um ${r.time}` : ""}`;
        messages.push(`📅 ${when} (${r.owner}): ${body}`);
        if (!ctx.dryRun) {
          await sendPush({ title: `📅 ${when}`, body, data: { kind: "termin", id: r.termin_id }, owner: r.owner }).catch(() => {});
          const col = offset === 2 ? "reminder_2d_sent" : "reminder_1d_sent";
          ctx.db.prepare(`UPDATE termin_user_state SET ${col}=1, updated_at=datetime('now') WHERE termin_id=? AND owner=?`).run(r.termin_id, r.owner);
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
        await sendPush({ title: "🗑️ Abfuhr morgen", body, data: { kind: "abfuhr" } }).catch(() => {});
        await ctx.notify("abfuhrkalender", body);
        ctx.db.prepare("UPDATE abfuhr_termine SET push_gesendet=1 WHERE datum=date('now','+1 day')").run();
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
