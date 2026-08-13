import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { config } from "@/server/config";
import { log } from "@/server/observability/logger";

/**
 * Serverseitige Vorschaubilder für `/api/v1/media/<key>?w=<breite>`.
 *
 * Grundsatz: eine Vorschau darf NIEMALS einen Fehler verursachen. Fehlt `sharp` zur Laufzeit,
 * ist der Key krumm, das Format kein Rasterbild oder geht beim Skalieren irgendetwas schief,
 * liefert `thumbFuer` schlicht `null` — der Aufrufer schickt dann unverändert das Original.
 * Gleiches Muster wie die token-gated KI-Funktionen: degradieren statt scheitern.
 *
 * Erzeugung LAZY beim ersten Abruf (nicht beim Upload): so ist der komplette Altbestand
 * automatisch abgedeckt und es braucht keinen Backfill-Job.
 */

/** Ablage der erzeugten Vorschauen unterhalb von `$DATA_DIR/media`. */
const THUMB_DIR = ".thumbs";

/**
 * Feste Breitenstufen. Ohne feste Stufen würde jede abweichende `w`-Angabe eine eigene
 * Datei auf der Platte anlegen und den Cache unbegrenzt aufblähen.
 */
const STUFEN = [160, 320, 640] as const;

/** Nur Rasterformate — PDF/SVG/GIF bleiben immer das Original. */
const RASTER = new Set([".jpg", ".jpeg", ".png", ".webp"]);

/** Erlaubte Zeichen im Storage-Key (wie in der Media-Route), zusätzlich zum Traversal-Schutz. */
const SICHERER_KEY = /^[a-zA-Z0-9._/-]+$/;

const QUALITAET = 78;

/** Laufende Erzeugungen je Zielpfad — zwei gleichzeitige Anfragen sollen nicht doppelt rechnen. */
const inFlight = new Map<string, Promise<string | null>>();

type SharpFabrik = typeof import("sharp");
/** `undefined` = noch nicht versucht, `null` = nicht verfügbar (dauerhaft aus). */
let sharpCache: SharpFabrik | null | undefined;

/**
 * `sharp` ausschließlich per dynamischem Import in try/catch — das Modul ist eine native
 * Abhängigkeit und darf beim Fehlen nicht schon den Import der Route sprengen.
 */
async function ladeSharp(): Promise<SharpFabrik | null> {
  if (sharpCache !== undefined) return sharpCache;
  try {
    const mod = (await import("sharp")) as unknown as { default?: SharpFabrik };
    // CJS über ESM-Interop liefert die Funktion unter `default`; transpiliert kann das Modul
    // selbst die Funktion sein — beide Formen abdecken.
    const fabrik = mod.default ?? (mod as unknown as SharpFabrik);
    sharpCache = typeof fabrik === "function" ? fabrik : null;
    if (!sharpCache) log.warn("thumbs: sharp geladen, aber nicht aufrufbar — Vorschau deaktiviert");
  } catch (e) {
    sharpCache = null;
    log.warn("thumbs: sharp nicht verfügbar — es wird das Original ausgeliefert", { error: String(e) });
  }
  return sharpCache;
}

/** Gewünschte Breite auf die nächstgrößere feste Stufe runden; größer als die größte Stufe → Original. */
function stufeFuer(breite: number): number | null {
  if (!Number.isFinite(breite) || breite <= 0) return null;
  for (const s of STUFEN) if (breite <= s) return s;
  return null;
}

/**
 * Liefert den Dateipfad eines verkleinerten JPEGs unter
 * `$DATA_DIR/media/.thumbs/<breite>/<key>.jpg` und erzeugt es beim ersten Abruf.
 * Bei jedem Problem `null` → Aufrufer liefert das Original aus.
 */
