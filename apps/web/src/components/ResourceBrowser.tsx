"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { apiGet, apiSend } from "@/lib/api";

interface ImageSpec { col: string; multi: boolean; area: string }
interface Column { name: string; type: string; required: boolean; primary_key: boolean }
type Row = Record<string, unknown>;

const AUTO = new Set(["created_at", "erstellt_am", "erfasst_am", "added_at", "updated_at", "aktualisiert_am"]);
const LONG = new Set(["beschreibung", "notizen", "notes", "details", "description", "anleitung", "warnhinweise", "begruendung", "text_content", "tips", "kid_notes", "geeignet_fuer"]);
const TITLE = ["title", "titel", "name", "friendly_name", "bezeichnung", "anbieter", "problem", "item", "input_text"];
const SUB = ["date", "datum", "start_date", "status", "kategorie", "category", "marke", "groesse", "destination", "anlass", "mhd", "sorte", "geschmack"];

const titleOf = (r: Row) => { for (const k of TITLE) if (r[k]) return String(r[k]); return `#${r.id ?? ""}`; };
const subOf = (r: Row) => { const p: string[] = []; for (const k of SUB) if (r[k] && p.length < 3) p.push(String(r[k])); return p.join(" · "); };
function imgOf(r: Row, image?: ImageSpec): string | null {
  if (!image) return null;
  if (image.multi) { const a = r[image.col + "_urls"]; return Array.isArray(a) && a.length ? String(a[0]) : null; }
  const v = r[image.col + "_url"]; return v ? String(v) : null;
}

