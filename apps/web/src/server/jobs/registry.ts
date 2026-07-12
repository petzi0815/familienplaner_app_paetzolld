import type BetterSqlite3 from "better-sqlite3";
import { sendPush } from "@/server/push/apns";
import { abfuhrCategory } from "@/server/abfuhr/abfuhr";

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
];

export const jobByName = (name: string): JobDef | undefined => JOBS.find((j) => j.name === name);