export async function thumbFuer(key: string, breite: number): Promise<string | null> {
  try {
    const stufe = stufeFuer(breite);
    if (stufe === null) return null;

    // Pfadsicherheit: erst über den Zeichenvorrat, dann über den aufgelösten Pfad.
    if (!SICHERER_KEY.test(key) || key.includes("..")) return null;
    const ext = path.extname(key).toLowerCase();
    if (!RASTER.has(ext)) return null;

    const mediaRoot = path.resolve(config.mediaDir);
    const quelle = path.resolve(mediaRoot, key);
    if (!quelle.startsWith(mediaRoot + path.sep)) return null;

    const thumbsRoot = path.resolve(mediaRoot, THUMB_DIR);
    // Eine bereits erzeugte Vorschau darf nicht selbst wieder Quelle werden (sonst Vorschau der Vorschau).
    if (quelle === thumbsRoot || quelle.startsWith(thumbsRoot + path.sep)) return null;

    const ziel = path.resolve(thumbsRoot, String(stufe), `${key}.jpg`);
    if (!ziel.startsWith(thumbsRoot + path.sep)) return null;

    let qStat: fs.Stats;
    try {
      qStat = fs.statSync(quelle);
    } catch {
      return null; // Original fehlt — die Route beantwortet das ohnehin schon.
    }
    if (!qStat.isFile()) return null;

    // Schnellpfad: schon erzeugt. Der mtime-Vergleich fängt den seltenen Fall ab, dass eine
    // Datei unter gleichem Namen ersetzt wurde (Uploads sind eigentlich unveränderlich).
    try {
      const zStat = fs.statSync(ziel);
      if (zStat.isFile() && zStat.size > 0 && zStat.mtimeMs >= qStat.mtimeMs) return ziel;
    } catch {
      /* noch nicht vorhanden — wird gleich erzeugt */
    }

    const laufend = inFlight.get(ziel);
    if (laufend) return await laufend;

    const arbeit = erzeuge(quelle, ziel, stufe).finally(() => inFlight.delete(ziel));
    inFlight.set(ziel, arbeit);
    return await arbeit;
  } catch (e) {
    log.warn("thumbs: unerwarteter Fehler — es wird das Original ausgeliefert", { key, breite, error: String(e) });
    return null;
  }
}

/** Skaliert und legt die Datei atomar ab (temporär schreiben + umbenennen). */
async function erzeuge(quelle: string, ziel: string, stufe: number): Promise<string | null> {
  const sharp = await ladeSharp();
  if (!sharp) return null;
  let tmp = "";
  try {
    const buf = await sharp(quelle)
      // `.rotate()` ohne Winkel wendet die EXIF-Ausrichtung an — ohne das stehen
      // Hochformat-Etiketten in der Vorschau quer.
      .rotate()
      .resize({ width: stufe, fit: "inside", withoutEnlargement: true })
      .jpeg({ quality: QUALITAET })
      .toBuffer();

    fs.mkdirSync(path.dirname(ziel), { recursive: true });
    // Atomar: erst vollständig in eine temporäre Datei, dann umbenennen. Sonst könnte eine
    // zweite, gleichzeitige Anfrage eine halb geschriebene Datei ausliefern.
    tmp = `${ziel}.${crypto.randomBytes(6).toString("hex")}.tmp`;
    fs.writeFileSync(tmp, buf);
    try {
      fs.renameSync(tmp, ziel);
    } catch (e) {
      try { fs.unlinkSync(tmp); } catch { /* Aufräumen ist Beiwerk */ }
      // Hat ein paralleler Lauf das Ziel bereits geschrieben, ist alles gut.
      if (fs.existsSync(ziel)) return ziel;
      throw e;
    }
    tmp = "";
    return ziel;
  } catch (e) {
    if (tmp) { try { fs.unlinkSync(tmp); } catch { /* Aufräumen ist Beiwerk */ } }
    log.warn("thumbs: Vorschau konnte nicht erzeugt werden — Original", { quelle, stufe, error: String(e) });
    return null;
  }
}
