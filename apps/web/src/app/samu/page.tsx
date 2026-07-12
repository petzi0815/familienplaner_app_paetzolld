'use client';

import { useState, useEffect, useCallback, Suspense } from 'react';
import { useSearchParams } from 'next/navigation';
import Link from 'next/link';

interface Item {
  id: number;
  typ: string;
  kategorie: string;
  unterkategorie?: string;
  name?: string;
  marke?: string;
  beschreibung?: string;
  groesse?: string;
  altersgruppe?: string;
  zustand?: string;
  verkaufswert?: number;
  farbe?: string;
  saison?: string;
  material?: string;
  status: string;
  bild_pfade?: string;
  erfasst_am: string;
  notizen?: string;
}

interface Stats {
  gesamt: number;
  nach_status: { status: string; count: number }[];
  nach_typ: { typ: string; count: number }[];
  geschaetzter_wert: number;
}

interface Marke {
  id: number;
  name: string;
  groessen_info?: string;
  herkunft?: string;
  material_fokus?: string;
  website?: string;
  preis_segment?: string;
  notizen?: string;
  angereichert_am?: string;
  erstellt_am: string;
}

interface BedarfsItem {
  id: number;
  beschreibung: string;
  kategorie?: string;
  groesse?: string;
  prioritaet: 'hoch' | 'normal' | 'niedrig';
  notizen?: string;
  erledigt: number;
  erledigt_am?: string;
  erstellt_am: string;
  aktualisiert_am: string;
}

const statusConfig: Record<string, { bg: string; text: string; emoji: string; label: string; gradient: string; badge: string }> = {
  aktiv:        { bg: 'bg-green-500/10', text: 'text-green-600', emoji: '🌟', label: 'Aktiv',       gradient: 'from-green-400 to-emerald-500', badge: 'bg-green-600 text-white' },
  eingelagert:  { bg: 'bg-blue-500/10',  text: 'text-blue-600',  emoji: '📦', label: 'Im Schrank',  gradient: 'from-blue-400 to-indigo-500',  badge: 'bg-blue-600 text-white' },
  aussortiert:  { bg: 'bg-orange-500/10', text: 'text-orange-600', emoji: '👋', label: 'Tschüss',   gradient: 'from-orange-400 to-red-400',   badge: 'bg-orange-600 text-white' },
  verkauft:     { bg: 'bg-purple-500/10', text: 'text-purple-600', emoji: '🎉', label: 'Verkauft',  gradient: 'from-purple-400 to-pink-500',  badge: 'bg-purple-600 text-white' },
};

const zustandLabels: Record<string, string> = {
  neu: 'Neu ✨', sehr_gut: 'Sehr gut', gut: 'Gut', gebraucht: 'Gebraucht',
};

const prioritaetConfig: Record<string, { color: string; emoji: string; label: string }> = {
  hoch: { color: 'text-red-600', emoji: '🔴', label: 'Dringend' },
  normal: { color: 'text-blue-600', emoji: '🔵', label: 'Normal' },
  niedrig: { color: 'text-gray-600', emoji: '⚪', label: 'Niedrig' },
};

export default function SamuInventarPage() {
  return (
    <Suspense fallback={<div className="min-h-screen bg-[#F2F2F7] flex items-center justify-center"><div className="text-4xl animate-pulse">👶</div></div>}>
      <SamuInventar />
    </Suspense>
  );
}

