'use client';

import { useState, useEffect, useCallback } from 'react';
import Link from 'next/link';

/* ── Types ── */
interface Kind {
  id: number; name: string; geburtsdatum: string | null; profil: string | null;
  negativliste: string | null; profil_bestaetigt_am: string | null;
  naechste_ereignisse: Ereignis[]; anlaesse: AnlassConfig[];
}
interface AnlassConfig {
  id: number; kind_id: number; anlass: string; aktiv: number;
  budget_min: number | null; budget_max: number | null;
}
interface Ereignis {
  id: number; kind_id: number; anlass: string; datum: string; jahr: number;
  alter_zum_ereignis: number | null; kind_name?: string;
  budget_min?: number | null; budget_max?: number | null;
  geschenke?: Geschenk[];
  geschenke_count?: number; geschenke_ausgaben?: number;
  geschenke_status?: Record<string, number>;
  profil_bestaetigung_angefragt?: number; profil_bestaetigt?: number;
  profil?: string;
  erinnerungen_aktiv?: number;
}
interface Geschenk {
  id: number; ereignis_id: number | null; kind_id: number; titel: string;
  beschreibung: string | null; preis: number | null; url: string | null;
  shop: string | null; status: string; quelle: string | null; notizen: string | null;
  bild_url: string | null; ranking: number | null; begruendung: string | null;
}
interface VergGeschenk {
  id: number; kind_id: number; titel: string; anlass: string | null;
  jahr: number | null; notizen: string | null; kind_name?: string;
}
interface DashboardData {
  anstehende: Ereignis[];
  offene_bestaetigung: Ereignis[];
  stats: { kinder: number; anstehende_ereignisse: number };
}

/* ── Helpers ── */
const anlassEmoji: Record<string, string> = { geburtstag: '🎂', ostern: '🐣', weihnachten: '🎄' };
const anlassLabel: Record<string, string> = { geburtstag: 'Geburtstag', ostern: 'Ostern', weihnachten: 'Weihnachten' };
const statusLabel: Record<string, string> = { vorschlag: 'Vorschlag', ausgewaehlt: 'Ausgewählt', bestellt: 'Bestellt', verpackt: 'Verpackt', vergeben: 'Vergeben' };
const statusStyle: Record<string, string> = {
  vorschlag: 'bg-gray-100 text-gray-600',
  ausgewaehlt: 'bg-blue-100 text-blue-700',
  bestellt: 'bg-amber-100 text-amber-700',
  verpackt: 'bg-green-100 text-green-700',
  vergeben: 'bg-purple-100 text-purple-700 line-through',
};
const anlassBorder: Record<string, string> = {
  geburtstag: 'border-l-amber-400', ostern: 'border-l-emerald-400', weihnachten: 'border-l-red-400',
};
const STATUSES = ['vorschlag', 'ausgewaehlt', 'bestellt', 'verpackt', 'vergeben'];

function fmtDate(d: string) { return new Date(d).toLocaleDateString('de-DE', { day: '2-digit', month: '2-digit', year: 'numeric' }); }
function fmtEur(v: number | null) { return v != null ? `${Number(v).toFixed(2)} €` : '–'; }
function idealoUrl(titel: string) { return `https://www.idealo.de/preisvergleich/MainSearchProductCategory.html?q=${encodeURIComponent(titel)}`; }
function gshopUrl(titel: string) { return `https://www.google.de/search?q=${encodeURIComponent(titel)}&tbm=shop`; }

function countdown(dateStr: string) {
  const d = new Date(dateStr); const now = new Date();
  d.setHours(0,0,0,0); now.setHours(0,0,0,0);
  const diff = Math.ceil((d.getTime() - now.getTime()) / 86400000);
  if (diff < 0) return { text: `vor ${-diff} Tagen`, soon: false, past: true };
  if (diff === 0) return { text: 'Heute! 🎉', soon: true, past: false };
  if (diff === 1) return { text: 'Morgen!', soon: true, past: false };
  return { text: `in ${diff} Tagen`, soon: diff <= 14, past: false };
}

function berechneAlter(geb: string, datum: string) {
  const g = new Date(geb); const d = new Date(datum);
  let a = d.getFullYear() - g.getFullYear();
  if (d.getMonth() < g.getMonth() || (d.getMonth() === g.getMonth() && d.getDate() < g.getDate())) a--;
  return a;
}

/* ── API ── */
const api = {
  get: async (url: string) => { const r = await fetch(url); if (!r.ok) throw new Error((await r.json()).error); return r.json(); },
  post: async (url: string, body?: any) => { const r = await fetch(url, { method: 'POST', headers: {'Content-Type':'application/json'}, body: body ? JSON.stringify(body) : undefined }); if (!r.ok) throw new Error((await r.json()).error); return r.json(); },
  patch: async (url: string, body: any) => { const r = await fetch(url, { method: 'PATCH', headers: {'Content-Type':'application/json'}, body: JSON.stringify(body) }); if (!r.ok) throw new Error((await r.json()).error); return r.json(); },
  put: async (url: string, body: any) => { const r = await fetch(url, { method: 'PUT', headers: {'Content-Type':'application/json'}, body: JSON.stringify(body) }); if (!r.ok) throw new Error((await r.json()).error); return r.json(); },
  del: async (url: string) => { const r = await fetch(url, { method: 'DELETE' }); if (!r.ok) throw new Error((await r.json()).error); return r.json(); },
};

/* ── Toast ── */
function useToast() {
  const [toasts, setToasts] = useState<{ id: number; msg: string; type: string }[]>([]);
  const toast = (msg: string, type = 'success') => {
    const id = Date.now();
    setToasts(t => [...t, { id, msg, type }]);
    setTimeout(() => setToasts(t => t.filter(x => x.id !== id)), 3000);
  };
  const ToastContainer = () => (
    <div className="fixed bottom-4 right-4 z-50 flex flex-col gap-2">
      {toasts.map(t => (
        <div key={t.id} className={`px-4 py-2.5 rounded-2xl text-sm font-semibold text-white shadow-lg animate-slide-up ${t.type === 'error' ? 'bg-red-500' : 'bg-emerald-500'}`}>
          {t.msg}
        </div>
      ))}
    </div>
  );
  return { toast, ToastContainer };
}

/* ── Modal Shell ── */
function Modal({ children, onClose }: { children: React.ReactNode; onClose: () => void }) {
  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/40 backdrop-blur-sm" onClick={onClose}>
      <div className="w-full max-w-lg bg-white rounded-t-3xl sm:rounded-3xl shadow-2xl p-6 pb-10 sm:pb-6 animate-slide-up max-h-[90vh] overflow-y-auto" onClick={e => e.stopPropagation()}>
        <div className="w-10 h-1 bg-gray-300 rounded-full mx-auto mb-4 sm:hidden" />
        {children}
      </div>
    </div>
  );
}

/* ══════════════════════════════════════════════════════════════════════════════
   MAIN PAGE
   ══════════════════════════════════════════════════════════════════════════════ */
export default function GeschenkplanerPage() {
  const [view, setView] = useState<'dashboard' | 'kinder' | 'ereignis' | 'kind' | 'archiv' | 'einkauf'>('dashboard');
  const [selectedId, setSelectedId] = useState<number | null>(null);
  const { toast, ToastContainer } = useToast();

  // Navigation helpers
  const goTo = (v: typeof view, id?: number) => { setView(v); setSelectedId(id ?? null); };

  return (
    <main className="min-h-screen bg-gradient-to-br from-[#FFF8F0] via-[#FFF5F5] to-[#F5F0FF]">
      <style jsx global>{`
        @keyframes slide-up { from { transform: translateY(100%); opacity: 0; } to { transform: translateY(0); opacity: 1; } }
        .animate-slide-up { animation: slide-up 0.3s ease-out; }
      `}</style>

      {/* ── Header ── */}
      <header className="pt-12 pb-3 px-5 safe-area-inset">
        <div className="max-w-2xl mx-auto">
          <div className="flex items-center gap-3 mb-3">
            <Link href="/" className="flex items-center justify-center w-10 h-10 bg-white/70 backdrop-blur-sm rounded-2xl border border-amber-200/50 shadow-sm hover:bg-white transition active:scale-95">
              <svg className="w-5 h-5 text-amber-600" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2.5}>
                <path strokeLinecap="round" strokeLinejoin="round" d="M15 19l-7-7 7-7" />
              </svg>
            </Link>
            <div>
              <h1 className="text-2xl font-extrabold text-[#1C1C1E] tracking-tight leading-tight">🎁 Geschenkplaner</h1>
              <p className="text-amber-600/80 text-xs font-medium mt-0.5">Geschenke für jeden Anlass</p>
            </div>
          </div>

          {/* Nav tabs */}
          <div className="flex gap-1.5 overflow-x-auto pb-1 -mx-1 px-1">
            {[
              { v: 'dashboard' as const, label: '📊 Übersicht' },
              { v: 'einkauf' as const, label: '🛒 Einkauf' },
              { v: 'kinder' as const, label: '👶 Kinder' },
              { v: 'archiv' as const, label: '📦 Archiv' },
            ].map(tab => (
              <button key={tab.v} onClick={() => goTo(tab.v)}
                className={`flex-shrink-0 px-4 py-2 rounded-2xl text-sm font-semibold transition-all border ${
                  view === tab.v ? 'bg-amber-500 text-white border-amber-500 shadow-sm' : 'bg-white/60 text-[#636366] border-amber-200/40 hover:border-amber-300'
                }`}>
                {tab.label}
              </button>
            ))}
          </div>
        </div>
      </header>

      <div className="max-w-2xl mx-auto px-5 pb-16">
        {view === 'dashboard' && <DashboardView toast={toast} goTo={goTo} />}
        {view === 'einkauf' && <EinkaufView toast={toast} goTo={goTo} />}
        {view === 'kinder' && <KinderView toast={toast} goTo={goTo} />}
        {view === 'ereignis' && selectedId && <EreignisView id={selectedId} toast={toast} goTo={goTo} />}
        {view === 'kind' && selectedId && <KindView id={selectedId} toast={toast} goTo={goTo} />}
        {view === 'archiv' && <ArchivView toast={toast} />}
      </div>

      <ToastContainer />
    </main>
  );
}

/* ══════════════════════════════════════════════════════════════════════════════
   DASHBOARD VIEW
   ══════════════════════════════════════════════════════════════════════════════ */
