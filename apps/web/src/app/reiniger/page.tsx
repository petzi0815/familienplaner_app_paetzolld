'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import type { ReactNode } from 'react';
import Link from 'next/link';

interface Reiniger {
  id: number;
  name: string;
  marke?: string;
  kategorie: string;
  einsatzorte?: string;
  geeignet_fuer?: string;
  nicht_geeignet_fuer?: string;
  flecken?: string;
  pflegehinweise?: string;
  sicherheit?: string;
  dosierung?: string;
  menge?: string;
  bild_pfad?: string;
  status: 'aktiv' | 'leer' | 'nachkaufen' | 'entsorgt';
  restock: number;
  quelle_url?: string;
  notizen?: string;
}

interface Anwendung {
  id: number;
  reiniger_id: number;
  problem: string;
  material?: string;
  oberflaeche?: string;
  fleck_art?: string;
  anwendungsfall?: string;
  anleitung: string;
  begruendung?: string;
  warnhinweise?: string;
  prioritaet: number;
  produkt_name?: string;
  produkt_marke?: string;
  produkt_kategorie?: string;
  produkt_bild_pfad?: string;
  produkt_quelle_url?: string;
}

interface Stats {
  active: number;
  restock: number;
  useCases: number;
  categories: { kategorie: string; count: number }[];
}

const CATEGORIES: Record<string, { label: string; emoji: string; color: string }> = {
  allzweck: { label: 'Allzweck', emoji: '🧽', color: 'bg-sky-100 text-sky-700' },
  bad: { label: 'Bad', emoji: '🚿', color: 'bg-cyan-100 text-cyan-700' },
  kueche: { label: 'Küche', emoji: '🍳', color: 'bg-amber-100 text-amber-700' },
  boden: { label: 'Boden', emoji: '🪣', color: 'bg-emerald-100 text-emerald-700' },
  waesche: { label: 'Wäsche', emoji: '👕', color: 'bg-violet-100 text-violet-700' },
  flecken: { label: 'Flecken', emoji: '🎯', color: 'bg-rose-100 text-rose-700' },
  pflege: { label: 'Pflege', emoji: '✨', color: 'bg-lime-100 text-lime-700' },
  spezial: { label: 'Spezial', emoji: '🧴', color: 'bg-slate-100 text-slate-700' },
  holzpflege_fleckentferner: { label: 'Holz-Flecken', emoji: '🪵', color: 'bg-orange-100 text-orange-800' },
  holzpflege_tannin_fleckentferner: { label: 'Tannin/Holz', emoji: '🪵', color: 'bg-yellow-100 text-yellow-800' },
  scheuermilch_saeure_reiniger: { label: 'Säure/Scheuer', emoji: '🧴', color: 'bg-rose-100 text-rose-700' },
  kochfeldreiniger_glaskeramik_politur: { label: 'Kochfeld', emoji: '♨️', color: 'bg-zinc-100 text-zinc-700' },
  outdoor: { label: 'Outdoor', emoji: '🏡', color: 'bg-green-100 text-green-800' },
  stein: { label: 'Stein', emoji: '🧱', color: 'bg-stone-100 text-stone-700' },
  terrasse: { label: 'Terrasse', emoji: '🏡', color: 'bg-emerald-100 text-emerald-800' },
};

const STATUS_LABELS: Record<string, string> = {
  aktiv: 'Da',
  leer: 'Leer',
  nachkaufen: 'Nachkaufen',
  entsorgt: 'Entsorgt',
};