function SamuInventar() {
  const searchParams = useSearchParams();
  const [activeTab, setActiveTab] = useState<'inventar' | 'uebersicht' | 'bedarf'>('inventar');
  const [matrixData, setMatrixData] = useState<{ kategorie: string; groesse: string; count: number }[]>([]);
  
  // Inventar State
  const [items, setItems] = useState<Item[]>([]);
  const [stats, setStats] = useState<Stats | null>(null);
  const [loading, setLoading] = useState(true);
  const [selectedItem, setSelectedItem] = useState<Item | null>(null);
  const [editMode, setEditMode] = useState(false);
  const [imageViewer, setImageViewer] = useState<string | null>(null);
  const [statusFilter, setStatusFilter] = useState('');
  const [typFilter, setTypFilter] = useState('');
  const [kategorieFilter, setKategorieFilter] = useState('');
  const [groesseFilter, setGroesseFilter] = useState('');
  const [availableGroessen, setAvailableGroessen] = useState<string[]>([]);
  const [availableKategorien, setAvailableKategorien] = useState<string[]>([]);
  const [searchQuery, setSearchQuery] = useState('');
  const [showRules, setShowRules] = useState(false);
  const [markenFilter, setMarkenFilter] = useState('');
  const [availableMarken, setAvailableMarken] = useState<string[]>([]);
  const [selectedMarke, setSelectedMarke] = useState<Marke | null>(null);
  const [markenData, setMarkenData] = useState<Map<string, Marke>>(new Map());

  // Bedarf State
  const [bedarfItems, setBedarfItems] = useState<BedarfsItem[]>([]);
  const [bedarfFilter, setBedarfFilter] = useState<'alle' | 'offen' | 'erledigt'>('offen');
  const [showBedarfForm, setShowBedarfForm] = useState(false);
  const [newBedarf, setNewBedarf] = useState({
    beschreibung: '',
    kategorie: '',
    groesse: '',
    prioritaet: 'normal' as 'hoch' | 'normal' | 'niedrig',
    notizen: '',
  });

  const fetchItems = useCallback(async () => {
    const params = new URLSearchParams();
    if (statusFilter) params.set('status', statusFilter);
    if (typFilter) params.set('typ', typFilter);
    if (groesseFilter) params.set('groesse', groesseFilter);
    if (kategorieFilter) params.set('kategorie', kategorieFilter);
    if (searchQuery) params.set('search', searchQuery);
    const res = await fetch(`/api/items?${params}`);
    let fetchedItems = await res.json();
    
    if (markenFilter) {
      fetchedItems = fetchedItems.filter((item: Item) => item.marke === markenFilter);
    }
    
    setItems(fetchedItems);
    
    const marken = [...new Set(fetchedItems.map((item: Item) => item.marke).filter(Boolean))].sort() as string[];
    setAvailableMarken(marken);
  }, [statusFilter, typFilter, groesseFilter, kategorieFilter, searchQuery, markenFilter]);

  const fetchGroessen = useCallback(async () => {
    const params = new URLSearchParams({ groessen: 'true' });
    if (statusFilter) params.set('status', statusFilter);
    if (typFilter) params.set('typ', typFilter);
    const res = await fetch(`/api/items?${params}`);
    setAvailableGroessen(await res.json());
  }, [statusFilter, typFilter]);

  const fetchKategorien = useCallback(async () => {
    if (!typFilter) {
      setAvailableKategorien([]);
      setKategorieFilter('');
      return;
    }
    const params = new URLSearchParams({ kategorien: 'true', typ: typFilter });
    if (statusFilter) params.set('status', statusFilter);
    const res = await fetch(`/api/items?${params}`);
    setAvailableKategorien(await res.json());
  }, [statusFilter, typFilter]);

  const fetchStats = async () => {
    const res = await fetch('/api/items?stats=true');
    setStats(await res.json());
  };

  const fetchMarkenData = async () => {
    const res = await fetch('/api/marken');
    const marken = await res.json() as Marke[];
    const markenMap = new Map(marken.map(m => [m.name, m]));
    setMarkenData(markenMap);
  };

  const fetchBedarf = async () => {
    const params = new URLSearchParams();
    if (bedarfFilter === 'offen') params.set('erledigt', '0');
    if (bedarfFilter === 'erledigt') params.set('erledigt', '1');
    const res = await fetch(`/api/bedarf?${params}`);
    setBedarfItems(await res.json());
  };

  const fetchMatrix = async () => {
    const res = await fetch('/api/items?matrix=true');
    setMatrixData(await res.json());
  };

  useEffect(() => { 
    Promise.all([fetchItems(), fetchStats(), fetchMarkenData(), fetchBedarf(), fetchMatrix()]).then(() => setLoading(false)); 
  }, []);
  
  useEffect(() => { fetchGroessen(); }, [statusFilter, typFilter, fetchGroessen]);
  useEffect(() => { fetchKategorien(); }, [statusFilter, typFilter, fetchKategorien]);
  useEffect(() => { fetchItems(); }, [statusFilter, typFilter, kategorieFilter, groesseFilter, searchQuery, markenFilter, fetchItems]);
  useEffect(() => { fetchBedarf(); }, [bedarfFilter]);

  // Deep-link: /samu?item=123 opens detail modal directly
  useEffect(() => {
    const itemId = searchParams.get('item');
    if (itemId && items.length > 0) {
      const item = items.find(i => i.id === Number(itemId));
      if (item) {
        setSelectedItem(item);
      } else {
        // Item not in current filter — fetch it directly
        fetch(`/api/items/${itemId}`).then(r => r.ok ? r.json() : null).then(data => {
          if (data) setSelectedItem(data);
        });
      }
    }
  }, [searchParams, items]);

  // Wrapper to sync URL with selected item
  const openItem = (item: Item | null) => {
    setSelectedItem(item);
    if (item) {
      window.history.replaceState(null, '', `/samu?item=${item.id}`);
    } else {
      window.history.replaceState(null, '', '/samu');
    }
  };

  const handleUpdate = async (id: number, data: Partial<Item>) => {
    await fetch(`/api/items/${id}`, { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data) });
    await Promise.all([fetchItems(), fetchStats()]);
    openItem(null);
    setEditMode(false);
  };

  const handleMarkeClick = (markeName: string) => {
    const marke = markenData.get(markeName);
    if (marke) {
      setSelectedMarke(marke);
    } else {
      setSelectedMarke({
        id: 0,
        name: markeName,
        erstellt_am: new Date().toISOString(),
      });
    }
  };

  const handleCreateBedarf = async () => {
    if (!newBedarf.beschreibung.trim()) {
      alert('Bitte eine Beschreibung eingeben!');
      return;
    }
    
    await fetch('/api/bedarf', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(newBedarf),
    });
    
    setNewBedarf({ beschreibung: '', kategorie: '', groesse: '', prioritaet: 'normal', notizen: '' });
    setShowBedarfForm(false);
    fetchBedarf();
  };

  const handleToggleBedarf = async (id: number, currentState: number) => {
    await fetch(`/api/bedarf/${id}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ erledigt: currentState === 1 ? 0 : 1 }),
    });
    fetchBedarf();
  };

  const handleDeleteBedarf = async (id: number) => {
    if (!confirm('Wirklich löschen?')) return;
    await fetch(`/api/bedarf/${id}`, { method: 'DELETE' });
    fetchBedarf();
  };

  const getImageUrl = (item: Item) => {
    if (!item.bild_pfade) return null;
    try {
      const paths = JSON.parse(item.bild_pfade);
      if (paths.length > 0) return `/api/v1/media/${paths[0].replace('images/', '')}`;
    } catch { /* */ }
    return null;
  };

  const offeneBedarf = bedarfItems.filter(b => b.erledigt === 0);
  const erledigteBedarf = bedarfItems.filter(b => b.erledigt === 1);

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-[#F2F2F7]">
        <div className="flex flex-col items-center gap-4">
          <div className="text-5xl animate-bounce">👶</div>
          <p className="text-[#8E8E93] text-sm font-medium">Laden…</p>
        </div>
      </div>
    );
  }

  return (
    <main className="min-h-screen pb-24 bg-[#F2F2F7]">
      {/* ── Compact Header ── */}
      <header className="relative overflow-hidden bg-gradient-to-br from-[#FF9F0A] via-[#FF6B6B] to-[#AF52DE] pt-4 pb-4 px-5 safe-area-inset">
        <div className="absolute inset-0 opacity-20">
          <div className="absolute -top-10 -right-10 w-40 h-40 bg-white rounded-full blur-3xl" />
        </div>
        <div className="relative max-w-xl mx-auto">
          <div className="flex items-center gap-3">
            <Link href="/" className="flex items-center justify-center w-9 h-9 bg-white/20 backdrop-blur-sm rounded-full hover:bg-white/30 active:scale-90 transition">
              <svg className="w-5 h-5 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2.5}>
                <path strokeLinecap="round" strokeLinejoin="round" d="M10 19l-7-7m0 0l7-7m-7 7h18" />
              </svg>
            </Link>
            <div className="flex-1">
              <h1 className="text-2xl font-extrabold text-white tracking-tight">Samus Sachen</h1>
              {stats && (
                <p className="text-white/80 text-xs font-medium">{stats.gesamt} Teile · ~{stats.geschaetzter_wert.toFixed(0)}€</p>
              )}
            </div>
            <div className="text-4xl drop-shadow-lg">👶</div>
          </div>
        </div>
      </header>

      {/* ── Tab Bar ── */}
      <div className="max-w-xl mx-auto px-4 -mt-4 relative z-10">
        <div className="bg-white rounded-2xl shadow-sm border border-black/5 p-1.5 flex gap-1.5">
          <button
            onClick={() => setActiveTab('inventar')}
            className={`flex-1 py-2.5 rounded-xl text-center font-semibold text-[14px] transition-all ${
              activeTab === 'inventar'
                ? 'bg-[#007AFF] text-white shadow-sm'
                : 'text-[#1C1C1E] hover:bg-[#F2F2F7]'
            }`}
          >
            📦 Inventar
          </button>
          <button
            onClick={() => setActiveTab('uebersicht')}
            className={`flex-1 py-2.5 rounded-xl text-center font-semibold text-[14px] transition-all ${
              activeTab === 'uebersicht'
                ? 'bg-[#007AFF] text-white shadow-sm'
                : 'text-[#1C1C1E] hover:bg-[#F2F2F7]'
            }`}
          >
            📊 Übersicht
          </button>
          <button
            onClick={() => setActiveTab('bedarf')}
            className={`flex-1 py-2.5 rounded-xl text-center font-semibold text-[14px] transition-all relative ${
              activeTab === 'bedarf'
                ? 'bg-[#007AFF] text-white shadow-sm'
                : 'text-[#1C1C1E] hover:bg-[#F2F2F7]'
            }`}
          >
            🛒 Bedarf
            {offeneBedarf.length > 0 && (
              <span className={`absolute -top-1 -right-1 w-5 h-5 rounded-full text-[10px] font-bold flex items-center justify-center ${
                activeTab === 'bedarf' ? 'bg-white text-[#007AFF]' : 'bg-red-500 text-white'
              }`}>
                {offeneBedarf.length}
              </span>
            )}
          </button>
        </div>
      </div>

      {activeTab === 'inventar' ? (
        <>
          {/* ── Status Pills ── */}
          {stats && (
            <div className="max-w-xl mx-auto px-4 mt-3 relative z-10">
              <div className="bg-white rounded-2xl shadow-sm border border-black/5 p-3 flex gap-2">
                {stats.nach_status.map(s => {
                  const cfg = statusConfig[s.status] || statusConfig.aktiv;
                  const active = statusFilter === s.status;
                  return (
                    <button
                      key={s.status}
                      onClick={() => setStatusFilter(active ? '' : s.status)}
                      className={`flex-1 py-2.5 rounded-xl text-center transition-all ${
                        active
                          ? `bg-gradient-to-br ${cfg.gradient} text-white shadow-md scale-[1.02]`
                          : 'bg-[#F2F2F7] hover:bg-[#E5E5EA]'
                      }`}
                    >
                      <div className="text-lg leading-none">{cfg.emoji}</div>
                      <div className={`text-xl font-bold mt-0.5 ${active ? 'text-white' : 'text-[#1C1C1E]'}`}>{s.count}</div>
                      <div className={`text-[9px] font-semibold uppercase tracking-wider mt-0.5 ${active ? 'text-white/80' : 'text-[#8E8E93]'}`}>
                        {cfg.label}
                      </div>
                    </button>
                  );
                })}
              </div>
            </div>
          )}

          {/* ── Search & Filters ── */}
          <div className="max-w-xl mx-auto px-4 pt-5 space-y-3">
            <div className="relative">
              <svg className="absolute left-4 top-1/2 -translate-y-1/2 w-4 h-4 text-[#8E8E93]" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2.5}>
                <path strokeLinecap="round" strokeLinejoin="round" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
              </svg>
              <input
                type="search"
                placeholder="Suchen…"
                className="w-full pl-11 pr-4 py-3 rounded-2xl bg-white text-[15px] text-[#1C1C1E] placeholder:text-[#8E8E93] border border-black/5 focus:outline-none focus:ring-2 focus:ring-[#007AFF]/30 shadow-sm transition"
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
              />
            </div>
            <div className="flex gap-2 overflow-x-auto pb-1">
              <Pill label="Alle" active={!typFilter} onClick={() => setTypFilter('')} />
              <Pill label="👕 Kleidung" active={typFilter === 'kleidung'} onClick={() => setTypFilter('kleidung')} />
              <Pill label="🧸 Spielzeug" active={typFilter === 'spielzeug'} onClick={() => setTypFilter('spielzeug')} />
              {availableGroessen.length > 0 && (
                <select
                  value={groesseFilter}
                  onChange={(e) => setGroesseFilter(e.target.value)}
                  className={`px-4 py-2 rounded-full text-[13px] font-semibold transition appearance-none cursor-pointer ${
                    groesseFilter
                      ? 'bg-[#007AFF] text-white shadow-sm'
                      : 'bg-white text-[#1C1C1E] border border-black/5 shadow-sm'
                  }`}
                >
                  <option value="">📏 Größe</option>
                  {availableGroessen.map(g => <option key={g} value={g}>Gr. {g}</option>)}
                </select>
              )}
              {availableMarken.length > 0 && (
                <select
                  value={markenFilter}
                  onChange={(e) => setMarkenFilter(e.target.value)}
                  className={`px-4 py-2 rounded-full text-[13px] font-semibold transition appearance-none cursor-pointer ${
                    markenFilter
                      ? 'bg-[#007AFF] text-white shadow-sm'
                      : 'bg-white text-[#1C1C1E] border border-black/5 shadow-sm'
                  }`}
                >
                  <option value="">🏷️ Marke</option>
                  {availableMarken.map(m => <option key={m} value={m}>{m}</option>)}
                </select>
              )}
              {availableKategorien.length > 0 && (
                <>
                  <div className="w-px h-6 bg-[#C6C6C8]/40 self-center mx-1" />
                  {availableKategorien.map(k => (
                    <Pill
                      key={k}
                      label={k}
                      active={kategorieFilter === k}
                      onClick={() => setKategorieFilter(kategorieFilter === k ? '' : k)}
                    />
                  ))}
                </>
              )}
              {(statusFilter || typFilter || kategorieFilter || groesseFilter || markenFilter || searchQuery) && (
                <button
                  onClick={() => { setStatusFilter(''); setTypFilter(''); setKategorieFilter(''); setGroesseFilter(''); setMarkenFilter(''); setSearchQuery(''); }}
                  className="px-4 py-2 rounded-full text-[13px] font-semibold text-[#FF3B30] bg-[#FF3B30]/10 whitespace-nowrap transition hover:bg-[#FF3B30]/20"
                >
                  ✕ Reset
                </button>
              )}
            </div>

            {typFilter && availableKategorien.length > 0 && (
              <div className="flex gap-2 overflow-x-auto pb-1 pt-2">
                <Pill label="Alle" active={!kategorieFilter} onClick={() => setKategorieFilter('')} />
                {availableKategorien.map(k => (
                  <Pill
                    key={k}
                    label={k}
                    active={kategorieFilter === k}
                    onClick={() => setKategorieFilter(kategorieFilter === k ? '' : k)}
                  />
                ))}
              </div>
            )}
          </div>

          {/* ── Items Grid ── */}
          <div className="max-w-xl mx-auto px-4 pt-4 grid grid-cols-2 gap-3">
            {items.map(item => (
              <ItemCard key={item.id} item={item} imageUrl={getImageUrl(item)} onClick={() => openItem(item)} onMarkeClick={handleMarkeClick} />
            ))}
          </div>

          {items.length === 0 && (
            <div className="text-center py-20">
              <div className="text-6xl mb-4">🔍</div>
              <p className="text-[#8E8E93] font-semibold">Nix gefunden!</p>
              <p className="text-[#AEAEB2] text-sm mt-1">Versuch andere Filter 🎯</p>
            </div>
          )}

          {/* ── Regeln / Hilfe ── */}
          <div className="max-w-xl mx-auto px-4 pt-6 pb-4">
            <button
              onClick={() => setShowRules(!showRules)}
              className="w-full bg-white rounded-2xl shadow-sm border border-black/5 p-4 flex items-center justify-between text-left transition hover:bg-[#F9F9F9]"
            >
              <div className="flex items-center gap-3">
                <div className="text-2xl">ℹ️</div>
                <span className="text-[15px] font-semibold text-[#1C1C1E]">Regeln & Hilfe</span>
              </div>
              <svg
                className={`w-5 h-5 text-[#8E8E93] transition-transform ${showRules ? 'rotate-180' : ''}`}
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
                strokeWidth={2.5}
              >
                <path strokeLinecap="round" strokeLinejoin="round" d="M19 9l-7 7-7-7" />
              </svg>
            </button>

            {showRules && (
              <div className="mt-3 bg-gradient-to-br from-blue-50 to-indigo-50 rounded-2xl p-5 border border-blue-100 shadow-sm">
                <h3 className="text-[16px] font-bold text-[#1C1C1E] mb-3">📸 Einfach per Telegram:</h3>
                <div className="space-y-2.5 text-[14px] text-[#1C1C1E]">
                  <div className="flex items-start gap-3">
                    <div className="flex-shrink-0 w-8 h-8 bg-blue-500 rounded-lg flex items-center justify-center text-white font-bold text-sm">+</div>
                    <div>
                      <div className="font-semibold">Neues Item → Schrank</div>
                      <div className="text-[#5C5C5E] text-[13px]">Foto senden mit Caption <code className="bg-white/60 px-1.5 py-0.5 rounded">+</code></div>
                    </div>
                  </div>
                  <div className="flex items-start gap-3">
                    <div className="flex-shrink-0 w-8 h-8 bg-green-500 rounded-lg flex items-center justify-center text-white font-bold text-sm">+</div>
                    <div>
                      <div className="font-semibold">Neues Item → Aktiv (wird getragen)</div>
                      <div className="text-[#5C5C5E] text-[13px]">Foto senden mit Caption <code className="bg-white/60 px-1.5 py-0.5 rounded">+ aktiv</code></div>
                    </div>
                  </div>
                  <div className="flex items-start gap-3">
                    <div className="flex-shrink-0 w-8 h-8 bg-orange-500 rounded-lg flex items-center justify-center text-white font-bold text-sm">−</div>
                    <div>
                      <div className="font-semibold">Item aussortiert</div>
                      <div className="text-[#5C5C5E] text-[13px]">Foto senden mit Caption <code className="bg-white/60 px-1.5 py-0.5 rounded">-</code> oder <code className="bg-white/60 px-1.5 py-0.5 rounded">Raus</code></div>
                    </div>
                  </div>
                  <div className="flex items-start gap-3">
                    <div className="flex-shrink-0 w-8 h-8 bg-purple-500 rounded-lg flex items-center justify-center text-white font-bold text-sm">?</div>
                    <div>
                      <div className="font-semibold">Im Inventar suchen</div>
                      <div className="text-[#5C5C5E] text-[13px]">Nachricht mit <code className="bg-white/60 px-1.5 py-0.5 rounded">?</code> + Suchbegriff</div>
                    </div>
                  </div>
                </div>
                <div className="mt-4 pt-4 border-t border-blue-200">
                  <p className="text-[13px] text-[#5C5C5E] leading-relaxed">
                    💡 <strong>Tipp:</strong> Einfach Foto mit Caption an Ole's Telegram senden — alles andere wird automatisch erkannt!
                  </p>
                </div>
              </div>
            )}
          </div>
        </>
      ) : activeTab === 'uebersicht' ? (
        /* ── ÜBERSICHT TAB ── */
        <div className="max-w-xl mx-auto px-4 pt-5 pb-8">
          <div className="bg-white rounded-2xl shadow-sm border border-black/5 overflow-hidden">
            <div className="px-4 py-3 border-b border-[#E5E5EA]">
              <h3 className="text-[16px] font-bold text-[#1C1C1E]">📊 Kategorie × Größe</h3>
              <p className="text-[12px] text-[#8E8E93] mt-0.5">Aktiv + Im Schrank · Tippe auf eine Zahl zum Filtern</p>
            </div>
            {(() => {
              // Build matrix
              const kategorien = [...new Set(matrixData.map(d => d.kategorie))].sort();
              const groessen = [...new Set(matrixData.map(d => d.groesse))].sort((a, b) => {
                const na = parseInt(a), nb = parseInt(b);
                if (!isNaN(na) && !isNaN(nb)) return na - nb;
                return a.localeCompare(b);
              });
              const lookup = new Map(matrixData.map(d => [`${d.kategorie}|${d.groesse}`, d.count]));
              // Row totals
              const rowTotals = new Map(kategorien.map(k => [k, matrixData.filter(d => d.kategorie === k).reduce((s, d) => s + d.count, 0)]));
              // Col totals
              const colTotals = new Map(groessen.map(g => [g, matrixData.filter(d => d.groesse === g).reduce((s, d) => s + d.count, 0)]));
              const grandTotal = matrixData.reduce((s, d) => s + d.count, 0);

              if (kategorien.length === 0) return <div className="p-8 text-center text-[#8E8E93]">Keine Daten</div>;

              return (
                <div className="overflow-x-auto max-h-[70vh] overflow-y-auto relative">
                  <table className="w-full text-[13px] border-collapse">
                    <thead className="sticky top-0 z-20">
                      <tr className="bg-[#F2F2F7]">
                        <th className="text-left px-3 py-2.5 font-semibold text-[#8E8E93] text-[11px] uppercase tracking-wider sticky left-0 bg-[#F2F2F7] z-30 min-w-[100px] border-r border-dashed border-[#C6C6C8]/50">Kategorie</th>
                        {groessen.map(g => (
                          <th key={g} className="px-2 py-2.5 font-semibold text-[#8E8E93] text-[11px] text-center min-w-[40px] border-r border-dashed border-[#C6C6C8]/50">{g}</th>
                        ))}
                        <th className="px-3 py-2.5 font-bold text-[#1C1C1E] text-[11px] text-center bg-[#E5E5EA] min-w-[40px]">Σ</th>
                      </tr>
                    </thead>
                    <tbody>
                      {kategorien.map((kat, i) => (
                        <tr key={kat} className={i % 2 === 0 ? 'bg-white' : 'bg-[#FAFAFA]'}>
                          <td className={`px-3 py-2.5 font-semibold text-[#1C1C1E] sticky left-0 z-10 border-r border-dashed border-[#C6C6C8]/50 ${i % 2 === 0 ? 'bg-white' : 'bg-[#FAFAFA]'}`}>{kat}</td>
                          {groessen.map(g => {
                            const count = lookup.get(`${kat}|${g}`) || 0;
                            return (
                              <td key={g} className="px-2 py-2.5 text-center border-r border-dashed border-[#C6C6C8]/50">
                                {count > 0 ? (
                                  <button
                                    onClick={() => {
                                      setTypFilter('kleidung');
                                      setKategorieFilter(kat);
                                      setGroesseFilter(g);
                                      setStatusFilter('');
                                      setActiveTab('inventar');
                                    }}
                                    className="inline-flex items-center justify-center w-7 h-7 rounded-lg bg-[#007AFF]/10 text-[#007AFF] font-bold text-[13px] hover:bg-[#007AFF]/20 active:scale-90 transition"
                                  >
                                    {count}
                                  </button>
                                ) : (
                                  <span className="text-[#D1D1D6]">·</span>
                                )}
                              </td>
                            );
                          })}
                          <td className="px-3 py-2.5 text-center font-bold text-[#1C1C1E] bg-[#F2F2F7]">{rowTotals.get(kat)}</td>
                        </tr>
                      ))}
                    </tbody>
                    <tfoot>
                      <tr className="bg-[#E5E5EA]">
                        <td className="px-3 py-2.5 font-bold text-[#1C1C1E] text-[12px] sticky left-0 bg-[#E5E5EA] z-10 border-r border-dashed border-[#C6C6C8]/50">Gesamt</td>
                        {groessen.map(g => (
                          <td key={g} className="px-2 py-2.5 text-center font-bold text-[#1C1C1E] text-[12px] border-r border-dashed border-[#C6C6C8]/50">{colTotals.get(g)}</td>
                        ))}
                        <td className="px-3 py-2.5 text-center font-extrabold text-[#007AFF] text-[14px]">{grandTotal}</td>
                      </tr>
                    </tfoot>
                  </table>
                </div>
              );
            })()}
          </div>
        </div>
      ) : (
        /* ── BEDARF TAB ── */
        <div className="max-w-xl mx-auto px-4 pt-5 space-y-4">
          {/* Filter Pills */}
          <div className="flex gap-2">
            <Pill label="Offen" active={bedarfFilter === 'offen'} onClick={() => setBedarfFilter('offen')} />
            <Pill label="Alle" active={bedarfFilter === 'alle'} onClick={() => setBedarfFilter('alle')} />
            <Pill label="Erledigt" active={bedarfFilter === 'erledigt'} onClick={() => setBedarfFilter('erledigt')} />
          </div>

          {/* Neues Item Button */}
          <button
            onClick={() => setShowBedarfForm(!showBedarfForm)}
            className="w-full py-3.5 bg-gradient-to-r from-green-500 to-emerald-600 hover:from-green-600 hover:to-emerald-700 text-white rounded-2xl font-semibold text-[15px] shadow-md transition flex items-center justify-center gap-2"
          >
            <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2.5}>
              <path strokeLinecap="round" strokeLinejoin="round" d="M12 4v16m8-8H4" />
            </svg>
            Neuer Bedarf
          </button>

          {/* Formular */}
          {showBedarfForm && (
            <div className="bg-white rounded-2xl shadow-sm border border-black/5 p-5 space-y-4">
              <h3 className="text-[17px] font-bold text-[#1C1C1E]">Was wird gebraucht?</h3>
              
              <div>
                <label className="text-[12px] font-semibold text-[#8E8E93] uppercase tracking-wide ml-1">Beschreibung *</label>
                <input
                  type="text"
                  className="w-full mt-1 px-4 py-3 bg-[#F2F2F7] rounded-xl text-[15px] text-[#1C1C1E] placeholder:text-[#C7C7CC] focus:outline-none focus:ring-2 focus:ring-[#007AFF]/30 transition"
                  placeholder="z.B. Winterjacke, Gummistiefel..."
                  value={newBedarf.beschreibung}
                  onChange={(e) => setNewBedarf({ ...newBedarf, beschreibung: e.target.value })}
                />
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="text-[12px] font-semibold text-[#8E8E93] uppercase tracking-wide ml-1">Kategorie</label>
                  <input
                    type="text"
                    className="w-full mt-1 px-4 py-3 bg-[#F2F2F7] rounded-xl text-[15px] text-[#1C1C1E] placeholder:text-[#C7C7CC] focus:outline-none focus:ring-2 focus:ring-[#007AFF]/30 transition"
                    placeholder="z.B. Jacke, Hose..."
                    value={newBedarf.kategorie}
                    onChange={(e) => setNewBedarf({ ...newBedarf, kategorie: e.target.value })}
                  />
                </div>
                <div>
                  <label className="text-[12px] font-semibold text-[#8E8E93] uppercase tracking-wide ml-1">Größe</label>
                  <input
                    type="text"
                    className="w-full mt-1 px-4 py-3 bg-[#F2F2F7] rounded-xl text-[15px] text-[#1C1C1E] placeholder:text-[#C7C7CC] focus:outline-none focus:ring-2 focus:ring-[#007AFF]/30 transition"
                    placeholder="z.B. 92, 98..."
                    value={newBedarf.groesse}
                    onChange={(e) => setNewBedarf({ ...newBedarf, groesse: e.target.value })}
                  />
                </div>
              </div>

              <div>
                <label className="text-[12px] font-semibold text-[#8E8E93] uppercase tracking-wide ml-1">Priorität</label>
                <select
                  className="w-full mt-1 px-4 py-3 bg-[#F2F2F7] rounded-xl text-[15px] text-[#1C1C1E] focus:outline-none focus:ring-2 focus:ring-[#007AFF]/30 appearance-none cursor-pointer transition"
                  value={newBedarf.prioritaet}
                  onChange={(e) => setNewBedarf({ ...newBedarf, prioritaet: e.target.value as any })}
                >
                  <option value="hoch">🔴 Dringend</option>
                  <option value="normal">🔵 Normal</option>
                  <option value="niedrig">⚪ Niedrig</option>
                </select>
              </div>

              <div>
                <label className="text-[12px] font-semibold text-[#8E8E93] uppercase tracking-wide ml-1">Notizen</label>
                <textarea
                  className="w-full mt-1 px-4 py-3 bg-[#F2F2F7] rounded-xl text-[15px] text-[#1C1C1E] placeholder:text-[#C7C7CC] focus:outline-none focus:ring-2 focus:ring-[#007AFF]/30 resize-none transition"
                  rows={2}
                  placeholder="Zusätzliche Infos..."
                  value={newBedarf.notizen}
                  onChange={(e) => setNewBedarf({ ...newBedarf, notizen: e.target.value })}
                />
              </div>

              <div className="flex gap-3 pt-1">
                <button
                  onClick={() => {
                    setShowBedarfForm(false);
                    setNewBedarf({ beschreibung: '', kategorie: '', groesse: '', prioritaet: 'normal', notizen: '' });
                  }}
                  className="flex-1 py-3.5 bg-[#F2F2F7] hover:bg-[#E5E5EA] text-[#1C1C1E] rounded-2xl font-semibold text-[15px] transition"
                >
                  Abbrechen
                </button>
                <button
                  onClick={handleCreateBedarf}
                  className="flex-1 py-3.5 bg-[#007AFF] hover:bg-[#0066D6] text-white rounded-2xl font-semibold text-[15px] transition shadow-sm"
                >
                  Hinzufügen ✓
                </button>
              </div>
            </div>
          )}

          {/* Offene Items */}
          {bedarfFilter !== 'erledigt' && offeneBedarf.length > 0 && (
            <div className="space-y-3">
              {bedarfFilter === 'alle' && <h3 className="text-[15px] font-bold text-[#8E8E93] uppercase tracking-wide px-2">Offen</h3>}
              {offeneBedarf.map(item => (
                <BedarfCard key={item.id} item={item} onToggle={handleToggleBedarf} onDelete={handleDeleteBedarf} />
              ))}
            </div>
          )}

          {/* Erledigte Items */}
          {bedarfFilter !== 'offen' && erledigteBedarf.length > 0 && (
            <div className="space-y-3">
              {bedarfFilter === 'alle' && <h3 className="text-[15px] font-bold text-[#8E8E93] uppercase tracking-wide px-2 mt-6">Erledigt</h3>}
              {erledigteBedarf.map(item => (
                <BedarfCard key={item.id} item={item} onToggle={handleToggleBedarf} onDelete={handleDeleteBedarf} />
              ))}
            </div>
          )}

          {bedarfItems.length === 0 && (
            <div className="text-center py-20">
              <div className="text-6xl mb-4">🎉</div>
              <p className="text-[#8E8E93] font-semibold">Nichts auf der Liste!</p>
              <p className="text-[#AEAEB2] text-sm mt-1">Alles vorhanden 👍</p>
            </div>
          )}
        </div>
      )}

      {/* ── Detail Sheet ── */}
      {selectedItem && !imageViewer && (
        <DetailSheet
          item={selectedItem}
          imageUrl={getImageUrl(selectedItem)}
          editMode={editMode}
          onClose={() => { openItem(null); setEditMode(false); }}
          onEdit={() => setEditMode(true)}
          onSave={(data) => handleUpdate(selectedItem.id, data)}
          onUpdate={async (id, data) => {
            await fetch(`/api/items/${id}`, { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data) });
            await Promise.all([fetchItems(), fetchStats()]);
            if (selectedItem) openItem({ ...selectedItem, ...data });
          }}
          onImageClick={(url) => setImageViewer(url)}
        />
      )}

      {/* ── Fullscreen Image ── */}
      {imageViewer && (
        <div className="fixed inset-0 z-[70] bg-black/95 flex items-center justify-center" onClick={() => setImageViewer(null)}>
          <button onClick={() => setImageViewer(null)} className="absolute top-5 right-5 z-10 w-10 h-10 bg-white/15 hover:bg-white/25 rounded-full text-white flex items-center justify-center backdrop-blur-md transition">
            <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2.5}><path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" /></svg>
          </button>
          <img src={imageViewer} alt="Vollbild" className="max-w-full max-h-full object-contain p-4" style={{ touchAction: 'pinch-zoom' }} onClick={(e) => e.stopPropagation()} />
        </div>
      )}

      {/* ── Marken-Info Modal ── */}
      {selectedMarke && (
        <MarkenInfoModal marke={selectedMarke} onClose={() => setSelectedMarke(null)} />
      )}
    </main>
  );
}

