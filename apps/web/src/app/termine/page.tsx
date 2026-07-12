'use client';

import { useState, useEffect, useCallback } from 'react';
import Link from 'next/link';

interface Termin {
  id: number;
  title: string;
  description: string | null;
  category: string;
  date: string;
  time: string | null;
  end_date: string | null;
  end_time: string | null;
  location: string | null;
  person: string | null;
  recurring: string | null;
  reminder_days: number;
  status: string;
  notes: string | null;
  source: string;
}

interface Category {
  id: string;
  label: string;
  emoji: string;
  color: string;
}

const WEEKDAYS = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
const MONTHS = ['Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'];

function getCatStyle(cat: string, categories: Category[]) {
  const c = categories.find(x => x.id === cat);
  const colors: Record<string, { bg: string; text: string; border: string; dot: string }> = {
    blue:   { bg: 'bg-blue-50', text: 'text-blue-700', border: 'border-blue-200', dot: 'bg-blue-500' },
    red:    { bg: 'bg-red-50', text: 'text-red-700', border: 'border-red-200', dot: 'bg-red-500' },
    rose:   { bg: 'bg-rose-50', text: 'text-rose-700', border: 'border-rose-200', dot: 'bg-rose-500' },
    purple: { bg: 'bg-purple-50', text: 'text-purple-700', border: 'border-purple-200', dot: 'bg-purple-500' },
    indigo: { bg: 'bg-indigo-50', text: 'text-indigo-700', border: 'border-indigo-200', dot: 'bg-indigo-500' },
    cyan:   { bg: 'bg-cyan-50', text: 'text-cyan-700', border: 'border-cyan-200', dot: 'bg-cyan-500' },
    amber:  { bg: 'bg-amber-50', text: 'text-amber-700', border: 'border-amber-200', dot: 'bg-amber-500' },
    orange: { bg: 'bg-orange-50', text: 'text-orange-700', border: 'border-orange-200', dot: 'bg-orange-500' },
    gray:   { bg: 'bg-gray-50', text: 'text-gray-700', border: 'border-gray-200', dot: 'bg-gray-500' },
    green:  { bg: 'bg-green-50', text: 'text-green-700', border: 'border-green-200', dot: 'bg-green-500' },
    pink:   { bg: 'bg-pink-50', text: 'text-pink-700', border: 'border-pink-200', dot: 'bg-pink-500' },
    violet: { bg: 'bg-violet-50', text: 'text-violet-700', border: 'border-violet-200', dot: 'bg-violet-500' },
    slate:  { bg: 'bg-slate-50', text: 'text-slate-700', border: 'border-slate-200', dot: 'bg-slate-500' },
  };
  return colors[c?.color || 'blue'] || colors.blue;
}

function formatDate(d: string) {
  const date = new Date(d + 'T00:00:00');
  return date.toLocaleDateString('de-DE', { weekday: 'short', day: '2-digit', month: '2-digit', year: 'numeric' });
}

function formatTime(t: string | null) {
  if (!t) return '';
  return t.slice(0, 5) + ' Uhr';
}

function daysUntil(dateStr: string): number {
  const now = new Date(); now.setHours(0,0,0,0);
  const target = new Date(dateStr + 'T00:00:00'); target.setHours(0,0,0,0);
  return Math.ceil((target.getTime() - now.getTime()) / 86400000);
}

function daysBadge(dateStr: string) {
  const days = daysUntil(dateStr);
  if (days < 0) return <span className="text-[10px] bg-gray-200 text-gray-500 px-2 py-0.5 rounded-full">vorbei</span>;
  if (days === 0) return <span className="text-[10px] bg-red-100 text-red-600 px-2 py-0.5 rounded-full font-bold animate-pulse">🔴 Heute</span>;
  if (days === 1) return <span className="text-[10px] bg-orange-100 text-orange-600 px-2 py-0.5 rounded-full font-bold">⚡ Morgen</span>;
  if (days <= 7) return <span className="text-[10px] bg-amber-100 text-amber-700 px-2 py-0.5 rounded-full font-semibold">{days} Tage</span>;
  if (days <= 30) return <span className="text-[10px] bg-gray-100 text-gray-600 px-2 py-0.5 rounded-full">{days} Tage</span>;
  return null;
}

