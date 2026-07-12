'use client';

import { useState, useEffect, useCallback } from 'react';
import Link from 'next/link';

interface Lebensmittel {
  id: number;
  name: string;
  marke?: string;
  kategorie: 'trocken' | 'kuehlschrank' | 'gefrierfach';
  menge?: string;
  mhd?: string;
  bild_pfad?: string;
  status: 'aktiv' | 'verbraucht';
  restock: number;
  erfasst_am: string;
  verbraucht_am?: string;
  notizen?: string;
}

interface Stats {
  total: number;
  trocken: number;
  kuehlschrank: number;
  gefrierfach: number;
  ablaufend: number;
  einkaufsliste: number;
}

interface Rezept {
  id: number;
  titel: string;
  url?: string;
  quelle?: string;
  beschreibung?: string;
  zutaten_match?: string;
  bild_url?: string;
  erstellt_am: string;
  notizen?: string;
}

const KATEGORIE_LABELS: Record<string, { label: string; emoji: string }> = {
  trocken: { label: 'Trocken', emoji: '🗄️' },
  kuehlschrank: { label: 'Kühlschrank', emoji: '❄️' },
  gefrierfach: { label: 'Gefrierfach', emoji: '🧊' },
};

function getMhdColor(mhd?: string): string {
  if (!mhd) return '';
  const now = new Date();
  const mhdDate = new Date(mhd + 'T00:00:00');
  const diffDays = Math.ceil((mhdDate.getTime() - now.getTime()) / 86400000);
  if (diffDays < 0) return 'bg-red-900 text-white';
  if (diffDays < 7) return 'bg-red-500 text-white';
  if (diffDays <= 30) return 'bg-yellow-400 text-black';
  return 'bg-green-500 text-white';
}

function getMhdLabel(mhd?: string): string {
  if (!mhd) return '';
  const now = new Date();
  const mhdDate = new Date(mhd + 'T00:00:00');
  const diffDays = Math.ceil((mhdDate.getTime() - now.getTime()) / 86400000);
  if (diffDays < 0) return `${Math.abs(diffDays)}d abgelaufen!`;
  if (diffDays === 0) return 'Heute!';
  if (diffDays === 1) return 'Morgen';
  return `${diffDays} Tage`;
}

function formatDate(d: string): string {
  return new Date(d).toLocaleDateString('de-DE', { day: '2-digit', month: '2-digit', year: 'numeric' });
}

