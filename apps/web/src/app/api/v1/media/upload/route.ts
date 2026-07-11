import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { config } from "@/server/config";
import { getDb } from "@/server/db/connection";
import { getAuth, hasRole } from "@/server/auth/auth";
import { randomToken } from "@/server/util/hash";
import { unauthorized, forbidden, fail, ok } from "@/server/http/respond";

// Bild-/Datei-Upload → $DATA_DIR/media/<area>/<name>, liefert storage_key + URL zurück.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function POST(req: Request): Promise<Response> {
  const auth = getAuth(req);
  if (!hasRole(auth, "agent")) return auth ? forbidden() : unauthorized();
  let form: FormData;
  try { form = await req.formData(); } catch { return fail("bad_form", "multipart/form-data erwartet.", 400); }
  const area = String(form.get("area") ?? "uploads").replace(/[^a-z0-9_-]/gi, "") || "uploads";
  const file = form.get("file");
  if (!(file instanceof File)) return fail("no_file", "Feld 'file' fehlt.", 400);

  const ext = (path.extname(file.name) || ".bin").toLowerCase().replace(/[^.a-z0-9]/g, "");
  const name = `up_${Date.now()}_${randomToken(6)}${ext}`;
  const buf = Buffer.from(await file.arrayBuffer());
  const dir = path.join(config.mediaDir, area);
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, name), buf);
  const key = `${area}/${name}`;

  try {
    getDb().prepare("INSERT OR IGNORE INTO media_assets (bereich,storage_key,original_name,mime,bytes,sha256) VALUES (?,?,?,?,?,?)")
      .run(area, key, file.name, file.type || "application/octet-stream", buf.length, crypto.createHash("sha256").update(buf).digest("hex"));
  } catch { /* ignore */ }

  return ok({ storage_key: key, url: `/api/v1/media/${key}`, bytes: buf.length });
}