/* ── Calendar Grid ── */
function CalendarGrid({ year, month, termine, onDayClick }: { year: number; month: number; termine: Termin[]; onDayClick: (date: string) => void }) {
  const firstDay = new Date(year, month - 1, 1);
  let startDay = firstDay.getDay() - 1;
  if (startDay < 0) startDay = 6;
  const daysInMonth = new Date(year, month, 0).getDate();
  const today = new Date().toISOString().split('T')[0];

  const terminsByDate = new Map<string, Termin[]>();
  termine.forEach(t => {
    const key = t.date;
    if (!terminsByDate.has(key)) terminsByDate.set(key, []);
    terminsByDate.get(key)!.push(t);
    // Multi-day events
    if (t.end_date && t.end_date !== t.date) {
      let d = new Date(t.date + 'T00:00:00');
      const end = new Date(t.end_date + 'T00:00:00');
      while (d < end) {
        d.setDate(d.getDate() + 1);
        const dk = d.toISOString().split('T')[0];
        if (!terminsByDate.has(dk)) terminsByDate.set(dk, []);
        terminsByDate.get(dk)!.push(t);
      }
    }
  });

  const cells: React.ReactElement[] = [];
  for (let i = 0; i < startDay; i++) {
    cells.push(<div key={`empty-${i}`} className="h-12" />);
  }

  for (let day = 1; day <= daysInMonth; day++) {
    const dateStr = `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
    const dayTermine = terminsByDate.get(dateStr) || [];
    const isToday = dateStr === today;
    const isPast = dateStr < today;

    cells.push(
      <button
        key={day}
        onClick={() => onDayClick(dateStr)}
        className={`h-12 rounded-xl text-center relative transition-all active:scale-95 ${
          isToday ? 'bg-blue-500 text-white font-bold shadow-sm' :
          isPast ? 'text-gray-400' :
          'text-[#1C1C1E] hover:bg-blue-50'
        }`}
      >
        <span className="text-sm">{day}</span>
        {dayTermine.length > 0 && (
          <div className="flex justify-center gap-0.5 mt-0.5">
            {dayTermine.slice(0, 3).map((t, i) => (
              <div key={i} className={`w-1.5 h-1.5 rounded-full ${isToday ? 'bg-white' : 'bg-blue-500'}`} />
            ))}
          </div>
        )}
      </button>
    );
  }

  return (
    <div className="bg-white/70 backdrop-blur-sm rounded-2xl border border-blue-200/40 p-4 shadow-sm">
      <div className="grid grid-cols-7 gap-1 mb-2">
        {WEEKDAYS.map(d => (
          <div key={d} className="text-center text-[11px] font-bold text-[#8E8E93] py-1">{d}</div>
        ))}
      </div>
      <div className="grid grid-cols-7 gap-1">{cells}</div>
    </div>
  );
}

/* ── Termin Card ── */
function TerminCard({ termin, categories, onUpdate, onDelete }: { termin: Termin; categories: Category[]; onUpdate: (id: number, data: Partial<Termin>) => void; onDelete: (id: number) => void }) {
  const [editing, setEditing] = useState(false);
  const [editData, setEditData] = useState({ ...termin });
  const cat = categories.find(c => c.id === termin.category);
  const style = getCatStyle(termin.category, categories);
  const isPast = termin.date < new Date().toISOString().split('T')[0];

  const handleSave = () => {
    onUpdate(termin.id, editData);
    setEditing(false);
  };

  if (editing) {
    return (
      <div className="bg-white/80 backdrop-blur-sm rounded-2xl border border-blue-300/60 p-4 shadow-sm space-y-2">
        <input type="text" value={editData.title} onChange={e => setEditData(d => ({...d, title: e.target.value}))} className="w-full bg-[#F2F2F7] rounded-xl px-3 py-2 text-sm outline-none focus:ring-2 focus:ring-blue-400" />
        <textarea value={editData.description || ''} onChange={e => setEditData(d => ({...d, description: e.target.value}))} placeholder="Beschreibung" rows={2} className="w-full bg-[#F2F2F7] rounded-xl px-3 py-2 text-sm outline-none focus:ring-2 focus:ring-blue-400 resize-none" />
        <div className="flex gap-2">
          <input type="date" value={editData.date} onChange={e => setEditData(d => ({...d, date: e.target.value}))} className="flex-1 bg-[#F2F2F7] rounded-xl px-3 py-2 text-sm outline-none focus:ring-2 focus:ring-blue-400" />
          <input type="time" value={editData.time || ''} onChange={e => setEditData(d => ({...d, time: e.target.value || null}))} className="flex-1 bg-[#F2F2F7] rounded-xl px-3 py-2 text-sm outline-none focus:ring-2 focus:ring-blue-400" />
        </div>
        <div className="flex gap-2">
          <input type="text" value={editData.location || ''} onChange={e => setEditData(d => ({...d, location: e.target.value}))} placeholder="📍 Ort" className="flex-1 bg-[#F2F2F7] rounded-xl px-3 py-2 text-sm outline-none focus:ring-2 focus:ring-blue-400" />
          <select value={editData.person || ''} onChange={e => setEditData(d => ({...d, person: e.target.value || null}))} className="flex-1 bg-[#F2F2F7] rounded-xl px-3 py-2 text-sm outline-none focus:ring-2 focus:ring-blue-400">
            <option value="">Für…</option>
            <option value="Samu">👶 Samu</option>
            <option value="Lars">👨 Lars</option>
            <option value="Elita">👩 Elita</option>
            <option value="Gypsi">🐱 Gypsi</option>
            <option value="Familie">👨‍👩‍👦 Familie</option>
          </select>
        </div>
        <select value={editData.category} onChange={e => setEditData(d => ({...d, category: e.target.value}))} className="w-full bg-[#F2F2F7] rounded-xl px-3 py-2 text-sm outline-none focus:ring-2 focus:ring-blue-400">
          {categories.map(c => <option key={c.id} value={c.id}>{c.emoji} {c.label}</option>)}
        </select>
        <div className="flex gap-2">
          <button onClick={handleSave} className="flex-1 py-2 bg-blue-500 text-white text-sm font-semibold rounded-xl transition active:scale-95">💾 Speichern</button>
          <button onClick={() => setEditing(false)} className="px-4 py-2 bg-gray-100 text-gray-500 text-sm rounded-xl transition active:scale-95">✕</button>
        </div>
      </div>
    );
  }

  return (
    <div className={`overflow-hidden bg-white/70 backdrop-blur-sm rounded-2xl border shadow-sm transition-all ${isPast && termin.status === 'offen' ? 'opacity-60' : ''} ${style.border}`}>
      <div className="flex items-start gap-3 p-3.5">
        {/* Category dot + time */}
        <div className="flex-shrink-0 flex flex-col items-center gap-1 min-w-[40px]">
          <span className="text-lg">{cat?.emoji || '📅'}</span>
          {termin.time && <span className="text-[11px] font-bold text-[#1C1C1E]">{termin.time.slice(0, 5)}</span>}
        </div>

        <div className="flex-1 min-w-0">
          <div className="flex items-start justify-between gap-2">
            <h3 className={`text-sm font-bold text-[#1C1C1E] leading-tight ${termin.status === 'erledigt' ? 'line-through opacity-60' : ''}`}>
              {termin.title}
            </h3>
            {daysBadge(termin.date)}
          </div>

          {termin.description && (
            <p className="text-[11px] text-[#636366] mt-0.5 line-clamp-2">{termin.description}</p>
          )}

          <div className="flex flex-wrap gap-1.5 mt-1.5">
            <span className="text-[10px] font-medium text-[#8E8E93]">📅 {formatDate(termin.date)}</span>
            {termin.end_date && termin.end_date !== termin.date && (
              <span className="text-[10px] font-medium text-[#8E8E93]">→ {formatDate(termin.end_date)}</span>
            )}
            {termin.location && <span className="text-[10px] text-[#636366]">📍 {termin.location}</span>}
            {termin.person && <span className={`text-[10px] font-medium ${style.text} ${style.bg} px-1.5 py-0.5 rounded-full`}>{termin.person}</span>}
            <span className={`text-[10px] font-medium ${style.text} ${style.bg} px-1.5 py-0.5 rounded-full`}>{cat?.label}</span>
          </div>

          {termin.notes && <p className="text-[10px] text-[#8E8E93] mt-1 italic">{termin.notes}</p>}

          <div className="flex justify-between items-center mt-2 pt-1.5 border-t border-gray-100">
            <div className="flex gap-1.5">
              {termin.status === 'offen' ? (
                <button onClick={() => onUpdate(termin.id, { status: 'erledigt' })} className="text-[11px] py-1 px-2.5 rounded-lg bg-green-50 text-green-600 font-medium hover:bg-green-100 transition active:scale-95">✅ Erledigt</button>
              ) : (
                <button onClick={() => onUpdate(termin.id, { status: 'offen' })} className="text-[11px] py-1 px-2.5 rounded-lg bg-amber-50 text-amber-600 font-medium hover:bg-amber-100 transition active:scale-95">↩️ Offen</button>
              )}
              <button onClick={() => setEditing(true)} className="text-[11px] py-1 px-2.5 rounded-lg bg-blue-50 text-blue-500 font-medium hover:bg-blue-100 transition active:scale-95">✏️</button>
            </div>
            <button onClick={() => { if (confirm(`"${termin.title}" löschen?`)) onDelete(termin.id); }} className="text-[11px] py-1 px-2 rounded-lg bg-gray-50 text-gray-400 hover:bg-red-50 hover:text-red-400 transition active:scale-95">🗑️</button>
          </div>
        </div>
      </div>
    </div>
  );
}

/* ── Add Termin Form ── */
function AddTerminForm({ categories, initialDate, onAdded }: { categories: Category[]; initialDate?: string; onAdded: () => void }) {
  const [open, setOpen] = useState(false);
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [category, setCategory] = useState('allgemein');
  const [date, setDate] = useState(initialDate || '');
  const [time, setTime] = useState('');
  const [endDate, setEndDate] = useState('');
  const [location, setLocation] = useState('');
  const [person, setPerson] = useState('');
  const [reminderDays, setReminderDays] = useState('2');
  const [notes, setNotes] = useState('');
  const [saving, setSaving] = useState(false);
  const [conflicts, setConflicts] = useState<Termin[]>([]);

  useEffect(() => {
    if (initialDate) setDate(initialDate);
  }, [initialDate]);

  // Check conflicts when date changes
  useEffect(() => {
    if (!date) { setConflicts([]); return; }
    fetch(`/api/termine?mode=conflicts&date=${date}`)
      .then(r => r.json())
      .then(data => setConflicts(Array.isArray(data) ? data : []))
      .catch(() => setConflicts([]));
  }, [date]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!title.trim() || !date) return;
    setSaving(true);
    try {
      await fetch('/api/termine', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          title: title.trim(),
          description: description.trim() || null,
          category,
          date,
          time: time || null,
          end_date: endDate || null,
          location: location.trim() || null,
          person: person || null,
          reminder_days: parseInt(reminderDays) || 2,
          notes: notes.trim() || null,
        }),
      });
      setTitle(''); setDescription(''); setDate(initialDate || ''); setTime(''); setEndDate(''); setLocation(''); setPerson(''); setNotes('');
      setOpen(false);
      onAdded();
    } finally { setSaving(false); }
  };

  if (!open) {
    return (
      <button onClick={() => setOpen(true)} className="w-full py-3.5 border-2 border-dashed border-blue-300/60 rounded-2xl text-sm font-semibold text-blue-400 hover:border-blue-400 hover:text-blue-500 transition-all active:scale-[0.98]">
        ＋ Neuen Termin anlegen
      </button>
    );
  }

  return (
    <form onSubmit={handleSubmit} className="bg-white/80 backdrop-blur-sm rounded-2xl border border-blue-200/60 p-4 shadow-sm space-y-2.5">
      <h4 className="text-sm font-bold text-[#1C1C1E] mb-1">📅 Neuer Termin</h4>

      <input type="text" value={title} onChange={e => setTitle(e.target.value)} placeholder="Was steht an? *" required autoFocus className="w-full bg-[#F2F2F7] rounded-xl px-4 py-2.5 text-sm text-[#1C1C1E] placeholder:text-[#C7C7CC] outline-none focus:ring-2 focus:ring-blue-400" />

      <textarea value={description} onChange={e => setDescription(e.target.value)} placeholder="Beschreibung / Details" rows={2} className="w-full bg-[#F2F2F7] rounded-xl px-4 py-2.5 text-sm text-[#1C1C1E] placeholder:text-[#C7C7CC] outline-none focus:ring-2 focus:ring-blue-400 resize-none" />

      <select value={category} onChange={e => setCategory(e.target.value)} className="w-full bg-[#F2F2F7] rounded-xl px-4 py-2.5 text-sm text-[#1C1C1E] outline-none focus:ring-2 focus:ring-blue-400">
        {categories.map(c => <option key={c.id} value={c.id}>{c.emoji} {c.label}</option>)}
      </select>

      <div className="flex gap-2">
        <div className="flex-1">
          <label className="text-[10px] text-[#8E8E93] font-medium px-1">Datum *</label>
          <input type="date" value={date} onChange={e => setDate(e.target.value)} required className="w-full bg-[#F2F2F7] rounded-xl px-4 py-2.5 text-sm text-[#1C1C1E] outline-none focus:ring-2 focus:ring-blue-400" />
        </div>
        <div className="flex-1">
          <label className="text-[10px] text-[#8E8E93] font-medium px-1">Uhrzeit</label>
          <input type="time" value={time} onChange={e => setTime(e.target.value)} className="w-full bg-[#F2F2F7] rounded-xl px-4 py-2.5 text-sm text-[#1C1C1E] outline-none focus:ring-2 focus:ring-blue-400" />
        </div>
      </div>

      <div className="flex gap-2">
        <div className="flex-1">
          <label className="text-[10px] text-[#8E8E93] font-medium px-1">Ende (mehrtägig)</label>
          <input type="date" value={endDate} onChange={e => setEndDate(e.target.value)} className="w-full bg-[#F2F2F7] rounded-xl px-4 py-2.5 text-sm text-[#1C1C1E] outline-none focus:ring-2 focus:ring-blue-400" />
        </div>
        <div className="flex-1">
          <label className="text-[10px] text-[#8E8E93] font-medium px-1">Erinnerung</label>
          <select value={reminderDays} onChange={e => setReminderDays(e.target.value)} className="w-full bg-[#F2F2F7] rounded-xl px-4 py-2.5 text-sm text-[#1C1C1E] outline-none focus:ring-2 focus:ring-blue-400">
            <option value="0">Keine</option>
            <option value="1">1 Tag vorher</option>
            <option value="2">2 Tage vorher</option>
            <option value="3">3 Tage vorher</option>
            <option value="7">1 Woche vorher</option>
            <option value="14">2 Wochen vorher</option>
          </select>
        </div>
      </div>

      {/* Conflict warning */}
      {conflicts.length > 0 && (
        <div className="bg-amber-50 border border-amber-200 rounded-xl p-3">
          <p className="text-[11px] font-bold text-amber-700 mb-1">⚠️ An diesem Tag gibt es bereits {conflicts.length} Termin{conflicts.length > 1 ? 'e' : ''}:</p>
          {conflicts.map(c => {
            const cat = categories.find(x => x.id === c.category);
            return (
              <div key={c.id} className="text-[11px] text-amber-800 flex items-center gap-1.5 ml-2">
                <span>{cat?.emoji || '📅'}</span>
                <span className="font-medium">{c.title}</span>
                {c.time && <span className="text-amber-600">({c.time.slice(0, 5)})</span>}
              </div>
            );
          })}
        </div>
      )}

      <div className="flex gap-2">
        <input type="text" value={location} onChange={e => setLocation(e.target.value)} placeholder="📍 Ort" className="flex-1 bg-[#F2F2F7] rounded-xl px-4 py-2.5 text-sm text-[#1C1C1E] placeholder:text-[#C7C7CC] outline-none focus:ring-2 focus:ring-blue-400" />
        <select value={person} onChange={e => setPerson(e.target.value)} className="flex-1 bg-[#F2F2F7] rounded-xl px-4 py-2.5 text-sm text-[#1C1C1E] outline-none focus:ring-2 focus:ring-blue-400">
          <option value="">Für…</option>
          <option value="Samu">👶 Samu</option>
          <option value="Lars">👨 Lars</option>
          <option value="Elita">👩 Elita</option>
          <option value="Gypsi">🐱 Gypsi</option>
          <option value="Familie">👨‍👩‍👦 Familie</option>
        </select>
      </div>

      <input type="text" value={notes} onChange={e => setNotes(e.target.value)} placeholder="📝 Notizen" className="w-full bg-[#F2F2F7] rounded-xl px-4 py-2.5 text-sm text-[#1C1C1E] placeholder:text-[#C7C7CC] outline-none focus:ring-2 focus:ring-blue-400" />

      <div className="flex gap-2 pt-1">
        <button type="submit" disabled={saving || !title.trim() || !date} className="flex-1 py-2.5 bg-gradient-to-r from-blue-500 to-indigo-500 text-white text-sm font-semibold rounded-xl shadow-sm transition-all active:scale-95 disabled:opacity-50">
          {saving ? '⏳' : '✅ Termin anlegen'}
        </button>
        <button type="button" onClick={() => setOpen(false)} className="px-4 py-2.5 bg-gray-100 text-gray-500 text-sm font-semibold rounded-xl transition active:scale-95">✕</button>
      </div>
    </form>
  );
}