/* ── Components ── */

function Pill({ label, active, onClick }: { label: string; active: boolean; onClick: () => void }) {
  return (
    <button onClick={onClick} className={`px-4 py-2 rounded-full text-[13px] font-semibold whitespace-nowrap transition ${
      active ? 'bg-[#007AFF] text-white shadow-sm' : 'bg-white text-[#1C1C1E] border border-black/5 shadow-sm hover:bg-[#F2F2F7]'
    }`}>
      {label}
    </button>
  );
}

function BedarfCard({ item, onToggle, onDelete }: {
  item: BedarfsItem;
  onToggle: (id: number, currentState: number) => void;
  onDelete: (id: number) => void;
}) {
  const prioConfig = prioritaetConfig[item.prioritaet];
  const isErledigt = item.erledigt === 1;
  
  return (
    <div className={`bg-white rounded-2xl shadow-sm border overflow-hidden transition ${
      isErledigt ? 'border-green-200 opacity-60' : 'border-black/5'
    }`}>
      <div className="p-4">
        <div className="flex items-start gap-3">
          {/* Checkbox */}
          <button
            onClick={() => onToggle(item.id, item.erledigt)}
            className={`flex-shrink-0 w-6 h-6 rounded-lg border-2 flex items-center justify-center transition mt-0.5 ${
              isErledigt
                ? 'bg-green-500 border-green-500'
                : 'border-[#C7C7CC] hover:border-[#007AFF]'
            }`}
          >
            {isErledigt && (
              <svg className="w-4 h-4 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={3}>
                <path strokeLinecap="round" strokeLinejoin="round" d="M5 13l4 4L19 7" />
              </svg>
            )}
          </button>

          {/* Content */}
          <div className="flex-1 min-w-0">
            <div className="flex items-start justify-between gap-2">
              <h3 className={`text-[15px] font-semibold leading-tight ${
                isErledigt ? 'line-through text-[#8E8E93]' : 'text-[#1C1C1E]'
              }`}>
                {item.beschreibung}
              </h3>
              {!isErledigt && (
                <span className={`flex-shrink-0 text-sm ${prioConfig.color}`}>
                  {prioConfig.emoji}
                </span>
              )}
            </div>

            <div className="flex items-center gap-2 mt-1 text-[12px] text-[#8E8E93]">
              {item.kategorie && <span>{item.kategorie}</span>}
              {item.groesse && (
                <>
                  {item.kategorie && <span>·</span>}
                  <span>Gr. {item.groesse}</span>
                </>
              )}
              {!isErledigt && !item.kategorie && !item.groesse && (
                <span className={prioConfig.color}>{prioConfig.label}</span>
              )}
            </div>

            {item.notizen && (
              <p className={`text-[13px] mt-2 ${isErledigt ? 'text-[#AEAEB2]' : 'text-[#5C5C5E]'}`}>
                {item.notizen}
              </p>
            )}

            {isErledigt && item.erledigt_am && (
              <p className="text-[11px] text-[#AEAEB2] mt-2">
                ✓ Erledigt: {new Date(item.erledigt_am).toLocaleDateString('de-DE', { day: '2-digit', month: 'short' })}
              </p>
            )}
          </div>
        </div>

        {/* Actions */}
        {isErledigt && (
          <div className="mt-3 pt-3 border-t border-black/5 flex justify-end">
            <button
              onClick={() => onDelete(item.id)}
              className="px-3 py-1.5 text-[13px] font-semibold text-red-600 hover:bg-red-50 rounded-lg transition"
            >
              Löschen
            </button>
          </div>
        )}
      </div>
    </div>
  );
}