function DashboardView({ toast, goTo }: { toast: (m: string, t?: string) => void; goTo: (v: any, id?: number) => void }) {
  const [data, setData] = useState<DashboardData | null>(null);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    setLoading(true);
    try { setData(await api.get('/api/geschenkplaner/dashboard')); }
    catch (e: any) { toast(e.message, 'error'); }
    finally { setLoading(false); }
  }, [toast]);

  useEffect(() => { load(); }, [load]);

  const handleConfirm = async (kindId: number) => {
    try { await api.post(`/api/geschenkplaner/kinder/${kindId}/profil-bestaetigen`); toast('Profil bestätigt ✅'); load(); }
    catch (e: any) { toast(e.message, 'error'); }
  };

  if (loading) return <div className="flex flex-col items-center py-16"><div className="text-4xl animate-bounce mb-3">🎁</div><p className="text-[#8E8E93] font-medium">Lade Dashboard…</p></div>;
  if (!data) return null;

  const totalSpent = data.anstehende.reduce((s, e) => s + (e.geschenke_ausgaben || 0), 0);

  return (
    <div className="space-y-4 mt-4">
      {/* Stats */}
      <div className="grid grid-cols-3 gap-2">
        <div className="bg-white/70 backdrop-blur-sm rounded-2xl border border-amber-200/40 p-3 text-center shadow-sm">
          <div className="text-2xl font-extrabold text-amber-600">{data.stats.kinder}</div>
          <div className="text-[10px] text-[#8E8E93] font-medium">Kinder</div>
        </div>
        <div className="bg-white/70 backdrop-blur-sm rounded-2xl border border-amber-200/40 p-3 text-center shadow-sm">
          <div className="text-2xl font-extrabold text-amber-600">{data.stats.anstehende_ereignisse}</div>
          <div className="text-[10px] text-[#8E8E93] font-medium">Ereignisse</div>
        </div>
        <div className="bg-white/70 backdrop-blur-sm rounded-2xl border border-amber-200/40 p-3 text-center shadow-sm">
          <div className="text-2xl font-extrabold text-amber-600">{fmtEur(totalSpent)}</div>
          <div className="text-[10px] text-[#8E8E93] font-medium">Geplant</div>
        </div>
      </div>

      {/* Profile confirmations */}
      {data.offene_bestaetigung.map(ob => (
        <div key={ob.id} className="bg-gradient-to-r from-amber-50 to-orange-50 rounded-2xl border border-amber-300/50 p-4 flex items-center gap-3">
          <span className="text-2xl">⚠️</span>
          <div className="flex-1">
            <p className="text-sm font-bold text-[#1C1C1E]">{ob.kind_name}: Profil bestätigen</p>
            <p className="text-[11px] text-[#636366]">{anlassEmoji[ob.anlass]} {anlassLabel[ob.anlass]} {ob.jahr}</p>
          </div>
          <button onClick={() => handleConfirm(ob.kind_id)} className="px-3 py-1.5 bg-amber-500 text-white text-xs font-bold rounded-xl transition active:scale-95">✅</button>
        </div>
      ))}

      {/* Upcoming events */}
      <h3 className="text-sm font-bold text-[#1C1C1E] pt-2">📅 Nächste Ereignisse</h3>
      {data.anstehende.length === 0 ? (
        <div className="text-center py-8">
          <div className="text-4xl mb-2">🎉</div>
          <p className="text-sm text-[#8E8E93]">Keine anstehenden Ereignisse mit Geschenken</p>
          <p className="text-[10px] text-[#8E8E93] mt-1">Geschenkvorschläge werden 60 Tage vor dem Anlass automatisch recherchiert.</p>
        </div>
      ) : (
        data.anstehende.map(e => {
          const cd = countdown(e.datum);
          const budgetPct = e.budget_max ? Math.min(100, ((e.geschenke_ausgaben || 0) / e.budget_max) * 100) : 0;
          const budgetColor = budgetPct > 90 ? 'bg-red-400' : budgetPct > 60 ? 'bg-amber-400' : 'bg-emerald-400';
          return (
            <button key={e.id} onClick={() => goTo('ereignis', e.id)}
              className={`w-full text-left bg-white/70 backdrop-blur-sm rounded-2xl border border-l-4 ${anlassBorder[e.anlass] || 'border-l-gray-300'} border-amber-200/40 p-4 shadow-sm transition active:scale-[0.98]`}>
              <div className="flex items-start justify-between">
                <div>
                  <h4 className="text-sm font-bold text-[#1C1C1E]">{anlassEmoji[e.anlass]} {e.kind_name} — {anlassLabel[e.anlass]} {e.jahr}</h4>
                  <p className="text-[11px] text-[#636366] mt-0.5">
                    {fmtDate(e.datum)} · {e.alter_zum_ereignis != null ? `${e.alter_zum_ereignis} Jahre` : ''}
                    · {e.geschenke_count || 0} Geschenk{(e.geschenke_count || 0) !== 1 ? 'e' : ''}
                    {e.budget_max ? ` · Budget: ${e.budget_min || 0}–${e.budget_max} €` : ''}
                  </p>
                </div>
                <span className={`text-[10px] font-bold px-2 py-1 rounded-full ${cd.soon ? 'bg-red-100 text-red-600' : cd.past ? 'bg-gray-100 text-gray-500' : 'bg-gray-100 text-gray-500'}`}>{cd.text}</span>
              </div>
              {e.budget_max ? (
                <div className="h-1.5 bg-gray-100 rounded-full mt-2 overflow-hidden">
                  <div className={`h-full rounded-full ${budgetColor} transition-all`} style={{ width: `${budgetPct}%` }} />
                </div>
              ) : null}
              {e.geschenke_status && (
                <div className="flex gap-1.5 mt-2 flex-wrap items-center">
                  {Object.entries(e.geschenke_status).filter(([, v]) => v > 0).map(([k, v]) => (
                    <span key={k} className={`text-[10px] font-bold px-2 py-0.5 rounded-full ${statusStyle[k]}`}>{v}× {statusLabel[k]}</span>
                  ))}
                  {e.erinnerungen_aktiv === 0 && (
                    <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-gray-100 text-gray-400">🔕 Stumm</span>
                  )}
                </div>
              )}
            </button>
          );
        })
      )}
    </div>
  );
}

/* ══════════════════════════════════════════════════════════════════════════════
   KINDER VIEW
   ══════════════════════════════════════════════════════════════════════════════ */