export default function ReinigerPage() {
  const [tab, setTab] = useState<'inventar' | 'ratgeber' | 'einkauf'>('inventar');
  const [items, setItems] = useState<Reiniger[]>([]);
  const [anwendungen, setAnwendungen] = useState<Anwendung[]>([]);
  const [stats, setStats] = useState<Stats | null>(null);
  const [search, setSearch] = useState('');
  const [loading, setLoading] = useState(true);
  const [showAdd, setShowAdd] = useState(false);
  const [editItem, setEditItem] = useState<Reiniger | null>(null);
  const [selectedItem, setSelectedItem] = useState<Reiniger | null>(null);
  const [deleteConfirm, setDeleteConfirm] = useState<number | null>(null);

  const fetchAll = useCallback(async () => {
    setLoading(true);
    const query = search ? `&search=${encodeURIComponent(search)}` : '';
    try {
      const [itemsRes, statsRes, appsRes] = await Promise.all([
        fetch(`/api/reiniger?${query.slice(1)}`),
        fetch('/api/reiniger?stats=true'),
        fetch(`/api/reiniger?anwendungen=true${query}`),
      ]);
      const [nextItems, nextStats, nextAnwendungen] = await Promise.all([
        itemsRes.json(),
        statsRes.json(),
        appsRes.json(),
      ]);
      setItems(Array.isArray(nextItems) ? nextItems : []);
      setStats(nextStats && !nextStats.error ? nextStats : null);
      setAnwendungen(Array.isArray(nextAnwendungen) ? nextAnwendungen : []);
    } catch (error) {
      console.error(error);
    }
    setLoading(false);
  }, [search]);

  useEffect(() => { fetchAll(); }, [fetchAll]);

  const restockItems = useMemo(
    () => items.filter(item => item.restock && ['leer', 'nachkaufen'].includes(item.status)),
    [items]
  );

  const grouped = useMemo(() => items.reduce((acc, item) => {
    if (item.status === 'entsorgt') return acc;
    if (!acc[item.kategorie]) acc[item.kategorie] = [];
    acc[item.kategorie].push(item);
    return acc;
  }, {} as Record<string, Reiniger[]>), [items]);

  const updateStatus = async (id: number, status: Reiniger['status']) => {
    await fetch(`/api/reiniger/${id}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ status }),
    });
    fetchAll();
  };

  const handleDelete = async (id: number) => {
    await fetch(`/api/reiniger/${id}`, { method: 'DELETE' });
    setDeleteConfirm(null);
    fetchAll();
  };

  return (
    <main className="min-h-[100dvh] bg-[#F2F2F7]">
      <header className="bg-gradient-to-r from-[#0EA5E9] via-[#14B8A6] to-[#84CC16] pt-10 pb-4 px-4 safe-area-inset">
        <div className="max-w-3xl mx-auto">
          <Link href="/" className="text-white/80 text-xs font-medium mb-1 block">← Portal</Link>
          <h1 className="text-2xl font-extrabold text-white tracking-tight">🧽 Reiniger & Putzmittel</h1>
          {stats && (
            <p className="text-white/85 text-xs mt-1">
              {stats.active} Produkte · {stats.useCases} Anwendungsfälle · {stats.restock} nachkaufen
            </p>
          )}
        </div>
      </header>

      <div className="max-w-3xl mx-auto px-3 -mt-2">
        <div className="flex gap-1 bg-white/80 backdrop-blur-md rounded-xl p-1 shadow-sm border border-black/5">
          {([
            { key: 'inventar', label: '🧴 Inventar', count: stats?.active },
            { key: 'ratgeber', label: '🎯 Flecken', count: anwendungen.length || undefined },
            { key: 'einkauf', label: '🛒 Einkauf', count: restockItems.length || undefined },
          ] as const).map(t => (
            <button
              key={t.key}
              onClick={() => setTab(t.key)}
              className={`flex-1 py-2 px-2 rounded-lg text-xs font-bold transition-all ${
                tab === t.key
                  ? 'bg-gradient-to-r from-[#0EA5E9] to-[#84CC16] text-white shadow-sm'
                  : 'text-[#8E8E93]'
              }`}
            >
              {t.label} {t.count ? `(${t.count})` : ''}
            </button>
          ))}
        </div>

        <div className="flex gap-2 mt-3">
          <input
            type="text"
            value={search}
            onChange={e => setSearch(e.target.value)}
            placeholder={tab === 'ratgeber' ? 'Fleck, Material oder Pflege suchen...' : 'Produkt, Marke, Oberfläche suchen...'}
            className="flex-1 bg-white rounded-xl px-3 py-2 text-sm border border-black/5 shadow-sm outline-none focus:ring-2 focus:ring-teal-300"
          />
          {tab === 'inventar' && (
            <button
              onClick={() => { setEditItem(null); setShowAdd(true); }}
              className="bg-gradient-to-r from-[#0EA5E9] to-[#84CC16] text-white px-4 py-2 rounded-xl text-sm font-bold shadow-sm active:scale-95 transition-transform"
            >
              + Neu
            </button>
          )}
        </div>

        <div className="mt-3 pb-8 space-y-3">
          {loading ? (
            <div className="text-center py-12 text-[#8E8E93]">Laden...</div>
          ) : tab === 'inventar' ? (
            Object.keys(grouped).length === 0 ? (
              <EmptyState emoji="🧽" text="Noch keine Reiniger erfasst" />
            ) : (
              Object.entries(grouped).map(([category, categoryItems]) => {
                const meta = CATEGORIES[category] || CATEGORIES.spezial;
                return (
                  <section key={category}>
                    <h2 className="text-xs font-bold text-[#8E8E93] uppercase tracking-wider mb-1.5 px-1">
                      {meta.emoji} {meta.label} ({categoryItems.length})
                    </h2>
                    <div className="space-y-1.5">
                      {categoryItems.map(item => (
                        <ReinigerCard
                          key={item.id}
                          item={item}
                          onOpen={() => setSelectedItem(item)}
                        />
                      ))}
                    </div>
                  </section>
                );
              })
            )
          ) : tab === 'ratgeber' ? (
          <GuideView items={items} anwendungen={anwendungen} />
          ) : restockItems.length === 0 ? (
            <EmptyState emoji="🛒" text="Keine Putzmittel auf der Einkaufsliste" />
          ) : (
            <div className="space-y-1.5">
              {restockItems.map(item => (
                <div key={item.id} className="bg-white rounded-2xl p-3 shadow-sm border border-black/5 flex items-center gap-3">
                  <ProductImage item={item} size="small" />
                  <div className="flex-1 min-w-0">
                    <p className="font-bold text-sm text-[#1C1C1E] truncate">{item.name}</p>
                    <p className="text-xs text-[#8E8E93] truncate">{[item.marke, item.menge].filter(Boolean).join(' · ')}</p>
                  </div>
                  <button
                    onClick={() => updateStatus(item.id, 'aktiv')}
                    className="bg-green-500 text-white px-2.5 py-1.5 rounded-lg text-[10px] font-bold active:scale-95 transition-transform"
                  >
                    Wieder da
                  </button>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>

      {deleteConfirm !== null && (
        <ConfirmDelete onCancel={() => setDeleteConfirm(null)} onDelete={() => handleDelete(deleteConfirm)} />
      )}

      {selectedItem && (
        <DetailModal
          item={selectedItem}
          anwendungen={anwendungen.filter(app => app.reiniger_id === selectedItem.id)}
          onClose={() => setSelectedItem(null)}
          onEdit={() => { setEditItem(selectedItem); setSelectedItem(null); setShowAdd(true); }}
          onEmpty={() => { updateStatus(selectedItem.id, 'leer'); setSelectedItem(null); }}
          onBuy={() => { updateStatus(selectedItem.id, 'nachkaufen'); setSelectedItem(null); }}
          onDelete={() => { setDeleteConfirm(selectedItem.id); setSelectedItem(null); }}
        />
      )}

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

function imageSrc(pathValue?: string) {
  return pathValue ? `/api/v1/media/${pathValue.replace('images/', '')}` : undefined;
}

function ProductImage({ item, size = 'normal' }: { item: Pick<Reiniger, 'kategorie' | 'bild_pfad'>; size?: 'small' | 'normal' | 'large' }) {
  const cls = size === 'small' ? 'w-10 h-10' : size === 'large' ? 'w-full h-56' : 'w-16 h-16';
  const meta = CATEGORIES[item.kategorie] || CATEGORIES.spezial;
  if (item.bild_pfad) {
    return <img src={imageSrc(item.bild_pfad)} alt="" className={`${cls} rounded-xl object-cover shrink-0 bg-[#F2F2F7]`} />;
  }
  return (
    <div className={`${cls} rounded-xl bg-gradient-to-br from-sky-100 to-lime-100 flex items-center justify-center text-xl shrink-0`}>
      {meta.emoji}
    </div>
  );
}

function ReinigerCard({ item, onOpen }: {
  item: Reiniger;
  onOpen: () => void;
}) {
  const meta = CATEGORIES[item.kategorie] || CATEGORIES.spezial;
  return (
    <button
      type="button"
      onClick={onOpen}
      className="w-full text-left bg-white rounded-2xl p-3 shadow-sm border border-black/5 active:scale-[0.99] transition-transform"
    >
      <div className="flex items-start gap-3">
        <ProductImage item={item} />
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-1.5 flex-wrap">
            <p className="font-bold text-sm text-[#1C1C1E] line-clamp-2">{item.name}</p>
            <span className={`px-1.5 py-0.5 rounded-full text-[10px] font-bold ${meta.color}`}>{meta.label}</span>
          </div>
          <p className="text-xs text-[#8E8E93] truncate">{[item.marke, item.menge, STATUS_LABELS[item.status]].filter(Boolean).join(' · ')}</p>
          {item.flecken && <p className="text-xs text-[#1C1C1E] mt-1 line-clamp-2">Hilft bei: {item.flecken}</p>}
          {item.geeignet_fuer && <p className="text-xs text-[#8E8E93] mt-0.5 line-clamp-1">Für: {item.geeignet_fuer}</p>}
          {item.nicht_geeignet_fuer && <p className="text-[10px] text-red-500 mt-0.5 line-clamp-1">Nicht für: {item.nicht_geeignet_fuer}</p>}
        </div>
      </div>
    </button>
  );
}

function DetailModal({ item, anwendungen, onClose, onEdit, onEmpty, onBuy, onDelete }: {
  item: Reiniger;
  anwendungen: Anwendung[];
  onClose: () => void;
  onEdit: () => void;
  onEmpty: () => void;
  onBuy: () => void;
  onDelete: () => void;
}) {
  const meta = CATEGORIES[item.kategorie] || CATEGORIES.spezial;
  const sourceUrl = item.quelle_url?.split(/[\s;]+/).find(url => url.startsWith('http'));

  return (
    <div className="fixed inset-0 bg-black/40 backdrop-blur-sm z-50 flex items-end sm:items-center justify-center" onClick={onClose}>
      <div className="bg-white rounded-t-3xl sm:rounded-2xl w-full max-w-md shadow-xl max-h-[92vh] overflow-y-auto" onClick={e => e.stopPropagation()}>
        <div className="p-4 border-b border-black/5 flex items-start justify-between gap-3">
          <div className="min-w-0">
            <p className={`inline-flex px-2 py-1 rounded-full text-[10px] font-bold ${meta.color}`}>{meta.label}</p>
            <h3 className="text-lg font-extrabold text-[#1C1C1E] mt-2 leading-tight">{item.name}</h3>
            <p className="text-sm text-[#8E8E93] mt-0.5">{[item.marke, item.menge, STATUS_LABELS[item.status]].filter(Boolean).join(' · ')}</p>
          </div>
          <button onClick={onClose} className="w-9 h-9 rounded-xl bg-[#F2F2F7] text-[#8E8E93] text-lg font-bold shrink-0">×</button>
        </div>

        <div className="p-4 space-y-4">
          <ProductImage item={item} size="large" />

          <DetailSection title="Einsatz">
            {item.einsatzorte && <DetailLine label="Orte" value={item.einsatzorte} />}
            {item.geeignet_fuer && <DetailLine label="Geeignet" value={item.geeignet_fuer} />}
            {item.nicht_geeignet_fuer && <DetailLine label="Nicht geeignet" value={item.nicht_geeignet_fuer} tone="danger" />}
            {item.flecken && <DetailLine label="Hilft bei" value={item.flecken} />}
          </DetailSection>

          {(item.pflegehinweise || item.dosierung || item.sicherheit || item.notizen) && (
            <DetailSection title="Anwendung">
              {item.pflegehinweise && <DetailLine label="Hinweise" value={item.pflegehinweise} />}
              {item.dosierung && <DetailLine label="Dosierung" value={item.dosierung} />}
              {item.sicherheit && <DetailLine label="Sicherheit" value={item.sicherheit} tone="danger" />}
              {item.notizen && <DetailLine label="Notizen" value={item.notizen} />}
            </DetailSection>
          )}

          {anwendungen.length > 0 && (
            <DetailSection title="Verknüpfte Fälle">
              <div className="space-y-2">
                {anwendungen.map(app => (
                  <div key={app.id} className="rounded-xl bg-[#F2F2F7] p-3">
                    <p className="text-sm font-bold text-[#1C1C1E]">{app.fleck_art || app.anwendungsfall || app.problem}</p>
                    {(app.oberflaeche || app.material) && <p className="text-xs text-[#8E8E93] mt-0.5">Auf: {app.oberflaeche || app.material}</p>}
                    {app.begruendung && <p className="text-xs text-[#3A3A3C] mt-1">Warum: {app.begruendung}</p>}
                  </div>
                ))}
              </div>
            </DetailSection>
          )}
        </div>

        <div className="sticky bottom-0 bg-white/95 backdrop-blur border-t border-black/5 p-3 grid grid-cols-2 gap-2">
          {sourceUrl && (
            <a href={sourceUrl} target="_blank" rel="noreferrer" className="py-2.5 rounded-xl bg-[#F2F2F7] text-center text-sm font-bold text-[#1C1C1E]">
              Produktlink
            </a>
          )}
          <button onClick={onEdit} className="py-2.5 rounded-xl bg-blue-500 text-white text-sm font-bold">Bearbeiten</button>
          <button onClick={onBuy} className="py-2.5 rounded-xl bg-green-500 text-white text-sm font-bold">Nachkaufen</button>
          <button onClick={onEmpty} className="py-2.5 rounded-xl bg-amber-500 text-white text-sm font-bold">Leer</button>
          <button onClick={onDelete} className="py-2.5 rounded-xl bg-red-500 text-white text-sm font-bold">Löschen</button>
        </div>
      </div>
    </div>
  );
}

function DetailSection({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section>
      <h4 className="text-xs font-bold text-[#8E8E93] uppercase tracking-wider mb-2">{title}</h4>
      <div className="space-y-2">{children}</div>
    </section>
  );
}

function DetailLine({ label, value, tone }: { label: string; value: string; tone?: 'danger' }) {
  return (
    <div>
      <p className="text-[11px] font-bold text-[#8E8E93]">{label}</p>
      <p className={`text-sm whitespace-pre-line ${tone === 'danger' ? 'text-red-600' : 'text-[#1C1C1E]'}`}>{value}</p>
    </div>
  );
}

function GuideView({ items, anwendungen }: { items: Reiniger[]; anwendungen: Anwendung[] }) {
  const [surface, setSurface] = useState<string>('alle');
  const surfaces = useMemo(() => {
    const values = anwendungen
      .map(app => app.oberflaeche || app.material)
      .filter((value): value is string => Boolean(value?.trim()));
    return ['alle', ...Array.from(new Set(values)).sort((a, b) => a.localeCompare(b, 'de'))];
  }, [anwendungen]);
  const visibleAnwendungen = useMemo(() => {
    if (surface === 'alle') return anwendungen;
    return anwendungen.filter(app => (app.oberflaeche || app.material) === surface);
  }, [anwendungen, surface]);

  if (items.length === 0 && anwendungen.length === 0) {
    return <EmptyState emoji="🎯" text="Noch keine Flecken- oder Pflegehinweise erfasst" />;
  }

  return (
    <div className="space-y-3">
      <section className="bg-white rounded-2xl p-3 shadow-sm border border-black/5">
        <p className="text-xs font-bold text-[#8E8E93] uppercase tracking-wider">1. Oberfläche</p>
        <div className="flex gap-1.5 overflow-x-auto pt-2 pb-0.5">
          {surfaces.map(value => (
            <button
              key={value}
              onClick={() => setSurface(value)}
              className={`shrink-0 px-3 py-1.5 rounded-full text-xs font-bold ${
                surface === value ? 'bg-[#1C1C1E] text-white' : 'bg-[#F2F2F7] text-[#3A3A3C]'
              }`}
            >
              {value === 'alle' ? 'Alle' : value}
            </button>
          ))}
        </div>
      </section>

      <div className="px-1">
        <p className="text-xs font-bold text-[#8E8E93] uppercase tracking-wider">2. Fleck oder Anwendungsfall</p>
      </div>

      {visibleAnwendungen.map(app => {
        const item = items.find(i => i.id === app.reiniger_id);
        const product = item || {
          id: app.reiniger_id,
          name: app.produkt_name || 'Reiniger',
          marke: app.produkt_marke,
          kategorie: app.produkt_kategorie || 'spezial',
          bild_pfad: app.produkt_bild_pfad,
          quelle_url: app.produkt_quelle_url,
        } as Reiniger;
        const sourceUrl = product.quelle_url?.split(/[\s;]+/).find(url => url.startsWith('http'));
        const productHref = sourceUrl || `#produkt-${app.reiniger_id}`;
        const problem = app.fleck_art || app.anwendungsfall || app.problem;
        const surfaceLabel = app.oberflaeche || app.material;
        return (
          <div key={app.id} className="bg-white rounded-2xl p-3 shadow-sm border border-black/5">
            <div className="flex gap-3">
              <ProductImage item={product} size="small" />
              <div className="flex-1 min-w-0">
                <p className="font-bold text-sm text-[#1C1C1E]">{problem}</p>
                {surfaceLabel && <p className="text-xs text-[#8E8E93] mt-0.5">Auf: {surfaceLabel}</p>}
                <a
                  href={productHref}
                  target={sourceUrl ? '_blank' : undefined}
                  rel={sourceUrl ? 'noreferrer' : undefined}
                  className="text-xs text-teal-700 font-bold mt-1 inline-block"
                >
                  Produkt: {[product.marke, product.name].filter(Boolean).join(' ')}
                </a>
              </div>
            </div>
            {app.begruendung && <p className="text-xs text-[#1C1C1E] mt-2">Warum: {app.begruendung}</p>}
            <p className="text-xs text-[#3A3A3C] mt-2 whitespace-pre-line">{app.anleitung}</p>
            {app.warnhinweise && <p className="text-[11px] text-red-500 mt-2">Achtung: {app.warnhinweise}</p>}
          </div>
        );
      })}
      {visibleAnwendungen.length === 0 && (
        <EmptyState emoji="🔎" text="Für diese Oberfläche ist noch kein Fall erfasst" />
      )}
      {items.filter(item => item.flecken || item.pflegehinweise).map(item => (
        <div key={`item-${item.id}`} id={`produkt-${item.id}`} className="bg-white rounded-2xl p-3 shadow-sm border border-black/5">
          <p className="font-bold text-sm text-[#1C1C1E]">{item.name}</p>
          {item.flecken && <p className="text-xs text-[#3A3A3C] mt-1">Flecken: {item.flecken}</p>}
          {item.pflegehinweise && <p className="text-xs text-[#3A3A3C] mt-1">Pflege: {item.pflegehinweise}</p>}
          {item.sicherheit && <p className="text-[11px] text-red-500 mt-1">Sicherheit: {item.sicherheit}</p>}
        </div>
      ))}
    </div>
  );
}

function EmptyState({ emoji, text }: { emoji: string; text: string }) {
  return (
    <div className="text-center py-12 text-[#8E8E93]">
      <div className="text-4xl mb-2">{emoji}</div>
      <p className="text-sm">{text}</p>
    </div>
  );
}

function ConfirmDelete({ onCancel, onDelete }: { onCancel: () => void; onDelete: () => void }) {
  return (
    <div className="fixed inset-0 bg-black/40 backdrop-blur-sm z-50 flex items-end sm:items-center justify-center p-4" onClick={onCancel}>
      <div className="bg-white rounded-2xl p-5 w-full max-w-sm shadow-xl" onClick={e => e.stopPropagation()}>
        <h3 className="text-lg font-bold text-[#1C1C1E] mb-2">Wirklich löschen?</h3>
        <p className="text-sm text-[#8E8E93] mb-4">Der Reiniger wird aus dem Inventar entfernt.</p>
        <div className="flex gap-2">
          <button onClick={onCancel} className="flex-1 py-2.5 rounded-xl bg-[#F2F2F7] text-sm font-bold text-[#1C1C1E]">Abbrechen</button>
          <button onClick={onDelete} className="flex-1 py-2.5 rounded-xl bg-red-500 text-white text-sm font-bold active:scale-95 transition-transform">Löschen</button>
        </div>
      </div>
    </div>
  );
}

function EditModal({ item, onClose, onSave }: { item: Reiniger | null; onClose: () => void; onSave: () => void }) {
  const [form, setForm] = useState({
    name: item?.name || '',
    marke: item?.marke || '',
    kategorie: item?.kategorie || 'allzweck',
    einsatzorte: item?.einsatzorte || '',
    geeignet_fuer: item?.geeignet_fuer || '',
    nicht_geeignet_fuer: item?.nicht_geeignet_fuer || '',
    flecken: item?.flecken || '',
    pflegehinweise: item?.pflegehinweise || '',
    sicherheit: item?.sicherheit || '',
    dosierung: item?.dosierung || '',
    menge: item?.menge || '',
    status: item?.status || 'aktiv',
    restock: item?.restock ?? 1,
    quelle_url: item?.quelle_url || '',
    notizen: item?.notizen || '',
  });
  const [saving, setSaving] = useState(false);

  const handleSave = async () => {
    if (!form.name.trim()) return;
    setSaving(true);
    await fetch(item ? `/api/reiniger/${item.id}` : '/api/reiniger', {
      method: item ? 'PATCH' : 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(form),
    });
    setSaving(false);
    onSave();
  };

  return (
    <div className="fixed inset-0 bg-black/40 backdrop-blur-sm z-50 flex items-end sm:items-center justify-center" onClick={onClose}>
      <div className="bg-white rounded-t-3xl sm:rounded-2xl p-5 w-full max-w-md shadow-xl max-h-[90vh] overflow-y-auto" onClick={e => e.stopPropagation()}>
        <h3 className="text-lg font-bold text-[#1C1C1E] mb-4">{item ? 'Reiniger bearbeiten' : 'Neuer Reiniger'}</h3>
        <div className="space-y-3">
          <TextInput label="Name *" value={form.name} onChange={name => setForm(f => ({ ...f, name }))} placeholder="z.B. Frosch Badreiniger" />
          <TextInput label="Marke" value={form.marke} onChange={marke => setForm(f => ({ ...f, marke }))} placeholder="z.B. Frosch, Dr. Beckmann" />
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="text-xs font-bold text-[#8E8E93] block mb-1">Kategorie</label>
              <select value={form.kategorie} onChange={e => setForm(f => ({ ...f, kategorie: e.target.value }))} className="w-full bg-[#F2F2F7] rounded-xl px-3 py-2.5 text-sm outline-none focus:ring-2 focus:ring-teal-300">
                {Object.entries(CATEGORIES).map(([key, val]) => <option key={key} value={key}>{val.emoji} {val.label}</option>)}
              </select>
            </div>
            <TextInput label="Menge" value={form.menge} onChange={menge => setForm(f => ({ ...f, menge }))} placeholder="750 ml" />
          </div>
          <TextInput label="Einsatzorte" value={form.einsatzorte} onChange={einsatzorte => setForm(f => ({ ...f, einsatzorte }))} placeholder="Bad, Dusche, Armaturen..." />
          <TextInput label="Geeignet für" value={form.geeignet_fuer} onChange={geeignet_fuer => setForm(f => ({ ...f, geeignet_fuer }))} placeholder="Keramik, Edelstahl, Glas..." />
          <TextInput label="Nicht geeignet für" value={form.nicht_geeignet_fuer} onChange={nicht_geeignet_fuer => setForm(f => ({ ...f, nicht_geeignet_fuer }))} placeholder="Naturstein, Marmor..." />
          <TextArea label="Flecken und Probleme" value={form.flecken} onChange={flecken => setForm(f => ({ ...f, flecken }))} placeholder="Kalk, Fett, Wasserflecken..." />
          <TextArea label="Pflege und Anwendung" value={form.pflegehinweise} onChange={pflegehinweise => setForm(f => ({ ...f, pflegehinweise }))} placeholder="Kurz einwirken lassen, mit Wasser nachspülen..." />
          <TextArea label="Sicherheit" value={form.sicherheit} onChange={sicherheit => setForm(f => ({ ...f, sicherheit }))} placeholder="Nicht mit Chlor mischen, Handschuhe..." />
          <TextInput label="Dosierung" value={form.dosierung} onChange={dosierung => setForm(f => ({ ...f, dosierung }))} placeholder="pur, 1 Kappe auf 5 l..." />
          <TextInput label="Quelle / Produktseite" value={form.quelle_url} onChange={quelle_url => setForm(f => ({ ...f, quelle_url }))} placeholder="https://..." />
          <TextArea label="Notizen" value={form.notizen} onChange={notizen => setForm(f => ({ ...f, notizen }))} placeholder="Interne Hinweise..." />
          <div className="flex items-center justify-between bg-[#F2F2F7] rounded-xl px-3 py-2.5">
            <span className="text-sm text-[#1C1C1E]">Nachkaufen wenn leer</span>
            <button onClick={() => setForm(f => ({ ...f, restock: f.restock ? 0 : 1 }))} className={`w-12 h-7 rounded-full transition-colors relative ${form.restock ? 'bg-teal-500' : 'bg-[#D1D1D6]'}`}>
              <div className={`w-5 h-5 bg-white rounded-full shadow absolute top-1 transition-all ${form.restock ? 'right-1' : 'left-1'}`} />
            </button>
          </div>
        </div>
        <div className="flex gap-2 mt-5">
          <button onClick={onClose} className="flex-1 py-2.5 rounded-xl bg-[#F2F2F7] text-sm font-bold text-[#1C1C1E]">Abbrechen</button>
          <button onClick={handleSave} disabled={!form.name.trim() || saving} className="flex-1 py-2.5 rounded-xl bg-gradient-to-r from-[#0EA5E9] to-[#84CC16] text-white text-sm font-bold active:scale-95 transition-transform disabled:opacity-50">
            {saving ? 'Speichern...' : 'Speichern'}
          </button>
        </div>
      </div>
    </div>
  );
}

function TextInput({ label, value, onChange, placeholder }: { label: string; value: string; onChange: (value: string) => void; placeholder?: string }) {
  return (
    <div>
      <label className="text-xs font-bold text-[#8E8E93] block mb-1">{label}</label>
      <input type="text" value={value} onChange={e => onChange(e.target.value)} placeholder={placeholder} className="w-full bg-[#F2F2F7] rounded-xl px-3 py-2.5 text-sm outline-none focus:ring-2 focus:ring-teal-300" />
    </div>
  );
}

function TextArea({ label, value, onChange, placeholder }: { label: string; value: string; onChange: (value: string) => void; placeholder?: string }) {
  return (
    <div>
      <label className="text-xs font-bold text-[#8E8E93] block mb-1">{label}</label>
      <textarea value={value} onChange={e => onChange(e.target.value)} placeholder={placeholder} className="w-full bg-[#F2F2F7] rounded-xl px-3 py-2.5 text-sm outline-none focus:ring-2 focus:ring-teal-300 min-h-[62px]" />
    </div>
  );
}
