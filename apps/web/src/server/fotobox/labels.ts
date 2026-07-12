import type BetterSqlite3 from "better-sqlite3";

// Dynamische, per API erweiterbare Wertebereiche (statt statischer CHECK-Constraints).
// Quelle: Tabelle fotobox_labels. Neue Werte via POST /api/v1/fotobox-labels.

export type LabelField = "domain" | "intent" | "status" | "review_reason" | "target_resource" | "label_key";

export interface LabelRow {
  value: string;
  label: string | null;
  target_resource: string | null;
  description: string | null;
  sort: number;
}

/** Aktive Werte eines Feldes (nur value[]). */
export function allowedValues(db: BetterSqlite3.Database, field: LabelField): string[] {
  return (db.prepare("SELECT value FROM fotobox_labels WHERE field=? AND active=1 ORDER BY sort, value").all(field) as { value: string }[])
    .map((r) => r.value);
}

/** Aktive Labels eines Feldes (mit Metadaten für UI/Schema). */
export function labelsFor(db: BetterSqlite3.Database, field: LabelField): LabelRow[] {
  return db.prepare(
    "SELECT value, label, target_resource, description, sort FROM fotobox_labels WHERE field=? AND active=1 ORDER BY sort, value",
  ).all(field) as LabelRow[];
}

/** Alle Enum-Felder → aktive Werte (für /fotobox-items/schema). */
export function allowedMap(db: BetterSqlite3.Database): Record<LabelField, string[]> {
  const fields: LabelField[] = ["domain", "intent", "status", "review_reason", "target_resource", "label_key"];
  const out = {} as Record<LabelField, string[]>;
  for (const f of fields) out[f] = allowedValues(db, f);
  return out;
}

const ITEM_FIELD_MAP: Partial<Record<string, LabelField>> = {
  domain: "domain",
  intent: "intent",
  status: "status",
  target_resource: "target_resource",
  review_reason: "review_reason",
};

/**
 * Validiert die gesetzten Routing/Status-Felder eines Items gegen die aktiven Labels.
 * Gibt den ersten Verstoß zurück (oder null). Leere/NULL-Werte sind erlaubt.
 */
export function validateItemValues(
  db: BetterSqlite3.Database,
  values: Record<string, unknown>,
): { field: string; value: unknown; allowed: string[] } | null {
  for (const [col, field] of Object.entries(ITEM_FIELD_MAP)) {
    const v = values[col];
    if (v == null || v === "") continue;
    const allowed = allowedValues(db, field as LabelField);
    if (!allowed.includes(String(v))) return { field: col, value: v, allowed };
  }
  return null;
}

/** Ziel-Ressource für eine Domain (aus dem Label-Mapping). */
export function targetResourceForDomain(db: BetterSqlite3.Database, domain: string): string | null {
  const r = db.prepare("SELECT target_resource FROM fotobox_labels WHERE field='domain' AND value=?").get(domain) as
    | { target_resource: string | null }
    | undefined;
  return r?.target_resource ?? null;
}