function KinderView({ toast, goTo }: { toast: (m: string, t?: string) => void; goTo: (v: any, id?: number) => void }) {
  const [kinder, setKinder] = useState<Kind[]>([]);
  const [loading, setLoading] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [editKindId, setEditKindId] = useState<number | null>(null);
  const [formName, setFormName] = useState('');
  const [formGeb, setFormGeb] = useState('');
  const [formProfil, setFormProfil] = useState('');
  const [formNegativ, setFormNegativ] = useState('');

  const load = useCallback(async () => {
    setLoading(true);
    try { setKinder(await api.get('/api/geschenkplaner/kinder')); }
    catch (e: any) { toast(e.message, 'error'); }
    finally { setLoading(false); }
  }, [toast]);

  useEffect(() => { load(); }, [load]);

  const openForm = (kind?: Kind) => {
    setEditKindId(kind?.id ?? null);
    setFormName(kind?.name || '');
    setFormGeb(kind?.geburtsdatum || '');
    setFormProfil(kind?.profil || '');
    setFormNegativ(kind?.negativliste || '');
    setShowForm(true);
  };

  const saveKind = async () => {
    const data = { name: formName, geburtsdatum: formGeb || null, profil: formProfil || null, negativliste: formNegativ || null };
    try {
      if (editKindId) await api.patch(`/api/geschenkplaner/kinder/${editKindId}`, data);
      else await api.post('/api/geschenkplaner/kinder', data);
      setShowForm(false);
      toast(editKindId ? 'Kind aktualisiert ✅' : 'Kind angelegt ✅');
      load();
    } catch (e: any) { toast(e.message, 'error'); }
  };

  // Matrix: lokaler State statt sofort speichern
  type MatrixEntry = { aktiv: boolean; min: string; max: string };
  type MatrixState = Record<string, MatrixEntry>; // key: `${kindId}_${anlass}`
  const [matrix, setMatrix] = useState<MatrixState>({});
  const [matrixDirty, setMatrixDirty] = useState(false);

  // Matrix aus Kinder-Daten initialisieren (nach load)
  useEffect(() => {
    const m: MatrixState = {};
    for (const k of kinder) {
      for (const anlass of ['geburtstag', 'ostern', 'weihnachten']) {
        const cfg = k.anlaesse.find(a => a.anlass === anlass);
        const noDate = anlass === 'geburtstag' && !k.geburtsdatum;
        m[`${k.id}_${anlass}`] = {
          aktiv: !noDate && cfg?.aktiv === 1,
          min: cfg?.budget_min?.toString() || '',
          max: cfg?.budget_max?.toString() || '',
        };
      }
    }
    setMatrix(m);
    setMatrixDirty(false);
  }, [kinder]);

  const matrixSet = (kindId: number, anlass: string, patch: Partial<MatrixEntry>) => {
    setMatrix(prev => ({ ...prev, [`${kindId}_${anlass}`]: { ...prev[`${kindId}_${anlass}`], ...patch } }));
    setMatrixDirty(true);
  };

  const saveMatrix = async () => {
    try {
      for (const k of kinder) {
        const configs = ['geburtstag', 'ostern', 'weihnachten'].map(anlass => {
          const entry = matrix[`${k.id}_${anlass}`];
          return {
            anlass,
            aktiv: entry?.aktiv ? 1 : 0,
            budget_min: parseInt(entry?.min) || null,
            budget_max: parseInt(entry?.max) || null,
          };
        });
        await api.put(`/api/geschenkplaner/kinder/${k.id}/anlaesse`, configs);
      }
      // Ereignisse automatisch generieren für neu aktivierte Anlässe
      await api.post('/api/geschenkplaner/ereignisse/generieren');
      toast('Matrix gespeichert ✅');
      setMatrixDirty(false);
      load();
    } catch (e: any) { toast(e.message, 'error'); }
  };

  const delKind = async (id: number, name: string) => {
    if (!confirm(`"${name}" wirklich löschen? Alle Ereignisse und Geschenke werden gelöscht!`)) return;
    try { await api.del(`/api/geschenkplaner/kinder/${id}`); toast('Kind gelöscht'); load(); }
    catch (e: any) { toast(e.message, 'error'); }
  };

  if (loading) return <div className="flex flex-col items-center py-16"><div className="text-4xl animate-bounce">👶</div><p className="text-[#8E8E93] font-medium mt-3">Lade Kinder…</p></div>;

  return (
    <div className="space-y-3 mt-4">
      <div className="flex items-center justify-between">
        <h3 className="text-sm font-bold text-[#1C1C1E]">👶 Kinder ({kinder.length})</h3>
        <button onClick={() => openForm()} className="px-3 py-1.5 bg-amber-500 text-white text-xs font-bold rounded-xl transition active:scale-95">+ Hinzufügen</button>
      </div>

      {kinder.length === 0 ? (
        <div className="text-center py-8">
          <div className="text-4xl mb-2">👶</div>
          <p className="text-sm text-[#8E8E93]">Noch keine Kinder angelegt.</p>
        </div>
      ) : kinder.map(k => {
        const alter = k.geburtsdatum ? berechneAlter(k.geburtsdatum, new Date().toISOString().slice(0, 10)) : null;
        return (
          <div key={k.id} className="bg-white/70 backdrop-blur-sm rounded-2xl border border-amber-200/40 p-4 shadow-sm">
            <div className="flex items-start justify-between">
              <button onClick={() => goTo('kind', k.id)} className="text-left flex-1">
                <h4 className="text-sm font-bold text-[#1C1C1E]">👶 {k.name}{alter !== null && <span className="font-normal text-[#8E8E93]"> ({alter} Jahre)</span>}</h4>
                {k.geburtsdatum && <p className="text-[11px] text-[#636366] mt-0.5">📅 {fmtDate(k.geburtsdatum)}</p>}
                {k.profil && <p className="text-[11px] text-[#636366] mt-1 line-clamp-2">{k.profil}</p>}
                {k.negativliste && <p className="text-[10px] text-red-500 mt-1">🚫 {k.negativliste}</p>}
              </button>
              <div className="flex gap-1 ml-2">
                <button onClick={(e) => { e.stopPropagation(); goTo('kind', k.id); }} className="px-2 py-1 bg-gray-100 text-xs rounded-lg transition active:scale-95">✏️</button>
                <button onClick={(e) => { e.stopPropagation(); delKind(k.id, k.name); }} className="px-2 py-1 bg-gray-100 text-xs rounded-lg hover:bg-red-50 transition active:scale-95">🗑️</button>
              </div>
            </div>
            <div className="flex gap-1.5 mt-2 flex-wrap">
              {k.anlaesse.map(a => (
                <span key={a.anlass} className={`text-[10px] font-bold px-2 py-0.5 rounded-full ${a.aktiv ? 'bg-amber-100 text-amber-700' : 'bg-gray-100 text-gray-400'}`}>
                  {anlassEmoji[a.anlass]} {a.budget_min || 0}–{a.budget_max || '?'} €
                </span>
              ))}
            </div>
            {k.naechste_ereignisse.length > 0 && (
              <div className="mt-2 pt-2 border-t border-gray-100">
                {k.naechste_ereignisse.map(e => {
                  const cd = countdown(e.datum);
                  return (
                    <button key={e.id} onClick={() => goTo('ereignis', e.id)} className="flex items-center gap-2 text-[11px] text-[#636366] py-0.5 w-full text-left hover:text-[#1C1C1E] transition">
                      <span>{anlassEmoji[e.anlass]}</span>
                      <span>{anlassLabel[e.anlass]} {e.jahr}</span>
                      <span className={`ml-auto font-bold ${cd.soon ? 'text-red-500' : ''}`}>{cd.text}</span>
                    </button>
                  );
                })}
              </div>
            )}
          </div>
        );
      })}

      {/* Form Modal */}
      {/* Budget-Matrix */}
      {kinder.length > 0 && (
        <div className="bg-white/70 backdrop-blur-sm rounded-2xl border border-amber-200/40 p-4 shadow-sm">
          <h3 className="text-sm font-bold text-[#1C1C1E] mb-3">⚙️ Budget-Matrix</h3>
          <div className="overflow-x-auto -mx-2 px-2">
            <table className="w-full text-xs min-w-[300px]">
              <thead>
                <tr className="text-[#636366]">
                  <th className="text-left py-2 pr-3 font-bold">Kind</th>
                  {(['geburtstag', 'ostern', 'weihnachten'] as const).map(a => (
                    <th key={a} className="text-center px-2 py-2 font-bold">
                      <span className="block text-base">{anlassEmoji[a]}</span>
                      <span className="block text-[10px] font-medium text-[#636366]">{anlassLabel[a]}</span>
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {kinder.map(k => (
                  <tr key={k.id} className="border-t border-gray-100">
                    <td className="py-2 pr-3 font-semibold text-[#1C1C1E] whitespace-nowrap">{k.name}</td>
                    {(['geburtstag', 'ostern', 'weihnachten'] as const).map(anlass => {
                      const key = `${k.id}_${anlass}`;
                      const entry = matrix[key];
                      const noDate = anlass === 'geburtstag' && !k.geburtsdatum;
                      const aktiv = entry?.aktiv ?? false;
                      return (
                        <td key={anlass} className="px-1 py-2 text-center align-top">
                          <div className="flex flex-col items-center gap-1.5">
                            <button
                              disabled={noDate}
                              title={noDate ? 'Kein Geburtsdatum eingetragen' : undefined}
                              onClick={() => !noDate && matrixSet(k.id, anlass, { aktiv: !aktiv })}
                              className={`w-8 h-5 rounded-full transition-colors relative flex-shrink-0 ${noDate ? 'opacity-30 cursor-not-allowed' : 'cursor-pointer'} ${aktiv ? 'bg-amber-500' : 'bg-gray-300'}`}
                            >
                              <div className={`absolute w-4 h-4 bg-white rounded-full top-0.5 shadow-sm transition-all ${aktiv ? 'left-[14px]' : 'left-0.5'}`} />
                            </button>
                            {aktiv && (
                              <div className="flex items-center gap-0.5">
                                <input
                                  type="number"
                                  placeholder="Min"
                                  value={entry?.min || ''}
                                  onChange={e => matrixSet(k.id, anlass, { min: e.target.value })}
                                  className="w-10 bg-[#F2F2F7] rounded-lg px-1 py-0.5 text-[10px] outline-none focus:ring-1 focus:ring-amber-400 text-center"
                                />
                                <span className="text-[10px] text-gray-400">–</span>
                                <input
                                  type="number"
                                  placeholder="Max"
                                  value={entry?.max || ''}
                                  onChange={e => matrixSet(k.id, anlass, { max: e.target.value })}
                                  className="w-10 bg-[#F2F2F7] rounded-lg px-1 py-0.5 text-[10px] outline-none focus:ring-1 focus:ring-amber-400 text-center"
                                />
                              </div>
                            )}
                          </div>
                        </td>
                      );
                    })}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          {matrixDirty && (
            <button onClick={saveMatrix} className="mt-3 w-full py-2.5 bg-amber-500 text-white text-sm font-bold rounded-xl transition active:scale-95 shadow-sm">
              💾 Alles speichern
            </button>
          )}
        </div>
      )}

      {/* Form Modal */}
      {showForm && (
        <Modal onClose={() => setShowForm(false)}>
          <h2 className="text-lg font-bold text-[#1C1C1E] mb-4">{editKindId ? '✏️ Kind bearbeiten' : '👶 Kind hinzufügen'}</h2>
          <div className="space-y-3">
            <div>
              <label className="text-xs font-bold text-[#636366] block mb-1">Name *</label>
              <input value={formName} onChange={e => setFormName(e.target.value)} className="w-full bg-[#F2F2F7] rounded-xl px-4 py-2.5 text-sm outline-none focus:ring-2 focus:ring-amber-400" />
            </div>
            <div>
              <label className="text-xs font-bold text-[#636366] block mb-1">Geburtsdatum <span className="font-normal text-[#8E8E93]">(optional)</span></label>
              <input type="date" value={formGeb} onChange={e => setFormGeb(e.target.value)} className="w-full bg-[#F2F2F7] rounded-xl px-4 py-2.5 text-sm outline-none focus:ring-2 focus:ring-amber-400" />
              {!formGeb && <p className="text-[10px] text-[#8E8E93] mt-1">Ohne Geburtsdatum werden keine Geburtstags-Ereignisse generiert.</p>}
            </div>
            <div>
              <label className="text-xs font-bold text-[#636366] block mb-1">Profil (Interessen, Hobbys)</label>
              <textarea value={formProfil} onChange={e => setFormProfil(e.target.value)} rows={3} className="w-full bg-[#F2F2F7] rounded-xl px-4 py-2.5 text-sm outline-none focus:ring-2 focus:ring-amber-400 resize-none" />
            </div>
            <div>
              <label className="text-xs font-bold text-[#636366] block mb-1">🚫 Negativliste (was NICHT vorgeschlagen werden soll)</label>
              <textarea value={formNegativ} onChange={e => setFormNegativ(e.target.value)} rows={2} placeholder="z.B. Kleidung, Süßigkeiten, Videospiele…" className="w-full bg-red-50 rounded-xl px-4 py-2.5 text-sm outline-none focus:ring-2 focus:ring-red-300 resize-none border border-red-200/50" />
            </div>
            <div className="flex gap-2 pt-1">
              <button onClick={saveKind} disabled={!formName} className="flex-1 py-2.5 bg-amber-500 text-white text-sm font-bold rounded-xl transition active:scale-95 disabled:opacity-50">
                {editKindId ? '💾 Speichern' : '✅ Anlegen'}
              </button>
              <button onClick={() => setShowForm(false)} className="px-4 py-2.5 bg-gray-100 text-gray-500 text-sm rounded-xl transition active:scale-95">✕</button>
            </div>
          </div>
        </Modal>
      )}
    </div>
  );
}

/* ══════════════════════════════════════════════════════════════════════════════
   EREIGNIS DETAIL VIEW
   ══════════════════════════════════════════════════════════════════════════════ */
function EreignisView({ id, toast, goTo }: { id: number; toast: (m: string, t?: string) => void; goTo: (v: any, id?: number) => void }) {
  const [ereignis, setEreignis] = useState<Ereignis | null>(null);
  const [loading, setLoading] = useState(true);
  const [showGeschenkForm, setShowGeschenkForm] = useState(false);
  const [editGeschenk, setEditGeschenk] = useState<Geschenk | null>(null);
  const [filterStatus, setFilterStatus] = useState<string | null>(null);
  const [swipeMode, setSwipeMode] = useState(false);
  const [swipeIdx, setSwipeIdx] = useState(0);
  const [swipeAnim, setSwipeAnim] = useState<'left' | 'right' | 'super' | null>(null);
  const [touchStart, setTouchStart] = useState<{ x: number; y: number } | null>(null);
  const [touchDelta, setTouchDelta] = useState(0);
  const [votedIds, setVotedIds] = useState<Set<number>>(new Set());
  const [swipeDone, setSwipeDone] = useState(false);

  // Form fields
  const [gTitel, setGTitel] = useState('');
  const [gBeschr, setGBeschr] = useState('');
  const [gPreis, setGPreis] = useState('');
  const [gUrl, setGUrl] = useState('');
  const [gShop, setGShop] = useState('');
  const [gQuelle, setGQuelle] = useState('');
  const [gNotizen, setGNotizen] = useState('');
  const [gStatus, setGStatus] = useState('vorschlag');
  const [gRanking, setGRanking] = useState('0');

  const load = useCallback(async () => {
    setLoading(true);
    try { setEreignis(await api.get(`/api/geschenkplaner/ereignisse/${id}`)); }
    catch (e: any) { toast(e.message, 'error'); }
    finally { setLoading(false); }
  }, [id, toast]);

  useEffect(() => { load(); }, [load]);

  const openGeschenkForm = (g?: Geschenk) => {
    setEditGeschenk(g || null);
    setGTitel(g?.titel || ''); setGBeschr(g?.beschreibung || ''); setGPreis(g?.preis?.toString() || '');
    setGUrl(g?.url || ''); setGShop(g?.shop || ''); setGQuelle(g?.quelle || '');
    setGNotizen(g?.notizen || ''); setGStatus(g?.status || 'vorschlag');
    setGRanking((g?.ranking ?? 0).toString());
    setShowGeschenkForm(true);
  };

  const saveGeschenk = async () => {
    const data: any = {
      titel: gTitel, beschreibung: gBeschr || null,
      preis: gPreis ? parseFloat(gPreis) : null,
      url: gUrl || null, shop: gShop || null,
      quelle: gQuelle || null, notizen: gNotizen || null, status: gStatus,
      ranking: parseInt(gRanking) || 0,
    };
    try {
      if (editGeschenk) { await api.patch(`/api/geschenkplaner/geschenke/${editGeschenk.id}`, data); }
      else { data.ereignis_id = id; data.kind_id = ereignis?.kind_id; data.ist_manuell = 1; await api.post('/api/geschenkplaner/geschenke', data); }
      setShowGeschenkForm(false);
      toast(editGeschenk ? 'Geschenk aktualisiert ✅' : 'Geschenk hinzugefügt ✅');
      load();
    } catch (e: any) { toast(e.message, 'error'); }
  };

  const cycleStatus = async (g: Geschenk) => {
    const idx = STATUSES.indexOf(g.status);
    const next = STATUSES[(idx + 1) % (STATUSES.length - 1)]; // skip vergeben
    try { await api.patch(`/api/geschenkplaner/geschenke/${g.id}`, { status: next }); toast(`Status → ${statusLabel[next]}`); load(); }
    catch (e: any) { toast(e.message, 'error'); }
  };

  const vergebeG = async (g: Geschenk) => {
    if (!confirm('Geschenk als vergeben markieren und ins Archiv übernehmen?')) return;
    try { await api.post(`/api/geschenkplaner/geschenke/${g.id}/vergeben`); toast('Vergeben & archiviert 🎉'); load(); }
    catch (e: any) { toast(e.message, 'error'); }
  };

  const schonGeschenkt = async (g: Geschenk) => {
    try {
      await api.post(`/api/geschenkplaner/geschenke/${g.id}/schon-geschenkt`);
      toast('Als "schon geschenkt" markiert & entfernt 🔄');
      setSwipeAnim('left');
      setVotedIds(prev => new Set(prev).add(g.id));
      setTimeout(() => { setSwipeAnim(null); load(); }, 400);
    } catch (e: any) { toast(e.message, 'error'); }
  };

  const deleteG = async (g: Geschenk) => {
    if (!confirm(`"${g.titel}" löschen?`)) return;
    try { await api.del(`/api/geschenkplaner/geschenke/${g.id}`); toast('Gelöscht'); load(); }
    catch (e: any) { toast(e.message, 'error'); }
  };

  const handleConfirm = async () => {
    if (!ereignis) return;
    try { await api.post(`/api/geschenkplaner/kinder/${ereignis.kind_id}/profil-bestaetigen`); toast('Profil bestätigt ✅'); load(); }
    catch (e: any) { toast(e.message, 'error'); }
  };

  const vote = async (g: Geschenk, delta: number) => {
    const newRanking = (g.ranking || 0) + delta;
    try {
      await api.patch(`/api/geschenkplaner/geschenke/${g.id}`, { ranking: newRanking });
      setSwipeAnim(delta > 1 ? 'super' : delta > 0 ? 'right' : 'left');
      setVotedIds(prev => new Set(prev).add(g.id));
      setTimeout(() => {
        setSwipeAnim(null);
        load();
      }, 400);
    } catch (e: any) { toast(e.message, 'error'); }
  };

  const handleTouchStart = (e: React.TouchEvent) => {
    setTouchStart({ x: e.touches[0].clientX, y: e.touches[0].clientY });
    setTouchDelta(0);
  };
  const handleTouchMove = (e: React.TouchEvent) => {
    if (!touchStart) return;
    setTouchDelta(e.touches[0].clientX - touchStart.x);
  };
  const handleTouchEnd = (g: Geschenk) => {
    if (Math.abs(touchDelta) > 80) {
      vote(g, touchDelta > 0 ? 1 : -1);
    }
    setTouchStart(null);
    setTouchDelta(0);
  };

  if (loading) return <div className="flex flex-col items-center py-16"><div className="text-4xl animate-bounce">🎁</div></div>;
  if (!ereignis) return null;

  const cd = countdown(ereignis.datum);
  const geschenke = ereignis.geschenke || [];
  const ausgaben = geschenke.filter(g => ['ausgewaehlt','bestellt','verpackt','vergeben'].includes(g.status)).reduce((s, g) => s + (g.preis || 0), 0);
  const budgetPct = ereignis.budget_max ? Math.min(100, (ausgaben / ereignis.budget_max) * 100) : 0;
  const budgetColor = budgetPct > 90 ? 'bg-red-400' : budgetPct > 60 ? 'bg-amber-400' : 'bg-emerald-400';

  return (
    <div className="space-y-3 mt-4">
      {/* Back */}
      <button onClick={() => goTo('dashboard')} className="text-xs font-medium text-amber-600 flex items-center gap-1">
        <svg className="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2.5}><path strokeLinecap="round" strokeLinejoin="round" d="M15 19l-7-7 7-7" /></svg>
        Dashboard
      </button>

      {/* Profile confirm — hidden in swipe mode */}
      {!swipeMode && ereignis.profil_bestaetigung_angefragt === 1 && !ereignis.profil_bestaetigt && (
        <div className="bg-gradient-to-r from-amber-50 to-orange-50 rounded-2xl border border-amber-300/50 p-4 flex items-center gap-3">
          <span className="text-xl">⚠️</span>
          <div className="flex-1 text-sm"><strong>Profil prüfen:</strong> Sind {ereignis.kind_name}s Interessen noch aktuell?</div>
          <button onClick={handleConfirm} className="px-3 py-1.5 bg-amber-500 text-white text-xs font-bold rounded-xl transition active:scale-95">✅</button>
        </div>
      )}

      {/* Event header — hidden in swipe mode */}
      {!swipeMode && (
      <div className={`bg-white/70 backdrop-blur-sm rounded-2xl border border-l-4 ${anlassBorder[ereignis.anlass] || ''} border-amber-200/40 p-4 shadow-sm`}>
        <div className="flex items-start justify-between">
          <div>
            <h2 className="text-lg font-bold text-[#1C1C1E]">{anlassEmoji[ereignis.anlass]} {ereignis.kind_name} — {anlassLabel[ereignis.anlass]} {ereignis.jahr}</h2>
            <p className="text-[11px] text-[#636366] mt-0.5">
              📅 {fmtDate(ereignis.datum)}{ereignis.alter_zum_ereignis != null ? ` · 👶 ${ereignis.alter_zum_ereignis} Jahre` : ''}
              {ereignis.budget_max ? ` · 💰 ${ereignis.budget_min || 0}–${ereignis.budget_max} € (${fmtEur(ausgaben)} geplant)` : ''}
            </p>
          </div>
          <span className={`text-[10px] font-bold px-2 py-1 rounded-full ${cd.soon ? 'bg-red-100 text-red-600' : 'bg-gray-100 text-gray-500'}`}>{cd.text}</span>
        </div>
        {ereignis.budget_max ? (
          <div className="h-1.5 bg-gray-100 rounded-full mt-2 overflow-hidden">
            <div className={`h-full rounded-full ${budgetColor} transition-all`} style={{ width: `${budgetPct}%` }} />
          </div>
        ) : null}
        {ereignis.profil && (
          <p className="text-[11px] text-[#636366] mt-2 bg-[#F2F2F7] rounded-xl p-2.5">
            <strong>Profil:</strong> {ereignis.profil}
          </p>
        )}
        {/* Erinnerungen Toggle */}
        <div className="flex items-center justify-between mt-3 pt-3 border-t border-gray-100">
          <div className="flex items-center gap-2">
            <span className="text-sm">🔔</span>
            <span className="text-xs font-semibold text-[#636366]">Erinnerungen</span>
          </div>
          <button
            onClick={async (e) => {
              e.stopPropagation();
              const newVal = ereignis.erinnerungen_aktiv === 1 ? 0 : 1;
              try {
                await api.patch(`/api/geschenkplaner/ereignisse/${ereignis.id}`, { erinnerungen_aktiv: newVal });
                toast(newVal ? 'Erinnerungen aktiviert 🔔' : 'Erinnerungen deaktiviert 🔕');
                load();
              } catch (err: any) { toast(err.message, 'error'); }
            }}
            className={`w-11 h-6 rounded-full transition-colors relative ${ereignis.erinnerungen_aktiv !== 0 ? 'bg-amber-500' : 'bg-gray-300'}`}
          >
            <div className={`absolute w-5 h-5 bg-white rounded-full top-0.5 shadow-sm transition-all ${ereignis.erinnerungen_aktiv !== 0 ? 'left-[22px]' : 'left-0.5'}`} />
          </button>
        </div>
      </div>
      )}

      {/* Geschenke header */}
      <div className="flex items-center justify-between pt-1">
        {swipeMode ? (
          <>
            <h3 className="text-sm font-bold text-[#1C1C1E]">💘 {ereignis.kind_name} — {anlassLabel[ereignis.anlass]}</h3>
            <button onClick={() => { setSwipeMode(false); setVotedIds(new Set()); setSwipeDone(false); }} className="px-3 py-1.5 text-xs font-bold rounded-xl transition active:scale-95 bg-pink-500 text-white">
              📋 Liste
            </button>
          </>
        ) : (
          <>
            <h3 className="text-sm font-bold text-[#1C1C1E]">🎁 Geschenke ({geschenke.length})</h3>
            <div className="flex gap-1.5">
              <button onClick={() => { setSwipeMode(true); setSwipeIdx(0); setVotedIds(new Set()); setSwipeDone(false); }} className="px-3 py-1.5 text-xs font-bold rounded-xl transition active:scale-95 bg-pink-100 text-pink-600">
                💘 Bewerten
              </button>
              <button onClick={() => openGeschenkForm()} className="px-3 py-1.5 bg-amber-500 text-white text-xs font-bold rounded-xl transition active:scale-95">+ Geschenk</button>
            </div>
          </>
        )}
      </div>

      {/* Status-Filter — hidden in swipe mode */}
      {!swipeMode && geschenke.length > 0 && (
        <div className="flex gap-1.5 overflow-x-auto pb-1 -mx-1 px-1">
          <button onClick={() => setFilterStatus(null)}
            className={`flex-shrink-0 px-3 py-1.5 rounded-2xl text-[11px] font-semibold transition-all border ${
              filterStatus === null ? 'bg-amber-500 text-white border-amber-500 shadow-sm' : 'bg-white/60 text-[#636366] border-amber-200/40 hover:border-amber-300'
            }`}>
            Alle ({geschenke.length})
          </button>
          {STATUSES.map(s => {
            const count = geschenke.filter(g => g.status === s).length;
            if (count === 0) return null;
            return (
              <button key={s} onClick={() => setFilterStatus(filterStatus === s ? null : s)}
                className={`flex-shrink-0 px-3 py-1.5 rounded-2xl text-[11px] font-semibold transition-all border ${
                  filterStatus === s ? 'bg-amber-500 text-white border-amber-500 shadow-sm' : `bg-white/60 border-amber-200/40 hover:border-amber-300 ${statusStyle[s]}`
                }`}>
                {statusLabel[s]} ({count})
              </button>
            );
          })}
        </div>
      )}

      {/* ── SWIPE MODE ── */}
      {swipeMode && geschenke.length > 0 && (() => {
        const unvoted = geschenke.filter(g => !votedIds.has(g.id));
        if (unvoted.length === 0 || swipeDone) {
          return (
            <div className="text-center py-12">
              <div className="text-6xl mb-4">🎉</div>
              <h3 className="text-lg font-extrabold text-[#1C1C1E]">Alle bewertet!</h3>
              <p className="text-sm text-[#8E8E93] mt-2">{votedIds.size} Geschenkideen durchgesehen</p>
              <div className="flex gap-2 justify-center mt-5">
                <button onClick={() => { setVotedIds(new Set()); setSwipeDone(false); }} className="px-4 py-2 bg-pink-500 text-white text-sm font-bold rounded-xl transition active:scale-95">🔄 Neuer Durchlauf</button>
                <button onClick={() => { setSwipeMode(false); setVotedIds(new Set()); setSwipeDone(false); }} className="px-4 py-2 bg-gray-200 text-gray-600 text-sm font-bold rounded-xl transition active:scale-95">📋 Zur Liste</button>
              </div>
            </div>
          );
        }
        const current = unvoted[0];
        return (
          <div className="relative">
            {/* Progress */}
            <div className="text-center text-[10px] text-[#8E8E93] font-medium mb-2">
              {votedIds.size + 1} / {geschenke.length} · noch {unvoted.length}
            </div>

            {/* Card */}
            <div
              className={`relative bg-white rounded-3xl border-2 shadow-lg overflow-hidden transition-all duration-300 ${
                swipeAnim === 'right' ? 'translate-x-[120%] rotate-12 opacity-0' :
                swipeAnim === 'left' ? '-translate-x-[120%] -rotate-12 opacity-0' :
                swipeAnim === 'super' ? '-translate-y-[120%] scale-110 opacity-0' : ''
              } ${touchDelta > 40 ? 'border-green-400' : touchDelta < -40 ? 'border-red-400' : 'border-amber-200/60'}`}
              style={{ transform: !swipeAnim && touchDelta ? `translateX(${touchDelta}px) rotate(${touchDelta * 0.05}deg)` : undefined }}
              onTouchStart={handleTouchStart}
              onTouchMove={handleTouchMove}
              onTouchEnd={() => handleTouchEnd(current)}
            >
              {/* Swipe indicators */}
              {touchDelta > 40 && <div className="absolute top-6 left-6 z-10 text-4xl font-black text-green-500 border-4 border-green-500 rounded-2xl px-4 py-1 -rotate-12 bg-white/80">👍</div>}
              {touchDelta < -40 && <div className="absolute top-6 right-6 z-10 text-4xl font-black text-red-500 border-4 border-red-500 rounded-2xl px-4 py-1 rotate-12 bg-white/80">👎</div>}

              {/* Image */}
              {current.bild_url ? (
                <div className="w-full h-64 bg-gray-100">
                  <img src={current.bild_url} alt={current.titel} className="w-full h-full object-contain" onError={(e) => { (e.target as HTMLImageElement).parentElement!.innerHTML = '<div class="w-full h-full flex items-center justify-center text-6xl">🎁</div>'; }} />
                </div>
              ) : (
                <div className="w-full h-48 bg-gradient-to-br from-amber-50 to-orange-50 flex items-center justify-center text-6xl">🎁</div>
              )}

              {/* Content */}
              <div className="p-5">
                <div className="flex items-center gap-2 mb-2">
                  <span className={`text-xs font-bold px-2.5 py-1 rounded-full ${statusStyle[current.status]}`}>{statusLabel[current.status]}</span>
                  {current.ranking != null && current.ranking !== 0 && (
                    <span className={`text-xs font-bold px-2.5 py-1 rounded-full ${current.ranking > 0 ? 'bg-green-100 text-green-700' : 'bg-red-100 text-red-700'}`}>
                      {current.ranking > 0 ? '👍' : '👎'} {current.ranking}
                    </span>
                  )}
                </div>
                <h3 className="text-xl font-extrabold text-[#1C1C1E] leading-tight">{current.titel}</h3>
                {current.beschreibung && <p className="text-sm text-[#636366] mt-2 line-clamp-3">{current.beschreibung}</p>}
                {current.begruendung && <p className="text-xs text-amber-700 bg-amber-50 rounded-xl px-3 py-2 mt-2">💡 {current.begruendung}</p>}
                <div className="flex flex-wrap gap-1.5 mt-3">
                  {current.preis != null && <span className="text-xs font-bold bg-green-50 text-green-700 px-3 py-1 rounded-full">💰 {fmtEur(current.preis)}</span>}
                  {current.shop && <span className="text-xs bg-blue-50 text-blue-600 px-3 py-1 rounded-full">🏪 {current.shop}</span>}
                  {current.url && <a href={current.url} target="_blank" rel="noopener noreferrer" className="text-xs font-medium text-indigo-500 bg-indigo-50 px-3 py-1 rounded-full">🔗 Shop</a>}
                  <a href={idealoUrl(current.titel)} target="_blank" rel="noopener noreferrer" className="text-xs font-medium text-teal-600 bg-teal-50 px-3 py-1 rounded-full">📊 idealo</a>
                  <a href={gshopUrl(current.titel)} target="_blank" rel="noopener noreferrer" className="text-xs font-medium text-rose-600 bg-rose-50 px-3 py-1 rounded-full">🛍️ Google</a>
                </div>
              </div>
            </div>

            {/* Action buttons */}
            <div className="flex items-center justify-center gap-3 mt-5">
              <button onClick={() => vote(current, -1)} className="w-14 h-14 flex items-center justify-center bg-red-100 text-red-500 rounded-full text-2xl font-bold shadow-md transition active:scale-90 hover:bg-red-200 border-2 border-red-200">
                👎
              </button>
              <button onClick={() => schonGeschenkt(current)} className="w-11 h-11 flex items-center justify-center bg-orange-100 text-orange-500 rounded-full text-lg font-bold shadow-sm transition active:scale-90 hover:bg-orange-200 border-2 border-orange-200" title="Hatten wir schon">
                🔄
              </button>
              <button onClick={() => { setVotedIds(prev => new Set(prev).add(current.id)); }} className="w-10 h-10 flex items-center justify-center bg-gray-100 text-gray-400 rounded-full text-lg shadow-sm transition active:scale-90 border border-gray-200">
                ⏩
              </button>
              <button onClick={() => vote(current, 3)} className="w-14 h-14 flex items-center justify-center bg-blue-100 text-blue-500 rounded-full text-2xl font-bold shadow-md transition active:scale-90 hover:bg-blue-200 border-2 border-blue-200">
                ⭐
              </button>
              <button onClick={() => vote(current, 1)} className="w-14 h-14 flex items-center justify-center bg-green-100 text-green-500 rounded-full text-2xl font-bold shadow-md transition active:scale-90 hover:bg-green-200 border-2 border-green-200">
                👍
              </button>
            </div>
            <div className="flex items-center justify-center gap-4 mt-2 text-[10px] text-[#8E8E93]">
              <span>−1</span>
              <span>Hatten wir</span>
              <span>Skip</span>
              <span>+3</span>
              <span>+1</span>
            </div>
          </div>
        );
      })()}

      {/* ── LIST MODE ── */}
      {!swipeMode && geschenke.length === 0 ? (
        <div className="text-center py-8">
          <div className="text-4xl mb-2">🎁</div>
          <p className="text-sm text-[#8E8E93]">Noch keine Geschenkideen. Füge eine hinzu!</p>
        </div>
      ) : !swipeMode && [...geschenke].filter(g => !filterStatus || g.status === filterStatus).sort((a, b) => ((b.ranking || 0) - (a.ranking || 0))).map(g => (
        <div key={g.id} className="bg-white/70 backdrop-blur-sm rounded-2xl border border-amber-200/40 p-3 shadow-sm">
          <div className="flex items-start gap-3">
            {g.bild_url && (
              <div className="flex-shrink-0 w-16 h-16 rounded-xl overflow-hidden bg-gray-100 border border-gray-200">
                <img src={g.bild_url} alt={g.titel} className="w-full h-full object-cover" onError={(e) => { (e.target as HTMLImageElement).style.display = 'none'; }} />
              </div>
            )}
            <div className="flex-1 min-w-0">
              <div className="flex items-center gap-2">
                {g.ranking != null && g.ranking !== 0 && <span className={`flex-shrink-0 min-w-[24px] h-6 flex items-center justify-center text-[10px] font-black px-1.5 rounded-full border ${g.ranking > 0 ? 'bg-green-100 text-green-700 border-green-300' : 'bg-red-100 text-red-600 border-red-300'}`}>{g.ranking > 0 ? '+' : ''}{g.ranking}</span>}
                <h4 className={`text-sm font-bold text-[#1C1C1E] ${g.status === 'vergeben' ? 'line-through opacity-50' : ''}`}>{g.titel}</h4>
                <button onClick={() => cycleStatus(g)} className={`flex-shrink-0 text-[10px] font-bold px-2 py-0.5 rounded-full transition active:scale-95 ${statusStyle[g.status]}`}>
                  {statusLabel[g.status]}
                </button>
              </div>
              <div className="flex flex-wrap gap-1 mt-1">
                {g.preis != null && <span className="text-[10px] font-bold bg-green-50 text-green-700 px-2 py-0.5 rounded-full">💰 {fmtEur(g.preis)}</span>}
                {g.shop && <span className="text-[10px] bg-blue-50 text-blue-600 px-2 py-0.5 rounded-full">🏪 {g.shop}</span>}
                {g.quelle && <span className="text-[10px] bg-purple-50 text-purple-600 px-2 py-0.5 rounded-full">📝 {g.quelle}</span>}
                {g.url && <a href={g.url} target="_blank" rel="noopener noreferrer" className="text-[10px] font-medium text-indigo-500 bg-indigo-50 px-2 py-0.5 rounded-full hover:bg-indigo-100 transition">🔗 Shop</a>}
                <a href={idealoUrl(g.titel)} target="_blank" rel="noopener noreferrer" className="text-[10px] font-medium text-teal-600 bg-teal-50 px-2 py-0.5 rounded-full hover:bg-teal-100 transition">📊 idealo</a>
                <a href={gshopUrl(g.titel)} target="_blank" rel="noopener noreferrer" className="text-[10px] font-medium text-rose-600 bg-rose-50 px-2 py-0.5 rounded-full hover:bg-rose-100 transition">🛍️ Google</a>
              </div>
              {g.begruendung && <p className="text-[10px] text-amber-700 bg-amber-50 rounded-lg px-2 py-1 mt-1">💡 {g.begruendung}</p>}
              {g.beschreibung && <p className="text-[10px] text-[#636366] mt-1">{g.beschreibung}</p>}
              {g.notizen && <p className="text-[10px] text-[#8E8E93] mt-1 italic">{g.notizen}</p>}
            </div>
            <div className="flex gap-1 flex-shrink-0">
              <button onClick={() => openGeschenkForm(g)} className="px-2 py-1 bg-gray-100 text-[10px] rounded-lg transition active:scale-95">✏️</button>
              {g.status !== 'vergeben' && <button onClick={() => vergebeG(g)} className="px-2 py-1 bg-gray-100 text-[10px] rounded-lg transition active:scale-95">🎉</button>}
              {g.status === 'vorschlag' && <button onClick={() => schonGeschenkt(g)} className="px-2 py-1 bg-orange-50 text-[10px] rounded-lg hover:bg-orange-100 transition active:scale-95" title="Hatten wir schon">🔄</button>}
              <button onClick={() => deleteG(g)} className="px-2 py-1 bg-gray-100 text-[10px] rounded-lg hover:bg-red-50 transition active:scale-95">🗑️</button>
            </div>
          </div>
        </div>
      ))}

      {/* Geschenk Form Modal */}
      {showGeschenkForm && (
        <Modal onClose={() => setShowGeschenkForm(false)}>
          <h2 className="text-lg font-bold text-[#1C1C1E] mb-4">{editGeschenk ? '✏️ Geschenk bearbeiten' : '🎁 Geschenk hinzufügen'}</h2>
          <div className="space-y-3">
            <div>
              <label className="text-xs font-bold text-[#636366] block mb-1">Titel *</label>
              <input value={gTitel} onChange={e => setGTitel(e.target.value)} className="w-full bg-[#F2F2F7] rounded-xl px-4 py-2.5 text-sm outline-none focus:ring-2 focus:ring-amber-400" />
            </div>
            <div>
              <label className="text-xs font-bold text-[#636366] block mb-1">Beschreibung</label>
              <textarea value={gBeschr} onChange={e => setGBeschr(e.target.value)} rows={2} className="w-full bg-[#F2F2F7] rounded-xl px-4 py-2.5 text-sm outline-none focus:ring-2 focus:ring-amber-400 resize-none" />
            </div>
            <div className="grid grid-cols-3 gap-2">
              <div>
                <label className="text-xs font-bold text-[#636366] block mb-1">Preis (€)</label>
                <input type="number" step="0.01" value={gPreis} onChange={e => setGPreis(e.target.value)} className="w-full bg-[#F2F2F7] rounded-xl px-4 py-2.5 text-sm outline-none focus:ring-2 focus:ring-amber-400" />
              </div>
              <div>
                <label className="text-xs font-bold text-[#636366] block mb-1">Status</label>
                <select value={gStatus} onChange={e => setGStatus(e.target.value)} className="w-full bg-[#F2F2F7] rounded-xl px-4 py-2.5 text-sm outline-none focus:ring-2 focus:ring-amber-400">
                  {STATUSES.map(s => <option key={s} value={s}>{statusLabel[s]}</option>)}
                </select>
              </div>
              <div>
                <label className="text-xs font-bold text-[#636366] block mb-1">Ranking</label>
                <div className="flex items-center gap-1">
                  <button type="button" onClick={() => setGRanking(String(parseInt(gRanking || '0') - 1))} className="w-8 h-10 bg-red-100 text-red-600 rounded-l-xl text-lg font-bold transition active:scale-95 hover:bg-red-200">−</button>
                  <input type="number" value={gRanking} onChange={e => setGRanking(e.target.value)} className="w-full bg-[#F2F2F7] px-1 py-2.5 text-sm outline-none focus:ring-2 focus:ring-amber-400 text-center" />
                  <button type="button" onClick={() => setGRanking(String(parseInt(gRanking || '0') + 1))} className="w-8 h-10 bg-green-100 text-green-600 rounded-r-xl text-lg font-bold transition active:scale-95 hover:bg-green-200">+</button>
                </div>
              </div>
            </div>
            <div className="grid grid-cols-2 gap-2">
              <div>
                <label className="text-xs font-bold text-[#636366] block mb-1">Shop</label>
                <input value={gShop} onChange={e => setGShop(e.target.value)} className="w-full bg-[#F2F2F7] rounded-xl px-4 py-2.5 text-sm outline-none focus:ring-2 focus:ring-amber-400" />
              </div>
              <div>
                <label className="text-xs font-bold text-[#636366] block mb-1">Quelle</label>
                <input value={gQuelle} onChange={e => setGQuelle(e.target.value)} placeholder="z.B. Lars, AI" className="w-full bg-[#F2F2F7] rounded-xl px-4 py-2.5 text-sm outline-none focus:ring-2 focus:ring-amber-400" />
              </div>
            </div>
            <div>
              <label className="text-xs font-bold text-[#636366] block mb-1">URL</label>
              <input value={gUrl} onChange={e => setGUrl(e.target.value)} placeholder="https://..." className="w-full bg-[#F2F2F7] rounded-xl px-4 py-2.5 text-sm outline-none focus:ring-2 focus:ring-amber-400" />
            </div>
            <div>
              <label className="text-xs font-bold text-[#636366] block mb-1">Notizen</label>
              <textarea value={gNotizen} onChange={e => setGNotizen(e.target.value)} rows={2} className="w-full bg-[#F2F2F7] rounded-xl px-4 py-2.5 text-sm outline-none focus:ring-2 focus:ring-amber-400 resize-none" />
            </div>
            <div className="flex gap-2 pt-1">
              <button onClick={saveGeschenk} disabled={!gTitel} className="flex-1 py-2.5 bg-amber-500 text-white text-sm font-bold rounded-xl transition active:scale-95 disabled:opacity-50">
                {editGeschenk ? '💾 Speichern' : '✅ Hinzufügen'}
              </button>
              {editGeschenk && (
                <button onClick={() => { setShowGeschenkForm(false); schonGeschenkt(editGeschenk); }} className="px-3 py-2.5 bg-orange-100 text-orange-600 text-sm font-bold rounded-xl transition active:scale-95" title="Hatten wir schon">
                  🔄
                </button>
              )}
              <button onClick={() => setShowGeschenkForm(false)} className="px-4 py-2.5 bg-gray-100 text-gray-500 text-sm rounded-xl transition active:scale-95">✕</button>
            </div>
          </div>
        </Modal>
      )}
    </div>
  );
}

/* ══════════════════════════════════════════════════════════════════════════════
   KIND PROFIL VIEW
   ══════════════════════════════════════════════════════════════════════════════ */
function KindView({ id, toast, goTo }: { id: number; toast: (m: string, t?: string) => void; goTo: (v: any, id?: number) => void }) {
  const [kind, setKind] = useState<Kind | null>(null);
  const [anlaesse, setAnlaesse] = useState<AnlassConfig[]>([]);
  const [ereignisse, setEreignisse] = useState<Ereignis[]>([]);
  const [vergangene, setVergangene] = useState<VergGeschenk[]>([]);
  const [loading, setLoading] = useState(true);
  const [profil, setProfil] = useState('');
  const [negativliste, setNegativliste] = useState('');

  // Anlass form state
  const [anlassState, setAnlassState] = useState<Record<string, { aktiv: boolean; min: string; max: string }>>({});

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const [kinder, anl, erg, verg] = await Promise.all([
        api.get('/api/geschenkplaner/kinder'),
        api.get(`/api/geschenkplaner/kinder/${id}/anlaesse`),
        api.get(`/api/geschenkplaner/ereignisse?kind_id=${id}`),
        api.get(`/api/geschenkplaner/vergangene-geschenke?kind_id=${id}`),
      ]);
      const k = kinder.find((x: Kind) => x.id === id);
      setKind(k); setProfil(k?.profil || ''); setNegativliste(k?.negativliste || '');
      setAnlaesse(anl); setEreignisse(erg); setVergangene(verg);
      const state: Record<string, any> = {};
      for (const a of ['geburtstag', 'ostern', 'weihnachten']) {
        const cfg = anl.find((x: AnlassConfig) => x.anlass === a);
        state[a] = { aktiv: cfg?.aktiv ? true : false, min: cfg?.budget_min?.toString() || '', max: cfg?.budget_max?.toString() || '' };
      }
      setAnlassState(state);
    } catch (e: any) { toast(e.message, 'error'); }
    finally { setLoading(false); }
  }, [id, toast]);

  useEffect(() => { load(); }, [load]);

  const saveProfil = async () => {
    try { await api.patch(`/api/geschenkplaner/kinder/${id}`, { profil, negativliste: negativliste || null }); toast('Profil gespeichert ✅'); }
    catch (e: any) { toast(e.message, 'error'); }
  };

  const confirmProfil = async () => {
    try { await api.post(`/api/geschenkplaner/kinder/${id}/profil-bestaetigen`); toast('Profil bestätigt ✅'); load(); }
    catch (e: any) { toast(e.message, 'error'); }
  };

  const saveAnlaesse = async () => {
    const configs = ['geburtstag', 'ostern', 'weihnachten'].map(a => ({
      anlass: a, aktiv: anlassState[a]?.aktiv ? 1 : 0,
      budget_min: parseInt(anlassState[a]?.min) || null,
      budget_max: parseInt(anlassState[a]?.max) || null,
    }));
    try { await api.put(`/api/geschenkplaner/kinder/${id}/anlaesse`, configs); toast('Anlass-Konfiguration gespeichert ✅'); }
    catch (e: any) { toast(e.message, 'error'); }
  };

  const deleteV = async (vid: number) => {
    if (!confirm('Wirklich löschen?')) return;
    try { await api.del(`/api/geschenkplaner/vergangene-geschenke/${vid}`); toast('Gelöscht'); load(); }
    catch (e: any) { toast(e.message, 'error'); }
  };

  if (loading) return <div className="flex flex-col items-center py-16"><div className="text-4xl animate-bounce">👶</div></div>;
  if (!kind) return null;

  const alter = kind.geburtsdatum ? berechneAlter(kind.geburtsdatum, new Date().toISOString().slice(0, 10)) : null;

  return (
    <div className="space-y-3 mt-4">
      <button onClick={() => goTo('kinder')} className="text-xs font-medium text-amber-600 flex items-center gap-1">
        <svg className="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2.5}><path strokeLinecap="round" strokeLinejoin="round" d="M15 19l-7-7 7-7" /></svg>
        Kinder
      </button>

      {/* Profile */}
      <div className="bg-white/70 backdrop-blur-sm rounded-2xl border border-amber-200/40 p-4 shadow-sm">
        <h2 className="text-lg font-bold text-[#1C1C1E] mb-1">👶 {kind.name}{alter !== null && <span className="font-normal text-[#8E8E93]"> ({alter} Jahre)</span>}</h2>
        <p className="text-[11px] text-[#636366] mb-3">{kind.geburtsdatum ? `📅 ${fmtDate(kind.geburtsdatum)}` : '📅 Kein Geburtsdatum'}{kind.profil_bestaetigt_am ? ` · Profil bestätigt: ${fmtDate(kind.profil_bestaetigt_am)}` : ''}</p>
        <label className="text-xs font-bold text-[#636366] block mb-1">Profil (Interessen, Hobbys)</label>
        <textarea value={profil} onChange={e => setProfil(e.target.value)} rows={3} className="w-full bg-[#F2F2F7] rounded-xl px-4 py-2.5 text-sm outline-none focus:ring-2 focus:ring-amber-400 resize-none mb-3" />
        <label className="text-xs font-bold text-[#636366] block mb-1">🚫 Negativliste (was NICHT vorgeschlagen werden soll)</label>
        <textarea value={negativliste} onChange={e => setNegativliste(e.target.value)} rows={2} placeholder="z.B. Kleidung, Süßigkeiten, Videospiele…" className="w-full bg-red-50 rounded-xl px-4 py-2.5 text-sm outline-none focus:ring-2 focus:ring-red-300 resize-none border border-red-200/50 mb-2" />
        <div className="flex gap-2">
          <button onClick={saveProfil} className="px-3 py-1.5 bg-amber-500 text-white text-xs font-bold rounded-xl transition active:scale-95">💾 Speichern</button>
          <button onClick={confirmProfil} className="px-3 py-1.5 bg-emerald-500 text-white text-xs font-bold rounded-xl transition active:scale-95">✅ Bestätigen</button>
        </div>
      </div>

      {/* Anlass config */}
      <div className="bg-white/70 backdrop-blur-sm rounded-2xl border border-amber-200/40 p-4 shadow-sm">
        <h3 className="text-sm font-bold text-[#1C1C1E] mb-3">⚙️ Anlass-Konfiguration</h3>
        {['geburtstag', 'ostern', 'weihnachten'].map(a => (
          <div key={a} className="flex items-center gap-3 py-2 border-b border-gray-100 last:border-0">
            <button onClick={() => setAnlassState(s => ({ ...s, [a]: { ...s[a], aktiv: !s[a]?.aktiv } }))}
              className={`w-10 h-6 rounded-full transition-colors relative ${anlassState[a]?.aktiv ? 'bg-amber-500' : 'bg-gray-300'}`}>
              <div className={`absolute w-5 h-5 bg-white rounded-full top-0.5 shadow-sm transition-all ${anlassState[a]?.aktiv ? 'left-[18px]' : 'left-0.5'}`} />
            </button>
            <span className="text-sm min-w-[90px]">{anlassEmoji[a]} {anlassLabel[a]}</span>
            <input type="number" placeholder="Min €" value={anlassState[a]?.min || ''} onChange={e => setAnlassState(s => ({ ...s, [a]: { ...s[a], min: e.target.value } }))}
              className="w-16 bg-[#F2F2F7] rounded-lg px-2 py-1 text-xs outline-none focus:ring-2 focus:ring-amber-400" />
            <span className="text-xs text-gray-400">–</span>
            <input type="number" placeholder="Max €" value={anlassState[a]?.max || ''} onChange={e => setAnlassState(s => ({ ...s, [a]: { ...s[a], max: e.target.value } }))}
              className="w-16 bg-[#F2F2F7] rounded-lg px-2 py-1 text-xs outline-none focus:ring-2 focus:ring-amber-400" />
            <span className="text-xs text-gray-400">€</span>
          </div>
        ))}
        <button onClick={saveAnlaesse} className="mt-3 px-3 py-1.5 bg-amber-500 text-white text-xs font-bold rounded-xl transition active:scale-95">💾 Speichern</button>
      </div>

      {/* Ereignisse */}
      <div className="bg-white/70 backdrop-blur-sm rounded-2xl border border-amber-200/40 p-4 shadow-sm">
        <div className="flex items-center justify-between mb-3">
          <h3 className="text-sm font-bold text-[#1C1C1E]">📅 Ereignisse</h3>
        </div>
        {ereignisse.length === 0 ? (
          <p className="text-[11px] text-[#8E8E93]">Ereignisse werden automatisch angelegt.</p>
        ) : ereignisse.map(e => {
          const cd = countdown(e.datum);
          return (
            <button key={e.id} onClick={() => goTo('ereignis', e.id)} className="flex items-center gap-2 w-full text-left py-2 border-b border-gray-100 last:border-0 hover:bg-amber-50/50 rounded-lg px-1 transition">
              <span className="text-lg">{anlassEmoji[e.anlass]}</span>
              <div className="flex-1 min-w-0">
                <p className="text-sm font-semibold text-[#1C1C1E]">{anlassLabel[e.anlass]} {e.jahr}</p>
                <p className="text-[10px] text-[#636366]">{fmtDate(e.datum)}{e.alter_zum_ereignis != null ? ` · ${e.alter_zum_ereignis} Jahre` : ''} · {e.geschenke?.length || 0} Geschenke</p>
              </div>
              <span className={`text-[10px] font-bold ${cd.soon ? 'text-red-500' : 'text-gray-400'}`}>{cd.text}</span>
            </button>
          );
        })}
      </div>

      {/* Vergangene */}
      <div className="bg-white/70 backdrop-blur-sm rounded-2xl border border-amber-200/40 p-4 shadow-sm">
        <h3 className="text-sm font-bold text-[#1C1C1E] mb-3">📦 Vergangene Geschenke</h3>
        {vergangene.length === 0 ? (
          <p className="text-[11px] text-[#8E8E93]">Noch keine vergangenen Geschenke.</p>
        ) : vergangene.map(v => (
          <div key={v.id} className="flex items-center gap-2 py-2 border-b border-gray-100 last:border-0">
            <div className="flex-1">
              <p className="text-sm font-medium text-[#1C1C1E]">{v.titel}</p>
              <p className="text-[10px] text-[#636366]">{v.anlass ? `${anlassEmoji[v.anlass]} ${anlassLabel[v.anlass]}` : ''} {v.jahr || ''}</p>
            </div>
            <button onClick={() => deleteV(v.id)} className="px-2 py-1 bg-gray-100 text-[10px] rounded-lg hover:bg-red-50 transition active:scale-95">🗑️</button>
          </div>
        ))}
      </div>
    </div>
  );
}

/* ══════════════════════════════════════════════════════════════════════════════
   EINKAUF VIEW
   ══════════════════════════════════════════════════════════════════════════════ */
function EinkaufView({ toast, goTo }: { toast: (m: string, t?: string) => void; goTo: (v: any, id?: number) => void }) {
  const [items, setItems] = useState<(Geschenk & { anlass?: string; jahr?: number; datum?: string; kind_name?: string })[]>([]);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const data = await api.get('/api/geschenkplaner/geschenke?status=ausgewaehlt&status=bestellt');
      setItems(data);
    } catch (e: any) { toast(e.message, 'error'); }
    finally { setLoading(false); }
  }, [toast]);

  useEffect(() => { load(); }, [load]);

  const setStatus = async (id: number, newStatus: string) => {
    try {
      await api.patch(`/api/geschenkplaner/geschenke/${id}`, { status: newStatus });
      toast(`Status → ${statusLabel[newStatus]}`);
      load();
    } catch (e: any) { toast(e.message, 'error'); }
  };

  if (loading) return <div className="flex flex-col items-center py-16"><div className="text-4xl animate-bounce">🛒</div><p className="text-[#8E8E93] font-medium mt-3">Lade Einkaufsliste…</p></div>;

  const ausgewaehlt = items.filter(i => i.status === 'ausgewaehlt');
  const bestellt = items.filter(i => i.status === 'bestellt');
  const totalPreis = ausgewaehlt.reduce((s, i) => s + (i.preis || 0), 0);

  // Group by kind+event
  const grouped: Record<string, typeof items> = {};
  for (const item of ausgewaehlt) {
    const key = `${item.kind_name} — ${item.anlass ? `${anlassEmoji[item.anlass]} ${anlassLabel[item.anlass]}` : ''} ${item.jahr || ''}`;
    if (!grouped[key]) grouped[key] = [];
    grouped[key].push(item);
  }

  return (
    <div className="space-y-3 mt-4">
      {/* Stats */}
      <div className="grid grid-cols-2 gap-2">
        <div className="bg-white/70 backdrop-blur-sm rounded-2xl border border-blue-200/40 p-3 text-center shadow-sm">
          <div className="text-2xl font-extrabold text-blue-600">{ausgewaehlt.length}</div>
          <div className="text-[10px] text-[#8E8E93] font-medium">Ausgewählt</div>
        </div>
        <div className="bg-white/70 backdrop-blur-sm rounded-2xl border border-blue-200/40 p-3 text-center shadow-sm">
          <div className="text-2xl font-extrabold text-blue-600">{fmtEur(totalPreis)}</div>
          <div className="text-[10px] text-[#8E8E93] font-medium">Gesamt</div>
        </div>
      </div>

      {/* Ausgewählt — zum Einkaufen */}
      <h3 className="text-sm font-bold text-[#1C1C1E] pt-1">🛒 Noch einzukaufen</h3>
      {ausgewaehlt.length === 0 ? (
        <div className="text-center py-8">
          <div className="text-4xl mb-2">✨</div>
          <p className="text-sm text-[#8E8E93]">Keine ausgewählten Geschenke.</p>
          <p className="text-[10px] text-[#8E8E93] mt-1">Wähle Vorschläge in der Übersicht aus.</p>
        </div>
      ) : Object.entries(grouped).map(([group, groupItems]) => (
        <div key={group}>
          <h4 className="text-[11px] font-bold text-[#636366] mt-3 mb-1.5">{group}</h4>
          {groupItems.map(g => (
            <div key={g.id} className="bg-white/70 backdrop-blur-sm rounded-2xl border border-blue-200/40 p-3 shadow-sm mb-2">
              <div className="flex items-start gap-3">
                {g.bild_url && (
                  <div className="flex-shrink-0 w-14 h-14 rounded-xl overflow-hidden bg-gray-100 border border-gray-200">
                    <img src={g.bild_url} alt={g.titel} className="w-full h-full object-cover" onError={(e) => { (e.target as HTMLImageElement).style.display = 'none'; }} />
                  </div>
                )}
                <div className="flex-1 min-w-0">
                  <h4 className="text-sm font-bold text-[#1C1C1E]">{g.titel}</h4>
                  <div className="flex flex-wrap gap-1 mt-1">
                    {g.preis != null && <span className="text-[10px] font-bold bg-green-50 text-green-700 px-2 py-0.5 rounded-full">💰 {fmtEur(g.preis)}</span>}
                    {g.shop && <span className="text-[10px] bg-blue-50 text-blue-600 px-2 py-0.5 rounded-full">🏪 {g.shop}</span>}
                    {g.url && <a href={g.url} target="_blank" rel="noopener noreferrer" className="text-[10px] font-medium text-indigo-500 bg-indigo-50 px-2 py-0.5 rounded-full hover:bg-indigo-100 transition">🔗 Kaufen</a>}
                  </div>
                </div>
                <div className="flex gap-1 flex-shrink-0">
                  <button onClick={() => setStatus(g.id, 'bestellt')} className="px-2.5 py-1.5 bg-amber-100 text-amber-700 text-[10px] font-bold rounded-xl transition active:scale-95" title="Als bestellt markieren">📦</button>
                  <button onClick={() => setStatus(g.id, 'vorschlag')} className="px-2 py-1.5 bg-gray-100 text-gray-500 text-[10px] rounded-xl transition active:scale-95" title="Zurück zu Vorschlag">↩️</button>
                </div>
              </div>
            </div>
          ))}
        </div>
      ))}

      {/* Bestellt */}
      {bestellt.length > 0 && (
        <>
          <h3 className="text-sm font-bold text-[#1C1C1E] pt-3">📦 Bereits bestellt ({bestellt.length})</h3>
          {bestellt.map(g => (
            <div key={g.id} className="bg-white/70 backdrop-blur-sm rounded-2xl border border-amber-200/40 p-3 shadow-sm opacity-70">
              <div className="flex items-center gap-3">
                <div className="flex-1 min-w-0">
                  <h4 className="text-sm font-medium text-[#1C1C1E]">{g.titel}</h4>
                  <p className="text-[10px] text-[#636366]">👶 {g.kind_name} {g.anlass ? `· ${anlassEmoji[g.anlass]} ${anlassLabel[g.anlass]}` : ''} {g.preis != null ? `· ${fmtEur(g.preis)}` : ''}</p>
                </div>
                <div className="flex gap-1 flex-shrink-0">
                  <button onClick={() => setStatus(g.id, 'verpackt')} className="px-2 py-1.5 bg-green-100 text-green-700 text-[10px] font-bold rounded-xl transition active:scale-95" title="Als verpackt markieren">🎀</button>
                  <button onClick={() => setStatus(g.id, 'ausgewaehlt')} className="px-2 py-1.5 bg-gray-100 text-gray-500 text-[10px] rounded-xl transition active:scale-95" title="Zurück zu ausgewählt">↩️</button>
                </div>
              </div>
            </div>
          ))}
        </>
      )}
    </div>
  );
}

