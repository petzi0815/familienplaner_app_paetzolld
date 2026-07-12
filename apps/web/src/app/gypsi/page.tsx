'use client';

import { useState, useEffect, useCallback } from 'react';
import Link from 'next/link';

interface Futter {
  id: number;
  marke: string;
  sorte: string;
  geschmack?: string;
  bild_pfad?: string;
  status: 'mag_er' | 'mag_er_nicht_mehr';
  erfasst_am: string;
  status_geaendert_am?: string;
  notizen?: string;
}

type StatusFilter = 'alle' | 'mag_er' | 'mag_er_nicht_mehr';

function formatDate(dateStr: string) {
  return new Date(dateStr).toLocaleDateString('de-DE', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
  });
}

function FutterCard({
  futter,
  onStatusToggle,
  onDelete,
}: {
  futter: Futter;
  onStatusToggle: (id: number, newStatus: 'mag_er' | 'mag_er_nicht_mehr') => void;
  onDelete: (id: number) => void;
}) {
  const [deleting, setDeleting] = useState(false);
  const [toggling, setToggling] = useState(false);

  const newStatus = futter.status === 'mag_er' ? 'mag_er_nicht_mehr' : 'mag_er';

  const handleToggle = async () => {
    if (toggling) return;
    setToggling(true);
    await onStatusToggle(futter.id, newStatus);
    setToggling(false);
  };

  const handleDelete = async () => {
    if (deleting) return;
    if (!confirm(`"${futter.marke} ${futter.sorte}" wirklich löschen?`)) return;
    setDeleting(true);
    await onDelete(futter.id);
    setDeleting(false);
  };

  const imageUrl = futter.bild_pfad
    ? `/api/v1/media/${futter.bild_pfad.replace('images/', '')}`
    : null;

  return (
    <div
      className={`
        relative overflow-hidden bg-white/70 backdrop-blur-sm rounded-2xl border shadow-sm
        transition-all duration-300
        ${futter.status === 'mag_er'
          ? 'border-amber-200/60 shadow-amber-100'
          : 'border-red-200/60 shadow-red-50 opacity-80'}
      `}
    >
      <div className="flex items-start gap-3 p-4">
        {/* Foto */}
        <div className="flex-shrink-0 w-20 h-20 rounded-xl overflow-hidden bg-gradient-to-br from-amber-100 to-orange-100 flex items-center justify-center border border-amber-200/40">
          {imageUrl ? (
            <img
              src={imageUrl}
              alt={`${futter.marke} ${futter.sorte}`}
              className="w-full h-full object-cover"
            />
          ) : (
            <span className="text-3xl">🐱</span>
          )}
        </div>

        {/* Info */}
        <div className="flex-1 min-w-0">
          <div className="flex items-start justify-between gap-2">
            <div className="min-w-0">
              <p className="text-xs font-semibold text-amber-600 uppercase tracking-wide truncate">
                {futter.marke}
              </p>
              <h3 className="text-sm font-bold text-[#1C1C1E] leading-tight mt-0.5 line-clamp-2">
                {futter.sorte}
              </h3>
            </div>
            {/* Status Badge */}
            <span
              className={`
                flex-shrink-0 text-[10px] font-bold px-2 py-0.5 rounded-full
                ${futter.status === 'mag_er'
                  ? 'bg-green-100 text-green-700'
                  : 'bg-red-100 text-red-600'}
              `}
            >
              {futter.status === 'mag_er' ? '✓ Mag er' : '✗ Mag er nicht mehr'}
            </span>
          </div>

          <div className="flex flex-wrap gap-1.5 mt-2">
            {futter.geschmack && (
              <span className="text-[11px] font-medium bg-amber-100 text-amber-700 px-2 py-0.5 rounded-full">
                🥩 {futter.geschmack}
              </span>
            )}
            <span className="text-[11px] text-[#8E8E93] bg-[#F2F2F7] px-2 py-0.5 rounded-full">
              {formatDate(futter.erfasst_am)}
            </span>
          </div>

          {futter.notizen && (
            <p className="text-[11px] text-[#8E8E93] mt-1.5 line-clamp-2 italic">
              {futter.notizen}
            </p>
          )}

          {/* Action buttons */}
          <div className="flex gap-2 mt-3">
            <button
              onClick={handleToggle}
              disabled={toggling}
              className={`
                flex-1 text-[12px] font-semibold py-1.5 px-3 rounded-xl transition-all active:scale-95
                ${futter.status === 'mag_er'
                  ? 'bg-red-100 text-red-600 hover:bg-red-200'
                  : 'bg-green-100 text-green-700 hover:bg-green-200'}
                ${toggling ? 'opacity-50' : ''}
              `}
            >
              {toggling ? '⏳' : futter.status === 'mag_er' ? '👎 Mag er nicht mehr' : '👍 Mag er wieder'}
            </button>
            <button
              onClick={handleDelete}
              disabled={deleting}
              className="text-[12px] font-semibold py-1.5 px-3 rounded-xl bg-gray-100 text-gray-500 hover:bg-gray-200 transition-all active:scale-95"
            >
              {deleting ? '⏳' : '🗑️'}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

function AddFutterModal({
  onClose,
  onAdded,
}: {
  onClose: () => void;
  onAdded: () => void;
}) {
  const [marke, setMarke] = useState('');
  const [sorte, setSorte] = useState('');
  const [geschmack, setGeschmack] = useState('');
  const [notizen, setNotizen] = useState('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!marke.trim() || !sorte.trim()) {
      setError('Marke und Sorte sind Pflichtfelder.');
      return;
    }
    setSaving(true);
    setError('');
    try {
      const res = await fetch('/api/gypsi/futter', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ marke: marke.trim(), sorte: sorte.trim(), geschmack: geschmack.trim() || undefined, notizen: notizen.trim() || undefined }),
      });
      if (!res.ok) {
        const data = await res.json();
        throw new Error(data.error || 'Fehler beim Speichern');
      }
      onAdded();
      onClose();
    } catch (err: any) {
      setError(err.message);
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center sm:items-center bg-black/40 backdrop-blur-sm" onClick={onClose}>
      <div
        className="w-full max-w-md bg-white rounded-t-3xl sm:rounded-3xl shadow-2xl p-6 pb-safe"
        onClick={e => e.stopPropagation()}
      >
        <div className="flex items-center justify-between mb-5">
          <h2 className="text-xl font-extrabold text-[#1C1C1E]">🐱 Neues Futter</h2>
          <button onClick={onClose} className="text-[#8E8E93] hover:text-[#1C1C1E] transition">✕</button>
        </div>

        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="block text-xs font-semibold text-amber-700 mb-1 uppercase tracking-wide">Marke *</label>
            <input
              type="text"
              value={marke}
              onChange={e => setMarke(e.target.value)}
              placeholder="z.B. Animonda, MjAMjAM"
              className="w-full bg-[#F2F2F7] rounded-xl px-4 py-3 text-sm text-[#1C1C1E] placeholder:text-[#C7C7CC] outline-none focus:ring-2 focus:ring-amber-400"
              required
            />
          </div>
          <div>
            <label className="block text-xs font-semibold text-amber-700 mb-1 uppercase tracking-wide">Sorte *</label>
            <input
              type="text"
              value={sorte}
              onChange={e => setSorte(e.target.value)}
              placeholder="z.B. Carny Adult Rind & Huhn"
              className="w-full bg-[#F2F2F7] rounded-xl px-4 py-3 text-sm text-[#1C1C1E] placeholder:text-[#C7C7CC] outline-none focus:ring-2 focus:ring-amber-400"
              required
            />
          </div>
          <div>
            <label className="block text-xs font-semibold text-amber-700 mb-1 uppercase tracking-wide">Geschmack</label>
            <input
              type="text"
              value={geschmack}
              onChange={e => setGeschmack(e.target.value)}
              placeholder="z.B. Rind, Huhn, Fisch"
              className="w-full bg-[#F2F2F7] rounded-xl px-4 py-3 text-sm text-[#1C1C1E] placeholder:text-[#C7C7CC] outline-none focus:ring-2 focus:ring-amber-400"
            />
          </div>
          <div>
            <label className="block text-xs font-semibold text-amber-700 mb-1 uppercase tracking-wide">Notizen</label>
            <textarea
              value={notizen}
              onChange={e => setNotizen(e.target.value)}
              placeholder="Optionale Anmerkungen..."
              rows={2}
              className="w-full bg-[#F2F2F7] rounded-xl px-4 py-3 text-sm text-[#1C1C1E] placeholder:text-[#C7C7CC] outline-none focus:ring-2 focus:ring-amber-400 resize-none"
            />
          </div>

          {error && (
            <p className="text-red-600 text-sm font-medium bg-red-50 rounded-xl px-4 py-2">{error}</p>
          )}

          <button
            type="submit"
            disabled={saving}
            className="w-full bg-gradient-to-r from-amber-500 to-orange-500 text-white font-bold py-3.5 rounded-2xl shadow-lg hover:from-amber-600 hover:to-orange-600 active:scale-95 transition-all disabled:opacity-60 text-base"
          >
            {saving ? 'Speichern…' : '✓ Futter hinzufügen'}
          </button>
        </form>
      </div>
    </div>
  );
}