function ItemCard({ item, imageUrl, onClick, onMarkeClick }: { 
  item: Item; 
  imageUrl: string | null; 
  onClick: () => void;
  onMarkeClick?: (markeName: string) => void;
}) {
  const cfg = statusConfig[item.status] || statusConfig.aktiv;
  return (
    <div onClick={onClick} className="bg-white rounded-[20px] overflow-hidden shadow-sm border border-black/5 active:scale-[0.96] transition-transform cursor-pointer">
      <div className="aspect-square bg-[#F2F2F7] relative overflow-hidden">
        {imageUrl ? (
          <img src={imageUrl} alt={item.name || ''} className="w-full h-full object-cover" loading="lazy" />
        ) : (
          <div className="w-full h-full flex items-center justify-center text-5xl opacity-25">
            {item.typ === 'kleidung' ? '👕' : '🧸'}
          </div>
        )}
        <div className={`absolute top-2.5 left-2.5 px-2.5 py-1 rounded-full text-[11px] font-bold shadow-lg ${cfg.badge}`}>
          {cfg.emoji} {cfg.label}
        </div>
      </div>
      <div className="p-3.5">
        <div className="flex items-center gap-1.5">
          <p className="font-bold text-[15px] text-[#1C1C1E] truncate leading-tight flex-1">
            <span className="text-[11px] text-[#8E8E93] font-semibold mr-1">#{item.id}</span>{item.marke || item.name || 'Unbenannt'}
          </p>
          {item.marke && onMarkeClick && (
            <button
              onClick={(e) => {
                e.stopPropagation();
                onMarkeClick(item.marke!);
              }}
              className="flex-shrink-0 w-5 h-5 rounded-full bg-[#007AFF]/10 hover:bg-[#007AFF]/20 text-[#007AFF] flex items-center justify-center transition active:scale-90"
              title="Marken-Infos"
            >
              <span className="text-xs font-bold">ℹ️</span>
            </button>
          )}
        </div>
        <p className="text-[12px] text-[#8E8E93] truncate mt-0.5 font-medium">
          {item.kategorie}{item.groesse ? ` · Gr. ${item.groesse}` : ''}
        </p>
        {item.verkaufswert ? (
          <div className="mt-2 inline-flex items-center gap-1 px-2.5 py-1 rounded-full bg-green-500/10">
            <span className="text-[12px] font-bold text-green-600">{item.verkaufswert}€</span>
          </div>
        ) : null}
      </div>
    </div>
  );
}