/* ══════════════════════════════════════════════════════════════════════════════
   ARCHIV VIEW
   ══════════════════════════════════════════════════════════════════════════════ */
function ArchivView({ toast }: { toast: (m: string, t?: string) => void }) {
  const [kinder, setKinder] = useState<Kind[]>([]);
  const [vergangene, setVergangene] = useState<VergGeschenk[]>([]);
  const [filterKind, setFilterKind] = useState<string>('');
  const [loading, setLoading] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [fKindId, setFKindId] = useState('');
  const [fTitel, setFTitel] = useState('');
  const [fAnlass, setFAnlass] = useState('');
  const [fJahr, setFJahr] = useState(new Date().getFullYear().toString());
  const [fNotizen, setFNotizen] = useState('');

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const [k, v] = await Promise.all([
        api.get('/api/geschenkplaner/kinder'),
        api.get('/api/geschenkplaner/vergangene-geschenke'),
      ]);
      setKinder(k); setVergangene(v);
    } catch (e: any) { toast(e.message, 'error'); }
    finally { setLoading(false); }
  }, [toast]);

  useEffect(() => { load(); }, [load]);

  const saveV = async () => {
    try {
      await api.post('/api/geschenkplaner/vergangene-geschenke', {
        kind_id: parseInt(fKindId), titel: fTitel,
        anlass: fAnlass || null, jahr: parseInt(fJahr) || null, notizen: fNotizen || null,
      });
      setShowForm(false); toast('Eingetragen ✅'); load();
    } catch (e: any) { toast(e.message, 'error'); }
  };

  const deleteV = async (id: number) => {
    if (!confirm('Wirklich löschen?')) return;
    try { await api.del(`/api/geschenkplaner/vergangene-geschenke/${id}`); toast('Gelöscht'); load(); }
    catch (e: any) { toast(e.message, 'error'); }
  };

  if (loading) return <div className="flex flex-col items-center py-16"><div className="text-4xl animate-bounce">📦</div></div>;

  const filtered = filterKind ? vergangene.filter(v => v.kind_id === parseInt(filterKind)) : vergangene;

  return (
    <div className="space-y-3 mt-4">
      <div className="flex items-center justify-between">
        <h3 className="text-sm font-bold text-[#1C1C1E]">📦 Vergangene Geschenke ({filtered.length})</h3>
        <button onClick={() => { setShowForm(true); if (kinder.length) setFKindId(kinder[0].id.toString()); }} className="px-3 py-1.5 bg-amber-500 text-white text-xs font-bold rounded-xl transition active:scale-95">+ Hinzufügen</button>
      </div>

      {/* Filter */}
      <select value={filterKind} onChange={e => setFilterKind(e.target.value)} className="bg-[#F2F2F7] rounded-xl px-4 py-2 text-sm outline-none focus:ring-2 focus:ring-amber-400">
        <option value="">Alle Kinder</option>
        {kinder.map(k => <option key={k.id} value={k.id}>{k.name}</option>)}
      </select>

      {filtered.length === 0 ? (
        <div className="text-center py-8">
          <div className="text-4xl mb-2">📦</div>
          <p className="text-sm text-[#8E8E93]">Noch keine vergangenen Geschenke.</p>
        </div>
      ) : filtered.map(v => (
        <div key={v.id} className="bg-white/70 backdrop-blur-sm rounded-2xl border border-amber-200/40 p-3 shadow-sm flex items-center gap-3">
          <div className="flex-1">
            <p className="text-sm font-bold text-[#1C1C1E]">{v.titel}</p>
            <p className="text-[10px] text-[#636366]">
              👶 {v.kind_name} {v.anlass ? `· ${anlassEmoji[v.anlass]} ${anlassLabel[v.anlass]}` : ''} {v.jahr ? `· ${v.jahr}` : ''}
              {v.notizen ? ` · ${v.notizen}` : ''}
            </p>
          </div>
          <button onClick={() => deleteV(v.id)} className="px-2 py-1 bg-gray-100 text-[10px] rounded-lg hover:bg-red-50 transition active:scale-95">🗑️</button>
        </div>
      ))}

      {showForm && (
        <Modal onClose={() => setShowForm(false)}>
          <h2 className="text-lg font-bold text-[#1C1C1E] mb-4">📦 Vergangenes Geschenk eintragen</h2>
          <div className="space-y-3">
            <div>
              <label className="text-xs font-bold text-[#636366] block mb-1">Kind *</label>
              <select value={fKindId} onChange={e => setFKindId(e.target.value)} className="w-full bg-[#F2F2F7] rounded-xl px-4 py-2.5 text-sm outline-none focus:ring-2 focus:ring-amber-400">
                {kinder.map(k => <option key={k.id} value={k.id}>{k.name}</option>)}
              </select>
            </div>
            <div>
              <label className="text-xs font-bold text-[#636366] block mb-1">Titel *</label>
              <input value={fTitel} onChange={e => setFTitel(e.target.value)} className="w-full bg-[#F2F2F7] rounded-xl px-4 py-2.5 text-sm outline-none focus:ring-2 focus:ring-amber-400" />
            </div>
            <div className="grid grid-cols-2 gap-2">
              <div>
                <label className="text-xs font-bold text-[#636366] block mb-1">Anlass</label>
                <select value={fAnlass} onChange={e => setFAnlass(e.target.value)} className="w-full bg-[#F2F2F7] rounded-xl px-4 py-2.5 text-sm outline-none focus:ring-2 focus:ring-amber-400">
                  <option value="">–</option>
                  <option value="geburtstag">Geburtstag</option>
                  <option value="ostern">Ostern</option>
                  <option value="weihnachten">Weihnachten</option>
                </select>
              </div>
              <div>
                <label className="text-xs font-bold text-[#636366] block mb-1">Jahr</label>
                <input type="number" value={fJahr} onChange={e => setFJahr(e.target.value)} className="w-full bg-[#F2F2F7] rounded-xl px-4 py-2.5 text-sm outline-none focus:ring-2 focus:ring-amber-400" />
              </div>
            </div>
            <div>
              <label className="text-xs font-bold text-[#636366] block mb-1">Notizen</label>
              <textarea value={fNotizen} onChange={e => setFNotizen(e.target.value)} rows={2} className="w-full bg-[#F2F2F7] rounded-xl px-4 py-2.5 text-sm outline-none focus:ring-2 focus:ring-amber-400 resize-none" />
            </div>
            <div className="flex gap-2 pt-1">
              <button onClick={saveV} disabled={!fKindId || !fTitel} className="flex-1 py-2.5 bg-amber-500 text-white text-sm font-bold rounded-xl transition active:scale-95 disabled:opacity-50">✅ Speichern</button>
              <button onClick={() => setShowForm(false)} className="px-4 py-2.5 bg-gray-100 text-gray-500 text-sm rounded-xl transition active:scale-95">✕</button>
            </div>
          </div>
        </Modal>
      )}
    </div>
  );
}
