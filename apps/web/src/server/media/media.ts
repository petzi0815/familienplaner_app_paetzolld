import type { ImageSpec } from "@/server/domains/registry";

/** storage-key (`<area>/<datei>`) oder externe/Legacy-URL → auslieferbare URL. */
export function imageUrl(ref: string): string {
  if (!ref) return ref;
  if (/^https?:\/\//i.test(ref) || ref.startsWith("/api/") || ref.startsWith("/")) return ref;
  return `/api/v1/media/${ref}`;
}

/** Ergänzt an einer Zeile die aufgelösten Bild-URLs (`<col>_url` / `<col>_urls`), Rohwert bleibt. */
export function expandImages(row: Record<string, unknown>, image?: ImageSpec): void {
  if (!image) return;
  const v = row[image.col];
  if (v == null || v === "") return;
  if (image.multi) {
    let arr: unknown;
    try { arr = JSON.parse(String(v)); } catch { arr = [String(v)]; }
    row[image.col + "_urls"] = Array.isArray(arr) ? arr.map((r) => imageUrl(String(r))) : [];
  } else {
    row[image.col + "_url"] = imageUrl(String(v));
  }
}