export function ResourceBrowser({ resource, label, image, backHref }: { resource: string; label: string; image?: ImageSpec; backHref: string }) {
  const [rows, setRows] = useState<Row[]>([]);
  const [total, setTotal] = useState(0);
  const [cols, setCols] = useState<Column[]>([]);
  const [pk, setPk] = useState("id");
  const [readonly, setReadonly] = useState(false);
  const [q, setQ] = useState("");
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState("");
  const [detail, setDetail] = useState<Row | null>(null);
  const [form, setForm] = useState<Row | null>(null); // offenes Formular (create/edit)
  const [editingId, setEditingId] = useState<string | null>(null); // null=create
  const [saving, setSaving] = useState(false);

  const load = useCallback(async (search: string) => {
    setLoading(true); setErr("");
    try {
      const res = await apiGet<{ data: Row[]; total: number }>(`/${resource}?limit=300${search ? `&search=${encodeURIComponent(search)}` : ""}`);
      setRows(res.data); setTotal(res.total);
    } catch (e) { setErr(String((e as Error).message)); } finally { setLoading(false); }
  }, [resource]);

  // Initial-Load asynchron (setState nur in async-Callbacks → keine synchronen Effekt-Renders).
  useEffect(() => {
    let alive = true;
    (async () => {
      try {
        const s = await apiGet<{ columns: Column[]; primary_key: string; readonly: boolean }>(`/${resource}/schema`);
        if (alive) { setCols(s.columns); setPk(s.primary_key); setReadonly(s.readonly); }
      } catch { /* Schema optional */ }
      try {
        const res = await apiGet<{ data: Row[]; total: number }>(`/${resource}?limit=300`);
        if (alive) { setRows(res.data); setTotal(res.total); }
      } catch (e) { if (alive) setErr(String((e as Error).message)); }
      if (alive) setLoading(false);
    })();
    return () => { alive = false; };
  }, [resource]);

  const formCols = cols.filter((c) => !c.primary_key && !AUTO.has(c.name));

  function openCreate() { setEditingId(null); setForm({}); }
  function openEdit(r: Row) { setEditingId(String(r[pk])); setForm({ ...r }); setDetail(null); }

  async function save() {
    if (!form) return;
    setSaving(true); setErr("");
    try {
      const payload: Row = {};
      for (const c of formCols) { const v = form[c.name]; if (v !== undefined && v !== "") payload[c.name] = v; }
      if (editingId === null) await apiSend(`/${resource}`, "POST", payload);
      else await apiSend(`/${resource}/${editingId}`, "PATCH", payload);
      setForm(null); await load(q);
    } catch (e) { setErr(String((e as Error).message)); } finally { setSaving(false); }
  }

  async function remove(r: Row) {
    if (!confirm(`„${titleOf(r)}" wirklich löschen?`)) return;
    try { await apiSend(`/${resource}/${r[pk]}`, "DELETE"); setDetail(null); await load(q); }
    catch (e) { setErr(String((e as Error).message)); }
  }

  return (
    <main className="min-h-[100dvh] bg-gradient-to-br from-[#F2F2F7] via-[#E5E5EA] to-[#F2F2F7]">
      <header className="pt-10 pb-3 px-4 safe-area-inset max-w-3xl mx-auto">
        <div className="flex items-center justify-between">
          <Link href={backHref} className="text-[#007AFF] text-sm font-semibold">‹ Zurück</Link>
          {!readonly && <button onClick={openCreate} className="text-white text-sm font-bold bg-[#007AFF] rounded-full px-3.5 py-1.5 active:scale-95 transition">+ Neu</button>}
        </div>
        <h1 className="text-2xl font-extrabold text-[#1C1C1E] tracking-tight mt-2">{label}</h1>
        <p className="text-[#8E8E93] text-xs font-medium">{total} Einträge</p>
        <form onSubmit={(e) => { e.preventDefault(); load(q); }} className="mt-3">
          <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Suchen…"
            className="w-full rounded-2xl bg-white border border-black/5 px-4 py-2.5 text-[15px] outline-none focus:ring-2 focus:ring-[#007AFF]/30" />
        </form>
      </header>

      <div className="max-w-3xl mx-auto px-3 pb-10">
        {err && <p className="text-[#FF3B30] text-sm font-medium px-1 mb-2">{err}</p>}
        {loading ? (
          <p className="text-[#8E8E93] text-sm px-1">Lädt…</p>
        ) : image ? (
          <div className="grid grid-cols-2 sm:grid-cols-3 gap-2.5">
            {rows.map((r) => (
              <button key={String(r[pk])} onClick={() => setDetail(r)} className="text-left bg-white rounded-2xl overflow-hidden border border-black/5 shadow-sm active:scale-[0.98] transition">
                <div className="aspect-square bg-[#F2F2F7] flex items-center justify-center overflow-hidden">
                  {imgOf(r, image) ? <img src={imgOf(r, image)!} alt="" className="w-full h-full object-cover" /> : <span className="text-3xl opacity-30">🖼️</span>}
                </div>
                <div className="p-2">
                  <div className="text-[13px] font-bold text-[#1C1C1E] leading-tight line-clamp-1">{titleOf(r)}</div>
                  <div className="text-[10px] text-[#8E8E93] line-clamp-1">{subOf(r)}</div>
                </div>
              </button>
            ))}
          </div>
        ) : (
          <div className="bg-white rounded-2xl border border-black/5 shadow-sm divide-y divide-black/5 overflow-hidden">
            {rows.map((r) => (
              <button key={String(r[pk])} onClick={() => setDetail(r)} className="w-full text-left px-4 py-3 flex items-center justify-between gap-3 active:bg-black/[0.02]">
                <div className="min-w-0">
                  <div className="text-[15px] font-semibold text-[#1C1C1E] leading-tight truncate">{titleOf(r)}</div>
                  {subOf(r) && <div className="text-[12px] text-[#8E8E93] truncate">{subOf(r)}</div>}
                </div>
                <span className="text-[#C7C7CC] text-lg">›</span>
              </button>
            ))}
            {!rows.length && <p className="text-[#8E8E93] text-sm p-4">Keine Einträge.</p>}
          </div>
        )}
      </div>

      {/* Detail */}
      {detail && (
        <div className="fixed inset-0 bg-black/40 z-40 flex items-end sm:items-center justify-center p-0 sm:p-6" onClick={() => setDetail(null)}>
          <div className="bg-white rounded-t-3xl sm:rounded-3xl w-full max-w-lg max-h-[85dvh] overflow-y-auto" onClick={(e) => e.stopPropagation()}>
            <div className="sticky top-0 bg-white/90 backdrop-blur px-5 py-3 flex items-center justify-between border-b border-black/5">
              <h2 className="font-extrabold text-[#1C1C1E] truncate">{titleOf(detail)}</h2>
              <button onClick={() => setDetail(null)} className="text-[#8E8E93] text-xl">✕</button>
            </div>
            <div className="p-5 space-y-2">
              {imgOf(detail, image) && <img src={imgOf(detail, image)!} alt="" className="w-full rounded-2xl mb-3" />}
              {Object.entries(detail).filter(([k]) => !k.endsWith("_url") && !k.endsWith("_urls")).map(([k, v]) => (
                <div key={k} className="flex gap-3 text-[13px] border-b border-black/5 pb-1.5">
                  <span className="text-[#8E8E93] font-medium w-32 shrink-0">{k}</span>
                  <span className="text-[#1C1C1E] break-words min-w-0">{v == null ? "—" : String(v).slice(0, 400)}</span>
                </div>
              ))}
            </div>
            {!readonly && (
              <div className="sticky bottom-0 bg-white/90 backdrop-blur p-4 flex gap-2 border-t border-black/5">
                <button onClick={() => openEdit(detail)} className="flex-1 bg-[#007AFF] text-white font-bold rounded-2xl py-2.5 active:scale-[0.98]">Bearbeiten</button>
                <button onClick={() => remove(detail)} className="px-4 bg-[#FF3B30]/10 text-[#FF3B30] font-bold rounded-2xl py-2.5">Löschen</button>
              </div>
            )}
          </div>
        </div>
      )}

      {/* Formular */}
      {form && (
        <div className="fixed inset-0 bg-black/40 z-50 flex items-end sm:items-center justify-center" onClick={() => !saving && setForm(null)}>
          <div className="bg-white rounded-t-3xl sm:rounded-3xl w-full max-w-lg max-h-[88dvh] overflow-y-auto" onClick={(e) => e.stopPropagation()}>
            <div className="sticky top-0 bg-white/90 backdrop-blur px-5 py-3 flex items-center justify-between border-b border-black/5">
              <h2 className="font-extrabold text-[#1C1C1E]">{editingId === null ? "Neu anlegen" : "Bearbeiten"}</h2>
              <button onClick={() => setForm(null)} className="text-[#8E8E93] text-xl">✕</button>
            </div>
            <div className="p-5 space-y-3">
              {formCols.map((c) => {
                const val = form[c.name];
                const common = "w-full rounded-xl bg-[#F2F2F7] border border-black/5 px-3 py-2 text-[14px] outline-none focus:ring-2 focus:ring-[#007AFF]/30";
                return (
                  <label key={c.name} className="block">
                    <span className="text-[11px] text-[#8E8E93] font-semibold">{c.name}{c.required ? " *" : ""}</span>
                    {LONG.has(c.name) ? (
                      <textarea value={val == null ? "" : String(val)} onChange={(e) => setForm({ ...form, [c.name]: e.target.value })} rows={3} className={common} />
                    ) : (
                      <input type={/INT|REAL|NUM/i.test(c.type) ? "number" : "text"} value={val == null ? "" : String(val)}
                        onChange={(e) => setForm({ ...form, [c.name]: e.target.value })} className={common} />
                    )}
                  </label>
                );
              })}
              {err && <p className="text-[#FF3B30] text-sm">{err}</p>}
            </div>
            <div className="sticky bottom-0 bg-white/90 backdrop-blur p-4 border-t border-black/5">
              <button onClick={save} disabled={saving} className="w-full bg-[#007AFF] text-white font-bold rounded-2xl py-3 active:scale-[0.98] disabled:opacity-50">
                {saving ? "Speichert…" : "Speichern"}
              </button>
            </div>
          </div>
        </div>
      )}
    </main>
  );
}
