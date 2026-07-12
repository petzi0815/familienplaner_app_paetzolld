'use client';

import { useState, useEffect, useCallback } from 'react';
import Link from 'next/link';

interface Pflanze {
  id: number;
  name: string;
  art: string;
  sorte?: string;
  standort?: string;
  beschreibung?: string;
  bewaesserung: 'hunter' | 'manuell';
  status: 'aktiv' | 'entfernt';
  bild_pfade?: string;
  erfasst_am: string;
  notizen?: string;
}

interface Samen {
  id: number;
  nummer: string;
  name: string;
  art?: string;
  sorte?: string;
  beschreibung?: string;
  pflanz_von?: number;
  pflanz_bis?: number;
  vorziehen_ab?: number;
  ernte_von?: number;
  ernte_bis?: number;
  aussaat_2_von?: number;
  aussaat_2_bis?: number;
  ernte_2_von?: number;
  ernte_2_bis?: number;
  standort_empfehlung?: string;
  abstand_cm?: number;
  tiefe_cm?: number;
  keimzeit_tage?: number;
  hersteller?: string;
  bio?: string;
  samenfest?: number;
  botanisch?: string;
  keimtemp?: string;
  keimfaehig_bis?: string;
  inhalt?: string;
  verwendung?: string;
  typ?: string;
  herkunft?: string;
  besonderheiten?: string;
  aktiv: number;
  bild_pfade?: string;
  erfasst_am: string;
  aktualisiert_am?: string;
  metadata?: string;
  notizen?: string;
}

interface Aufgabe {
  id: number;
  pflanze_id?: number;
  samen_id?: number;
  duenger_id?: number;
  duenger_name?: string;
  duenger_vorraetig?: number;
  titel: string;
  beschreibung?: string;
  kategorie: string;
  monat: number;
  geplant_monat?: number;
  jahr: number;
  erledigt: number;
  erledigt_am?: string;
  prioritaet: 'niedrig' | 'normal' | 'hoch';
  wiederholung?: string;
  notizen?: string;
  _overdue?: boolean;
  _originalMonat?: number;
}

interface Duenger {
  id: number;
  name: string;
  marke?: string;
  typ?: string;
  beschreibung?: string;
  geeignet_fuer?: string;
  naehrstoffe?: string;
  dosierung?: string;
  intervall_wochen?: number;
  saison_von?: number;
  saison_bis?: number;
  vorraetig: number;
  kauflink?: string;
  bild_pfade?: string;
  erfasst_am: string;
  notizen?: string;
}

interface GardenStats {
  pflanzen: { gesamt: number; aktiv: number; nach_art: { art: string; count: number }[] };
  samen: { gesamt: number; aktiv: number };
  aufgaben: { gesamt: number; offen: number; erledigt: number };
  duenger?: { gesamt: number; vorraetig: number; fehlend: number };
}

const artEmojis: Record<string, string> = {
  baum: '🌳',
  strauch: '🌿',
  staude: '🌺',
  blume: '🌸',
  gras: '🌾',
  hecke: '🌳',
  kletterpflanze: '🌿',
  bodendecker: '🍀',
};

const kategorieConfig: Record<string, { emoji: string; color: string; label: string }> = {
  duengen: { emoji: '🌱', color: 'bg-green-500', label: 'Düngen' },
  schneiden: { emoji: '✂️', color: 'bg-orange-500', label: 'Schneiden' },
  giessen: { emoji: '💧', color: 'bg-blue-500', label: 'Wässern' },
  pflanzen: { emoji: '🌱', color: 'bg-emerald-500', label: 'Pflanzen' },
  ernten: { emoji: '🌽', color: 'bg-amber-500', label: 'Ernten' },
  maehen: { emoji: '🟡', color: 'bg-yellow-500', label: 'Mähen' },
  lueften: { emoji: '💨', color: 'bg-cyan-500', label: 'Lüften' },
  aerifizieren: { emoji: '🔵', color: 'bg-indigo-500', label: 'Aerifizieren' },
  sanden: { emoji: '🟤', color: 'bg-amber-600', label: 'Sanden' },
  nachsaeen: { emoji: '🌱', color: 'bg-lime-500', label: 'Nachsäen' },
  bodenanalyse: { emoji: '🔬', color: 'bg-purple-500', label: 'Bodenanalyse' },
  ph_messen: { emoji: '⚗️', color: 'bg-violet-500', label: 'pH messen' },
  vorziehen: { emoji: '🌱', color: 'bg-teal-500', label: 'Vorziehen' },
};

const monatNamen = ['', 'Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun', 'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez'];

type Tab = 'pflanzen' | 'samen' | 'pflegeplan' | 'pflanzplan' | 'duenger';

