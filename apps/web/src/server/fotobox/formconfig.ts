import type BetterSqlite3 from "better-sqlite3";
import { resourceByKey } from "@/server/domains/registry";
import { enumConstraints } from "@/server/db/constraints";
import { labelsFor } from "./labels";

// Kontextabhängige Vorschlags-Felder je Domäne für die iOS-Fotobox.
// iOS zeigt nach dem Foto pro gewählter Domäne 2–3 Dropdowns mit GÜLTIGEN Werten:
//  - Enum-Spalten (CHECK) → strikte Auswahl
//  - sonst reale DISTINCT-Werte aus der Zielressource → Vorschlag (freie Eingabe erlaubt)
//  - Bool-Spalten → Ja/Nein
// Die gewählten Werte landen im analysis_hint des Items; Ole schreibt damit valide in die Zielressource.

type FieldKind = "value" | "bool";
interface FieldDef { col: string; label: string; kind?: FieldKind }

// Kuratiert: welche Felder je Domäne sinnvoll sind (bewusst 2–3 für Übersichtlichkeit).
const DOMAIN_FIELDS: Record<string, FieldDef[]> = {
  samu_items:          [{ col: "typ", label: "Art" }, { col: "kategorie", label: "Kategorie" }, { col: "groesse", label: "Größe" }, { col: "status", label: "Status" }],
  gypsi_futter:        [{ col: "marke", label: "Marke" }, { col: "geschmack", label: "Geschmack" }, { col: "status", label: "Status" }],
  vorrat_lebensmittel: [{ col: "kategorie", label: "Kategorie" }, { col: "status", label: "Status" }],
  garten_pflanze:      [{ col: "art", label: "Art" }, { col: "standort", label: "Standort" }, { col: "status", label: "Status" }],
  garten_samen:        [{ col: "art", label: "Art" }, { col: "aktiv", label: "Aktiv", kind: "bool" }],
  garten_duenger:      [{ col: "marke", label: "Marke" }, { col: "typ", label: "Typ" }],
  reiniger_produkt:    [{ col: "kategorie", label: "Kategorie" }, { col: "status", label: "Status" }],
  buecher_scan:        [{ col: "category", label: "Kategorie" }, { col: "language", label: "Sprache" }, { col: "status", label: "Status" }],
  geschenk_wunsch:     [{ col: "category", label: "Kategorie" }, { col: "priority", label: "Priorität" }, { col: "status", label: "Status" }],
  reisen_doc:          [{ col: "doc_type", label: "Dokumenttyp" }],
  smarthome_device:    [{ col: "domain", label: "Typ" }, { col: "area_name", label: "Raum" }],
  vertrag_doc:         [{ col: "kategorie", label: "Kategorie" }, { col: "status", label: "Status" }],
  unknown:             [],
};

const BOOL_COLS = new Set(["aktiv", "erledigt", "vorraetig", "bio", "samenfest", "frostempfindlich"]);

export interface FormField {
  key: string;
  label: string;
  type: "enum" | "suggest" | "bool";
  required: boolean;
  options: string[];
}
export interface DomainForm {
  domain: string;
  label: string;
  target_resource: string | null;
  fields: FormField[];
}

function distinctValues(db: BetterSqlite3.Database, table: string, col: string, cols: Set<string>): string[] {
  if (!cols.has(col)) return [];
  try {
    return (db.prepare(`SELECT DISTINCT "${col}" AS v FROM "${table}" WHERE "${col}" IS NOT NULL AND "${col}" <> '' ORDER BY "${col}" LIMIT 60`).all() as { v: unknown }[])
      .map((r) => String(r.v));
  } catch { return []; }
}

function columnSet(db: BetterSqlite3.Database, table: string): Set<string> {
  try {
    return new Set((db.prepare(`PRAGMA table_info("${table}")`).all() as { name: string }[]).map((c) => c.name));
  } catch { return new Set(); }
}

function buildFields(db: BetterSqlite3.Database, targetKey: string, defs: FieldDef[]): FormField[] {
  const res = resourceByKey(targetKey);
  if (!res) return [];
  const table = res.table;
  const cols = columnSet(db, table);
  const enums = enumConstraints(db, table);
  const out: FormField[] = [];
  for (const d of defs) {
    if (!cols.has(d.col)) continue;
    if (d.kind === "bool" || BOOL_COLS.has(d.col)) {
      out.push({ key: d.col, label: d.label, type: "bool", required: false, options: ["ja", "nein"] });
      continue;
    }
    const enumVals = enums[d.col];
    if (enumVals && enumVals.length) {
      out.push({ key: d.col, label: d.label, type: "enum", required: false, options: enumVals });
    } else {
      out.push({ key: d.col, label: d.label, type: "suggest", required: false, options: distinctValues(db, table, d.col, cols) });
    }
  }
  return out;
}

/** Form-Config für alle Domänen (oder eine). Enthält für jede Domäne die kontextabhängigen Felder. */
export function formConfig(db: BetterSqlite3.Database, domainFilter?: string | null): DomainForm[] {
  const domains = labelsFor(db, "domain").filter((d) => !domainFilter || d.value === domainFilter);
  return domains.map((d) => ({
    domain: d.value,
    label: d.label ?? d.value,
    target_resource: d.target_resource,
    fields: d.target_resource ? buildFields(db, d.target_resource, DOMAIN_FIELDS[d.value] ?? []) : [],
  }));
}