/* ── Main Page ── */
export default function TerminePage() {
  const [termine, setTermine] = useState<Termin[]>([]);
  const [categories, setCategories] = useState<Category[]>([]);
  const [selectedCat, setSelectedCat] = useState<string | null>(null);
  const [view, setView] = useState<'list' | 'calendar'>('list');
  const [calYear, setCalYear] = useState(new Date().getFullYear());
  const [calMonth, setCalMonth] = useState(new Date().getMonth() + 1);
  const [selectedDate, setSelectedDate] = useState<string | null>(null);
  const [showPast, setShowPast] = useState(false);
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [searchResults, setSearchResults] = useState<Termin[] | null>(null);
  const [searching, setSearching] = useState(false);

  const today = new Date().toISOString().split('T')[0];

  const handleSearch = async (q: string) => {
    setSearchQuery(q);
    if (!q.trim()) { setSearchResults(null); return; }
    if (q.trim().length < 2) return;
    setSearching(true);
    try {
      const res = await fetch(`/api/termine?mode=search&q=${encodeURIComponent(q.trim())}`);
      const data = await res.json();
      setSearchResults(data);
    } catch { setSearchResults([]); }
    finally { setSearching(false); }
  };

  const loadData = useCallback(async () => {
    setLoading(true);
    try {
      const [catRes, tRes] = await Promise.all([
        fetch('/api/termine?mode=categories'),
        view === 'calendar'
          ? fetch(`/api/termine?mode=month&year=${calYear}&month=${calMonth}`)
          : fetch(`/api/termine${selectedCat ? `?category=${selectedCat}` : ''}`),
      ]);
      const [catData, tData] = await Promise.all([catRes.json(), tRes.json()]);
      setCategories(catData);
      setTermine(tData);
    } catch (err) { console.error(err); }
    finally { setLoading(false); }
  }, [view, calYear, calMonth, selectedCat]);

  useEffect(() => { loadData(); }, [loadData]);

  const handleUpdate = async (id: number, data: Partial<Termin>) => {
    await fetch(`/api/termine/${id}`, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data) });
    loadData();
  };

  const handleDelete = async (id: number) => {
    await fetch(`/api/termine/${id}`, { method: 'DELETE' });
    loadData();
  };

  const prevMonth = () => {
    if (calMonth === 1) { setCalMonth(12); setCalYear(y => y - 1); }
    else setCalMonth(m => m - 1);
  };
  const nextMonth = () => {
    if (calMonth === 12) { setCalMonth(1); setCalYear(y => y + 1); }
    else setCalMonth(m => m + 1);
  };

  // Filter logic for list view
  const filteredTermine = termine.filter(t => {
    if (!showPast && t.date < today && t.status !== 'erledigt') return daysUntil(t.date) >= -7; // show last 7 days
    return showPast || t.date >= today || t.status === 'erledigt';
  }).sort((a, b) => a.date.localeCompare(b.date) || (a.time || '').localeCompare(b.time || ''));

  // Group by relative sections
  const upcoming = filteredTermine.filter(t => t.date >= today && t.status === 'offen');
  const past = filteredTermine.filter(t => t.date < today || t.status === 'erledigt');

  // Day termine for calendar
  const dayTermine = selectedDate ? termine.filter(t => {
    if (t.date === selectedDate) return true;
    if (t.end_date && t.date <= selectedDate && t.end_date >= selectedDate) return true;
    return false;
  }) : [];

  // Stats
  const totalOpen = termine.filter(t => t.status === 'offen' && t.date >= today).length;
  const thisWeek = termine.filter(t => t.status === 'offen' && daysUntil(t.date) >= 0 && daysUntil(t.date) <= 7).length;

  return (
    <main className="min-h-screen bg-gradient-to-br from-[#F0F5FF] via-[#F5F0FF] to-[#F0FAFF]">
      <style jsx global>{`
        .scrollbar-hide::-webkit-scrollbar { display: none; }
        .scrollbar-hide { -ms-overflow-style: none; scrollbar-width: none; }
      `}</style>

      {/* ── Header ── */}
      <header className="pt-12 pb-4 px-5 safe-area-inset">
        <div className="max-w-2xl mx-auto">
          <div className="flex items-center gap-3 mb-4">
            <Link href="/" className="flex items-center justify-center w-10 h-10 bg-white/70 backdrop-blur-sm rounded-2xl border border-blue-200/50 shadow-sm hover:bg-white transition active:scale-95">
              <svg className="w-5 h-5 text-blue-600" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2.5}>
                <path strokeLinecap="round" strokeLinejoin="round" d="M15 19l-7-7 7-7" />
              </svg>
            </Link>
            <div>
              <h1 className="text-3xl font-extrabold text-[#1C1C1E] tracking-tight leading-tight">📅 Termine</h1>
              <p className="text-blue-600/80 text-sm font-medium mt-0.5">Familie Paetzold-Stilke</p>
            </div>
          </div>

          {/* Stats + View Toggle */}
          <div className="flex items-center justify-between">
            <div className="flex gap-2">
              <div className="flex items-center gap-1.5 bg-blue-100 text-blue-700 px-3 py-1.5 rounded-full text-sm font-semibold">📋 {totalOpen} offen</div>
              {thisWeek > 0 && <div className="flex items-center gap-1.5 bg-orange-100 text-orange-700 px-3 py-1.5 rounded-full text-sm font-semibold">⚡ {thisWeek} diese Woche</div>}
            </div>
            <div className="flex bg-white/70 rounded-xl border border-blue-200/40 overflow-hidden">
              <button onClick={() => setView('list')} className={`px-3 py-1.5 text-xs font-semibold transition ${view === 'list' ? 'bg-blue-500 text-white' : 'text-[#8E8E93]'}`}>📋</button>
              <button onClick={() => setView('calendar')} className={`px-3 py-1.5 text-xs font-semibold transition ${view === 'calendar' ? 'bg-blue-500 text-white' : 'text-[#8E8E93]'}`}>📆</button>
            </div>
          </div>
        </div>
      </header>

      {/* ── Search ── */}
      <div className="max-w-2xl mx-auto px-5 mb-3">
        <div className="relative">
          <input
            type="text"
            value={searchQuery}
            onChange={e => handleSearch(e.target.value)}
            placeholder="🔍 Termine suchen…"
            className="w-full bg-white/70 backdrop-blur-sm border border-blue-200/40 rounded-2xl px-4 py-2.5 pl-10 text-sm text-[#1C1C1E] placeholder:text-[#C7C7CC] outline-none focus:ring-2 focus:ring-blue-400 focus:border-transparent"
          />
          <svg className="w-4 h-4 absolute left-3.5 top-1/2 -translate-y-1/2 text-[#C7C7CC]" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
            <path strokeLinecap="round" strokeLinejoin="round" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
          </svg>
          {searchQuery && (
            <button onClick={() => { setSearchQuery(''); setSearchResults(null); }} className="absolute right-3 top-1/2 -translate-y-1/2 text-[#C7C7CC] hover:text-[#8E8E93] text-lg">✕</button>
          )}
        </div>

        {/* Search results */}
        {searchResults !== null && (
          <div className="mt-2 bg-white/80 backdrop-blur-sm rounded-2xl border border-blue-200/40 p-3 shadow-sm">
            {searching ? (
              <p className="text-[11px] text-[#8E8E93] animate-pulse">Suche…</p>
            ) : searchResults.length === 0 ? (
              <p className="text-[11px] text-[#8E8E93]">Keine Treffer für „{searchQuery}"</p>
            ) : (
              <div className="space-y-2">
                <p className="text-[10px] font-bold text-[#8E8E93] uppercase tracking-wider">{searchResults.length} Treffer</p>
                {searchResults.slice(0, 10).map(t => {
                  const cat = categories.find(c => c.id === t.category);
                  const style = getCatStyle(t.category, categories);
                  return (
                    <div key={t.id} className="flex items-center gap-2 py-1.5 border-b border-gray-100 last:border-0">
                      <span className="text-sm">{cat?.emoji || '📅'}</span>
                      <div className="flex-1 min-w-0">
                        <p className={`text-xs font-semibold text-[#1C1C1E] truncate ${t.status === 'erledigt' ? 'line-through opacity-60' : ''}`}>{t.title}</p>
                        <p className="text-[10px] text-[#8E8E93]">{formatDate(t.date)} {t.time ? `· ${t.time.slice(0, 5)}` : ''} {t.person ? `· ${t.person}` : ''}</p>
                      </div>
                      <span className={`text-[9px] font-medium ${style.text} ${style.bg} px-1.5 py-0.5 rounded-full`}>{cat?.label}</span>
                      {daysBadge(t.date)}
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        )}
      </div>

      {/* ── Category Filter ── */}
      <div className="max-w-2xl mx-auto px-5 mb-4">
        <div className="flex gap-2 overflow-x-auto pb-2 scrollbar-hide">
          <button onClick={() => setSelectedCat(null)} className={`flex-shrink-0 px-3 py-2 rounded-xl text-xs font-semibold transition border ${!selectedCat ? 'bg-blue-500 text-white border-blue-500' : 'bg-white/60 text-[#8E8E93] border-blue-200/40'}`}>
            Alle
          </button>
          {categories.map(c => (
            <button key={c.id} onClick={() => setSelectedCat(selectedCat === c.id ? null : c.id)} className={`flex-shrink-0 px-3 py-2 rounded-xl text-xs font-semibold transition border ${selectedCat === c.id ? 'bg-blue-500 text-white border-blue-500' : 'bg-white/60 text-[#636366] border-blue-200/40'}`}>
              {c.emoji} {c.label}
            </button>
          ))}
        </div>
      </div>

      <div className="max-w-2xl mx-auto px-5 pb-16 space-y-4">
        {/* ── Calendar View ── */}
        {view === 'calendar' && (
          <>
            <div className="flex items-center justify-between mb-2">
              <button onClick={prevMonth} className="w-10 h-10 flex items-center justify-center rounded-xl bg-white/70 border border-blue-200/40 text-blue-600 font-bold transition active:scale-95">‹</button>
              <h2 className="text-lg font-bold text-[#1C1C1E]">{MONTHS[calMonth - 1]} {calYear}</h2>
              <button onClick={nextMonth} className="w-10 h-10 flex items-center justify-center rounded-xl bg-white/70 border border-blue-200/40 text-blue-600 font-bold transition active:scale-95">›</button>
            </div>
            <CalendarGrid year={calYear} month={calMonth} termine={termine} onDayClick={d => setSelectedDate(selectedDate === d ? null : d)} />

            {selectedDate && (
              <div className="space-y-3">
                <h3 className="text-sm font-bold text-[#1C1C1E]">📅 {formatDate(selectedDate)}</h3>
                {dayTermine.length === 0 ? (
                  <p className="text-sm text-[#8E8E93]">Keine Termine an diesem Tag</p>
                ) : dayTermine.map(t => (
                  <TerminCard key={t.id} termin={t} categories={categories} onUpdate={handleUpdate} onDelete={handleDelete} />
                ))}
                <AddTerminForm categories={categories} initialDate={selectedDate} onAdded={loadData} />
              </div>
            )}
          </>
        )}

        {/* ── List View ── */}
        {view === 'list' && (
          <>
            {loading ? (
              <div className="flex flex-col items-center justify-center py-16">
                <div className="text-4xl animate-bounce mb-3">📅</div>
                <p className="text-[#8E8E93] font-medium">Lade Termine…</p>
              </div>
            ) : upcoming.length === 0 && past.length === 0 ? (
              <div className="flex flex-col items-center justify-center py-12 text-center">
                <div className="text-5xl mb-3">🗓️</div>
                <h3 className="text-lg font-bold text-[#1C1C1E] mb-1">Noch keine Termine</h3>
                <p className="text-[#8E8E93] text-sm">Lege den ersten Termin an!</p>
              </div>
            ) : (
              <>
                {upcoming.length > 0 && (
                  <div>
                    <h3 className="text-xs font-bold text-[#8E8E93] uppercase tracking-wider mb-2 px-1">Anstehend</h3>
                    <div className="space-y-2.5">
                      {upcoming.map(t => <TerminCard key={t.id} termin={t} categories={categories} onUpdate={handleUpdate} onDelete={handleDelete} />)}
                    </div>
                  </div>
                )}
                {past.length > 0 && (
                  <div>
                    <button onClick={() => setShowPast(!showPast)} className="text-xs font-bold text-[#8E8E93] uppercase tracking-wider mb-2 px-1 flex items-center gap-1 hover:text-[#636366] transition">
                      {showPast ? '▼' : '▶'} Vergangen / Erledigt ({past.length})
                    </button>
                    {showPast && (
                      <div className="space-y-2.5">
                        {past.map(t => <TerminCard key={t.id} termin={t} categories={categories} onUpdate={handleUpdate} onDelete={handleDelete} />)}
                      </div>
                    )}
                  </div>
                )}
              </>
            )}

            <AddTerminForm categories={categories} onAdded={loadData} />
          </>
        )}
      </div>
    </main>
  );
}
