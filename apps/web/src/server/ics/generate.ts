// Minimaler, RFC5545-konformer ICS-Generator (hand-rolled — keine Abhängigkeit).
// Wird vom abonnierbaren Familien-Kalender-Feed genutzt (Termine + Abfuhr + Reisen).
// Bewusst floating-local-Zeiten (Familie in EINER Zeitzone) → kein VTIMEZONE nötig.

export interface IcsEvent {
  uid: string;                 // stabil, damit Kalender-Apps Updates statt Dubletten erkennen
  summary: string;
  description?: string | null;
  location?: string | null;
  start: string;               // 'YYYY-MM-DD'
  startTime?: string | null;   // 'HH:MM' (nur wenn !allDay)
  end?: string | null;         // 'YYYY-MM-DD' (inklusives Enddatum; für mehrtägig)
  endTime?: string | null;     // 'HH:MM'
  allDay: boolean;
  categories?: string | null;
}

const enc = new TextEncoder();

/** TEXT-Wert escapen (RFC5545 3.3.11): Backslash, Semikolon, Komma, Zeilenumbruch. */
function esc(s: string): string {
  return s
    .replace(/\\/g, "\\\\")
    .replace(/;/g, "\\;")
    .replace(/,/g, "\\,")
    .replace(/\r?\n/g, "\\n");
}

/** Content-Zeile auf 75 Oktett falten (Folgezeilen mit führendem Space, RFC5545 3.1). Byte-genau. */
function fold(line: string): string {
  if (enc.encode(line).length <= 75) return line;
  const parts: string[] = [];
  let cur = "";
  let curBytes = 0;
  let first = true;
  for (const ch of line) {
    const b = enc.encode(ch).length;
    const limit = first ? 75 : 74; // Folgezeilen bekommen ein führendes Space → 74 Nutzbytes
    if (curBytes + b > limit) {
      parts.push(cur);
      cur = ch;
      curBytes = b;
      first = false;
    } else {
      cur += ch;
      curBytes += b;
    }
  }
  parts.push(cur);
  return parts.join("\r\n ");
}

const pad = (n: number) => String(n).padStart(2, "0");
const compactDate = (isoDate: string) => isoDate.slice(0, 10).replace(/-/g, ""); // '2026-07-14' → '20260714'

/** Enddatum für ganztägige Events ist exklusiv → +1 Tag. */
function addDay(isoDate: string, n: number): string {
  const d = new Date(isoDate.slice(0, 10) + "T00:00:00Z");
  d.setUTCDate(d.getUTCDate() + n);
  return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`;
}

function localTimeStamp(date: string, time?: string | null): string {
  const t = (time ?? "").trim();
  const [h, m] = t.split(":");
  return `${compactDate(date)}T${pad(Number(h) || 0)}${pad(Number(m) || 0)}00`; // floating local
}

function utcStamp(d: Date): string {
  return `${d.getUTCFullYear()}${pad(d.getUTCMonth() + 1)}${pad(d.getUTCDate())}T${pad(d.getUTCHours())}${pad(d.getUTCMinutes())}${pad(d.getUTCSeconds())}Z`;
}

function eventBlock(ev: IcsEvent, dtstamp: string): string[] {
  const lines = ["BEGIN:VEVENT", `UID:${esc(ev.uid)}`, `DTSTAMP:${dtstamp}`];
  if (ev.allDay) {
    lines.push(`DTSTART;VALUE=DATE:${compactDate(ev.start)}`);
    const endExclusive = addDay(ev.end && ev.end > ev.start ? ev.end : ev.start, 1);
    lines.push(`DTEND;VALUE=DATE:${compactDate(endExclusive)}`);
  } else {
    lines.push(`DTSTART:${localTimeStamp(ev.start, ev.startTime)}`);
    if (ev.end || ev.endTime) {
      lines.push(`DTEND:${localTimeStamp(ev.end ?? ev.start, ev.endTime ?? ev.startTime)}`);
    } else {
      // Standarddauer 1 Stunde — echte Datumsarithmetik (korrekter Rollover, z.B. 23:30 → 00:30 nächster Tag,
      // statt eines ungültigen „T243000").
      const [h, m] = (ev.startTime ?? "0:0").split(":");
      const d = new Date(ev.start.slice(0, 10) + "T00:00:00");
      d.setHours((Number(h) || 0) + 1, Number(m) || 0, 0, 0);
      lines.push(`DTEND:${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}T${pad(d.getHours())}${pad(d.getMinutes())}00`);
    }
  }
  lines.push(`SUMMARY:${esc(ev.summary)}`);
  if (ev.description) lines.push(`DESCRIPTION:${esc(ev.description)}`);
  if (ev.location) lines.push(`LOCATION:${esc(ev.location)}`);
  if (ev.categories) lines.push(`CATEGORIES:${esc(ev.categories)}`);
  lines.push("END:VEVENT");
  return lines;
}

/** Baut ein vollständiges VCALENDAR-Dokument (CRLF, gefaltet). */
export function buildICS(calName: string, events: IcsEvent[], opts?: { prodId?: string }): string {
  const dtstamp = utcStamp(new Date());
  const head = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    `PRODID:${opts?.prodId ?? "-//Familienplaner//Paetzold-Stilke//DE"}`,
    "CALSCALE:GREGORIAN",
    "METHOD:PUBLISH",
    `X-WR-CALNAME:${esc(calName)}`,
    "X-WR-TIMEZONE:Europe/Berlin",
    "REFRESH-INTERVAL;VALUE=DURATION:PT6H",
    "X-PUBLISHED-TTL:PT6H",
  ];
  const body = events.flatMap((e) => eventBlock(e, dtstamp));
  return [...head, ...body, "END:VCALENDAR"].map(fold).join("\r\n") + "\r\n";
}