function DetailSheet({ item, imageUrl, editMode, onClose, onEdit, onSave, onUpdate, onImageClick }: {
  item: Item; imageUrl: string | null; editMode: boolean;
  onClose: () => void; onEdit: () => void; onSave: (data: Partial<Item>) => void; onUpdate: (id: number, data: Partial<Item>) => void; onImageClick: (url: string) => void;
}) {
  const [formData, setFormData] = useState(item);
  const [currentItem, setCurrentItem] = useState(item);
  const cfg = statusConfig[currentItem.status] || statusConfig.aktiv;

  return (
    <div className="fixed inset-0 bg-black/30 backdrop-blur-sm z-50 flex items-end sm:items-center justify-center" onClick={onClose}>
      <div className="bg-[#F2F2F7] w-full max-w-lg max-h-[93vh] overflow-y-auto rounded-t-[28px] sm:rounded-[28px] shadow-2xl" onClick={(e) => e.stopPropagation()}>
        <div className="flex justify-center pt-3 sm:hidden"><div className="w-9 h-1 bg-[#C7C7CC] rounded-full" /></div>

        <div className="p-3 pt-2">
          <div className="relative bg-white rounded-[20px] overflow-hidden shadow-sm">
            <div className="aspect-[4/3]">
              {imageUrl ? (
                <img src={imageUrl} alt={item.name || ''} className="w-full h-full object-contain cursor-zoom-in bg-[#F9F9F9]" onClick={() => onImageClick(imageUrl)} />
              ) : (
                <div className="w-full h-full flex items-center justify-center text-7xl opacity-15 bg-[#F9F9F9]">
                  {item.typ === 'kleidung' ? '👕' : '🧸'}
                </div>
              )}
            </div>
            <button onClick={onClose} className="absolute top-3 right-3 w-8 h-8 bg-black/25 hover:bg-black/40 backdrop-blur-md rounded-full text-white flex items-center justify-center transition">
              <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={3}><path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" /></svg>
            </button>
            {imageUrl && (
              <div className="absolute bottom-3 left-1/2 -translate-x-1/2 px-3 py-1.5 bg-black/25 backdrop-blur-md rounded-full text-white text-[11px] font-medium">
                🔍 Tippen zum Vergrößern
              </div>
            )}
          </div>
        </div>

        <div className="px-3 pb-4">
          <div className="bg-white rounded-[20px] shadow-sm overflow-hidden">
            {editMode ? (
              <div className="p-5 space-y-4">
                <div className="grid grid-cols-2 gap-3">
                  <AppleInput label="Marke" value={formData.marke || ''} onChange={v => setFormData({ ...formData, marke: v })} />
                  <AppleInput label="Name" value={formData.name || ''} onChange={v => setFormData({ ...formData, name: v })} />
                  <AppleInput label="Größe" value={formData.groesse || ''} onChange={v => setFormData({ ...formData, groesse: v })} />
                  <AppleInput label="Farbe" value={formData.farbe || ''} onChange={v => setFormData({ ...formData, farbe: v })} />
                  <AppleInput label="Wert (€)" type="number" value={String(formData.verkaufswert || '')} onChange={v => setFormData({ ...formData, verkaufswert: parseFloat(v) || 0 })} />
                  <AppleSelect label="Status" value={formData.status}
                    options={Object.entries(statusConfig).map(([k, v]) => ({ value: k, label: `${v.emoji} ${v.label}` }))}
                    onChange={v => setFormData({ ...formData, status: v })} />
                  <AppleSelect label="Zustand" value={formData.zustand || ''}
                    options={Object.entries(zustandLabels).map(([k, v]) => ({ value: k, label: v }))}
                    onChange={v => setFormData({ ...formData, zustand: v })} />
                </div>
                <div>
                  <label className="text-[12px] font-semibold text-[#8E8E93] uppercase tracking-wide ml-1">Notizen</label>
                  <textarea
                    className="w-full mt-1 px-4 py-3 bg-[#F2F2F7] rounded-xl text-[15px] text-[#1C1C1E] placeholder:text-[#C7C7CC] focus:outline-none focus:ring-2 focus:ring-[#007AFF]/30 resize-none transition"
                    rows={3} value={formData.notizen || ''} onChange={e => setFormData({ ...formData, notizen: e.target.value })}
                  />
                </div>
                <div className="flex gap-3 pt-1">
                  <button onClick={() => { setFormData(item); onClose(); }} className="flex-1 py-3.5 bg-[#F2F2F7] hover:bg-[#E5E5EA] text-[#1C1C1E] rounded-2xl font-semibold text-[15px] transition">
                    Abbrechen
                  </button>
                  <button onClick={() => onSave({ name: formData.name, marke: formData.marke, groesse: formData.groesse, farbe: formData.farbe, zustand: formData.zustand, status: formData.status, verkaufswert: formData.verkaufswert, notizen: formData.notizen })}
                    className="flex-1 py-3.5 bg-[#007AFF] hover:bg-[#0066D6] text-white rounded-2xl font-semibold text-[15px] transition shadow-sm">
                    Speichern ✓
                  </button>
                </div>
              </div>
            ) : (
              <div className="p-5 space-y-5">
                <div>
                  <h2 className="text-[22px] font-bold text-[#1C1C1E] leading-tight">
                    <span className="text-[13px] text-[#8E8E93] font-semibold mr-1.5">#{item.id}</span>{item.marke}{item.marke && item.name ? ' ' : ''}{item.name || ''}
                  </h2>
                  <p className="text-[14px] text-[#8E8E93] mt-1 font-medium">
                    {item.kategorie}{item.unterkategorie ? ` › ${item.unterkategorie}` : ''}
                  </p>
                </div>

                <button
                  onClick={async () => {
                    const newStatus = currentItem.status === 'aktiv' ? 'eingelagert' : 'aktiv';
                    await onUpdate(currentItem.id, { status: newStatus });
                    setCurrentItem({ ...currentItem, status: newStatus });
                  }}
                  className={`inline-flex items-center gap-2 px-4 py-2 rounded-2xl bg-gradient-to-r ${cfg.gradient} active:scale-95 transition-transform`}
                >
                  <span className="text-base">{cfg.emoji}</span>
                  <span className="text-[14px] font-bold text-white">{cfg.label}</span>
                  <span className="text-white/70 text-[12px] ml-1">↔️ tippen zum wechseln</span>
                </button>

                <div className="bg-[#F2F2F7] rounded-2xl overflow-hidden divide-y divide-[#C6C6C8]/30">
                  <InfoRow icon="📏" label="Größe" value={item.groesse} />
                  <InfoRow icon="🎨" label="Farbe" value={item.farbe} />
                  <InfoRow icon="⭐" label="Zustand" value={item.zustand ? zustandLabels[item.zustand] || item.zustand : undefined} />
                  <InfoRow icon="🧶" label="Material" value={item.material} />
                  <InfoRow icon="🌤️" label="Saison" value={item.saison} />
                  <InfoRow icon="💰" label="Wert" value={item.verkaufswert ? `${item.verkaufswert}€` : undefined} valueColor="text-green-600" />
                  <InfoRow icon="📅" label="Erfasst" value={new Date(item.erfasst_am).toLocaleDateString('de-DE', { day: '2-digit', month: 'short', year: 'numeric' })} />
                </div>

                {item.notizen && (
                  <div className="bg-[#FFF9DB] rounded-2xl p-4">
                    <p className="text-[12px] font-bold text-[#B8860B] uppercase tracking-wider mb-1">📝 Notizen</p>
                    <p className="text-[14px] text-[#5C4A00] leading-relaxed">{item.notizen}</p>
                  </div>
                )}

                <button onClick={onEdit} className="w-full py-3.5 bg-[#007AFF] hover:bg-[#0066D6] text-white rounded-2xl font-semibold text-[15px] transition shadow-sm">
                  ✏️ Bearbeiten
                </button>
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

function InfoRow({ icon, label, value, valueColor }: { icon: string; label: string; value?: string; valueColor?: string }) {
  if (!value) return null;
  return (
    <div className="flex items-center justify-between px-4 py-3.5">
      <span className="flex items-center gap-2.5">
        <span className="text-base">{icon}</span>
        <span className="text-[15px] text-[#1C1C1E]">{label}</span>
      </span>
      <span className={`text-[15px] font-semibold ${valueColor || 'text-[#8E8E93]'}`}>{value}</span>
    </div>
  );
}

function AppleInput({ label, value, onChange, type = 'text' }: { label: string; value: string; onChange: (v: string) => void; type?: string }) {
  return (
    <div>
      <label className="text-[12px] font-semibold text-[#8E8E93] uppercase tracking-wide ml-1">{label}</label>
      <input type={type} className="w-full mt-1 px-4 py-3 bg-[#F2F2F7] rounded-xl text-[15px] text-[#1C1C1E] placeholder:text-[#C7C7CC] focus:outline-none focus:ring-2 focus:ring-[#007AFF]/30 transition" value={value} onChange={e => onChange(e.target.value)} />
    </div>
  );
}

function AppleSelect({ label, value, options, onChange }: { label: string; value: string; options: { value: string; label: string }[]; onChange: (v: string) => void }) {
  return (
    <div>
      <label className="text-[12px] font-semibold text-[#8E8E93] uppercase tracking-wide ml-1">{label}</label>
      <select className="w-full mt-1 px-4 py-3 bg-[#F2F2F7] rounded-xl text-[15px] text-[#1C1C1E] focus:outline-none focus:ring-2 focus:ring-[#007AFF]/30 appearance-none cursor-pointer transition" value={value} onChange={e => onChange(e.target.value)}>
        {options.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
      </select>
    </div>
  );
}

function MarkenInfoModal({ marke, onClose }: { marke: Marke; onClose: () => void }) {
  const hasInfo = marke.groessen_info || marke.herkunft || marke.material_fokus || marke.website || marke.preis_segment;
  
  return (
    <div className="fixed inset-0 bg-black/30 backdrop-blur-sm z-50 flex items-end sm:items-center justify-center" onClick={onClose}>
      <div className="bg-[#F2F2F7] w-full max-w-lg max-h-[85vh] overflow-y-auto rounded-t-[28px] sm:rounded-[28px] shadow-2xl" onClick={(e) => e.stopPropagation()}>
        <div className="flex justify-center pt-3 sm:hidden"><div className="w-9 h-1 bg-[#C7C7CC] rounded-full" /></div>

        <div className="p-5 space-y-4">
          <div className="flex items-start justify-between">
            <div>
              <h2 className="text-[24px] font-bold text-[#1C1C1E] leading-tight flex items-center gap-2">
                🏷️ {marke.name}
              </h2>
              {marke.angereichert_am && (
                <p className="text-[12px] text-[#8E8E93] mt-1">
                  Angereichert: {new Date(marke.angereichert_am).toLocaleDateString('de-DE', { day: '2-digit', month: 'short', year: 'numeric' })}
                </p>
              )}
            </div>
            <button onClick={onClose} className="w-8 h-8 bg-[#C7C7CC]/30 hover:bg-[#C7C7CC]/50 rounded-full text-[#1C1C1E] flex items-center justify-center transition flex-shrink-0">
              <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={3}><path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" /></svg>
            </button>
          </div>

          {hasInfo ? (
            <>
              {marke.groessen_info && (
                <div className="bg-gradient-to-br from-blue-50 to-indigo-50 rounded-2xl p-5 border border-blue-100 shadow-sm">
                  <div className="flex items-start gap-3">
                    <div className="text-2xl">📏</div>
                    <div className="flex-1">
                      <h3 className="text-[14px] font-bold text-[#1C1C1E] mb-2">Wie fallen die Größen aus?</h3>
                      <p className="text-[15px] text-[#1C1C1E] leading-relaxed">{marke.groessen_info}</p>
                    </div>
                  </div>
                </div>
              )}

              <div className="bg-white rounded-2xl overflow-hidden shadow-sm divide-y divide-[#C6C6C8]/30">
                {marke.herkunft && (
                  <div className="flex items-center justify-between px-4 py-3.5">
                    <span className="flex items-center gap-2.5">
                      <span className="text-base">🌍</span>
                      <span className="text-[15px] text-[#1C1C1E]">Herkunft</span>
                    </span>
                    <span className="text-[15px] font-semibold text-[#8E8E93]">{marke.herkunft}</span>
                  </div>
                )}
                {marke.material_fokus && (
                  <div className="px-4 py-3.5">
                    <div className="flex items-start gap-2.5">
                      <span className="text-base">🧶</span>
                      <div className="flex-1">
                        <span className="text-[15px] text-[#1C1C1E] block mb-1">Material-Fokus</span>
                        <span className="text-[14px] text-[#8E8E93]">{marke.material_fokus}</span>
                      </div>
                    </div>
                  </div>
                )}
                {marke.preis_segment && (
                  <div className="flex items-center justify-between px-4 py-3.5">
                    <span className="flex items-center gap-2.5">
                      <span className="text-base">💰</span>
                      <span className="text-[15px] text-[#1C1C1E]">Preissegment</span>
                    </span>
                    <span className="text-[15px] font-semibold text-[#8E8E93] capitalize">{marke.preis_segment}</span>
                  </div>
                )}
                {marke.website && (
                  <div className="px-4 py-3.5">
                    <a href={marke.website.startsWith('http') ? marke.website : `https://${marke.website}`} target="_blank" rel="noopener noreferrer" className="flex items-center gap-2.5 text-[#007AFF] hover:text-[#0066D6] transition">
                      <span className="text-base">🔗</span>
                      <span className="text-[15px] font-medium">Website besuchen →</span>
                    </a>
                  </div>
                )}
              </div>

              {marke.notizen && (
                <div className="bg-yellow-50 rounded-2xl p-4 border border-yellow-100">
                  <p className="text-[12px] font-bold text-yellow-700 uppercase tracking-wider mb-1">📝 Notizen</p>
                  <p className="text-[14px] text-yellow-900 leading-relaxed">{marke.notizen}</p>
                </div>
              )}
            </>
          ) : (
            <div className="bg-[#F9F9F9] rounded-2xl p-8 text-center">
              <div className="text-5xl mb-3 opacity-30">🔍</div>
              <p className="text-[16px] font-semibold text-[#1C1C1E] mb-1">Noch keine Infos vorhanden</p>
              <p className="text-[14px] text-[#8E8E93]">Diese Marke wird automatisch angereichert.</p>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