export default function Garten() {
  const [activeTab, setActiveTab] = useState<Tab>('pflanzen');
  const [loading, setLoading] = useState(true);
  const [stats, setStats] = useState<GardenStats | null>(null);
  const [showRules, setShowRules] = useState(false);
  const [gtsData, setGtsData] = useState<any>(null);
  const [showGtsDetail, setShowGtsDetail] = useState(false);

  // Pflanzen State
  const [pflanzen, setPflanzen] = useState<Pflanze[]>([]);
  const [pflanzenFilter, setPflanzenFilter] = useState({ art: '', bewaesserung: '', search: '' });
  const [availableArten, setAvailableArten] = useState<string[]>([]);

  // Samen State
  const [samen, setSamen] = useState<Samen[]>([]);
  const [samenFilter, setSamenFilter] = useState({ 
    aktiv: 1, 
    search: '', 
    hersteller: '',
    bio: '',
    typ: '',
    samenfest: -1, // -1 = alle, 0 = nicht samenfest, 1 = samenfest
    keimfaehig: '' // '' = alle, 'ok' | 'abgelaufen' | 'unbekannt'
  });

  // Aufgaben State
  const [aufgaben, setAufgaben] = useState<Aufgabe[]>([]);
  const [aufgabenFilter, setAufgabenFilter] = useState({ jahr: 2026, erledigt: -1, bereich: 'alle' as 'alle' | 'rasen' | 'baeume' | 'anzucht' }); // -1 = alle

  // Dünger State
  const [duenger, setDuenger] = useState<Duenger[]>([]);
  const [duengerFilter, setDuengerFilter] = useState({ typ: '', vorraetig: -1, search: '' });
  const [selectedDuenger, setSelectedDuenger] = useState<Duenger | null>(null);
  const [showAddDuenger, setShowAddDuenger] = useState(false);
  const [newDuengerName, setNewDuengerName] = useState('');
  const [duengerToast, setDuengerToast] = useState('');

  const fetchStats = async () => {
    const res = await fetch('/api/garten/stats');
    setStats(await res.json());
  };

  const fetchPflanzen = useCallback(async () => {
    const params = new URLSearchParams();
    if (pflanzenFilter.art) params.set('art', pflanzenFilter.art);
    if (pflanzenFilter.bewaesserung) params.set('bewaesserung', pflanzenFilter.bewaesserung);
    if (pflanzenFilter.search) params.set('search', pflanzenFilter.search);
    params.set('status', 'aktiv');
    const res = await fetch(`/api/garten/pflanzen?${params}`);
    setPflanzen(await res.json());
  }, [pflanzenFilter]);

  const fetchArten = async () => {
    const res = await fetch('/api/garten/pflanzen?arten=true');
    setAvailableArten(await res.json());
  };

  const fetchSamen = useCallback(async () => {
    const params = new URLSearchParams();
    if (samenFilter.aktiv !== -1) params.set('aktiv', String(samenFilter.aktiv));
    if (samenFilter.search) params.set('search', samenFilter.search);
    if (samenFilter.hersteller) params.set('hersteller', samenFilter.hersteller);
    if (samenFilter.bio) params.set('bio', samenFilter.bio);
    if (samenFilter.typ) params.set('typ', samenFilter.typ);
    if (samenFilter.samenfest !== -1) params.set('samenfest', String(samenFilter.samenfest));
    if (samenFilter.keimfaehig) params.set('keimfaehig', samenFilter.keimfaehig);
    const res = await fetch(`/api/garten/samen?${params}`);
    setSamen(await res.json());
  }, [samenFilter]);

  const fetchDuenger = useCallback(async () => {
    const params = new URLSearchParams();
    if (duengerFilter.typ) params.set('typ', duengerFilter.typ);
    if (duengerFilter.vorraetig !== -1) params.set('vorraetig', String(duengerFilter.vorraetig));
    if (duengerFilter.search) params.set('search', duengerFilter.search);
    const res = await fetch(`/api/garten/duenger?${params}`);
    setDuenger(await res.json());
  }, [duengerFilter]);

  const fetchAufgaben = useCallback(async () => {
    const params = new URLSearchParams();
    params.set('jahr', String(aufgabenFilter.jahr));
    if (aufgabenFilter.erledigt !== -1) params.set('erledigt', String(aufgabenFilter.erledigt));
    if (aufgabenFilter.bereich !== 'alle') params.set('bereich', aufgabenFilter.bereich);
    const res = await fetch(`/api/garten/aufgaben?${params}`);
    setAufgaben(await res.json());
  }, [aufgabenFilter]);

  const fetchGts = async () => {
    try {
      const res = await fetch('/api/garten/gts');
      if (res.ok) setGtsData(await res.json());
    } catch (e) { /* silent */ }
  };

  useEffect(() => {
    Promise.all([fetchStats(), fetchArten(), fetchGts()]).then(() => setLoading(false));
  }, []);

  useEffect(() => { if (activeTab === 'pflanzen') fetchPflanzen(); }, [activeTab, pflanzenFilter, fetchPflanzen]);
  useEffect(() => { if (activeTab === 'samen' || activeTab === 'pflanzplan') fetchSamen(); }, [activeTab, samenFilter, fetchSamen]);
  useEffect(() => { if (activeTab === 'pflegeplan' || activeTab === 'pflanzplan') fetchAufgaben(); }, [activeTab, aufgabenFilter, fetchAufgaben]);
  useEffect(() => { if (activeTab === 'duenger') fetchDuenger(); }, [activeTab, duengerFilter, fetchDuenger]);

  const toggleAufgabeErledigt = async (aufgabe: Aufgabe) => {
    await fetch(`/api/garten/aufgaben/${aufgabe.id}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ erledigt: aufgabe.erledigt ? 0 : 1 }),
    });
    await Promise.all([fetchAufgaben(), fetchStats()]);
  };

  const shiftAufgabeMonat = async (aufgabe: Aufgabe, delta: number) => {
    const current = aufgabe.geplant_monat || aufgabe.monat;
    const newMonat = Math.max(1, Math.min(12, current + delta));
    if (newMonat === current) return;
    await fetch(`/api/garten/aufgaben/${aufgabe.id}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ geplant_monat: newMonat }),
    });
    await fetchAufgaben();
  };

  const [selectedPflanze, setSelectedPflanze] = useState<Pflanze | null>(null);
  const [selectedSamen, setSelectedSamen] = useState<Samen | null>(null);
  const [neuerSamenName, setNeuerSamenName] = useState('');
  const [showAddSamen, setShowAddSamen] = useState(false);
  const [samenToast, setSamenToast] = useState(false);

  const addNeuerSamen = async () => {
    if (!neuerSamenName.trim()) return;
    const existingSamen = samen.length;
    const nextNummer = String(existingSamen + 1).padStart(3, '0');
    await fetch('/api/garten/samen', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ nummer: nextNummer, name: neuerSamenName.trim(), aktiv: 1 }),
    });
    setNeuerSamenName('');
    setShowAddSamen(false);
    await fetchSamen();
    setSamenToast(true);
    setTimeout(() => setSamenToast(false), 5000);
  };

  const deleteSamenHandler = async (id: number) => {
    if (!window.confirm('Samen wirklich löschen?')) return;
    await fetch(`/api/garten/samen/${id}`, { method: 'DELETE' });
    setSelectedSamen(null);
    await Promise.all([fetchSamen(), fetchStats()]);
  };

  const toggleSamenAktiv = async (s: Samen) => {
    await fetch(`/api/garten/samen/${s.id}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ aktiv: s.aktiv ? 0 : 1 }),
    });
    await fetchSamen();
  };

  const addNeuerDuenger = async () => {
    if (!newDuengerName.trim()) return;
    await fetch('/api/garten/duenger', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name: newDuengerName.trim(), vorraetig: 1 }),
    });
    setNewDuengerName('');
    setShowAddDuenger(false);
    await Promise.all([fetchDuenger(), fetchStats()]);
    setDuengerToast('✅ Dünger angelegt!');
    setTimeout(() => setDuengerToast(''), 4000);
  };

  const deleteDuengerHandler = async (id: number) => {
    if (!window.confirm('Dünger wirklich löschen?')) return;
    await fetch(`/api/garten/duenger?id=${id}`, { method: 'DELETE' });
    setSelectedDuenger(null);
    await Promise.all([fetchDuenger(), fetchStats()]);
  };

  const toggleDuengerVorraetig = async (d: Duenger) => {
    await fetch('/api/garten/duenger', {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id: d.id, vorraetig: d.vorraetig ? 0 : 1 }),
    });
    if (selectedDuenger?.id === d.id) setSelectedDuenger({ ...selectedDuenger, vorraetig: d.vorraetig ? 0 : 1 });
    await fetchDuenger();
  };

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-[#F2F2F7]">
        <div className="flex flex-col items-center gap-4">
          <div className="text-5xl animate-bounce">🌱</div>
          <p className="text-[#8E8E93] text-sm font-medium">Laden…</p>
        </div>
      </div>
    );
  }

  const currentMonth = new Date().getMonth() + 1;

  return (
    <main className="min-h-screen pb-24 bg-[#F2F2F7]">
      {/* ── Compact Header ── */}
      <header className="relative overflow-hidden bg-gradient-to-br from-[#34C759] via-[#30D158] to-[#00C7BE] pt-4 pb-4 px-5 safe-area-inset">
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
              <h1 className="text-2xl font-extrabold text-white tracking-tight">Garten</h1>
              {stats && (
                <p className="text-white/80 text-xs font-medium">{stats.pflanzen.aktiv} Pflanzen · {stats.samen.aktiv} Samen · {stats.aufgaben.offen} offen</p>
              )}
            </div>
            <div className="text-4xl drop-shadow-lg">🌱</div>
          </div>
          {/* GTS Badge */}
          {gtsData && (
            <button
              onClick={() => setShowGtsDetail(!showGtsDetail)}
              className="mt-2 flex items-center gap-2 bg-white/20 backdrop-blur-sm rounded-xl px-3 py-1.5 hover:bg-white/30 active:scale-95 transition"
            >
              <span className="text-xs">🌡️</span>
              <span className="text-white font-bold text-sm">GTS {Math.round(gtsData.gts_current)}</span>
              <span className="text-white/70 text-xs">/ 200</span>
              <div className="flex-1 h-1.5 bg-white/20 rounded-full min-w-[60px] overflow-hidden">
                <div
                  className="h-full rounded-full transition-all duration-1000"
                  style={{
                    width: `${Math.min(100, (gtsData.gts_current / 200) * 100)}%`,
                    background: gtsData.gts_current >= 200 ? '#34D399' : gtsData.gts_current >= 150 ? '#FBBF24' : '#FCA5A5',
                  }}
                />
              </div>
              <svg className={`w-3.5 h-3.5 text-white/70 transition-transform ${showGtsDetail ? 'rotate-180' : ''}`} fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2.5}>
                <path strokeLinecap="round" strokeLinejoin="round" d="M19 9l-7 7-7-7" />
              </svg>
            </button>
          )}
        </div>
      </header>

      {/* GTS Detail Panel */}
      {showGtsDetail && gtsData && <GTSDetailPanel gtsData={gtsData} />}

      {/* ── Tabs ── */}
      <div className="max-w-xl mx-auto px-4 -mt-5 relative z-10">
        <div className="bg-white rounded-2xl shadow-sm border border-black/5 p-1.5 flex gap-1 overflow-x-auto">
          <TabButton label="🌳" active={activeTab === 'pflanzen'} onClick={() => setActiveTab('pflanzen')} />
          <TabButton label="🌱" active={activeTab === 'samen'} onClick={() => setActiveTab('samen')} />
          <TabButton label="📋" active={activeTab === 'pflegeplan'} onClick={() => setActiveTab('pflegeplan')} />
          <TabButton label="🗓️" active={activeTab === 'pflanzplan'} onClick={() => setActiveTab('pflanzplan')} />
          <TabButton label="💩" active={activeTab === 'duenger'} onClick={() => setActiveTab('duenger')} />
        </div>
        <div className="flex justify-around mt-1 px-1">
          {(['pflanzen','samen','pflegeplan','pflanzplan','duenger'] as Tab[]).map((t, i) => (
            <span key={t} className={`text-[9px] font-semibold text-center flex-1 ${activeTab === t ? 'text-[#34C759]' : 'text-[#AEAEB2]'}`}>
              {['Pflanzen','Samen','Pflege','Pflanz','Dünger'][i]}
            </span>
          ))}
        </div>
      </div>

      {/* ── Tab Content ── */}
      <div className="max-w-xl mx-auto px-4 pt-5">
        {/* ── PFLANZEN TAB ── */}
        {activeTab === 'pflanzen' && (
          <>
            {/* Search & Filters */}
            <div className="space-y-3 mb-4">
              <input
                type="search"
                placeholder="Pflanzen suchen…"
                className="w-full px-4 py-3 rounded-2xl bg-white text-[15px] text-[#1C1C1E] placeholder:text-[#8E8E93] border border-black/5 focus:outline-none focus:ring-2 focus:ring-[#34C759]/30 shadow-sm transition"
                value={pflanzenFilter.search}
                onChange={(e) => setPflanzenFilter({ ...pflanzenFilter, search: e.target.value })}
              />
              <div className="flex gap-2 overflow-x-auto pb-1">
                <Pill label="Alle" active={!pflanzenFilter.art} onClick={() => setPflanzenFilter({ ...pflanzenFilter, art: '' })} />
                {availableArten.map(art => (
                  <Pill
                    key={art}
                    label={`${artEmojis[art] || '🌿'} ${art.charAt(0).toUpperCase() + art.slice(1)}`}
                    active={pflanzenFilter.art === art}
                    onClick={() => setPflanzenFilter({ ...pflanzenFilter, art: pflanzenFilter.art === art ? '' : art })}
                  />
                ))}
              </div>
              <div className="flex gap-2">
                <Pill label="💧 Hunter" active={pflanzenFilter.bewaesserung === 'hunter'} onClick={() => setPflanzenFilter({ ...pflanzenFilter, bewaesserung: pflanzenFilter.bewaesserung === 'hunter' ? '' : 'hunter' })} />
                <Pill label="🪣 Manuell" active={pflanzenFilter.bewaesserung === 'manuell'} onClick={() => setPflanzenFilter({ ...pflanzenFilter, bewaesserung: pflanzenFilter.bewaesserung === 'manuell' ? '' : 'manuell' })} />
              </div>
            </div>

            {/* Pflanzen Grid */}
            <div className="grid grid-cols-2 gap-3">
              {pflanzen.map(p => (
                <PflanzeCard key={p.id} pflanze={p} onClick={() => setSelectedPflanze(p)} />
              ))}
            </div>

            {pflanzen.length === 0 && (
              <div className="text-center py-20">
                <div className="text-6xl mb-4">🔍</div>
                <p className="text-[#8E8E93] font-semibold">Keine Pflanzen gefunden!</p>
              </div>
            )}
          </>
        )}

        {/* ── SAMEN TAB ── */}
        {activeTab === 'samen' && (
          <>
            {/* Search & Filters */}
            <div className="space-y-3 mb-4">
              <input
                type="search"
                placeholder="Samen suchen…"
                className="w-full px-4 py-3 rounded-2xl bg-white text-[15px] text-[#1C1C1E] placeholder:text-[#8E8E93] border border-black/5 focus:outline-none focus:ring-2 focus:ring-[#34C759]/30 shadow-sm transition"
                value={samenFilter.search}
                onChange={(e) => setSamenFilter({ ...samenFilter, search: e.target.value })}
              />
              <div className="flex gap-2 flex-wrap">
                <Pill label="✅ Aktiv" active={samenFilter.aktiv === 1} onClick={() => setSamenFilter({ ...samenFilter, aktiv: samenFilter.aktiv === 1 ? -1 : 1 })} />
                <Pill label="⏸️ Inaktiv" active={samenFilter.aktiv === 0} onClick={() => setSamenFilter({ ...samenFilter, aktiv: samenFilter.aktiv === 0 ? -1 : 0 })} />
                <Pill label="🌱 Samenfest" active={samenFilter.samenfest === 1} onClick={() => setSamenFilter({ ...samenFilter, samenfest: samenFilter.samenfest === 1 ? -1 : 1 })} />
                <Pill label="✅ Keimfähig" active={samenFilter.keimfaehig === 'ok'} onClick={() => setSamenFilter({ ...samenFilter, keimfaehig: samenFilter.keimfaehig === 'ok' ? '' : 'ok' })} />
                <Pill label="⚠️ Abgelaufen" active={samenFilter.keimfaehig === 'abgelaufen'} onClick={() => setSamenFilter({ ...samenFilter, keimfaehig: samenFilter.keimfaehig === 'abgelaufen' ? '' : 'abgelaufen' })} />
              </div>
              
              {/* Erweiterte Filter (Dropdowns) */}
              <div className="flex gap-2 flex-wrap">
                <select 
                  className="px-3 py-2 rounded-xl bg-white text-sm border border-black/10 focus:outline-none focus:ring-2 focus:ring-[#34C759]/30"
                  value={samenFilter.hersteller}
                  onChange={(e) => setSamenFilter({ ...samenFilter, hersteller: e.target.value })}
                >
                  <option value="">Alle Hersteller</option>
                  {Array.from(new Set(samen.map(s => s.hersteller).filter(Boolean))).sort().map(h => (
                    <option key={h} value={h}>{h}</option>
                  ))}
                </select>
                
                <select 
                  className="px-3 py-2 rounded-xl bg-white text-sm border border-black/10 focus:outline-none focus:ring-2 focus:ring-[#34C759]/30"
                  value={samenFilter.bio}
                  onChange={(e) => setSamenFilter({ ...samenFilter, bio: e.target.value })}
                >
                  <option value="">Alle Bio-Zertifizierungen</option>
                  <option value="Bio">Bio</option>
                  <option value="Demeter">Demeter</option>
                </select>
                
                <select 
                  className="px-3 py-2 rounded-xl bg-white text-sm border border-black/10 focus:outline-none focus:ring-2 focus:ring-[#34C759]/30"
                  value={samenFilter.typ}
                  onChange={(e) => setSamenFilter({ ...samenFilter, typ: e.target.value })}
                >
                  <option value="">Alle Typen</option>
                  {Array.from(new Set(samen.map(s => s.typ).filter(Boolean))).sort().map(t => (
                    <option key={t} value={t}>{t}</option>
                  ))}
                </select>
              </div>
            </div>

            {/* Add Samen */}
            {showAddSamen ? (
              <div className="bg-white rounded-2xl p-4 shadow-sm border border-black/5 mb-4">
                <h3 className="text-[15px] font-bold text-[#1C1C1E] mb-3">🌱 Neuen Samen hinzufügen</h3>
                <div className="flex gap-2">
                  <input
                    type="text"
                    placeholder="Name eingeben…"
                    className="flex-1 px-4 py-3 rounded-xl bg-[#F2F2F7] text-[15px] text-[#1C1C1E] placeholder:text-[#8E8E93] focus:outline-none focus:ring-2 focus:ring-[#34C759]/30 transition"
                    value={neuerSamenName}
                    onChange={(e) => setNeuerSamenName(e.target.value)}
                    onKeyDown={(e) => e.key === 'Enter' && addNeuerSamen()}
                    autoFocus
                  />
                  <button onClick={addNeuerSamen} className="px-5 py-3 bg-[#34C759] text-white rounded-xl font-semibold text-[15px] transition hover:bg-[#2DB84D] active:scale-95">
                    ✓
                  </button>
                  <button onClick={() => { setShowAddSamen(false); setNeuerSamenName(''); }} className="px-4 py-3 bg-[#F2F2F7] text-[#8E8E93] rounded-xl font-semibold text-[15px] transition hover:bg-[#E5E5EA]">
                    ✕
                  </button>
                </div>
              </div>
            ) : (
              <button
                onClick={() => setShowAddSamen(true)}
                className="w-full mb-4 py-3.5 bg-[#34C759] hover:bg-[#2DB84D] text-white rounded-2xl font-semibold text-[15px] transition shadow-sm active:scale-[0.98]"
              >
                ＋ Neuen Samen hinzufügen
              </button>
            )}

            {/* Toast */}
            {samenToast && (
              <div className="bg-emerald-50 border border-emerald-200 rounded-2xl p-4 mb-4 animate-pulse">
                <p className="text-[14px] text-emerald-800 font-medium">✨ Samen angelegt! Ole reichert die Daten automatisch an (Pflanzzeit, Ernte, Standort, Bild).</p>
              </div>
            )}

            {/* Samen List */}
            <div className="space-y-3">
              {samen.map(s => (
                <SamenCard key={s.id} samen={s} onToggle={() => toggleSamenAktiv(s)} onClick={() => setSelectedSamen(s)} />
              ))}
            </div>

            {samen.length === 0 && (
              <div className="text-center py-20">
                <div className="text-6xl mb-4">🔍</div>
                <p className="text-[#8E8E93] font-semibold">Keine Samen gefunden!</p>
              </div>
            )}
          </>
        )}

        {/* ── PFLEGEPLAN TAB ── */}
        {activeTab === 'pflegeplan' && (
          <>
            {/* Bereich-Filter */}
            <div className="flex gap-2 mb-3 overflow-x-auto pb-1">
              <Pill label="📋 Alle" active={aufgabenFilter.bereich === 'alle'} onClick={() => setAufgabenFilter({ ...aufgabenFilter, bereich: 'alle' })} />
              <Pill label="🌿 Rasen" active={aufgabenFilter.bereich === 'rasen'} onClick={() => setAufgabenFilter({ ...aufgabenFilter, bereich: 'rasen' })} />
              <Pill label="🌳 Bäume" active={aufgabenFilter.bereich === 'baeume'} onClick={() => setAufgabenFilter({ ...aufgabenFilter, bereich: 'baeume' })} />
              <Pill label="🌱 Anzucht" active={aufgabenFilter.bereich === 'anzucht'} onClick={() => setAufgabenFilter({ ...aufgabenFilter, bereich: 'anzucht' })} />
            </div>
            
            {/* Status-Filter */}
            <div className="flex gap-2 mb-4 overflow-x-auto pb-1">
              <Pill label="📋 Alle" active={aufgabenFilter.erledigt === -1} onClick={() => setAufgabenFilter({ ...aufgabenFilter, erledigt: -1 })} />
              <Pill label="⏳ Offen" active={aufgabenFilter.erledigt === 0} onClick={() => setAufgabenFilter({ ...aufgabenFilter, erledigt: 0 })} />
              <Pill label="✅ Erledigt" active={aufgabenFilter.erledigt === 1} onClick={() => setAufgabenFilter({ ...aufgabenFilter, erledigt: 1 })} />
            </div>

            {/* Timeline by Month */}
            <div className="space-y-4">
              {[...Array(12)].map((_, i) => {
                const monat = i + 1;
                // Normal tasks for this month (use geplant_monat if set)
                let monatsAufgaben = aufgaben.filter(a => (a.geplant_monat || a.monat) === monat);
                // Add overdue tasks (from past months, not completed) to current month
                if (monat === currentMonth) {
                  const overdue = aufgaben.filter(a => (a.geplant_monat || a.monat) < currentMonth && !a.erledigt);
                  overdue.forEach(a => {
                    if (!monatsAufgaben.find(m => m.id === a.id)) {
                      monatsAufgaben.push({ ...a, _overdue: true, _originalMonat: (a.geplant_monat || a.monat) });
                    }
                  });
                }
                // Hide past months that only had tasks which are now overdue (and moved to current)
                if (monat < currentMonth) {
                  monatsAufgaben = monatsAufgaben.filter(a => a.erledigt);
                  if (monatsAufgaben.length === 0) return null;
                }
                if (monatsAufgaben.length === 0) return null;

                const isCurrentMonth = monat === currentMonth;

                return (
                  <div key={monat} className={`rounded-2xl border-2 overflow-hidden ${isCurrentMonth ? 'border-emerald-500 shadow-lg' : 'border-black/5'}`}>
                    <div className={`px-4 py-3 ${isCurrentMonth ? 'bg-gradient-to-r from-emerald-500 to-green-500' : 'bg-white'}`}>
                      <div className="flex items-center justify-between">
                        <h3 className={`text-[16px] font-bold ${isCurrentMonth ? 'text-white' : 'text-[#1C1C1E]'}`}>
                          {monatNamen[monat]} 2026
                          {isCurrentMonth && <span className="ml-2 text-sm">← Aktuell</span>}
                        </h3>
                        <span className={`text-[13px] font-semibold ${isCurrentMonth ? 'text-white/80' : 'text-[#8E8E93]'}`}>
                          {monatsAufgaben.filter(a => !a.erledigt).length} offen
                        </span>
                      </div>
                    </div>
                    <div className="bg-white p-3 space-y-2">
                      {monatsAufgaben.map(a => (
                        <AufgabeCard key={a.id} aufgabe={a} onToggle={() => toggleAufgabeErledigt(a)} onShift={(delta) => shiftAufgabeMonat(a, delta)} />
                      ))}
                    </div>
                  </div>
                );
              })}
            </div>

            {aufgaben.length === 0 && (
              <div className="text-center py-20">
                <div className="text-6xl mb-4">📋</div>
                <p className="text-[#8E8E93] font-semibold">Keine Aufgaben gefunden!</p>
              </div>
            )}
          </>
        )}
        {/* ── PFLANZPLAN TAB ── */}
        {activeTab === 'pflanzplan' && (
          <PflanzplanView samen={samen.filter(s => s.aktiv)} aufgaben={aufgaben.filter(a => a.samen_id)} />
        )}

        {/* ── DÜNGER TAB ── */}
        {activeTab === 'duenger' && (
          <>
            {/* Search & Filters */}
            <div className="space-y-3 mb-4">
              <input
                type="search"
                placeholder="Dünger suchen…"
                className="w-full px-4 py-3 rounded-2xl bg-white text-[15px] text-[#1C1C1E] placeholder:text-[#8E8E93] border border-black/5 focus:outline-none focus:ring-2 focus:ring-[#A0522D]/30 shadow-sm transition"
                value={duengerFilter.search}
                onChange={(e) => setDuengerFilter({ ...duengerFilter, search: e.target.value })}
              />
              <div className="flex gap-2 overflow-x-auto pb-1 flex-wrap">
                <Pill label="Alle Typen" active={!duengerFilter.typ} onClick={() => setDuengerFilter({ ...duengerFilter, typ: '' })} />
                {(['fluessig','granulat','staebchen','pulver','organisch','kompost','sonstig'] as const).map(t => (
                  <Pill key={t} label={duengerTypEmoji[t] + ' ' + t.charAt(0).toUpperCase() + t.slice(1)} active={duengerFilter.typ === t} onClick={() => setDuengerFilter({ ...duengerFilter, typ: duengerFilter.typ === t ? '' : t })} />
                ))}
              </div>
              <div className="flex gap-2">
                <Pill label="✅ Vorrätig" active={duengerFilter.vorraetig === 1} onClick={() => setDuengerFilter({ ...duengerFilter, vorraetig: duengerFilter.vorraetig === 1 ? -1 : 1 })} />
                <Pill label="❌ Fehlt" active={duengerFilter.vorraetig === 0} onClick={() => setDuengerFilter({ ...duengerFilter, vorraetig: duengerFilter.vorraetig === 0 ? -1 : 0 })} />
              </div>
            </div>

            {/* Add Dünger */}
            {showAddDuenger ? (
              <div className="bg-white rounded-2xl p-4 shadow-sm border border-black/5 mb-4">
                <h3 className="text-[15px] font-bold text-[#1C1C1E] mb-3">💩 Neuen Dünger hinzufügen</h3>
                <div className="flex gap-2">
                  <input
                    type="text"
                    placeholder="Name eingeben…"
                    className="flex-1 px-4 py-3 rounded-xl bg-[#F2F2F7] text-[15px] text-[#1C1C1E] placeholder:text-[#8E8E93] focus:outline-none focus:ring-2 focus:ring-[#A0522D]/30 transition"
                    value={newDuengerName}
                    onChange={(e) => setNewDuengerName(e.target.value)}
                    onKeyDown={(e) => e.key === 'Enter' && addNeuerDuenger()}
                    autoFocus
                  />
                  <button onClick={addNeuerDuenger} className="px-5 py-3 bg-[#A0522D] text-white rounded-xl font-semibold text-[15px] transition hover:bg-[#8B4513] active:scale-95">✓</button>
                  <button onClick={() => { setShowAddDuenger(false); setNewDuengerName(''); }} className="px-4 py-3 bg-[#F2F2F7] text-[#8E8E93] rounded-xl font-semibold text-[15px] transition hover:bg-[#E5E5EA]">✕</button>
                </div>
              </div>
            ) : (
              <button onClick={() => setShowAddDuenger(true)} className="w-full mb-4 py-3.5 bg-[#A0522D] hover:bg-[#8B4513] text-white rounded-2xl font-semibold text-[15px] transition shadow-sm active:scale-[0.98]">
                ＋ Neuen Dünger hinzufügen
              </button>
            )}

            {duengerToast && (
              <div className="bg-amber-50 border border-amber-200 rounded-2xl p-4 mb-4">
                <p className="text-[14px] text-amber-800 font-medium">{duengerToast}</p>
              </div>
            )}

            {/* Stats bar */}
            {stats?.duenger && (
              <div className="grid grid-cols-3 gap-2 mb-4">
                <div className="bg-white rounded-xl p-3 text-center shadow-sm border border-black/5">
                  <div className="text-[22px] font-bold text-[#A0522D]">{stats.duenger.gesamt}</div>
                  <div className="text-[11px] text-[#8E8E93] font-medium">Gesamt</div>
                </div>
                <div className="bg-green-50 rounded-xl p-3 text-center shadow-sm border border-green-100">
                  <div className="text-[22px] font-bold text-green-700">{stats.duenger.vorraetig}</div>
                  <div className="text-[11px] text-green-600 font-medium">Vorrätig</div>
                </div>
                <div className="bg-orange-50 rounded-xl p-3 text-center shadow-sm border border-orange-100">
                  <div className="text-[22px] font-bold text-orange-700">{stats.duenger.fehlend}</div>
                  <div className="text-[11px] text-orange-600 font-medium">Bedarf fehlt</div>
                </div>
              </div>
            )}

            {/* Dünger Grid */}
            <div className="grid grid-cols-2 gap-3">
              {duenger.map(d => (
                <DuengerCard key={d.id} duenger={d} onClick={() => setSelectedDuenger(d)} />
              ))}
            </div>

            {duenger.length === 0 && (
              <div className="text-center py-20">
                <div className="text-6xl mb-4">💩</div>
                <p className="text-[#8E8E93] font-semibold">Noch kein Dünger erfasst!</p>
                <p className="text-[#AEAEB2] text-sm mt-1">Füge deinen ersten Dünger hinzu</p>
              </div>
            )}
          </>
        )}
      </div>

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
          <div className="mt-3 bg-gradient-to-br from-emerald-50 to-green-50 rounded-2xl p-5 border border-emerald-100 shadow-sm">
            <h3 className="text-[16px] font-bold text-[#1C1C1E] mb-3">🌱 So funktioniert's:</h3>
            <div className="space-y-2.5 text-[14px] text-[#1C1C1E]">
              <div className="flex items-start gap-3">
                <div className="text-2xl">📸</div>
                <div>
                  <div className="font-semibold">Pflanze/Gehölz erfassen</div>
                  <div className="text-[#5C5C5E] text-[13px]">Foto an Telegram senden → Automatisch erkannt & indexiert</div>
                </div>
              </div>
              <div className="flex items-start gap-3">
                <div className="text-2xl">🪣</div>
                <div>
                  <div className="font-semibold">Manuell bewässert</div>
                  <div className="text-[#5C5C5E] text-[13px]">Foto mit Caption <code className="bg-white/60 px-1.5 py-0.5 rounded">-</code> → Nicht vom Hunter bewässert</div>
                </div>
              </div>
              <div className="flex items-start gap-3">
                <div className="text-2xl">🌱</div>
                <div>
                  <div className="font-semibold">Samen hinzufügen</div>
                  <div className="text-[#5C5C5E] text-[13px]">Name über Portal eingeben → Ole reichert Infos an</div>
                </div>
              </div>
              <div className="flex items-start gap-3">
                <div className="text-2xl">📋</div>
                <div>
                  <div className="font-semibold">Pflegeplan automatisch</div>
                  <div className="text-[#5C5C5E] text-[13px]">Wird automatisch erstellt basierend auf Pflanze & Saison</div>
                </div>
              </div>
              <div className="flex items-start gap-3">
                <div className="text-2xl">💬</div>
                <div>
                  <div className="font-semibold">Monatliche Erinnerungen</div>
                  <div className="text-[#5C5C5E] text-[13px]">Ole meldet sich per Telegram was ansteht</div>
                </div>
              </div>
            </div>
          </div>
        )}
      </div>
      {/* ── Samen Detail Sheet ── */}
      {selectedSamen && (
        <SamenDetailSheet
          samen={selectedSamen}
          onClose={() => setSelectedSamen(null)}
          onDelete={() => deleteSamenHandler(selectedSamen.id)}
        />
      )}

      {/* ── Pflanzen Detail Sheet ── */}
      {/* ── Dünger Detail Sheet ── */}
      {selectedDuenger && (
        <DuengerDetailSheet
          duenger={selectedDuenger}
          onClose={() => setSelectedDuenger(null)}
          onDelete={() => deleteDuengerHandler(selectedDuenger.id)}
          onToggleVorraetig={() => toggleDuengerVorraetig(selectedDuenger)}
        />
      )}

      {selectedPflanze && (
        <div className="fixed inset-0 bg-black/30 backdrop-blur-sm z-50 flex items-end sm:items-center justify-center" onClick={() => setSelectedPflanze(null)}>
          <div className="bg-[#F2F2F7] w-full max-w-lg max-h-[93vh] overflow-y-auto rounded-t-[28px] sm:rounded-[28px] shadow-2xl" onClick={(e) => e.stopPropagation()}>
            <div className="flex justify-center pt-3 sm:hidden"><div className="w-9 h-1 bg-[#C7C7CC] rounded-full" /></div>
            <div className="p-3 pt-2">
              <div className="relative bg-gradient-to-br from-emerald-100 to-green-100 rounded-[20px] overflow-hidden shadow-sm aspect-[4/3] flex items-center justify-center">
                <div className="text-8xl opacity-60">{artEmojis[selectedPflanze.art] || '🌿'}</div>
                <button onClick={() => setSelectedPflanze(null)} className="absolute top-3 right-3 w-8 h-8 bg-black/25 hover:bg-black/40 backdrop-blur-md rounded-full text-white flex items-center justify-center transition">
                  <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={3}><path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" /></svg>
                </button>
              </div>
            </div>
            <div className="px-3 pb-4">
              <div className="bg-white rounded-[20px] shadow-sm overflow-hidden p-5 space-y-5">
                <div>
                  <h2 className="text-[22px] font-bold text-[#1C1C1E] leading-tight">{selectedPflanze.name}</h2>
                  {selectedPflanze.sorte && <p className="text-[14px] text-[#8E8E93] mt-1 font-medium">{selectedPflanze.sorte}</p>}
                </div>
                <div className="flex gap-2 flex-wrap">
                  <span className="px-3 py-1.5 rounded-full text-[12px] font-bold bg-emerald-500/10 text-emerald-600">
                    {artEmojis[selectedPflanze.art] || '🌿'} {selectedPflanze.art.charAt(0).toUpperCase() + selectedPflanze.art.slice(1)}
                  </span>
                  <span className={`px-3 py-1.5 rounded-full text-[12px] font-bold text-white ${selectedPflanze.bewaesserung === 'hunter' ? 'bg-blue-600' : 'bg-amber-600'}`}>
                    {selectedPflanze.bewaesserung === 'hunter' ? '💧 Hunter' : '🪣 Manuell'}
                  </span>
                </div>
                <div className="bg-[#F2F2F7] rounded-2xl overflow-hidden divide-y divide-[#C6C6C8]/30">
                  {selectedPflanze.standort && (
                    <div className="flex items-center justify-between px-4 py-3.5">
                      <span className="flex items-center gap-2.5"><span>📍</span><span className="text-[15px] text-[#1C1C1E]">Standort</span></span>
                      <span className="text-[15px] font-semibold text-[#8E8E93]">{selectedPflanze.standort}</span>
                    </div>
                  )}
                  <div className="flex items-center justify-between px-4 py-3.5">
                    <span className="flex items-center gap-2.5"><span>📅</span><span className="text-[15px] text-[#1C1C1E]">Erfasst</span></span>
                    <span className="text-[15px] font-semibold text-[#8E8E93]">{new Date(selectedPflanze.erfasst_am).toLocaleDateString('de-DE', { day: '2-digit', month: 'short', year: 'numeric' })}</span>
                  </div>
                </div>
                {selectedPflanze.beschreibung && (
                  <div className="bg-emerald-50 rounded-2xl p-4">
                    <p className="text-[12px] font-bold text-emerald-700 uppercase tracking-wider mb-1">📝 Beschreibung</p>
                    <p className="text-[14px] text-emerald-900 leading-relaxed">{selectedPflanze.beschreibung}</p>
                  </div>
                )}
                {selectedPflanze.notizen && (
                  <div className="bg-[#FFF9DB] rounded-2xl p-4">
                    <p className="text-[12px] font-bold text-[#B8860B] uppercase tracking-wider mb-1">📝 Notizen</p>
                    <p className="text-[14px] text-[#5C4A00] leading-relaxed">{selectedPflanze.notizen}</p>
                  </div>
                )}
              </div>
            </div>
          </div>
        </div>
      )}
    </main>
  );
}

/* ── Dünger Helpers ── */

const duengerTypEmoji: Record<string, string> = {
  fluessig: '💧',
  granulat: '⚫',
  staebchen: '🥢',
  pulver: '🌫️',
  organisch: '🍂',
  kompost: '🌿',
  sonstig: '📦',
};

const duengerTypColor: Record<string, string> = {
  fluessig: 'bg-blue-500',
  granulat: 'bg-gray-600',
  staebchen: 'bg-orange-500',
  pulver: 'bg-slate-400',
  organisch: 'bg-amber-600',
  kompost: 'bg-lime-600',
  sonstig: 'bg-neutral-500',
};

/* ── GTS Detail Panel ── */

function GTSDetailPanel({ gtsData }: { gtsData: any }) {
  const history = gtsData.history || [];
  const forecast = gtsData.forecast || [];
  const allDays = [...history, ...forecast];
  const tips = gtsData.plant_tips || [];
  const frostPlants = gtsData.frost_plants || [];

  // Chart: render a mini SVG sparkline of GTS cumulative
  const chartDays = allDays.filter((_: any, i: number) => i % 3 === 0 || i === allDays.length - 1);
  const maxGTS = Math.max(200, gtsData.gts_projected_14d, ...chartDays.map((d: any) => d.cumulative));
  const chartW = 320;
  const chartH = 120;
  const padL = 35;
  const padR = 10;
  const padT = 10;
  const padB = 20;
  const plotW = chartW - padL - padR;
  const plotH = chartH - padT - padB;

  const points = chartDays.map((d: any, i: number) => {
    const x = padL + (i / Math.max(1, chartDays.length - 1)) * plotW;
    const y = padT + plotH - (d.cumulative / maxGTS) * plotH;
    return { x, y, ...d };
  });

  const histCount = history.filter((_: any, i: number) => i % 3 === 0 || i === history.length - 1).length;
  const polyline = points.map((p: any) => `${p.x},${p.y}`).join(' ');

  // Threshold lines
  const y150 = padT + plotH - (150 / maxGTS) * plotH;
  const y200 = padT + plotH - (200 / maxGTS) * plotH;

  // Split into history and forecast segments for different styling
  const histPoints = points.slice(0, histCount);
  const fcPoints = points.slice(Math.max(0, histCount - 1));
  const histLine = histPoints.map((p: any) => `${p.x},${p.y}`).join(' ');
  const fcLine = fcPoints.map((p: any) => `${p.x},${p.y}`).join(' ');

  const formatDate = (d: string) => {
    const [, m, day] = d.split('-');
    return `${parseInt(day)}.${parseInt(m)}.`;
  };

  return (
    <div className="max-w-xl mx-auto px-4 -mt-1 mb-2 relative z-20">
      <div className="bg-white rounded-2xl shadow-lg border border-black/5 p-4 space-y-4">
        {/* Title & Current */}
        <div className="flex items-center justify-between">
          <div>
            <h3 className="text-[15px] font-bold text-[#1C1C1E]">🌡️ Grünlandtemperatursumme</h3>
            <p className="text-[11px] text-[#8E8E93]">Burgwedel · {gtsData.date}</p>
          </div>
          <div className="text-right">
            <div className="text-2xl font-extrabold text-[#1C1C1E]">{Math.round(gtsData.gts_current)}°C</div>
            <p className="text-[11px] text-[#8E8E93]">von 200°C</p>
          </div>
        </div>

        {/* Progress Bar */}
        <div className="space-y-1">
          <div className="relative h-3 bg-[#F2F2F7] rounded-full overflow-visible">
            {/* 150 marker */}
            <div className="absolute top-0 h-full w-0.5 bg-amber-400 z-10" style={{ left: `${(150 / Math.max(200, gtsData.gts_projected_14d)) * 100}%` }} />
            {/* 200 marker */}
            <div className="absolute top-0 h-full w-0.5 bg-green-500 z-10" style={{ left: `${(200 / Math.max(200, gtsData.gts_projected_14d)) * 100}%` }} />
            {/* Forecast bar */}
            {gtsData.gts_projected_14d > gtsData.gts_current && (
              <div
                className="absolute top-0 h-full rounded-full bg-amber-200/60"
                style={{ width: `${Math.min(100, (gtsData.gts_projected_14d / Math.max(200, gtsData.gts_projected_14d)) * 100)}%` }}
              />
            )}
            {/* Actual bar */}
            <div
              className="absolute top-0 h-full rounded-full transition-all duration-1000"
              style={{
                width: `${Math.min(100, (gtsData.gts_current / Math.max(200, gtsData.gts_projected_14d)) * 100)}%`,
                background: gtsData.gts_current >= 200 ? '#34D399' : gtsData.gts_current >= 150 ? '#FBBF24' : `linear-gradient(90deg, #FCA5A5, #FCD34D)`,
              }}
            />
          </div>
          <div className="flex justify-between text-[9px] text-[#8E8E93] font-medium">
            <span>0</span>
            <span className="text-amber-500">150 Düngung</span>
            <span className="text-green-600">200 Wachstum</span>
          </div>
        </div>

        {/* Forecast Info */}
        <div className="grid grid-cols-2 gap-2">
          <div className="bg-[#FFF9DB] rounded-xl p-2.5">
            <p className="text-[10px] text-amber-600 font-semibold uppercase tracking-wider">🧪 150°C Düngung</p>
            {gtsData.threshold_150_reached ? (
              <p className="text-[14px] font-bold text-amber-700">✅ Erreicht!</p>
            ) : gtsData.forecast_reach_150 ? (
              <p className="text-[14px] font-bold text-amber-700">~{formatDate(gtsData.forecast_reach_150)}</p>
            ) : (
              <p className="text-[14px] font-bold text-amber-700">Noch {gtsData.remaining_150}°C</p>
            )}
          </div>
          <div className="bg-[#E8F5E9] rounded-xl p-2.5">
            <p className="text-[10px] text-green-600 font-semibold uppercase tracking-wider">🌿 200°C Wachstum</p>
            {gtsData.threshold_200_reached ? (
              <p className="text-[14px] font-bold text-green-700">✅ Erreicht!</p>
            ) : gtsData.forecast_reach_200 ? (
              <p className="text-[14px] font-bold text-green-700">~{formatDate(gtsData.forecast_reach_200)}</p>
            ) : (
              <p className="text-[14px] font-bold text-green-700">Noch {gtsData.remaining_200}°C</p>
            )}
          </div>
        </div>

        {/* SVG Chart */}
        <div>
          <p className="text-[11px] font-semibold text-[#8E8E93] mb-1">📈 Verlauf & Forecast</p>
          <svg viewBox={`0 0 ${chartW} ${chartH}`} className="w-full" style={{ maxHeight: 140 }}>
            {/* Grid */}
            <line x1={padL} y1={y150} x2={chartW - padR} y2={y150} stroke="#FBBF24" strokeWidth={0.5} strokeDasharray="4,3" />
            <line x1={padL} y1={y200} x2={chartW - padR} y2={y200} stroke="#34D399" strokeWidth={0.5} strokeDasharray="4,3" />
            <text x={padL - 3} y={y150 + 3} fontSize={8} fill="#FBBF24" textAnchor="end">150</text>
            <text x={padL - 3} y={y200 + 3} fontSize={8} fill="#34D399" textAnchor="end">200</text>
            <text x={padL - 3} y={padT + plotH + 3} fontSize={8} fill="#AEAEB2" textAnchor="end">0</text>

            {/* History line */}
            {histLine && <polyline points={histLine} fill="none" stroke="#34C759" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" />}
            {/* Forecast line (dashed) */}
            {fcLine && fcPoints.length > 1 && <polyline points={fcLine} fill="none" stroke="#FBBF24" strokeWidth={2} strokeDasharray="4,3" strokeLinecap="round" strokeLinejoin="round" />}

            {/* Current point */}
            {histPoints.length > 0 && (
              <circle cx={histPoints[histPoints.length - 1].x} cy={histPoints[histPoints.length - 1].y} r={3} fill="#34C759" stroke="white" strokeWidth={1.5} />
            )}

            {/* Date labels */}
            {points.length > 0 && (
              <>
                <text x={points[0].x} y={chartH - 2} fontSize={7} fill="#AEAEB2" textAnchor="start">{formatDate(points[0].date)}</text>
                <text x={points[points.length - 1].x} y={chartH - 2} fontSize={7} fill="#AEAEB2" textAnchor="end">{formatDate(points[points.length - 1].date)}</text>
                {histPoints.length > 0 && (
                  <text x={histPoints[histPoints.length - 1].x} y={chartH - 2} fontSize={7} fill="#34C759" textAnchor="middle">Heute</text>
                )}
              </>
            )}
          </svg>
          <div className="flex items-center gap-4 mt-1 text-[9px] text-[#8E8E93]">
            <span className="flex items-center gap-1"><span className="w-3 h-0.5 bg-[#34C759] rounded inline-block" /> Historisch</span>
            <span className="flex items-center gap-1"><span className="w-3 h-0.5 bg-[#FBBF24] rounded inline-block border-dashed" style={{ borderTop: '1.5px dashed #FBBF24', background: 'none' }} /> Forecast</span>
          </div>
        </div>

        {/* Plant Tips / Milestones */}
        <div>
          <p className="text-[11px] font-semibold text-[#8E8E93] mb-2">🌱 Garten-Meilensteine</p>
          <div className="space-y-1.5">
            {tips.map((tip: any) => (
              <div key={tip.gts} className={`flex items-center gap-2 px-3 py-1.5 rounded-xl text-[12px] ${tip.reached ? 'bg-green-50' : 'bg-[#F2F2F7]'}`}>
                <span className="text-sm">{tip.emoji}</span>
                <span className={`font-mono font-bold text-[11px] min-w-[32px] ${tip.reached ? 'text-green-600' : 'text-[#8E8E93]'}`}>{tip.gts}°C</span>
                <span className={`flex-1 font-medium ${tip.reached ? 'text-green-800' : 'text-[#1C1C1E]'}`}>
                  {tip.label}
                  {tip.reached && ' ✅'}
                </span>
                {!tip.reached && tip.forecast_date && (
                  <span className="text-[10px] text-amber-600 font-semibold">~{formatDate(tip.forecast_date)}</span>
                )}
              </div>
            ))}
          </div>
        </div>
        {/* Frost-sensitive Plants Status */}
        {frostPlants.length > 0 && (
          <div>
            <p className="text-[11px] font-semibold text-[#8E8E93] mb-2">🥶 Frostempfindliche Pflanzen</p>
            <div className="space-y-1.5">
              {frostPlants.map((p: any) => (
                <div key={p.id} className={`flex items-start gap-2 px-3 py-2 rounded-xl text-[12px] ${
                  p.status === 'draussen_ok' ? 'bg-green-50' : p.status === 'reinholen' ? 'bg-red-50' : 'bg-blue-50'
                }`}>
                  <span className="text-sm mt-0.5">{p.status === 'draussen_ok' ? '☀️' : p.status === 'reinholen' ? '🚨' : '🏠'}</span>
                  <div className="flex-1">
                    <span className={`font-semibold ${
                      p.status === 'draussen_ok' ? 'text-green-800' : p.status === 'reinholen' ? 'text-red-800' : 'text-blue-800'
                    }`}>{p.name}</span>
                    <p className={`text-[11px] mt-0.5 ${
                      p.status === 'draussen_ok' ? 'text-green-600' : p.status === 'reinholen' ? 'text-red-600' : 'text-blue-600'
                    }`}>{p.hinweis}</p>
                  </div>
                  <span className="text-[10px] text-[#8E8E93] font-mono whitespace-nowrap mt-0.5">min {p.min_temp}°C</span>
                </div>
              ))}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

/* ── Components ── */

function TabButton({ label, active, onClick }: { label: string; active: boolean; onClick: () => void }) {
  return (
    <button
      onClick={onClick}
      className={`flex-1 py-2.5 rounded-xl text-[13px] font-semibold transition-all ${
        active
          ? 'bg-gradient-to-br from-emerald-400 to-green-500 text-white shadow-md'
          : 'text-[#1C1C1E] hover:bg-[#F2F2F7]'
      }`}
    >
      {label}
    </button>
  );
}

function Pill({ label, active, onClick }: { label: string; active: boolean; onClick: () => void }) {
  return (
    <button
      onClick={onClick}
      className={`px-4 py-2 rounded-full text-[13px] font-semibold whitespace-nowrap transition ${
        active ? 'bg-[#34C759] text-white shadow-sm' : 'bg-white text-[#1C1C1E] border border-black/5 shadow-sm hover:bg-[#F2F2F7]'
      }`}
    >
      {label}
    </button>
  );
}

function DuengerCard({ duenger, onClick }: { duenger: Duenger; onClick: () => void }) {
  const typEmoji = duenger.typ ? duengerTypEmoji[duenger.typ] : '💩';
  const typColor = duenger.typ ? duengerTypColor[duenger.typ] : 'bg-amber-700';
  return (
    <div onClick={onClick} className="bg-white rounded-[20px] overflow-hidden shadow-sm border border-black/5 active:scale-[0.96] transition-transform cursor-pointer">
      <div className="aspect-square bg-gradient-to-br from-amber-50 to-amber-100 relative flex items-center justify-center overflow-hidden">
        {(() => { try { const p = duenger.bild_pfade ? JSON.parse(duenger.bild_pfade) : []; if (p.length > 0) return <img src={`/api/v1/media/${p[0].replace('images/','')}`} alt={duenger.name} className="w-full h-full object-cover" />; } catch {} return <div className="text-6xl opacity-70">{typEmoji}</div>; })()}
        <div className={`absolute top-2.5 left-2.5 px-2.5 py-1 rounded-full text-[11px] font-bold text-white shadow-lg ${duenger.vorraetig ? 'bg-green-600' : 'bg-red-500'}`}>
          {duenger.vorraetig ? '✅ Vorrätig' : '❌ Fehlt'}
        </div>
      </div>
      <div className="p-3.5">
        <p className="font-bold text-[15px] text-[#1C1C1E] truncate leading-tight">{duenger.name}</p>
        {duenger.marke && <p className="text-[12px] text-[#8E8E93] truncate mt-0.5 font-medium">{duenger.marke}</p>}
        {duenger.typ && (
          <span className={`mt-1.5 inline-block px-2.5 py-0.5 rounded-full text-[10px] font-bold text-white ${typColor}`}>
            {typEmoji} {duenger.typ.charAt(0).toUpperCase() + duenger.typ.slice(1)}
          </span>
        )}
        {duenger.naehrstoffe && (
          <p className="text-[11px] text-[#8E8E93] mt-1 truncate font-mono">{duenger.naehrstoffe}</p>
        )}
      </div>
    </div>
  );
}

function DuengerDetailSheet({ duenger, onClose, onDelete, onToggleVorraetig }: {
  duenger: Duenger;
  onClose: () => void;
  onDelete: () => void;
  onToggleVorraetig: () => void;
}) {
  const typEmoji = duenger.typ ? duengerTypEmoji[duenger.typ] : '💩';
  const typColor = duenger.typ ? duengerTypColor[duenger.typ] : 'bg-amber-700';
  const monatNamen2 = ['', 'Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun', 'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez'];

  return (
    <div className="fixed inset-0 bg-black/30 backdrop-blur-sm z-50 flex items-end sm:items-center justify-center" onClick={onClose}>
      <div className="bg-[#F2F2F7] w-full max-w-lg max-h-[93vh] overflow-y-auto rounded-t-[28px] sm:rounded-[28px] shadow-2xl" onClick={(e) => e.stopPropagation()}>
        <div className="flex justify-center pt-3 sm:hidden"><div className="w-9 h-1 bg-[#C7C7CC] rounded-full" /></div>
        <div className="p-3 pt-2">
          <div className="relative bg-gradient-to-br from-amber-50 to-amber-100 rounded-[20px] overflow-hidden shadow-sm aspect-[4/3] flex items-center justify-center">
            {(() => { try { const p = duenger.bild_pfade ? JSON.parse(duenger.bild_pfade) : []; if (p.length > 0) return <img src={`/api/v1/media/${p[0].replace('images/','')}`} alt={duenger.name} className="w-full h-full object-cover" />; } catch {} return <div className="text-9xl opacity-60">{typEmoji}</div>; })()}
            <button onClick={onClose} className="absolute top-3 right-3 w-8 h-8 bg-black/25 hover:bg-black/40 backdrop-blur-md rounded-full text-white flex items-center justify-center transition">
              <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={3}><path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" /></svg>
            </button>
          </div>
        </div>
        <div className="px-3 pb-4 space-y-3">
          {/* Title + Badges */}
          <div className="bg-white rounded-[20px] shadow-sm p-5">
            <h2 className="text-[22px] font-bold text-[#1C1C1E] leading-tight">{duenger.name}</h2>
            {duenger.marke && <p className="text-[14px] text-[#8E8E93] mt-1 font-medium">{duenger.marke}</p>}
            <div className="flex gap-2 flex-wrap mt-3">
              {duenger.typ && (
                <span className={`px-3 py-1.5 rounded-full text-[12px] font-bold text-white ${typColor}`}>
                  {typEmoji} {duenger.typ.charAt(0).toUpperCase() + duenger.typ.slice(1)}
                </span>
              )}
              <button
                onClick={onToggleVorraetig}
                className={`px-3 py-1.5 rounded-full text-[12px] font-bold transition active:scale-95 ${duenger.vorraetig ? 'bg-green-500/10 text-green-700 hover:bg-green-500/20' : 'bg-red-500/10 text-red-700 hover:bg-red-500/20'}`}
              >
                {duenger.vorraetig ? '✅ Vorrätig' : '❌ Nicht vorrätig'} (tippen zum Wechseln)
              </button>
            </div>
          </div>

          {/* Info */}
          <div className="bg-white rounded-[20px] shadow-sm overflow-hidden divide-y divide-[#C6C6C8]/30">
            {duenger.naehrstoffe && <InfoRow emoji="🧪" label="Nährstoffe (NPK)" value={duenger.naehrstoffe} />}
            {duenger.dosierung && <InfoRow emoji="⚖️" label="Dosierung" value={duenger.dosierung} />}
            {duenger.intervall_wochen && <InfoRow emoji="🗓️" label="Intervall" value={`alle ${duenger.intervall_wochen} Wochen`} />}
            {duenger.saison_von && duenger.saison_bis && (
              <InfoRow emoji="🌤️" label="Saison" value={`${monatNamen2[duenger.saison_von]}–${monatNamen2[duenger.saison_bis]}`} />
            )}
            {duenger.geeignet_fuer && <InfoRow emoji="🌿" label="Geeignet für" value={duenger.geeignet_fuer} />}
            <InfoRow emoji="📅" label="Erfasst" value={new Date(duenger.erfasst_am).toLocaleDateString('de-DE', { day: '2-digit', month: 'short', year: 'numeric' })} />
          </div>

          {duenger.beschreibung && (
            <div className="bg-amber-50 rounded-2xl p-4">
              <p className="text-[12px] font-bold text-amber-700 uppercase tracking-wider mb-1">📝 Beschreibung</p>
              <p className="text-[14px] text-amber-900 leading-relaxed">{duenger.beschreibung}</p>
            </div>
          )}

          {duenger.notizen && (
            <div className="bg-[#FFF9DB] rounded-2xl p-4">
              <p className="text-[12px] font-bold text-[#B8860B] uppercase tracking-wider mb-1">📝 Notizen</p>
              <p className="text-[14px] text-[#5C4A00] leading-relaxed">{duenger.notizen}</p>
            </div>
          )}

          {duenger.kauflink && (
            <a href={duenger.kauflink} target="_blank" rel="noreferrer" className="block w-full py-3.5 bg-[#A0522D] hover:bg-[#8B4513] text-white rounded-2xl font-semibold text-[15px] transition text-center shadow-sm active:scale-[0.98]">
              🛒 Kauflink öffnen
            </a>
          )}

          <button onClick={onDelete} className="w-full py-3.5 bg-red-500 hover:bg-red-600 text-white rounded-2xl font-semibold text-[15px] transition shadow-sm active:scale-[0.98]">
            🗑️ Dünger löschen
          </button>
        </div>
      </div>
    </div>
  );
}

function PflanzeCard({ pflanze, onClick }: { pflanze: Pflanze; onClick: () => void }) {
  const artEmoji = artEmojis[pflanze.art] || '🌿';
  const bewaesserungBadge = pflanze.bewaesserung === 'hunter' ? '💧 Hunter' : '🪣 Manuell';
  const bewaesserungColor = pflanze.bewaesserung === 'hunter' ? 'bg-blue-600' : 'bg-amber-600';

  return (
    <div onClick={onClick} className="bg-white rounded-[20px] overflow-hidden shadow-sm border border-black/5 active:scale-[0.96] transition-transform cursor-pointer">
      <div className="aspect-square bg-gradient-to-br from-emerald-100 to-green-100 relative flex items-center justify-center">
        <div className="text-6xl opacity-60">{artEmoji}</div>
        <div className={`absolute top-2.5 left-2.5 px-2.5 py-1 rounded-full text-[11px] font-bold text-white shadow-lg ${bewaesserungColor}`}>
          {bewaesserungBadge}
        </div>
      </div>
      <div className="p-3.5">
        <p className="font-bold text-[15px] text-[#1C1C1E] truncate leading-tight">{pflanze.name}</p>
        <p className="text-[12px] text-[#8E8E93] truncate mt-0.5 font-medium">
          {artEmoji} {pflanze.art.charAt(0).toUpperCase() + pflanze.art.slice(1)}
          {pflanze.standort && ` · ${pflanze.standort}`}
        </p>
      </div>
    </div>
  );
}

const artSamenEmojis: Record<string, string> = {
  'Kräuter': '🌿',
  'Gemüse': '🥬',
  'Blume': '🌸',
  'Obst': '🍓',
  'Salat': '🥗',
};

const monatNameLang = ['', 'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'];

function getMonthRange(von?: number, bis?: number): string[] {
  if (!von || !bis) return [];
  const months: string[] = [];
  for (let m = von; m <= bis; m++) months.push(monatNamen[m]);
  return months;
}

function getSamenImageUrl(samen: Samen): string | null {
  if (!samen.bild_pfade) return null;
  try {
    const paths = JSON.parse(samen.bild_pfade);
    if (paths.length > 0) {
      const filename = paths[0].replace('images/', '');
      return `/api/v1/media/${filename}`;
    }
  } catch {}
  return null;
}

function getAllSamenImageUrls(samen: Samen): string[] {
  if (!samen.bild_pfade) return [];
  try {
    const paths = JSON.parse(samen.bild_pfade);
    return paths.map((p: string) => `/api/v1/media/${p.replace('images/', '')}`);
  } catch {}
  return [];
}

function SamenCard({ samen, onToggle, onClick }: { samen: Samen; onToggle: () => void; onClick: () => void }) {
  const pflanzBadges = getMonthRange(samen.pflanz_von, samen.pflanz_bis);
  const ernteBadges = getMonthRange(samen.ernte_von, samen.ernte_bis);
  const imageUrl = getSamenImageUrl(samen);

  return (
    <div className="bg-white rounded-2xl shadow-sm border border-black/5 overflow-hidden cursor-pointer active:scale-[0.98] transition-transform" onClick={onClick}>
      <div className="flex items-stretch">
        {/* Thumbnail */}
        <div className="w-20 h-20 flex-shrink-0 bg-gradient-to-br from-emerald-100 to-green-100 flex items-center justify-center overflow-hidden">
          {imageUrl ? (
            <img src={imageUrl} alt={samen.name} className="w-full h-full object-cover" />
          ) : (
            <span className="text-3xl opacity-50">{artSamenEmojis[samen.art || ''] || '🌱'}</span>
          )}
        </div>
        <div className="flex-1 min-w-0 p-3">
          <div className="flex items-center gap-2 mb-1">
            <span className="text-[11px] font-bold text-[#8E8E93] bg-[#F2F2F7] px-2 py-0.5 rounded">#{samen.nummer}</span>
            {samen.art && (
              <span className="text-[11px] font-bold text-emerald-600 bg-emerald-500/10 px-2 py-0.5 rounded-full">
                {artSamenEmojis[samen.art] || '🌱'} {samen.art}
              </span>
            )}
            {samen.aktiv ? (
              <span className="text-[10px] font-bold text-green-600 bg-green-500/10 px-1.5 py-0.5 rounded-full">Aktiv</span>
            ) : (
              <span className="text-[10px] font-bold text-orange-600 bg-orange-500/10 px-1.5 py-0.5 rounded-full">Inaktiv</span>
            )}
          </div>
          <h3 className="text-[15px] font-bold text-[#1C1C1E] truncate">{samen.name}</h3>
          {(pflanzBadges.length > 0 || ernteBadges.length > 0) && (
            <div className="flex gap-1 mt-1.5 flex-wrap">
              {pflanzBadges.map((m, i) => (
                <span key={`p${i}`} className="text-[10px] font-bold text-emerald-600 bg-emerald-500/10 px-1.5 py-0.5 rounded">🌱 {m}</span>
              ))}
              {ernteBadges.map((m, i) => (
                <span key={`e${i}`} className="text-[10px] font-bold text-orange-600 bg-orange-500/10 px-1.5 py-0.5 rounded">🌾 {m}</span>
              ))}
            </div>
          )}
        </div>
        <button
          onClick={(e) => { e.stopPropagation(); onToggle(); }}
          className={`flex-shrink-0 w-12 flex items-center justify-center transition ${
            samen.aktiv ? 'bg-green-500 hover:bg-green-600' : 'bg-gray-300 hover:bg-gray-400'
          }`}
        >
          <div className={`w-5 h-5 rounded-full transition ${samen.aktiv ? 'bg-white' : 'bg-gray-500'}`} />
        </button>
      </div>
    </div>
  );
}

function SamenDetailSheet({ samen, onClose, onDelete }: { samen: Samen; onClose: () => void; onDelete: () => void }) {
  const imageUrl = getSamenImageUrl(samen);
  const allImageUrls = getAllSamenImageUrls(samen);
  const [selectedStartMonth, setSelectedStartMonth] = useState<number | null>(null);
  let metadata: Record<string, any> = {};
  try { if (samen.metadata) metadata = JSON.parse(samen.metadata); } catch {}

  return (
    <div className="fixed inset-0 bg-black/30 backdrop-blur-sm z-50 flex items-end sm:items-center justify-center" onClick={onClose}>
      <div className="bg-[#F2F2F7] w-full max-w-lg max-h-[93vh] overflow-y-auto rounded-t-[28px] sm:rounded-[28px] shadow-2xl" onClick={(e) => e.stopPropagation()}>
        <div className="flex justify-center pt-3 sm:hidden"><div className="w-9 h-1 bg-[#C7C7CC] rounded-full" /></div>
        
        {/* Images (Front + Back) */}
        <div className="p-3 pt-2">
          {allImageUrls.length > 1 ? (
            <div className="relative flex gap-2">
              {allImageUrls.map((url, i) => (
                <div key={i} className="relative flex-1 rounded-[20px] overflow-hidden shadow-sm aspect-[3/4] bg-gradient-to-br from-emerald-100 to-green-100">
                  <img src={url} alt={`${samen.name} ${i === 0 ? 'Vorderseite' : 'Rückseite'}`} className="w-full h-full object-cover" />
                  <div className="absolute bottom-2 left-2 px-2 py-0.5 bg-black/40 backdrop-blur-md rounded-full text-[10px] text-white font-medium">
                    {i === 0 ? '📸 Vorne' : '📋 Hinten'}
                  </div>
                </div>
              ))}
              <button onClick={onClose} className="absolute top-3 right-3 w-8 h-8 bg-black/25 hover:bg-black/40 backdrop-blur-md rounded-full text-white flex items-center justify-center transition z-10">
                <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={3}><path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" /></svg>
              </button>
            </div>
          ) : (
            <div className="relative rounded-[20px] overflow-hidden shadow-sm aspect-[4/3] bg-gradient-to-br from-emerald-100 to-green-100 flex items-center justify-center">
              {imageUrl ? (
                <img src={imageUrl} alt={samen.name} className="w-full h-full object-cover" />
              ) : (
                <div className="text-8xl opacity-40">{artSamenEmojis[samen.art || ''] || '🌱'}</div>
              )}
              <button onClick={onClose} className="absolute top-3 right-3 w-8 h-8 bg-black/25 hover:bg-black/40 backdrop-blur-md rounded-full text-white flex items-center justify-center transition">
                <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={3}><path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" /></svg>
              </button>
            </div>
          )}
        </div>

        <div className="px-3 pb-4 space-y-3">
          {/* Title + Badges */}
          <div className="bg-white rounded-[20px] shadow-sm p-5">
            <h2 className="text-[22px] font-bold text-[#1C1C1E] leading-tight">{samen.name}</h2>
            {samen.sorte && <p className="text-[14px] text-[#8E8E93] mt-1 font-medium">{samen.sorte}</p>}
            <div className="flex gap-2 flex-wrap mt-3">
              {samen.art && (
                <span className="px-3 py-1.5 rounded-full text-[12px] font-bold bg-emerald-500/10 text-emerald-600">
                  {artSamenEmojis[samen.art] || '🌱'} {samen.art}
                </span>
              )}
              {samen.aktiv ? (
                <span className="px-3 py-1.5 rounded-full text-[12px] font-bold bg-green-500/10 text-green-600">✅ Aktiv</span>
              ) : (
                <span className="px-3 py-1.5 rounded-full text-[12px] font-bold bg-orange-500/10 text-orange-600">⏸️ Inaktiv</span>
              )}
            </div>
          </div>

          {/* Jahresverlauf Timeline (Interaktiv!) */}
          {(samen.vorziehen_ab || samen.pflanz_von || samen.ernte_von) && (() => {
            // Berechne projizierte Zeitpunkte basierend auf gewähltem Start
            const keimMonate = samen.keimzeit_tage ? Math.ceil(samen.keimzeit_tage / 30) : 1;
            const projAussaat = selectedStartMonth ? Math.min(selectedStartMonth + keimMonate, 12) : null;
            const ernteOffset = (samen.ernte_von && samen.pflanz_von) ? samen.ernte_von - samen.pflanz_von : 3;
            const projErnte = projAussaat ? Math.min(projAussaat + ernteOffset, 12) : null;
            const projErnteEnd = projErnte && samen.ernte_bis && samen.ernte_von ? Math.min(projErnte + (samen.ernte_bis - samen.ernte_von), 12) : projErnte ? Math.min(projErnte + 5, 12) : null;

            // Klickbare Monate: Vorziehen + Aussaat-Bereich
            const clickableFrom = samen.vorziehen_ab || samen.pflanz_von || 1;
            const clickableTo = samen.pflanz_bis || samen.pflanz_von || 12;

            return (
            <div className="bg-white rounded-[20px] shadow-sm p-5">
              <div className="flex items-center justify-between mb-3">
                <p className="text-[12px] font-bold text-emerald-700 uppercase tracking-wider">📅 Jahresverlauf</p>
                {selectedStartMonth && (
                  <button onClick={() => setSelectedStartMonth(null)} className="text-[11px] text-blue-500 font-semibold">✕ Reset</button>
                )}
              </div>

              {!selectedStartMonth && (
                <p className="text-[11px] text-blue-500 mb-2 bg-blue-50 rounded-lg px-3 py-1.5 font-medium">
                  👆 Tippe auf einen Monat um deinen Start zu markieren → Aussaat & Ernte werden berechnet
                </p>
              )}

              <div className="grid grid-cols-12 gap-0.5 mb-2">
                {[1,2,3,4,5,6,7,8,9,10,11,12].map(m => {
                  const isVorziehen = samen.vorziehen_ab && samen.pflanz_von && m >= samen.vorziehen_ab && m < samen.pflanz_von;
                  const isAussaat = samen.pflanz_von && samen.pflanz_bis && m >= samen.pflanz_von && m <= samen.pflanz_bis;
                  const isErnte = samen.ernte_von && samen.ernte_bis && m >= samen.ernte_von && m <= samen.ernte_bis;
                  const currentMonth = new Date().getMonth() + 1;
                  const isCurrent = m === currentMonth;
                  const isClickable = m >= clickableFrom && m <= clickableTo;

                  // Projected overlay
                  const isSelected = m === selectedStartMonth;
                  const isProjAussaat = projAussaat && m === projAussaat;
                  const isProjErnte = projErnte && projErnteEnd && m >= projErnte && m <= projErnteEnd;

                  let bg = 'bg-gray-100';
                  if (isVorziehen) bg = 'bg-purple-300/60';
                  if (isAussaat) bg = 'bg-emerald-300/60';
                  if (isErnte) bg = 'bg-amber-300/60';
                  if (isAussaat && isErnte) bg = 'bg-gradient-to-b from-emerald-300/60 to-amber-300/60';

                  // Override with projected if selected
                  if (selectedStartMonth) {
                    if (isSelected) bg = 'bg-purple-600';
                    else if (isProjAussaat) bg = 'bg-emerald-600';
                    else if (isProjErnte) bg = 'bg-amber-500';
                    else if (isVorziehen || isAussaat || isErnte) bg = bg; // keep muted original
                  }

                  return (
                    <div key={m} className="flex flex-col items-center">
                      <div
                        className={`w-full h-10 rounded-sm ${bg} ${isCurrent ? 'ring-2 ring-blue-500 ring-offset-1' : ''} ${isClickable && !selectedStartMonth ? 'cursor-pointer hover:opacity-80 active:scale-95' : ''} ${isSelected ? 'ring-2 ring-purple-700 ring-offset-1' : ''} ${isProjAussaat ? 'ring-2 ring-emerald-700 ring-offset-1' : ''} transition-all relative`}
                        onClick={() => { if (isClickable) setSelectedStartMonth(m === selectedStartMonth ? null : m); }}
                      >
                        {isSelected && <span className="absolute inset-0 flex items-center justify-center text-white text-[10px] font-bold">🏠</span>}
                        {isProjAussaat && <span className="absolute inset-0 flex items-center justify-center text-white text-[10px] font-bold">🌱</span>}
                        {isProjErnte && !isProjAussaat && m === projErnte && <span className="absolute inset-0 flex items-center justify-center text-[10px] font-bold">🌾</span>}
                      </div>
                      <span className={`text-[8px] mt-1 ${isCurrent ? 'font-bold text-blue-600' : isSelected ? 'font-bold text-purple-700' : 'text-[#8E8E93]'}`}>
                        {['J','F','M','A','M','J','J','A','S','O','N','D'][m-1]}
                      </span>
                    </div>
                  );
                })}
              </div>

              {/* Legende */}
              <div className="flex flex-wrap gap-3 mt-3">
                {samen.vorziehen_ab && (
                  <div className="flex items-center gap-1.5">
                    <div className="w-3 h-3 rounded-sm bg-purple-400" />
                    <span className="text-[11px] text-[#8E8E93] font-medium">🏠 Vorziehen</span>
                  </div>
                )}
                <div className="flex items-center gap-1.5">
                  <div className="w-3 h-3 rounded-sm bg-emerald-400" />
                  <span className="text-[11px] text-[#8E8E93] font-medium">🌱 Aussaat</span>
                </div>
                <div className="flex items-center gap-1.5">
                  <div className="w-3 h-3 rounded-sm bg-amber-400" />
                  <span className="text-[11px] text-[#8E8E93] font-medium">🌾 Ernte</span>
                </div>
              </div>

              {/* Projektion Info */}
              {selectedStartMonth && (
                <div className="mt-3 bg-purple-50 rounded-xl px-3 py-2.5 space-y-1">
                  <p className="text-[12px] font-bold text-purple-700">📌 Dein Plan:</p>
                  <p className="text-[11px] text-purple-900">
                    🏠 Vorziehen im <b>{monatNameLang[selectedStartMonth]}</b>
                    {samen.keimzeit_tage && <> → Keimung nach ~{samen.keimzeit_tage} Tagen</>}
                  </p>
                  {projAussaat && (
                    <p className="text-[11px] text-emerald-700">
                      🌱 Auspflanzen ab <b>{monatNameLang[projAussaat]}</b>
                    </p>
                  )}
                  {projErnte && (
                    <p className="text-[11px] text-amber-700">
                      🌾 Ernte ab <b>{monatNameLang[projErnte]}</b>{projErnteEnd && projErnteEnd !== projErnte ? <> bis <b>{monatNameLang[projErnteEnd]}</b></> : ''}
                    </p>
                  )}
                </div>
              )}

              {!selectedStartMonth && samen.keimzeit_tage && samen.pflanz_von && samen.ernte_von && (
                <p className="text-[11px] text-[#8E8E93] mt-3 bg-[#F2F2F7] rounded-xl px-3 py-2">
                  ⏱️ Bei Aussaat im {monatNameLang[samen.pflanz_von]}: Keimung nach ~{samen.keimzeit_tage} Tagen, erste Ernte ab {monatNameLang[samen.ernte_von]}
                </p>
              )}
            </div>
            );
          })()}

          {/* Info Rows */}
          <div className="bg-white rounded-[20px] shadow-sm overflow-hidden divide-y divide-[#C6C6C8]/30">
            {samen.pflanz_von && samen.pflanz_bis && (
              <InfoRow emoji="🌱" label="Aussaat" value={`${monatNameLang[samen.pflanz_von]}–${monatNameLang[samen.pflanz_bis]}`} />
            )}
            {samen.vorziehen_ab && (
              <InfoRow emoji="🏠" label="Vorziehen ab" value={monatNameLang[samen.vorziehen_ab]} />
            )}
            {samen.ernte_von && samen.ernte_bis && (
              <InfoRow emoji="🌾" label="Ernte" value={`${monatNameLang[samen.ernte_von]}–${monatNameLang[samen.ernte_bis]}`} />
            )}
            {samen.standort_empfehlung && (
              <InfoRow emoji="☀️" label="Standort" value={samen.standort_empfehlung} />
            )}
            {samen.abstand_cm && (
              <InfoRow emoji="📏" label="Abstand" value={`${samen.abstand_cm} cm`} />
            )}
            {samen.tiefe_cm && (
              <InfoRow emoji="📐" label="Saattiefe" value={`${samen.tiefe_cm} cm`} />
            )}
            {samen.keimzeit_tage && (
              <InfoRow emoji="⏱️" label="Keimzeit" value={`${samen.keimzeit_tage} Tage`} />
            )}
            {samen.hersteller && (
              <InfoRow emoji="🏭" label="Hersteller" value={samen.hersteller} />
            )}
            {samen.bio && (
              <InfoRow emoji="🌿" label="Bio-Zertifizierung" value={samen.bio} />
            )}
            {samen.samenfest === 1 && (
              <InfoRow emoji="🌱" label="Samenfest" value="Ja" />
            )}
            {samen.botanisch && (
              <InfoRow emoji="🔬" label="Botanisch" value={samen.botanisch} />
            )}
            {samen.keimtemp && (
              <InfoRow emoji="🌡️" label="Keimtemperatur" value={samen.keimtemp} />
            )}
            {samen.keimfaehig_bis && (() => {
              const currentYear = new Date().getFullYear();
              const expYear = parseInt(samen.keimfaehig_bis);
              const isExpired = expYear < currentYear;
              return (
                <InfoRow 
                  emoji={isExpired ? "⚠️" : "✅"} 
                  label="Keimfähig bis" 
                  value={`${samen.keimfaehig_bis}${isExpired ? ' (⚠️ abgelaufen)' : ''}`} 
                />
              );
            })()}
            {samen.inhalt && (
              <InfoRow emoji="📦" label="Inhalt" value={samen.inhalt} />
            )}
            {samen.typ && (
              <InfoRow emoji="🏷️" label="Typ" value={samen.typ} />
            )}
            {samen.herkunft && (
              <InfoRow emoji="🌍" label="Herkunft" value={samen.herkunft} />
            )}
            {samen.verwendung && (
              <InfoRow emoji="🍽️" label="Verwendung" value={samen.verwendung} />
            )}
            <InfoRow emoji="📅" label="Erfasst" value={new Date(samen.erfasst_am).toLocaleDateString('de-DE', { day: '2-digit', month: 'short', year: 'numeric' })} />
          </div>
          
          {/* 2. Aussaatzeitraum (falls vorhanden) */}
          {(samen.aussaat_2_von || samen.ernte_2_von) && (
            <div className="bg-gradient-to-br from-amber-50 to-orange-50 border-2 border-amber-200 rounded-[20px] shadow-sm p-5">
              <p className="text-[12px] font-bold text-amber-700 uppercase tracking-wider mb-3">🔄 2. Aussaatzeitraum</p>
              <div className="space-y-2">
                {samen.aussaat_2_von && samen.aussaat_2_bis && (
                  <div className="flex items-center gap-2">
                    <span className="text-lg">🌱</span>
                    <span className="text-[14px] text-[#1C1C1E]">
                      <b>Aussaat:</b> {monatNameLang[samen.aussaat_2_von]}–{monatNameLang[samen.aussaat_2_bis]}
                    </span>
                  </div>
                )}
                {samen.ernte_2_von && samen.ernte_2_bis && (
                  <div className="flex items-center gap-2">
                    <span className="text-lg">🌾</span>
                    <span className="text-[14px] text-[#1C1C1E]">
                      <b>Ernte:</b> {monatNameLang[samen.ernte_2_von]}–{monatNameLang[samen.ernte_2_bis]}
                    </span>
                  </div>
                )}
              </div>
            </div>
          )}

          {/* Besonderheiten */}
          {samen.besonderheiten && (
            <div className="bg-gradient-to-br from-purple-50 to-indigo-50 border-2 border-purple-200 rounded-[20px] p-5">
              <p className="text-[12px] font-bold text-purple-700 uppercase tracking-wider mb-2">✨ Besonderheiten</p>
              <p className="text-[14px] text-purple-900 leading-relaxed">{samen.besonderheiten}</p>
            </div>
          )}

          {/* Botanische Details */}
          {Object.keys(metadata).length > 0 && (
            <div className="bg-white rounded-[20px] shadow-sm p-5">
              <p className="text-[12px] font-bold text-emerald-700 uppercase tracking-wider mb-3">🔬 Botanische Details</p>
              <div className="space-y-2.5 text-[14px]">
                {metadata.botanischer_name && <MetaRow label="Botanischer Name" value={metadata.botanischer_name} italic />}
                {metadata.familie && <MetaRow label="Familie" value={metadata.familie} />}
                {metadata.lebensdauer && <MetaRow label="Lebensdauer" value={metadata.lebensdauer} />}
                {metadata.wuchshoehe && <MetaRow label="Wuchshöhe" value={metadata.wuchshoehe} />}
                {metadata.boden && <MetaRow label="Boden" value={metadata.boden} />}
                {metadata.keimtemperatur && <MetaRow label="Keimtemperatur" value={metadata.keimtemperatur} />}
                {metadata.besonderheiten && <MetaRow label="Besonderheiten" value={metadata.besonderheiten} />}
                {metadata.verwendung && <MetaRow label="Verwendung" value={metadata.verwendung} />}
                {metadata.ernte_hinweis && <MetaRow label="Ernte-Hinweis" value={metadata.ernte_hinweis} />}
              </div>
            </div>
          )}

          {/* Notizen */}
          {samen.notizen && (
            <div className="bg-[#FFF9DB] rounded-[20px] p-4">
              <p className="text-[12px] font-bold text-[#B8860B] uppercase tracking-wider mb-1">📝 Notizen</p>
              <p className="text-[14px] text-[#5C4A00] leading-relaxed">{samen.notizen}</p>
            </div>
          )}

          {/* Delete Button */}
          <button
            onClick={onDelete}
            className="w-full py-3.5 bg-red-500 hover:bg-red-600 text-white rounded-2xl font-semibold text-[15px] transition shadow-sm active:scale-[0.98]"
          >
            🗑️ Samen löschen
          </button>
        </div>
      </div>
    </div>
  );
}

function InfoRow({ emoji, label, value }: { emoji: string; label: string; value: string }) {
  return (
    <div className="flex items-center justify-between px-4 py-3.5">
      <span className="flex items-center gap-2.5"><span>{emoji}</span><span className="text-[15px] text-[#1C1C1E]">{label}</span></span>
      <span className="text-[15px] font-semibold text-[#8E8E93] text-right max-w-[55%]">{value}</span>
    </div>
  );
}

function MetaRow({ label, value, italic }: { label: string; value: string; italic?: boolean }) {
  return (
    <div className="flex justify-between gap-3">
      <span className="text-[#8E8E93] font-medium flex-shrink-0">{label}</span>
      <span className={`text-[#1C1C1E] text-right ${italic ? 'italic' : ''}`}>{value}</span>
    </div>
  );
}

function PflanzplanView({ samen, aufgaben }: { samen: Samen[]; aufgaben: Aufgabe[] }) {
  const monatNameKurz = ['','J','F','M','A','M','J','J','A','S','O','N','D'];
  const monatNameLangArr = ['','Januar','Februar','März','April','Mai','Juni','Juli','August','September','Oktober','November','Dezember'];
  const currentMonth = new Date().getMonth() + 1;

  if (samen.length === 0) {
    return (
      <div className="text-center py-20">
        <div className="text-6xl mb-4">🌱</div>
        <p className="text-[#8E8E93] font-semibold">Keine aktiven Samen!</p>
        <p className="text-[#AEAEB2] text-sm mt-1">Schalte Samen auf „aktiv" um sie hier zu sehen</p>
      </div>
    );
  }

  // Farben pro Samen (rotierend)
  const samenColors = [
    { vorziehen: 'bg-purple-500', aussaat: 'bg-emerald-500', ernte: 'bg-amber-500', text: 'text-purple-700', bg: 'bg-purple-50' },
    { vorziehen: 'bg-violet-500', aussaat: 'bg-green-500', ernte: 'bg-orange-500', text: 'text-violet-700', bg: 'bg-violet-50' },
    { vorziehen: 'bg-fuchsia-500', aussaat: 'bg-teal-500', ernte: 'bg-yellow-500', text: 'text-fuchsia-700', bg: 'bg-fuchsia-50' },
    { vorziehen: 'bg-indigo-500', aussaat: 'bg-lime-500', ernte: 'bg-red-400', text: 'text-indigo-700', bg: 'bg-indigo-50' },
  ];

  return (
    <div className="space-y-4">
      <div className="bg-blue-50 rounded-xl px-4 py-2.5">
        <p className="text-[12px] text-blue-600 font-medium">
          🗓️ Übersicht aller aktiven Samen — Vorziehen → Aussaat → Ernte auf einen Blick
        </p>
      </div>

      {/* Monats-Header */}
      <div className="bg-white rounded-[20px] shadow-sm p-4 overflow-x-auto">
        <div className="min-w-[320px]">
          {/* Header Row */}
          <div className="grid grid-cols-[120px_repeat(12,1fr)] gap-0.5 mb-1">
            <div className="text-[10px] font-bold text-[#8E8E93]">Samen</div>
            {[1,2,3,4,5,6,7,8,9,10,11,12].map(m => (
              <div key={m} className={`text-center text-[9px] font-bold ${m === currentMonth ? 'text-blue-600' : 'text-[#8E8E93]'}`}>
                {monatNameKurz[m]}
              </div>
            ))}
          </div>

          {/* Samen Rows */}
          {samen.map((s, idx) => {
            const colors = samenColors[idx % samenColors.length];
            const getSamenImageUrl = (sam: Samen) => {
              if (!sam.bild_pfade) return null;
              try { const paths = JSON.parse(sam.bild_pfade); if (paths.length > 0) return `/api/v1/media/${paths[0].replace('images/', '')}`; } catch {}
              return null;
            };
            const imgUrl = getSamenImageUrl(s);

            return (
              <div key={s.id} className="grid grid-cols-[120px_repeat(12,1fr)] gap-0.5 mb-1 items-center">
                {/* Samen Name */}
                <div className="flex items-center gap-1.5 pr-1">
                  {imgUrl ? (
                    <img src={imgUrl} alt={s.name} className="w-6 h-6 rounded-full object-cover flex-shrink-0" />
                  ) : (
                    <div className="w-6 h-6 rounded-full bg-emerald-100 flex items-center justify-center flex-shrink-0 text-[10px]">🌱</div>
                  )}
                  <span className="text-[10px] font-semibold text-[#1C1C1E] truncate">{s.name}</span>
                </div>

                {/* Monats-Balken (nutzt geplant_monat aus Aufgaben) */}
                {[1,2,3,4,5,6,7,8,9,10,11,12].map(m => {
                  // Geplante Monate aus Aufgaben ermitteln
                  const samenAufgaben = aufgaben.filter(a => a.samen_id === s.id);
                  const vorziehTask = samenAufgaben.find(a => a.kategorie === 'vorziehen');
                  const pflanzTask = samenAufgaben.find(a => a.kategorie === 'pflanzen');
                  const ernteTask = samenAufgaben.find(a => a.kategorie === 'ernten');

                  // Geplante Monate (Aufgabe > Seed-Default)
                  const vorziehMonat = vorziehTask?.geplant_monat || vorziehTask?.monat || s.vorziehen_ab;
                  const pflanzMonat = pflanzTask?.geplant_monat || pflanzTask?.monat || s.pflanz_von;
                  const ernteMonat = ernteTask?.geplant_monat || ernteTask?.monat || s.ernte_von;
                  const ernteEnd = s.ernte_bis && ernteMonat ? ernteMonat + (s.ernte_bis - (s.ernte_von || 0)) : (ernteMonat || 12);

                  const isVorziehen = vorziehMonat && pflanzMonat && m >= vorziehMonat && m < pflanzMonat;
                  const isAussaat = pflanzMonat && m === pflanzMonat;
                  const isErnte = ernteMonat && m >= ernteMonat && m <= Math.min(ernteEnd, 12);
                  
                  // 2. Zeiträume
                  const isAussaat2 = s.aussaat_2_von && s.aussaat_2_bis && m >= s.aussaat_2_von && m <= s.aussaat_2_bis;
                  const isErnte2 = s.ernte_2_von && s.ernte_2_bis && m >= s.ernte_2_von && m <= s.ernte_2_bis;
                  
                  const isCurrent = m === currentMonth;

                  // Prüfe ob verschoben (anders als Seed-Default)
                  const isShifted = (isVorziehen && vorziehMonat !== s.vorziehen_ab) ||
                                    (isAussaat && pflanzMonat !== s.pflanz_von) ||
                                    (isErnte && ernteMonat !== s.ernte_von);

                  let bg = 'bg-gray-50';
                  let content = '';
                  
                  // Priorität: 2. Zeiträume überlagern 1. (mit Streifen)
                  if (isVorziehen) { bg = colors.vorziehen; content = '🏠'; }
                  if (isAussaat) { bg = colors.aussaat; content = '🌱'; }
                  if (isErnte) { bg = colors.ernte; content = '🌾'; }
                  if (isAussaat2) { 
                    bg = `bg-[repeating-linear-gradient(45deg,rgb(16,185,129),rgb(16,185,129)_2px,rgb(16,185,129,0.3)_2px,rgb(16,185,129,0.3)_4px)]`; 
                    content = '🌱'; 
                  }
                  if (isErnte2) { 
                    bg = `bg-[repeating-linear-gradient(45deg,rgb(245,158,11),rgb(245,158,11)_2px,rgb(245,158,11,0.3)_2px,rgb(245,158,11,0.3)_4px)]`; 
                    content = '🌾'; 
                  }
                  if (isAussaat && isErnte) { bg = `bg-gradient-to-b from-emerald-400 to-amber-400`; content = '✨'; }

                  return (
                    <div key={m} className={`h-7 rounded-sm ${bg} ${isCurrent ? 'ring-1 ring-blue-500' : ''} ${isShifted ? 'ring-1 ring-blue-300' : ''} flex items-center justify-center`}>
                      {(isVorziehen || isAussaat || isErnte || isAussaat2 || isErnte2) && (
                        <span className="text-[8px]">{content}</span>
                      )}
                    </div>
                  );
                })}
              </div>
            );
          })}

          {/* Legende */}
          <div className="flex flex-wrap gap-3 mt-4 pt-3 border-t border-gray-100">
            <div className="flex items-center gap-1.5">
              <div className="w-3 h-3 rounded-sm bg-purple-500" />
              <span className="text-[10px] text-[#8E8E93] font-medium">🏠 Vorziehen</span>
            </div>
            <div className="flex items-center gap-1.5">
              <div className="w-3 h-3 rounded-sm bg-emerald-500" />
              <span className="text-[10px] text-[#8E8E93] font-medium">🌱 Aussaat 1</span>
            </div>
            <div className="flex items-center gap-1.5">
              <div className="w-3 h-3 rounded-sm bg-amber-500" />
              <span className="text-[10px] text-[#8E8E93] font-medium">🌾 Ernte 1</span>
            </div>
            <div className="flex items-center gap-1.5">
              <div className="w-3 h-3 rounded-sm bg-[repeating-linear-gradient(45deg,rgb(16,185,129),rgb(16,185,129)_2px,rgb(16,185,129,0.3)_2px,rgb(16,185,129,0.3)_4px)]" />
              <span className="text-[10px] text-[#8E8E93] font-medium">🌱 Aussaat 2</span>
            </div>
            <div className="flex items-center gap-1.5">
              <div className="w-3 h-3 rounded-sm bg-[repeating-linear-gradient(45deg,rgb(245,158,11),rgb(245,158,11)_2px,rgb(245,158,11,0.3)_2px,rgb(245,158,11,0.3)_4px)]" />
              <span className="text-[10px] text-[#8E8E93] font-medium">🌾 Ernte 2</span>
            </div>
            <div className="flex items-center gap-1.5">
              <div className="w-4 h-3 rounded-sm ring-1 ring-blue-500 bg-white" />
              <span className="text-[10px] text-[#8E8E93] font-medium">Aktuell</span>
            </div>
          </div>
        </div>
      </div>

      {/* Detail-Karten pro Samen (mit geplanten Monaten) */}
      <div className="space-y-3">
        {samen.map((s, idx) => {
          const colors = samenColors[idx % samenColors.length];
          const keimWochen = s.keimzeit_tage ? Math.ceil(s.keimzeit_tage / 7) : null;
          
          // Geplante Monate aus Aufgaben
          const samenAufgaben = aufgaben.filter(a => a.samen_id === s.id);
          const vorziehTask = samenAufgaben.find(a => a.kategorie === 'vorziehen');
          const pflanzTask = samenAufgaben.find(a => a.kategorie === 'pflanzen');
          const ernteTask = samenAufgaben.find(a => a.kategorie === 'ernten');
          const geplVorzieh = vorziehTask?.geplant_monat || vorziehTask?.monat || s.vorziehen_ab;
          const geplPflanz = pflanzTask?.geplant_monat || pflanzTask?.monat || s.pflanz_von;
          const geplErnte = ernteTask?.geplant_monat || ernteTask?.monat || s.ernte_von;
          
          const has2ndPeriod = s.aussaat_2_von || s.ernte_2_von;
          
          return (
            <div key={s.id} className={`${colors.bg} rounded-[20px] p-4 ${has2ndPeriod ? 'ring-2 ring-amber-300' : ''}`}>
              <h4 className={`text-[14px] font-bold ${colors.text} mb-2`}>{s.name}</h4>
              <div className="space-y-1.5">
                {geplVorzieh && (
                  <p className="text-[12px] text-gray-700">
                    🏠 <b>Vorziehen:</b> ab {monatNameLangArr[geplVorzieh]}
                    {geplVorzieh !== s.vorziehen_ab && s.vorziehen_ab && (
                      <span className="text-blue-500 font-medium"> (verschoben von {monatNameLangArr[s.vorziehen_ab]})</span>
                    )}
                    {keimWochen && <span className="text-gray-500"> · Keimzeit ~{keimWochen} Wo.</span>}
                  </p>
                )}
                {geplPflanz && (
                  <p className="text-[12px] text-gray-700">
                    🌱 <b>Auspflanzen:</b> {monatNameLangArr[geplPflanz]}
                    {geplPflanz !== s.pflanz_von && s.pflanz_von && (
                      <span className="text-blue-500 font-medium"> (verschoben von {monatNameLangArr[s.pflanz_von]})</span>
                    )}
                    {s.tiefe_cm && <span className="text-gray-500"> · {s.tiefe_cm}cm tief</span>}
                    {s.abstand_cm && <span className="text-gray-500"> · {s.abstand_cm}cm Abstand</span>}
                  </p>
                )}
                {geplErnte && (
                  <p className="text-[12px] text-gray-700">
                    🌾 <b>Ernte:</b> ab {monatNameLangArr[geplErnte]}
                    {geplErnte !== s.ernte_von && s.ernte_von && (
                      <span className="text-blue-500 font-medium"> (verschoben von {monatNameLangArr[s.ernte_von]})</span>
                    )}
                  </p>
                )}
                {/* 2. Aussaat & Ernte */}
                {s.aussaat_2_von && s.aussaat_2_bis && (
                  <p className="text-[12px] text-emerald-700 bg-emerald-100/60 rounded-lg px-2 py-1">
                    🔄 <b>2. Aussaat:</b> {monatNameLangArr[s.aussaat_2_von]}–{monatNameLangArr[s.aussaat_2_bis]}
                  </p>
                )}
                {s.ernte_2_von && s.ernte_2_bis && (
                  <p className="text-[12px] text-amber-700 bg-amber-100/60 rounded-lg px-2 py-1">
                    🔄 <b>2. Ernte:</b> {monatNameLangArr[s.ernte_2_von]}–{monatNameLangArr[s.ernte_2_bis]}
                  </p>
                )}
                {s.standort_empfehlung && (
                  <p className="text-[12px] text-gray-500">☀️ {s.standort_empfehlung}</p>
                )}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

function AufgabeCard({ aufgabe, onToggle, onShift }: { aufgabe: Aufgabe; onToggle: () => void; onShift?: (delta: number) => void }) {
  const monatNamenKurz = ['','Jan','Feb','Mär','Apr','Mai','Jun','Jul','Aug','Sep','Okt','Nov','Dez'];
  const cfg = kategorieConfig[aufgabe.kategorie] || { emoji: '🌱', color: 'bg-green-500', label: aufgabe.kategorie };
  
  // Quell-Badge bestimmen — zeige echte Pflanzenart, nicht pauschal "Rasen"
  const artLabels: Record<string, { emoji: string; label: string; color: string }> = {
    rasen: { emoji: '🌿', label: 'Rasen', color: 'bg-emerald-600' },
    gras: { emoji: '🌿', label: 'Rasen', color: 'bg-emerald-600' },
    baum: { emoji: '🌳', label: 'Baum', color: 'bg-green-700' },
    strauch: { emoji: '🌿', label: 'Strauch', color: 'bg-lime-600' },
    staude: { emoji: '🌸', label: 'Staude', color: 'bg-pink-600' },
    hecke: { emoji: '🌲', label: 'Hecke', color: 'bg-green-600' },
    kletterpflanze: { emoji: '🌱', label: 'Kletterpflanze', color: 'bg-teal-600' },
    kuebelpflanze: { emoji: '🪴', label: 'Kübelpflanze', color: 'bg-amber-600' },
    gemuese: { emoji: '🥬', label: 'Gemüse', color: 'bg-green-500' },
    kraut: { emoji: '🌿', label: 'Kräuter', color: 'bg-emerald-500' },
  };
  const pflArt = (aufgabe as any).pflanze_art || '';
  const quellBadge = aufgabe.pflanze_id 
    ? (artLabels[pflArt] || { emoji: '🌱', label: (aufgabe as any).pflanze_name || 'Pflanze', color: 'bg-green-600' })
    : aufgabe.samen_id 
    ? { emoji: '🌱', label: 'Samen', color: 'bg-teal-600' }
    : null;

  // Ernte-Info extrahieren
  let ernteInfo = null;
  if (aufgabe.beschreibung && (aufgabe.kategorie === 'vorziehen' || aufgabe.kategorie === 'pflanzen')) {
    const match = aufgabe.beschreibung.match(/🌾 Ernte ab ([^.]+)/);
    if (match) {
      ernteInfo = match[1].trim();
    }
  }

  return (
    <div
      className={`rounded-xl p-3.5 border transition ${
        (aufgabe as any)._overdue
          ? 'bg-orange-50 border-orange-300 shadow-md'
          : aufgabe.erledigt
          ? 'bg-gray-50 border-gray-200 opacity-60'
          : 'bg-white border-black/5 shadow-sm'
      }`}
    >
      <div className="flex items-start gap-3">
        <button
          onClick={onToggle}
          className={`flex-shrink-0 w-6 h-6 rounded-lg border-2 flex items-center justify-center transition ${
            aufgabe.erledigt
              ? 'bg-emerald-500 border-emerald-500'
              : 'bg-white border-gray-300 hover:border-emerald-400'
          }`}
        >
          {aufgabe.erledigt && (
            <svg className="w-4 h-4 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={3}>
              <path strokeLinecap="round" strokeLinejoin="round" d="M5 13l4 4L19 7" />
            </svg>
          )}
        </button>
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 mb-1 flex-wrap">
            {(aufgabe as any)._overdue && (
              <span className="text-[10px] font-bold text-white bg-orange-600 px-2 py-0.5 rounded-full animate-pulse">
                ⚠️ Überfällig ({monatNamenKurz[(aufgabe as any)._originalMonat || aufgabe.monat]})
              </span>
            )}
            {quellBadge && (
              <span className={`text-[10px] font-bold text-white px-2 py-0.5 rounded-full ${quellBadge.color}`}>
                {quellBadge.emoji} {quellBadge.label}
              </span>
            )}
            <span className={`text-[10px] font-bold text-white px-2 py-0.5 rounded-full ${cfg.color}`}>
              {cfg.emoji} {cfg.label}
            </span>
            {aufgabe.prioritaet === 'hoch' && !(aufgabe as any)._overdue && (
              <span className="text-[10px] font-bold text-red-600 bg-red-500/10 px-2 py-0.5 rounded-full">
                🔥 Wichtig
              </span>
            )}
          </div>
          <h4 className={`text-[14px] font-semibold ${aufgabe.erledigt ? 'text-gray-400 line-through' : 'text-[#1C1C1E]'}`}>
            {aufgabe.titel}
          </h4>
          {aufgabe.kategorie === 'duengen' && aufgabe.duenger_name && !aufgabe.erledigt && (
            <div className="mt-1.5 flex items-center gap-1.5">
              <span className="text-[11px] font-bold text-amber-700 bg-amber-100 px-2 py-0.5 rounded-full">
                💩 {aufgabe.duenger_name}
              </span>
              {aufgabe.duenger_vorraetig === 0 && (
                <span className="text-[11px] font-bold text-red-700 bg-red-100 px-2 py-0.5 rounded-full animate-pulse">⚠️ Nicht vorrätig!</span>
              )}
            </div>
          )}
          {ernteInfo && !aufgabe.erledigt && (
            <div className="mt-1.5">
              <span className="text-[11px] font-bold text-emerald-700 bg-emerald-100 px-2 py-0.5 rounded-full">
                🌾 Ernte: {ernteInfo}
              </span>
            </div>
          )}
          {/* +1 / -1 Shift-Buttons für Samen-Aufgaben */}
          {onShift && aufgabe.samen_id && !aufgabe.erledigt && (
            <div className="flex items-center gap-2 mt-2">
              <span className="text-[11px] text-[#8E8E93] font-medium">📅 Geplant:</span>
              <button
                onClick={(e) => { e.stopPropagation(); onShift(-1); }}
                disabled={(aufgabe.geplant_monat || aufgabe.monat) <= 1}
                className="w-7 h-7 rounded-lg bg-gray-100 hover:bg-gray-200 active:bg-gray-300 flex items-center justify-center text-[14px] font-bold text-gray-600 disabled:opacity-30 transition"
              >−</button>
              <span className={`text-[12px] font-bold px-2.5 py-1 rounded-lg ${
                (aufgabe.geplant_monat || aufgabe.monat) !== aufgabe.monat 
                  ? 'bg-blue-100 text-blue-700' 
                  : 'bg-gray-100 text-gray-700'
              }`}>
                {monatNamenKurz[aufgabe.geplant_monat || aufgabe.monat]}
                {(aufgabe.geplant_monat || aufgabe.monat) !== aufgabe.monat && (
                  <span className="text-[10px] text-blue-400 ml-1">(statt {monatNamenKurz[aufgabe.monat]})</span>
                )}
              </span>
              <button
                onClick={(e) => { e.stopPropagation(); onShift(1); }}
                disabled={(aufgabe.geplant_monat || aufgabe.monat) >= 12}
                className="w-7 h-7 rounded-lg bg-gray-100 hover:bg-gray-200 active:bg-gray-300 flex items-center justify-center text-[14px] font-bold text-gray-600 disabled:opacity-30 transition"
              >+</button>
            </div>
          )}
          {aufgabe.beschreibung && (
            <p className={`text-[12px] mt-1 ${aufgabe.erledigt ? 'text-gray-400' : 'text-[#8E8E93]'}`}>
              {aufgabe.beschreibung}
            </p>
          )}
          {aufgabe.erledigt && aufgabe.erledigt_am && (
            <p className="text-[11px] text-gray-400 mt-1">
              ✅ Erledigt am {new Date(aufgabe.erledigt_am).toLocaleDateString('de-DE')}
            </p>
          )}
        </div>
      </div>
    </div>
  );
}