export default function GypsiPage() {
  const [futter, setFutter] = useState<Futter[]>([]);
  const [marken, setMarken] = useState<string[]>([]);
  const [geschmacksrichtungen, setGeschmacksrichtungen] = useState<string[]>([]);
  const [loading, setLoading] = useState(true);
  const [showAddModal, setShowAddModal] = useState(false);

  // Filter state
  const [statusFilter, setStatusFilter] = useState<StatusFilter>('alle');
  const [markeFilter, setMarkeFilter] = useState('');
  const [geschmackFilter, setGeschmackFilter] = useState('');

  const loadData = useCallback(async () => {
    setLoading(true);
    try {
      const params = new URLSearchParams();
      if (statusFilter !== 'alle') params.set('status', statusFilter);
      if (markeFilter) params.set('marke', markeFilter);
      if (geschmackFilter) params.set('geschmack', geschmackFilter);

      const [futterRes, markenRes, geschmackRes] = await Promise.all([
        fetch(`/api/gypsi/futter?${params.toString()}`),
        fetch('/api/gypsi/futter?marken=true'),
        fetch('/api/gypsi/futter?geschmacksrichtungen=true'),
      ]);

      const [futterData, markenData, geschmackData] = await Promise.all([
        futterRes.json(),
        markenRes.json(),
        geschmackRes.json(),
      ]);

      setFutter(futterData);
      setMarken(markenData);
      setGeschmacksrichtungen(geschmackData);
    } catch (err) {
      console.error('Fehler beim Laden:', err);
    } finally {
      setLoading(false);
    }
  }, [statusFilter, markeFilter, geschmackFilter]);

  useEffect(() => {
    loadData();
  }, [loadData]);

  const handleStatusToggle = async (id: number, newStatus: 'mag_er' | 'mag_er_nicht_mehr') => {
    try {
      const res = await fetch(`/api/gypsi/futter/${id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ status: newStatus }),
      });
      if (res.ok) {
        await loadData();
      }
    } catch (err) {
      console.error('Fehler beim Status-Update:', err);
    }
  };

  const handleDelete = async (id: number) => {
    try {
      const res = await fetch(`/api/gypsi/futter/${id}`, { method: 'DELETE' });
      if (res.ok) {
        await loadData();
      }
    } catch (err) {
      console.error('Fehler beim Löschen:', err);
    }
  };

  const magErCount = futter.filter(f => f.status === 'mag_er').length;
  const magNichtMehrCount = futter.filter(f => f.status === 'mag_er_nicht_mehr').length;

  return (
    <main className="min-h-screen bg-gradient-to-br from-[#FFF8F0] via-[#FFF3E0] to-[#FFF8F0]">
      {/* ── Header ── */}
      <header className="pt-12 pb-6 px-5 safe-area-inset">
        <div className="max-w-2xl mx-auto">
          <div className="flex items-center gap-3 mb-4">
            <Link
              href="/"
              className="flex items-center justify-center w-10 h-10 bg-white/70 backdrop-blur-sm rounded-2xl border border-amber-200/50 shadow-sm hover:bg-white transition active:scale-95"
            >
              <svg className="w-5 h-5 text-amber-600" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2.5}>
                <path strokeLinecap="round" strokeLinejoin="round" d="M15 19l-7-7 7-7" />
              </svg>
            </Link>
            <div>
              <h1 className="text-3xl font-extrabold text-[#1C1C1E] tracking-tight leading-tight">
                🐱 Gypsis Futter
              </h1>
              <p className="text-amber-600/80 text-sm font-medium mt-0.5">
                Futter-Vorlieben & Tracking
              </p>
            </div>
          </div>

          {/* Stats pills */}
          <div className="flex gap-2 flex-wrap">
            <div className="flex items-center gap-1.5 bg-green-100 text-green-700 px-3 py-1.5 rounded-full text-sm font-semibold">
              <span>✓</span>
              <span>{magErCount} mag er</span>
            </div>
            <div className="flex items-center gap-1.5 bg-red-100 text-red-600 px-3 py-1.5 rounded-full text-sm font-semibold">
              <span>✗</span>
              <span>{magNichtMehrCount} mag er nicht mehr</span>
            </div>
            <div className="flex items-center gap-1.5 bg-amber-100 text-amber-700 px-3 py-1.5 rounded-full text-sm font-semibold">
              <span>📦</span>
              <span>{futter.length} gesamt</span>
            </div>
          </div>
        </div>
      </header>

      {/* ── Filter Bar ── */}
      <div className="max-w-2xl mx-auto px-5 mb-4">
        <div className="bg-white/60 backdrop-blur-sm rounded-2xl border border-amber-200/40 p-4 shadow-sm space-y-3">
          {/* Status Toggle */}
          <div className="flex gap-2">
            {(['alle', 'mag_er', 'mag_er_nicht_mehr'] as StatusFilter[]).map(s => (
              <button
                key={s}
                onClick={() => setStatusFilter(s)}
                className={`
                  flex-1 text-xs font-semibold py-2 px-3 rounded-xl transition-all
                  ${statusFilter === s
                    ? s === 'alle'
                      ? 'bg-amber-500 text-white shadow-sm'
                      : s === 'mag_er'
                        ? 'bg-green-500 text-white shadow-sm'
                        : 'bg-red-500 text-white shadow-sm'
                    : 'bg-[#F2F2F7] text-[#8E8E93] hover:bg-[#E5E5EA]'}
                `}
              >
                {s === 'alle' ? '🐱 Alles' : s === 'mag_er' ? '✓ Mag er' : '✗ Mag er nicht mehr'}
              </button>
            ))}
          </div>

          {/* Marke & Geschmack Dropdowns */}
          <div className="flex gap-2">
            <select
              value={markeFilter}
              onChange={e => setMarkeFilter(e.target.value)}
              className="flex-1 bg-[#F2F2F7] rounded-xl px-3 py-2 text-sm text-[#1C1C1E] outline-none focus:ring-2 focus:ring-amber-400"
            >
              <option value="">Alle Marken</option>
              {marken.map(m => (
                <option key={m} value={m}>{m}</option>
              ))}
            </select>
            <select
              value={geschmackFilter}
              onChange={e => setGeschmackFilter(e.target.value)}
              className="flex-1 bg-[#F2F2F7] rounded-xl px-3 py-2 text-sm text-[#1C1C1E] outline-none focus:ring-2 focus:ring-amber-400"
            >
              <option value="">Alle Geschmäcker</option>
              {geschmacksrichtungen.map(g => (
                <option key={g} value={g}>{g}</option>
              ))}
            </select>
            {(markeFilter || geschmackFilter) && (
              <button
                onClick={() => { setMarkeFilter(''); setGeschmackFilter(''); }}
                className="px-3 py-2 bg-[#F2F2F7] rounded-xl text-sm text-[#8E8E93] hover:bg-[#E5E5EA] transition"
              >
                ✕
              </button>
            )}
          </div>
        </div>
      </div>

      {/* ── Futter Liste ── */}
      <div className="max-w-2xl mx-auto px-5 pb-32">
        {loading ? (
          <div className="flex flex-col items-center justify-center py-16">
            <div className="text-4xl animate-bounce mb-3">🐱</div>
            <p className="text-[#8E8E93] font-medium">Lade Futter…</p>
          </div>
        ) : futter.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-16 text-center">
            <div className="text-6xl mb-4">🐾</div>
            <h3 className="text-xl font-bold text-[#1C1C1E] mb-2">Noch kein Futter eingetragen</h3>
            <p className="text-[#8E8E93] text-sm max-w-[220px]">
              Tippe auf das + unten, um Gypsis erstes Futter hinzuzufügen.
            </p>
          </div>
        ) : (
          <div className="space-y-3">
            {futter.map(f => (
              <FutterCard
                key={f.id}
                futter={f}
                onStatusToggle={handleStatusToggle}
                onDelete={handleDelete}
              />
            ))}
          </div>
        )}
      </div>

      {/* ── FAB: Add Button ── */}
      <div className="fixed bottom-8 right-5 z-40">
        <button
          onClick={() => setShowAddModal(true)}
          className="flex items-center gap-2 bg-gradient-to-r from-amber-500 to-orange-500 text-white font-bold py-3.5 px-5 rounded-2xl shadow-xl hover:from-amber-600 hover:to-orange-600 active:scale-95 transition-all"
        >
          <span className="text-xl">+</span>
          <span>Futter hinzufügen</span>
        </button>
      </div>

      {/* ── Add Modal ── */}
      {showAddModal && (
        <AddFutterModal
          onClose={() => setShowAddModal(false)}
          onAdded={loadData}
        />
      )}
    </main>
  );
}