export default function VorratskammerPage() {
  const [tab, setTab] = useState<'vorrat' | 'einkauf' | 'ablaufend' | 'rezepte'>('vorrat');
  const [items, setItems] = useState<Lebensmittel[]>([]);
  const [einkaufsliste, setEinkaufsliste] = useState<Lebensmittel[]>([]);
  const [ablaufend, setAblaufend] = useState<Lebensmittel[]>([]);
  const [rezepte, setRezepte] = useState<Rezept[]>([]);
  const [stats, setStats] = useState<Stats | null>(null);
  const [search, setSearch] = useState('');
  const [loading, setLoading] = useState(true);
  const [editItem, setEditItem] = useState<Lebensmittel | null>(null);
  const [showAdd, setShowAdd] = useState(false);
  const [deleteConfirm, setDeleteConfirm] = useState<number | null>(null);

  const fetchAll = useCallback(async () => {
    setLoading(true);
    try {
      const [itemsRes, statsRes, einkaufRes, ablaufRes, rezepteRes] = await Promise.all([
        fetch(`/api/vorratskammer?status=aktiv${search ? `&search=${encodeURIComponent(search)}` : ''}`),
        fetch('/api/vorratskammer?stats=true'),
        fetch('/api/vorratskammer?einkaufsliste=true'),
        fetch('/api/vorratskammer?ablaufend=true&tage=14'),
        fetch('/api/vorratskammer/rezepte'),
      ]);
      setItems(await itemsRes.json());
      setStats(await statsRes.json());
      setEinkaufsliste(await einkaufRes.json());
      setAblaufend(await ablaufRes.json());
      setRezepte(await rezepteRes.json());
    } catch (e) {
      console.error('Fetch error:', e);
    }
    setLoading(false);
  }, [search]);

  useEffect(() => { fetchAll(); }, [fetchAll]);

  const handleVerbraucht = async (id: number) => {
    await fetch(`/api/vorratskammer/${id}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ status: 'verbraucht' }),
    });
    fetchAll();
  };

  const handleWiederDa = async (id: number) => {
    await fetch(`/api/vorratskammer/${id}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ status: 'aktiv', verbraucht_am: null }),
    });
    fetchAll();
  };

  const handleKeinRestock = async (id: number) => {
    await fetch(`/api/vorratskammer/${id}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ restock: 0 }),
    });
    fetchAll();
  };

  const handleDelete = async (id: number) => {
    await fetch(`/api/vorratskammer/${id}`, { method: 'DELETE' });
    setDeleteConfirm(null);
    fetchAll();
  };

  const grouped = items.reduce((acc, item) => {
    if (!acc[item.kategorie]) acc[item.kategorie] = [];
    acc[item.kategorie].push(item);
    return acc;
  }, {} as Record<string, Lebensmittel[]>);

  return (
    <main className="min-h-[100dvh] bg-[#F2F2F7]">
      {/* Header */}
      <header className="bg-gradient-to-r from-[#F97316] via-[#FB923C] to-[#FBBF24] pt-10 pb-4 px-4 safe-area-inset">
        <div className="max-w-3xl mx-auto">
          <Link href="/" className="text-white/80 text-xs font-medium mb-1 block">← Portal</Link>
          <h1 className="text-2xl font-extrabold text-white tracking-tight">🍕🗄️ Vorratskammer</h1>
          {stats && (
            <p className="text-white/80 text-xs mt-1">
              {stats.total} Produkte · {stats.einkaufsliste} auf Einkaufsliste · {stats.ablaufend} bald ablaufend
            </p>
          )}
        </div>
      </header>

      <div className="max-w-3xl mx-auto px-3 -mt-2">
        {/* Tabs */}
        <div className="flex gap-1 bg-white/80 backdrop-blur-md rounded-xl p-1 shadow-sm border border-black/5">
          {([
            { key: 'vorrat', label: '🗄️ Vorrat', count: stats?.total },
            { key: 'einkauf', label: '🛒 Einkauf', count: stats?.einkaufsliste },
            { key: 'ablaufend', label: '⚠️ Ablaufend', count: stats?.ablaufend },
            { key: 'rezepte', label: '🍳 Rezepte', count: rezepte.length || undefined },
          ] as const).map(t => (
            <button
              key={t.key}
              onClick={() => setTab(t.key)}
              className={`flex-1 py-2 px-2 rounded-lg text-xs font-bold transition-all ${
                tab === t.key
                  ? 'bg-gradient-to-r from-[#F97316] to-[#FBBF24] text-white shadow-sm'
                  : 'text-[#8E8E93]'
              }`}
            >
              {t.label} {t.count !== undefined && t.count > 0 ? `(${t.count})` : ''}
            </button>
          ))}
        </div>

        {/* Search + Add (Vorrat tab) */}
        {tab === 'vorrat' && (
          <div className="flex gap-2 mt-3">
            <input
              type="text"
              placeholder="Suchen..."
              value={search}
              onChange={e => setSearch(e.target.value)}
              className="flex-1 bg-white rounded-xl px-3 py-2 text-sm border border-black/5 shadow-sm outline-none focus:ring-2 focus:ring-orange-300"
            />
            <button
              onClick={() => { setEditItem(null); setShowAdd(true); }}
              className="bg-gradient-to-r from-[#F97316] to-[#FBBF24] text-white px-4 py-2 rounded-xl text-sm font-bold shadow-sm active:scale-95 transition-transform"
            >
              + Neu
            </button>
          </div>
        )}

        {/* Content */}
        <div className="mt-3 pb-8 space-y-3">
          {loading ? (
            <div className="text-center py-12 text-[#8E8E93]">Laden...</div>
          ) : tab === 'vorrat' ? (
            Object.keys(grouped).length === 0 ? (
              <div className="text-center py-12 text-[#8E8E93]">
                <div className="text-4xl mb-2">🗄️</div>
                <p className="text-sm">Noch keine Lebensmittel erfasst</p>
              </div>
            ) : (
              ['trocken', 'kuehlschrank', 'gefrierfach'].map(kat => {
                const katItems = grouped[kat];
                if (!katItems || katItems.length === 0) return null;
                const info = KATEGORIE_LABELS[kat];
                return (
                  <div key={kat}>
                    <h2 className="text-xs font-bold text-[#8E8E93] uppercase tracking-wider mb-1.5 px-1">
                      {info.emoji} {info.label} ({katItems.length})
                    </h2>
                    <div className="space-y-1.5">
                      {katItems.map(item => (
                        <ItemCard
                          key={item.id}
                          item={item}
                          onVerbraucht={() => handleVerbraucht(item.id)}
                          onEdit={() => { setEditItem(item); setShowAdd(true); }}
                          onDelete={() => setDeleteConfirm(item.id)}
                        />
                      ))}
                    </div>
                  </div>
                );
              })
            )
          ) : tab === 'einkauf' ? (
            einkaufsliste.length === 0 ? (
              <div className="text-center py-12 text-[#8E8E93]">
                <div className="text-4xl mb-2">🛒</div>
                <p className="text-sm">Einkaufsliste ist leer — alles da!</p>
              </div>
            ) : (
              <div className="space-y-1.5">
                {einkaufsliste.map(item => (
                  <div key={item.id} className="bg-white rounded-2xl p-3 shadow-sm border border-black/5">
                    <div className="flex items-center gap-3">
                      {item.bild_pfad && (
                        <img src={`/api/v1/media/${item.bild_pfad.replace('images/', '')}`} alt="" className="w-10 h-10 rounded-lg object-cover" />
                      )}
                      <div className="flex-1 min-w-0">
                        <p className="font-bold text-sm text-[#1C1C1E] truncate">{item.name}</p>
                        {item.marke && <p className="text-xs text-[#8E8E93]">{item.marke}</p>}
                        {item.menge && <p className="text-xs text-[#8E8E93]">{item.menge}</p>}
                      </div>
                      <div className="flex gap-1.5 shrink-0">
                        <button
                          onClick={() => handleWiederDa(item.id)}
                          className="bg-green-500 text-white px-2.5 py-1.5 rounded-lg text-[10px] font-bold active:scale-95 transition-transform"
                        >
                          Wieder da!
                        </button>
                        <button
                          onClick={() => handleKeinRestock(item.id)}
                          className="bg-[#8E8E93] text-white px-2.5 py-1.5 rounded-lg text-[10px] font-bold active:scale-95 transition-transform"
                        >
                          Kein Restock
                        </button>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            )
          ) : tab === 'ablaufend' ? (
            ablaufend.length === 0 ? (
              <div className="text-center py-12 text-[#8E8E93]">
                <div className="text-4xl mb-2">✅</div>
                <p className="text-sm">Nichts läuft demnächst ab!</p>
              </div>
            ) : (
              <div className="space-y-1.5">
                {ablaufend.map(item => (
                  <div key={item.id} className="bg-white rounded-2xl p-3 shadow-sm border border-black/5">
                    <div className="flex items-center gap-3">
                      {item.bild_pfad && (
                        <img src={`/api/v1/media/${item.bild_pfad.replace('images/', '')}`} alt="" className="w-10 h-10 rounded-lg object-cover" />
                      )}
                      <div className="flex-1 min-w-0">
                        <p className="font-bold text-sm text-[#1C1C1E] truncate">{item.name}</p>
                        {item.marke && <p className="text-xs text-[#8E8E93]">{item.marke}</p>}
                        <p className="text-xs text-[#8E8E93]">{KATEGORIE_LABELS[item.kategorie]?.emoji} {KATEGORIE_LABELS[item.kategorie]?.label}</p>
                      </div>
                      <div className="text-right shrink-0">
                        {item.mhd && (
                          <>
                            <span className={`inline-block px-2 py-0.5 rounded-full text-[10px] font-bold ${getMhdColor(item.mhd)}`}>
                              {getMhdLabel(item.mhd)}
                            </span>
                            <p className="text-[10px] text-[#8E8E93] mt-0.5">MHD: {formatDate(item.mhd)}</p>
                          </>
                        )}
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            )
          ) : tab === 'rezepte' ? (
            rezepte.length === 0 ? (
              <div className="text-center py-12 text-[#8E8E93]">
                <div className="text-4xl mb-2">🍳</div>
                <p className="text-sm">Noch keine Rezeptvorschläge</p>
                <p className="text-xs mt-1">Sobald Lebensmittel mit MHD erfasst sind, recherchiere ich passende Rezepte!</p>
              </div>
            ) : (
              <div className="space-y-2">
                {rezepte.map(rezept => (
                  <a
                    key={rezept.id}
                    href={rezept.url || '#'}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="block bg-white rounded-2xl shadow-sm border border-black/5 overflow-hidden active:scale-[0.98] transition-transform"
                  >
                    <div className="flex gap-3 p-3">
                      {rezept.bild_url && (
                        <img
                          src={rezept.bild_url}
                          alt=""
                          className="w-16 h-16 rounded-xl object-cover shrink-0"
                          onError={e => (e.currentTarget.style.display = 'none')}
                        />
                      )}
                      <div className="flex-1 min-w-0">
                        <p className="font-bold text-sm text-[#1C1C1E] leading-tight">{rezept.titel}</p>
                        {rezept.quelle && (
                          <p className="text-[10px] text-orange-500 font-semibold mt-0.5">{rezept.quelle}</p>
                        )}
                        {rezept.beschreibung && (
                          <p className="text-xs text-[#8E8E93] mt-1 line-clamp-2">{rezept.beschreibung}</p>
                        )}
                        {rezept.zutaten_match && (
                          <div className="flex flex-wrap gap-1 mt-1.5">
                            {rezept.zutaten_match.split(',').map((z, i) => (
                              <span key={i} className="bg-orange-100 text-orange-700 text-[10px] font-semibold px-1.5 py-0.5 rounded-full">
                                {z.trim()}
                              </span>
                            ))}
                          </div>
                        )}
                      </div>
                      <div className="shrink-0 flex items-center">
                        <svg className="w-4 h-4 text-[#C7C7CC]" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                          <path strokeLinecap="round" strokeLinejoin="round" d="M9 5l7 7-7 7" />
                        </svg>
                      </div>
                    </div>
                  </a>
                ))}
              </div>
            )
          ) : null}
        </div>
      </div>

      {/* Delete Confirm Modal */}
      {deleteConfirm !== null && (
        <div className="fixed inset-0 bg-black/40 backdrop-blur-sm z-50 flex items-end sm:items-center justify-center p-4" onClick={() => setDeleteConfirm(null)}>
          <div className="bg-white rounded-2xl p-5 w-full max-w-sm shadow-xl" onClick={e => e.stopPropagation()}>
            <h3 className="text-lg font-bold text-[#1C1C1E] mb-2">Wirklich löschen?</h3>
            <p className="text-sm text-[#8E8E93] mb-4">Das Lebensmittel wird unwiderruflich gelöscht.</p>
            <div className="flex gap-2">
              <button onClick={() => setDeleteConfirm(null)} className="flex-1 py-2.5 rounded-xl bg-[#F2F2F7] text-sm font-bold text-[#1C1C1E]">
                Abbrechen
              </button>
              <button onClick={() => handleDelete(deleteConfirm)} className="flex-1 py-2.5 rounded-xl bg-red-500 text-white text-sm font-bold active:scale-95 transition-transform">
                Löschen
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Add/Edit Modal */}
      {showAdd && (
        <EditModal
          item={editItem}
          onClose={() => { setShowAdd(false); setEditItem(null); }}
          onSave={() => { setShowAdd(false); setEditItem(null); fetchAll(); }}
        />
      )}
    </main>
  );
}

function ItemCard({ item, onVerbraucht, onEdit, onDelete }: {
  item: Lebensmittel;
  onVerbraucht: () => void;
  onEdit: () => void;
  onDelete: () => void;
}) {
  return (
    <div className="bg-white rounded-2xl p-3 shadow-sm border border-black/5">
      <div className="flex items-center gap-3">
        {item.bild_pfad ? (
          <img src={`/api/v1/media/${item.bild_pfad.replace('images/', '')}`} alt="" className="w-12 h-12 rounded-xl object-cover" />
        ) : (
          <div className="w-12 h-12 rounded-xl bg-gradient-to-br from-orange-100 to-yellow-100 flex items-center justify-center text-xl">
            {KATEGORIE_LABELS[item.kategorie]?.emoji || '🍽️'}
          </div>
        )}
        <div className="flex-1 min-w-0">
          <p className="font-bold text-sm text-[#1C1C1E] truncate">{item.name}</p>
          <div className="flex items-center gap-2 flex-wrap">
            {item.marke && <span className="text-xs text-[#8E8E93]">{item.marke}</span>}
            {item.menge && <span className="text-xs text-[#8E8E93]">· {item.menge}</span>}
          </div>
          {item.mhd && (
            <span className={`inline-block mt-0.5 px-1.5 py-0.5 rounded-full text-[10px] font-bold ${getMhdColor(item.mhd)}`}>
              MHD: {formatDate(item.mhd)} ({getMhdLabel(item.mhd)})
            </span>
          )}
        </div>
        <div className="flex gap-1 shrink-0">
          <button onClick={onVerbraucht} className="w-8 h-8 rounded-lg bg-orange-100 flex items-center justify-center text-sm active:scale-90 transition-transform" title="Verbraucht">✅</button>
          <button onClick={onEdit} className="w-8 h-8 rounded-lg bg-blue-100 flex items-center justify-center text-sm active:scale-90 transition-transform" title="Bearbeiten">✏️</button>
          <button onClick={onDelete} className="w-8 h-8 rounded-lg bg-red-100 flex items-center justify-center text-sm active:scale-90 transition-transform" title="Löschen">🗑️</button>
        </div>
      </div>
    </div>
  );
}

function EditModal({ item, onClose, onSave }: {
  item: Lebensmittel | null;
  onClose: () => void;
  onSave: () => void;
}) {
  const [form, setForm] = useState({
    name: item?.name || '',
    marke: item?.marke || '',
    kategorie: item?.kategorie || 'trocken',
    menge: item?.menge || '',
    mhd: item?.mhd || '',
    restock: item?.restock ?? 1,
    notizen: item?.notizen || '',
  });
  const [saving, setSaving] = useState(false);

  const handleSave = async () => {
    if (!form.name.trim()) return;
    setSaving(true);
    try {
      if (item) {
        await fetch(`/api/vorratskammer/${item.id}`, {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(form),
        });
      } else {
        await fetch('/api/vorratskammer', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(form),
        });
      }
      onSave();
    } catch (e) {
      console.error(e);
    }
    setSaving(false);
  };

  return (
    <div className="fixed inset-0 bg-black/40 backdrop-blur-sm z-50 flex items-end sm:items-center justify-center" onClick={onClose}>
      <div className="bg-white rounded-t-3xl sm:rounded-2xl p-5 w-full max-w-md shadow-xl max-h-[90vh] overflow-y-auto" onClick={e => e.stopPropagation()}>
        <h3 className="text-lg font-bold text-[#1C1C1E] mb-4">
          {item ? 'Bearbeiten' : 'Neues Lebensmittel'}
        </h3>

        <div className="space-y-3">
          <div>
            <label className="text-xs font-bold text-[#8E8E93] block mb-1">Name *</label>
            <input
              type="text"
              value={form.name}
              onChange={e => setForm(f => ({ ...f, name: e.target.value }))}
              className="w-full bg-[#F2F2F7] rounded-xl px-3 py-2.5 text-sm outline-none focus:ring-2 focus:ring-orange-300"
              placeholder="z.B. Nudeln, Milch..."
            />
          </div>

          <div>
            <label className="text-xs font-bold text-[#8E8E93] block mb-1">Marke</label>
            <input
              type="text"
              value={form.marke}
              onChange={e => setForm(f => ({ ...f, marke: e.target.value }))}
              className="w-full bg-[#F2F2F7] rounded-xl px-3 py-2.5 text-sm outline-none focus:ring-2 focus:ring-orange-300"
              placeholder="z.B. Barilla, Alpro..."
            />
          </div>

          <div>
            <label className="text-xs font-bold text-[#8E8E93] block mb-1">Kategorie *</label>
            <select
              value={form.kategorie}
              onChange={e => setForm(f => ({ ...f, kategorie: e.target.value as 'trocken' | 'kuehlschrank' | 'gefrierfach' }))}
              className="w-full bg-[#F2F2F7] rounded-xl px-3 py-2.5 text-sm outline-none focus:ring-2 focus:ring-orange-300"
            >
              <option value="trocken">🗄️ Trocken</option>
              <option value="kuehlschrank">❄️ Kühlschrank</option>
              <option value="gefrierfach">🧊 Gefrierfach</option>
            </select>
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="text-xs font-bold text-[#8E8E93] block mb-1">Menge</label>
              <input
                type="text"
                value={form.menge}
                onChange={e => setForm(f => ({ ...f, menge: e.target.value }))}
                className="w-full bg-[#F2F2F7] rounded-xl px-3 py-2.5 text-sm outline-none focus:ring-2 focus:ring-orange-300"
                placeholder="z.B. 500g, 2 Stk"
              />
            </div>
            <div>
              <label className="text-xs font-bold text-[#8E8E93] block mb-1">MHD</label>
              <input
                type="date"
                value={form.mhd}
                onChange={e => setForm(f => ({ ...f, mhd: e.target.value }))}
                className="w-full bg-[#F2F2F7] rounded-xl px-3 py-2.5 text-sm outline-none focus:ring-2 focus:ring-orange-300"
              />
            </div>
          </div>

          <div className="flex items-center justify-between bg-[#F2F2F7] rounded-xl px-3 py-2.5">
            <span className="text-sm text-[#1C1C1E]">Nachkaufen wenn leer</span>
            <button
              onClick={() => setForm(f => ({ ...f, restock: f.restock ? 0 : 1 }))}
              className={`w-12 h-7 rounded-full transition-colors relative ${form.restock ? 'bg-orange-500' : 'bg-[#D1D1D6]'}`}
            >
              <div className={`w-5 h-5 bg-white rounded-full shadow absolute top-1 transition-all ${form.restock ? 'right-1' : 'left-1'}`} />
            </button>
          </div>

          <div>
            <label className="text-xs font-bold text-[#8E8E93] block mb-1">Notizen</label>
            <textarea
              value={form.notizen}
              onChange={e => setForm(f => ({ ...f, notizen: e.target.value }))}
              className="w-full bg-[#F2F2F7] rounded-xl px-3 py-2.5 text-sm outline-none focus:ring-2 focus:ring-orange-300 min-h-[60px]"
              placeholder="Optionale Notizen..."
            />
          </div>
        </div>

        <div className="flex gap-2 mt-5">
          <button onClick={onClose} className="flex-1 py-2.5 rounded-xl bg-[#F2F2F7] text-sm font-bold text-[#1C1C1E]">
            Abbrechen
          </button>
          <button
            onClick={handleSave}
            disabled={!form.name.trim() || saving}
            className="flex-1 py-2.5 rounded-xl bg-gradient-to-r from-[#F97316] to-[#FBBF24] text-white text-sm font-bold active:scale-95 transition-transform disabled:opacity-50"
          >
            {saving ? 'Speichern...' : item ? 'Speichern' : 'Hinzufügen'}
          </button>
        </div>
      </div>
    </div>
  );
}
