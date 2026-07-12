'use client';

import { useState, useEffect, useCallback } from 'react';
import Link from 'next/link';

interface WunschEvent {
  id: number;
  name: string;
  emoji: string;
  date: string | null;
  type: string;
  notes: string | null;
  archived: number;
  erinnerungen_aktiv: number;
  item_count: number;
  open_count: number;
}

interface PriceResult {
  shop: string;
  price: string;
  url: string;
}

interface WunschItem {
  id: number;
  event_id: number;
  title: string;
  description: string | null;
  price: string | null;
  url: string | null;
  image_url: string | null;
  category: string | null;
  priority: number;
  status: string;
  purchased_by: string | null;
  notes: string | null;
  ean: string | null;
  price_comparison: string | null;
  event_name?: string;
  event_emoji?: string;
}

function formatDate(d: string) {
  return new Date(d).toLocaleDateString('de-DE', { day: '2-digit', month: '2-digit', year: 'numeric' });
}

function daysUntil(dateStr: string): number {
  const now = new Date(); now.setHours(0,0,0,0);
  const target = new Date(dateStr); target.setHours(0,0,0,0);
  return Math.ceil((target.getTime() - now.getTime()) / 86400000);
}

function countdownBadge(dateStr: string | null) {
  if (!dateStr) return null;
  const days = daysUntil(dateStr);
  if (days < 0) return <span className="text-[10px] bg-gray-200 text-gray-500 px-2 py-0.5 rounded-full">vorbei</span>;
  if (days === 0) return <span className="text-[10px] bg-red-100 text-red-600 px-2 py-0.5 rounded-full font-bold animate-pulse">🎉 Heute!</span>;
  if (days <= 7) return <span className="text-[10px] bg-orange-100 text-orange-600 px-2 py-0.5 rounded-full font-bold">⏰ {days} Tage</span>;
  if (days <= 30) return <span className="text-[10px] bg-amber-100 text-amber-600 px-2 py-0.5 rounded-full">{days} Tage</span>;
  return <span className="text-[10px] bg-gray-100 text-gray-500 px-2 py-0.5 rounded-full">{days} Tage</span>;
}

function whatsAppShareUrl(item: WunschItem, eventName?: string) {
  let text = `🎁 Geschenkidee für Samu`;
  if (eventName) text += ` (${eventName})`;
  text += `:\n\n*${item.title}*`;
  if (item.description) text += `\n${item.description}`;
  if (item.price) text += `\n💰 ${item.price}`;
  if (item.url) text += `\n🔗 ${item.url}`;
  return `https://wa.me/?text=${encodeURIComponent(text)}`;
}

/* ── Share Modal ── */
function ShareModal({ item, eventName, onClose }: { item: WunschItem; eventName?: string; onClose: () => void }) {
  const contacts = [
    { name: 'Oma Erika', emoji: '👵' },
    { name: 'Maggie', emoji: '👩' },
    { name: 'Andre', emoji: '👨' },
    { name: 'Kai', emoji: '👨' },
    { name: 'Jens', emoji: '👨' },
  ];

  let text = `🎁 Geschenkidee für Samu`;
  if (eventName) text += ` (${eventName})`;
  text += `:\n\n*${item.title}*`;
  if (item.description) text += `\n${item.description}`;
  if (item.price) text += `\n💰 ${item.price}`;
  if (item.url) text += `\n🔗 ${item.url}`;

  const shareVia = (contact?: string) => {
    const url = `https://wa.me/?text=${encodeURIComponent(text)}`;
    window.open(url, '_blank');
    onClose();
  };

  const copyToClipboard = () => {
    navigator.clipboard.writeText(text.replace(/\*/g, ''));
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/40 backdrop-blur-sm" onClick={onClose}>
      <div className="w-full max-w-lg bg-white rounded-t-3xl shadow-2xl p-6 pb-10 animate-slide-up" onClick={e => e.stopPropagation()}>
        <div className="w-10 h-1 bg-gray-300 rounded-full mx-auto mb-5" />
        <h3 className="text-lg font-bold text-[#1C1C1E] mb-1">📲 Teilen</h3>
        <p className="text-sm text-[#8E8E93] mb-4 line-clamp-1">{item.title}</p>

        {/* Preview */}
        <div className="bg-[#F2F2F7] rounded-2xl p-3 mb-4 text-xs text-[#636366] whitespace-pre-line line-clamp-4">
          {text.replace(/\*/g, '')}
        </div>

        {/* Quick contacts */}
        <div className="flex gap-3 overflow-x-auto pb-3 mb-3">
          {contacts.map(c => (
            <button key={c.name} onClick={() => shareVia(c.name)}
              className="flex flex-col items-center gap-1 min-w-[60px] transition active:scale-95">
              <div className="w-12 h-12 rounded-full bg-gradient-to-br from-green-400 to-green-600 flex items-center justify-center text-xl shadow-sm">
                {c.emoji}
              </div>
              <span className="text-[10px] text-[#636366] font-medium">{c.name}</span>
            </button>
          ))}
        </div>

        <div className="space-y-2">
          <button onClick={() => shareVia()} className="w-full py-3 bg-gradient-to-r from-green-500 to-green-600 text-white text-sm font-bold rounded-2xl shadow-sm transition active:scale-[0.98] flex items-center justify-center gap-2">
            <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 24 24"><path d="M17.472 14.382c-.297-.149-1.758-.867-2.03-.967-.273-.099-.471-.148-.67.15-.197.297-.767.966-.94 1.164-.173.199-.347.223-.644.075-.297-.15-1.255-.463-2.39-1.475-.883-.788-1.48-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.298-.347.446-.52.149-.174.198-.298.298-.497.099-.198.05-.371-.025-.52-.075-.149-.669-1.612-.916-2.207-.242-.579-.487-.5-.669-.51-.173-.008-.371-.01-.57-.01-.198 0-.52.074-.792.372-.272.297-1.04 1.016-1.04 2.479 0 1.462 1.065 2.875 1.213 3.074.149.198 2.096 3.2 5.077 4.487.709.306 1.262.489 1.694.625.712.227 1.36.195 1.871.118.571-.085 1.758-.719 2.006-1.413.248-.694.248-1.289.173-1.413-.074-.124-.272-.198-.57-.347m-5.421 7.403h-.004a9.87 9.87 0 01-5.031-1.378l-.361-.214-3.741.982.998-3.648-.235-.374a9.86 9.86 0 01-1.51-5.26c.001-5.45 4.436-9.884 9.888-9.884 2.64 0 5.122 1.03 6.988 2.898a9.825 9.825 0 012.893 6.994c-.003 5.45-4.437 9.884-9.885 9.884m8.413-18.297A11.815 11.815 0 0012.05 0C5.495 0 .16 5.335.157 11.892c0 2.096.547 4.142 1.588 5.945L.057 24l6.305-1.654a11.882 11.882 0 005.683 1.448h.005c6.554 0 11.89-5.335 11.893-11.893a11.821 11.821 0 00-3.48-8.413z"/></svg>
            Per WhatsApp teilen
          </button>
          <button onClick={copyToClipboard} className="w-full py-3 bg-[#F2F2F7] text-[#1C1C1E] text-sm font-semibold rounded-2xl transition active:scale-[0.98]">
            📋 Text kopieren
          </button>
          <button onClick={onClose} className="w-full py-3 text-[#8E8E93] text-sm font-medium transition">
            Abbrechen
          </button>
        </div>
      </div>
    </div>
  );
}

/* ── Item Card ── */
function ItemCard({ item, eventName, onUpdate, onDelete }: { item: WunschItem; eventName?: string; onUpdate: (id: number, data: Partial<WunschItem>) => void; onDelete: (id: number) => void; }) {
  const [expanded, setExpanded] = useState(false);
  const [showShare, setShowShare] = useState(false);
  const [editing, setEditing] = useState(false);
  const [editData, setEditData] = useState({ title: item.title, description: item.description || '', price: item.price || '', url: item.url || '', notes: item.notes || '', category: item.category || '', ean: item.ean || '' });
  const [showPrices, setShowPrices] = useState(false);
  const [priceLoading, setPriceLoading] = useState(false);
  const [priceResults, setPriceResults] = useState<PriceResult[]>(item.price_comparison ? (() => { try { return JSON.parse(item.price_comparison); } catch { return []; } })() : []);
  const [idealoUrl, setIdealoUrl] = useState<string | null>(null);
  const [googleUrl, setGoogleUrl] = useState<string | null>(null);

  const runPriceCheck = async () => {
    setPriceLoading(true);
    setShowPrices(true);
    try {
      const res = await fetch('/api/wunschliste/pricecheck', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ title: item.title, ean: item.ean, isbn: item.ean }),
      });
      const data = await res.json();
      setPriceResults(data.results || []);
      setIdealoUrl(data.idealo_url || null);
      setGoogleUrl(data.google_url || null);
      // Save to DB
      if (data.results?.length > 0) {
        onUpdate(item.id, { price_comparison: JSON.stringify(data.results) } as any);
      }
    } catch (err) { console.error(err); }
    finally { setPriceLoading(false); }
  };

  const statusCycle = () => {
    const next = item.status === 'offen' ? 'gekauft' : item.status === 'gekauft' ? 'geschenkt' : 'offen';
    onUpdate(item.id, { status: next });
  };

  const handleSaveEdit = () => {
    onUpdate(item.id, {
      title: editData.title,
      description: editData.description || null,
      price: editData.price || null,
      url: editData.url || null,
      notes: editData.notes || null,
      category: editData.category || null,
      ean: editData.ean || null,
    } as any);
    setEditing(false);
  };

  const statusStyle = item.status === 'offen'
    ? 'bg-amber-100 text-amber-700 border-amber-200'
    : item.status === 'gekauft'
    ? 'bg-blue-100 text-blue-700 border-blue-200'
    : 'bg-green-100 text-green-700 border-green-200';

  const statusLabel = item.status === 'offen' ? '⬜ Offen' : item.status === 'gekauft' ? '🛒 Gekauft' : '✅ Geschenkt';

  if (editing) {
    return (
      <div className="bg-white/80 backdrop-blur-sm rounded-2xl border border-purple-300/60 p-4 shadow-sm space-y-2">
        <input type="text" value={editData.title} onChange={e => setEditData(d => ({...d, title: e.target.value}))} placeholder="Titel *" className="w-full bg-[#F2F2F7] rounded-xl px-3 py-2 text-sm text-[#1C1C1E] outline-none focus:ring-2 focus:ring-purple-400" />
        <textarea value={editData.description} onChange={e => setEditData(d => ({...d, description: e.target.value}))} placeholder="Beschreibung" rows={2} className="w-full bg-[#F2F2F7] rounded-xl px-3 py-2 text-sm text-[#1C1C1E] outline-none focus:ring-2 focus:ring-purple-400 resize-none" />
        <div className="flex gap-2">
          <input type="text" value={editData.price} onChange={e => setEditData(d => ({...d, price: e.target.value}))} placeholder="Preis" className="flex-1 bg-[#F2F2F7] rounded-xl px-3 py-2 text-sm text-[#1C1C1E] outline-none focus:ring-2 focus:ring-purple-400" />
          <input type="text" value={editData.category} onChange={e => setEditData(d => ({...d, category: e.target.value}))} placeholder="Kategorie" className="flex-1 bg-[#F2F2F7] rounded-xl px-3 py-2 text-sm text-[#1C1C1E] outline-none focus:ring-2 focus:ring-purple-400" />
        </div>
        <input type="url" value={editData.url} onChange={e => setEditData(d => ({...d, url: e.target.value}))} placeholder="Link" className="w-full bg-[#F2F2F7] rounded-xl px-3 py-2 text-sm text-[#1C1C1E] outline-none focus:ring-2 focus:ring-purple-400" />
        <input type="text" value={editData.ean} onChange={e => setEditData(d => ({...d, ean: e.target.value}))} placeholder="EAN / ISBN (z.B. 4005556318574)" className="w-full bg-[#F2F2F7] rounded-xl px-3 py-2 text-sm text-[#1C1C1E] outline-none focus:ring-2 focus:ring-purple-400 font-mono" />
        <input type="text" value={editData.notes} onChange={e => setEditData(d => ({...d, notes: e.target.value}))} placeholder="Notizen" className="w-full bg-[#F2F2F7] rounded-xl px-3 py-2 text-sm text-[#1C1C1E] outline-none focus:ring-2 focus:ring-purple-400" />
        <div className="flex gap-2">
          <button onClick={handleSaveEdit} className="flex-1 py-2 bg-purple-500 text-white text-sm font-semibold rounded-xl transition active:scale-95">💾 Speichern</button>
          <button onClick={() => setEditing(false)} className="px-4 py-2 bg-gray-100 text-gray-500 text-sm rounded-xl transition active:scale-95">✕</button>
        </div>
      </div>
    );
  }

  return (
    <>
      <div className={`overflow-hidden bg-white/70 backdrop-blur-sm rounded-2xl border shadow-sm transition-all duration-300 ${item.status === 'geschenkt' ? 'border-green-200/60 opacity-70' : 'border-purple-200/60'}`}>
        <div className="flex items-start gap-3 p-4">
          {/* Image */}
          <div className="flex-shrink-0 w-[64px] h-[64px] rounded-xl overflow-hidden bg-gradient-to-br from-purple-100 to-pink-100 flex items-center justify-center border border-purple-200/40">
            {item.image_url ? (
              <img src={item.image_url} alt={item.title} className="w-full h-full object-cover" onError={e => { (e.target as HTMLImageElement).style.display = 'none'; (e.target as HTMLImageElement).parentElement!.innerHTML = '<span class="text-2xl">🎁</span>'; }} />
            ) : item.category === '📚' ? (
              <span className="text-2xl">📚</span>
            ) : (
              <span className="text-2xl">🎁</span>
            )}
          </div>

          <div className="flex-1 min-w-0">
            <div className="flex items-start justify-between gap-2">
              <h3 className={`text-sm font-bold text-[#1C1C1E] leading-tight ${expanded ? '' : 'line-clamp-2'} ${item.status === 'geschenkt' ? 'line-through opacity-60' : ''}`}>
                {item.title}
              </h3>
              <button onClick={statusCycle} className={`flex-shrink-0 text-[10px] font-bold px-2 py-0.5 rounded-full border transition-all active:scale-95 ${statusStyle}`}>
                {statusLabel}
              </button>
            </div>

            {item.description && (
              <p className={`text-[11px] text-[#636366] mt-1 ${expanded ? '' : 'line-clamp-2'}`}>{item.description}</p>
            )}

            <div className="flex flex-wrap gap-1.5 mt-2">
              {item.price && <span className="text-[11px] font-bold bg-green-50 text-green-700 px-2 py-0.5 rounded-full">💰 {item.price}</span>}
              {item.category && item.category !== '📚' && <span className="text-[11px] bg-purple-50 text-purple-600 px-2 py-0.5 rounded-full">{item.category}</span>}
              {item.url && (
                <a href={item.url} target="_blank" rel="noopener noreferrer" className="text-[11px] font-medium text-indigo-500 bg-indigo-50 px-2 py-0.5 rounded-full hover:bg-indigo-100 transition">
                  🔗 Link
                </a>
              )}
              {item.purchased_by && <span className="text-[11px] bg-blue-50 text-blue-600 px-2 py-0.5 rounded-full">👤 {item.purchased_by}</span>}
            </div>

            {item.ean && (
              <div className="mt-1.5">
                <span className="text-[10px] font-mono bg-gray-100 text-gray-500 px-2 py-0.5 rounded-full">EAN: {item.ean}</span>
              </div>
            )}

            {item.notes && (
              <p className="text-[10px] text-[#8E8E93] mt-1.5 italic">{item.notes}</p>
            )}

            {/* Price comparison */}
            {showPrices && (
              <div className="mt-2 bg-gradient-to-r from-emerald-50 to-teal-50 rounded-xl p-3 border border-emerald-200/50">
                <div className="flex items-center justify-between mb-2">
                  <h4 className="text-[11px] font-bold text-emerald-800">💰 Preisvergleich</h4>
                  <button onClick={() => setShowPrices(false)} className="text-[10px] text-gray-400">✕</button>
                </div>
                {priceLoading ? (
                  <div className="flex items-center gap-2 py-2">
                    <div className="w-4 h-4 border-2 border-emerald-400 border-t-transparent rounded-full animate-spin" />
                    <span className="text-[11px] text-emerald-600">Suche besten Preis…</span>
                  </div>
                ) : priceResults.length > 0 ? (
                  <div className="space-y-1.5">
                    {priceResults.slice(0, 5).map((pr, i) => (
                      <a key={i} href={pr.url} target="_blank" rel="noopener noreferrer"
                        className={`flex items-center justify-between px-2 py-1.5 rounded-lg text-[11px] transition hover:bg-emerald-100 ${i === 0 ? 'bg-emerald-100 font-bold' : ''}`}>
                        <span className="text-[#1C1C1E]">{i === 0 ? '🏆 ' : ''}{pr.shop}</span>
                        <span className={`font-bold ${i === 0 ? 'text-emerald-700' : 'text-[#636366]'}`}>{pr.price}</span>
                      </a>
                    ))}
                  </div>
                ) : (
                  <p className="text-[11px] text-[#8E8E93] py-1">Keine Ergebnisse gefunden</p>
                )}
                <div className="flex gap-2 mt-2">
                  {idealoUrl && (
                    <a href={idealoUrl} target="_blank" rel="noopener noreferrer" className="text-[10px] font-medium text-indigo-500 bg-indigo-50 px-2 py-1 rounded-lg hover:bg-indigo-100 transition">🔍 idealo</a>
                  )}
                  {googleUrl && (
                    <a href={googleUrl} target="_blank" rel="noopener noreferrer" className="text-[10px] font-medium text-blue-500 bg-blue-50 px-2 py-1 rounded-lg hover:bg-blue-100 transition">🛒 Google Shopping</a>
                  )}
                </div>
              </div>
            )}

            {/* Action bar */}
            <div className="flex justify-between items-center mt-2.5 pt-1.5 border-t border-gray-100">
              <div className="flex gap-1.5">
                <button onClick={() => setShowShare(true)} className="text-[11px] py-1 px-2.5 rounded-lg bg-green-50 text-green-600 font-semibold hover:bg-green-100 transition active:scale-95 flex items-center gap-1">
                  <svg className="w-3.5 h-3.5" fill="currentColor" viewBox="0 0 24 24"><path d="M17.472 14.382c-.297-.149-1.758-.867-2.03-.967-.273-.099-.471-.148-.67.15-.197.297-.767.966-.94 1.164-.173.199-.347.223-.644.075-.297-.15-1.255-.463-2.39-1.475-.883-.788-1.48-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.298-.347.446-.52.149-.174.198-.298.298-.497.099-.198.05-.371-.025-.52-.075-.149-.669-1.612-.916-2.207-.242-.579-.487-.5-.669-.51-.173-.008-.371-.01-.57-.01-.198 0-.52.074-.792.372-.272.297-1.04 1.016-1.04 2.479 0 1.462 1.065 2.875 1.213 3.074.149.198 2.096 3.2 5.077 4.487.709.306 1.262.489 1.694.625.712.227 1.36.195 1.871.118.571-.085 1.758-.719 2.006-1.413.248-.694.248-1.289.173-1.413-.074-.124-.272-.198-.57-.347m-5.421 7.403h-.004a9.87 9.87 0 01-5.031-1.378l-.361-.214-3.741.982.998-3.648-.235-.374a9.86 9.86 0 01-1.51-5.26c.001-5.45 4.436-9.884 9.888-9.884 2.64 0 5.122 1.03 6.988 2.898a9.825 9.825 0 012.893 6.994c-.003 5.45-4.437 9.884-9.885 9.884m8.413-18.297A11.815 11.815 0 0012.05 0C5.495 0 .16 5.335.157 11.892c0 2.096.547 4.142 1.588 5.945L.057 24l6.305-1.654a11.882 11.882 0 005.683 1.448h.005c6.554 0 11.89-5.335 11.893-11.893a11.821 11.821 0 00-3.48-8.413z"/></svg>
                  Teilen
                </button>
                <button onClick={runPriceCheck} disabled={priceLoading} className="text-[11px] py-1 px-2.5 rounded-lg bg-emerald-50 text-emerald-600 font-semibold hover:bg-emerald-100 transition active:scale-95 disabled:opacity-50 flex items-center gap-1">
                  {priceLoading ? <span className="animate-spin">⏳</span> : '💰'} Preise
                </button>
                <button onClick={() => setEditing(true)} className="text-[11px] py-1 px-2.5 rounded-lg bg-purple-50 text-purple-500 font-medium hover:bg-purple-100 transition active:scale-95">✏️</button>
                <button onClick={() => setExpanded(!expanded)} className="text-[11px] py-1 px-2 rounded-lg bg-gray-50 text-gray-400 hover:bg-gray-100 transition active:scale-95">
                  {expanded ? '▲' : '▼'}
                </button>
              </div>
              <button onClick={() => { if (confirm(`"${item.title}" löschen?`)) onDelete(item.id); }} className="text-[11px] py-1 px-2 rounded-lg bg-gray-50 text-gray-400 hover:bg-red-50 hover:text-red-400 transition active:scale-95">🗑️</button>
            </div>
          </div>
        </div>
      </div>

      {showShare && <ShareModal item={item} eventName={eventName} onClose={() => setShowShare(false)} />}
    </>
  );
}

/* ── Add Item Form with URL Scraper ── */
function AddItemForm({ eventId, onAdded }: { eventId: number; onAdded: () => void; }) {
  const [open, setOpen] = useState(false);
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [price, setPrice] = useState('');
  const [url, setUrl] = useState('');
  const [imageUrl, setImageUrl] = useState('');
  const [ean, setEan] = useState('');
  const [category, setCategory] = useState('');
  const [notes, setNotes] = useState('');
  const [saving, setSaving] = useState(false);
  const [scraping, setScraping] = useState(false);
  const [scraped, setScraped] = useState(false);

  const handleUrlScrape = async (inputUrl: string) => {
    setUrl(inputUrl);
    if (!inputUrl.trim() || !inputUrl.startsWith('http')) {
      setScraped(false);
      return;
    }

    setScraping(true);
    try {
      const res = await fetch('/api/wunschliste/scrape', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ url: inputUrl.trim() }),
      });
      const data = await res.json();

      if (data.title && !title) setTitle(data.title);
      if (data.description && !description) setDescription(data.description);
      if (data.price && !price) setPrice(data.price);
      if (data.image) setImageUrl(data.image);
      if (data.ean && !ean) setEan(data.ean);
      setScraped(true);
    } catch (err) {
      console.error('Scrape failed:', err);
    } finally {
      setScraping(false);
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!title.trim()) return;
    setSaving(true);
    try {
      await fetch('/api/wunschliste/items', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          event_id: eventId,
          title: title.trim(),
          description: description.trim() || null,
          price: price.trim() || null,
          url: url.trim() || null,
          image_url: imageUrl.trim() || null,
          ean: ean.trim() || null,
          category: category.trim() || null,
          notes: notes.trim() || null,
        }),
      });
      setTitle(''); setDescription(''); setPrice(''); setUrl(''); setImageUrl(''); setEan(''); setCategory(''); setNotes('');
      setScraped(false);
      setOpen(false);
      onAdded();
    } finally { setSaving(false); }
  };

  if (!open) {
    return (
      <button onClick={() => setOpen(true)} className="w-full py-3.5 border-2 border-dashed border-purple-300/60 rounded-2xl text-sm font-semibold text-purple-400 hover:border-purple-400 hover:text-purple-500 transition-all active:scale-[0.98]">
        ＋ Geschenk hinzufügen
      </button>
    );
  }

  return (
    <form onSubmit={handleSubmit} className="bg-white/80 backdrop-blur-sm rounded-2xl border border-purple-200/60 p-4 shadow-sm space-y-2.5">
      <h4 className="text-sm font-bold text-[#1C1C1E] mb-1">🎁 Neues Geschenk</h4>

      {/* URL field first — triggers scraping */}
      <div className="relative">
        <input
          type="url"
          value={url}
          onChange={e => setUrl(e.target.value)}
          onBlur={e => { if (e.target.value && !scraped) handleUrlScrape(e.target.value); }}
          placeholder="🔗 Link einfügen (füllt automatisch aus)"
          className="w-full bg-[#F2F2F7] rounded-xl px-4 py-2.5 text-sm text-[#1C1C1E] placeholder:text-[#C7C7CC] outline-none focus:ring-2 focus:ring-purple-400 pr-12"
        />
        {scraping && (
          <div className="absolute right-3 top-1/2 -translate-y-1/2">
            <div className="w-5 h-5 border-2 border-purple-400 border-t-transparent rounded-full animate-spin" />
          </div>
        )}
        {scraped && !scraping && (
          <div className="absolute right-3 top-1/2 -translate-y-1/2 text-green-500 text-sm">✅</div>
        )}
      </div>

      {scraping && (
        <p className="text-[11px] text-purple-500 font-medium animate-pulse px-1">🔍 Lade Artikelinfos von der Seite…</p>
      )}

      {/* Preview image if scraped */}
      {imageUrl && (
        <div className="flex items-center gap-3 bg-purple-50/50 rounded-xl p-2">
          <img src={imageUrl} alt="Preview" className="w-14 h-14 rounded-lg object-cover border border-purple-200/40" onError={e => { (e.target as HTMLImageElement).style.display = 'none'; }} />
          <span className="text-[11px] text-[#636366]">Bild von der Seite geladen</span>
          <button type="button" onClick={() => setImageUrl('')} className="ml-auto text-xs text-gray-400 hover:text-red-400">✕</button>
        </div>
      )}

      <input type="text" value={title} onChange={e => setTitle(e.target.value)} placeholder="Titel / Artikelname *" required autoFocus={!url} className="w-full bg-[#F2F2F7] rounded-xl px-4 py-2.5 text-sm text-[#1C1C1E] placeholder:text-[#C7C7CC] outline-none focus:ring-2 focus:ring-purple-400" />

      <textarea value={description} onChange={e => setDescription(e.target.value)} placeholder="Beschreibung (wird vom Link automatisch gefüllt)" rows={2} className="w-full bg-[#F2F2F7] rounded-xl px-4 py-2.5 text-sm text-[#1C1C1E] placeholder:text-[#C7C7CC] outline-none focus:ring-2 focus:ring-purple-400 resize-none" />

      <div className="flex gap-2">
        <input type="text" value={price} onChange={e => setPrice(e.target.value)} placeholder="💰 Preis" className="flex-1 bg-[#F2F2F7] rounded-xl px-4 py-2.5 text-sm text-[#1C1C1E] placeholder:text-[#C7C7CC] outline-none focus:ring-2 focus:ring-purple-400" />
        <select value={category} onChange={e => setCategory(e.target.value)} className="flex-1 bg-[#F2F2F7] rounded-xl px-4 py-2.5 text-sm text-[#1C1C1E] outline-none focus:ring-2 focus:ring-purple-400">
          <option value="">Kategorie…</option>
          <option value="📚">📚 Buch</option>
          <option value="🧸">🧸 Spielzeug</option>
          <option value="👕">👕 Kleidung</option>
          <option value="👟">👟 Schuhe</option>
          <option value="🎨">🎨 Kreativ</option>
          <option value="🏊">🏊 Outdoor</option>
          <option value="🎵">🎵 Musik</option>
          <option value="🎁">🎁 Sonstiges</option>
        </select>
      </div>

      <div className="flex gap-2">
        <input type="text" value={ean} onChange={e => setEan(e.target.value)} placeholder="📊 EAN / ISBN (auto oder manuell)" className="flex-1 bg-[#F2F2F7] rounded-xl px-4 py-2.5 text-sm text-[#1C1C1E] placeholder:text-[#C7C7CC] outline-none focus:ring-2 focus:ring-purple-400 font-mono" />
        {ean && <span className="flex items-center text-[10px] text-green-600 font-medium">✅</span>}
      </div>

      <input type="text" value={notes} onChange={e => setNotes(e.target.value)} placeholder="📝 Notizen (optional)" className="w-full bg-[#F2F2F7] rounded-xl px-4 py-2.5 text-sm text-[#1C1C1E] placeholder:text-[#C7C7CC] outline-none focus:ring-2 focus:ring-purple-400" />

      <div className="flex gap-2 pt-1">
        <button type="submit" disabled={saving || !title.trim()} className="flex-1 py-2.5 bg-gradient-to-r from-purple-500 to-pink-500 text-white text-sm font-semibold rounded-xl shadow-sm transition-all active:scale-95 disabled:opacity-50">
          {saving ? '⏳ Speichern…' : '✅ Hinzufügen'}
        </button>
        <button type="button" onClick={() => { setOpen(false); setScraped(false); }} className="px-4 py-2.5 bg-gray-100 text-gray-500 text-sm font-semibold rounded-xl transition active:scale-95">✕</button>
      </div>
    </form>
  );
}

/* ── Add Event Form ── */
function AddEventForm({ onAdded }: { onAdded: () => void }) {
  const [open, setOpen] = useState(false);
  const [name, setName] = useState('');
  const [emoji, setEmoji] = useState('🎁');
  const [date, setDate] = useState('');
  const [saving, setSaving] = useState(false);

  const presets = [
    { emoji: '🐣', label: 'Ostern' },
    { emoji: '🎂', label: 'Geburtstag' },
    { emoji: '🎄', label: 'Weihnachten' },
    { emoji: '🎁', label: '' },
  ];

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!name.trim()) return;
    setSaving(true);
    try {
      await fetch('/api/wunschliste/events', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name: name.trim(), emoji, date: date || null }),
      });
      setName(''); setEmoji('🎁'); setDate('');
      setOpen(false);
      onAdded();
    } finally { setSaving(false); }
  };

  if (!open) {
    return (
      <button onClick={() => setOpen(true)} className="w-full py-3 border-2 border-dashed border-pink-300/60 rounded-2xl text-sm font-semibold text-pink-400 hover:border-pink-400 hover:text-pink-500 transition-all active:scale-[0.98]">
        ＋ Neues Event anlegen
      </button>
    );
  }

  return (
    <form onSubmit={handleSubmit} className="bg-white/70 backdrop-blur-sm rounded-2xl border border-pink-200/60 p-4 shadow-sm space-y-2.5">
      <div className="flex gap-2">
        {presets.map(p => (
          <button key={p.emoji} type="button" onClick={() => { setEmoji(p.emoji); if (!name && p.label) setName(p.label); }}
            className={`flex-1 py-2 rounded-xl text-center text-lg transition-all ${emoji === p.emoji ? 'bg-pink-100 border-2 border-pink-400 shadow-sm' : 'bg-[#F2F2F7] border-2 border-transparent'}`}>
            {p.emoji}
          </button>
        ))}
      </div>
      <input type="text" value={name} onChange={e => setName(e.target.value)} placeholder="Event-Name *" required autoFocus className="w-full bg-[#F2F2F7] rounded-xl px-4 py-2.5 text-sm text-[#1C1C1E] placeholder:text-[#C7C7CC] outline-none focus:ring-2 focus:ring-pink-400" />
      <input type="date" value={date} onChange={e => setDate(e.target.value)} className="w-full bg-[#F2F2F7] rounded-xl px-4 py-2.5 text-sm text-[#1C1C1E] outline-none focus:ring-2 focus:ring-pink-400" />
      <div className="flex gap-2">
        <button type="submit" disabled={saving || !name.trim()} className="flex-1 py-2.5 bg-gradient-to-r from-pink-500 to-rose-500 text-white text-sm font-semibold rounded-xl shadow-sm transition-all active:scale-95 disabled:opacity-50">
          {saving ? '⏳' : '🎉 Event anlegen'}
        </button>
        <button type="button" onClick={() => setOpen(false)} className="px-4 py-2.5 bg-gray-100 text-gray-500 text-sm font-semibold rounded-xl transition active:scale-95">✕</button>
      </div>
    </form>
  );
}

/* ── Main Page ── */
export default function WunschlistePage() {
  const [events, setEvents] = useState<WunschEvent[]>([]);
  const [items, setItems] = useState<WunschItem[]>([]);
  const [selectedEvent, setSelectedEvent] = useState<number | null>(null);
  const [loading, setLoading] = useState(true);
  const [enriching, setEnriching] = useState(false);
  const [enrichResult, setEnrichResult] = useState<string | null>(null);

  const loadData = useCallback(async () => {
    setLoading(true);
    try {
      const [evRes, itRes] = await Promise.all([
        fetch('/api/wunschliste/events'),
        fetch(`/api/wunschliste/items${selectedEvent ? `?event_id=${selectedEvent}` : ''}`),
      ]);
      const [evData, itData] = await Promise.all([evRes.json(), itRes.json()]);
      setEvents(evData);
      setItems(itData);
    } catch (err) {
      console.error(err);
    } finally { setLoading(false); }
  }, [selectedEvent]);

  useEffect(() => { loadData(); }, [loadData]);

  const handleUpdateItem = async (id: number, data: Partial<WunschItem>) => {
    await fetch(`/api/wunschliste/items/${id}`, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data) });
    loadData();
  };

  const handleDeleteItem = async (id: number) => {
    await fetch(`/api/wunschliste/items/${id}`, { method: 'DELETE' });
    loadData();
  };

  const handleDeleteEvent = async (id: number) => {
    if (!confirm('Event und alle Geschenke löschen?')) return;
    await fetch(`/api/wunschliste/events/${id}`, { method: 'DELETE' });
    if (selectedEvent === id) setSelectedEvent(null);
    loadData();
  };

  const handleEnrichAll = async () => {
    setEnriching(true);
    setEnrichResult(null);
    try {
      const res = await fetch('/api/wunschliste/enrich', { method: 'POST' });
      const data = await res.json();
      setEnrichResult(`✅ ${data.enriched}/${data.total} Einträge angereichert`);
      loadData();
    } catch (err) {
      setEnrichResult('❌ Fehler beim Anreichern');
    } finally { setEnriching(false); }
  };

  const totalItems = items.length;
  const openItems = items.filter(i => i.status === 'offen').length;
  const boughtItems = items.filter(i => i.status === 'gekauft').length;
  const itemsWithoutImage = items.filter(i => !i.image_url && i.url).length;

  const activeEvent = selectedEvent ? events.find(e => e.id === selectedEvent) : null;

  return (
    <main className="min-h-screen bg-gradient-to-br from-[#FFF5FF] via-[#FFF0F5] to-[#F5F0FF]">
      <style jsx global>{`
        @keyframes slide-up { from { transform: translateY(100%); } to { transform: translateY(0); } }
        .animate-slide-up { animation: slide-up 0.3s ease-out; }
        .scrollbar-hide::-webkit-scrollbar { display: none; }
        .scrollbar-hide { -ms-overflow-style: none; scrollbar-width: none; }
      `}</style>

      {/* ── Header ── */}
      <header className="pt-12 pb-4 px-5 safe-area-inset">
        <div className="max-w-2xl mx-auto">
          <div className="flex items-center gap-3 mb-4">
            <Link href="/" className="flex items-center justify-center w-10 h-10 bg-white/70 backdrop-blur-sm rounded-2xl border border-purple-200/50 shadow-sm hover:bg-white transition active:scale-95">
              <svg className="w-5 h-5 text-purple-600" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2.5}>
                <path strokeLinecap="round" strokeLinejoin="round" d="M15 19l-7-7 7-7" />
              </svg>
            </Link>
            <div>
              <h1 className="text-3xl font-extrabold text-[#1C1C1E] tracking-tight leading-tight">🎁 Samus Wunschliste</h1>
              <p className="text-purple-600/80 text-sm font-medium mt-0.5">Geschenke für jeden Anlass</p>
            </div>
          </div>

          {/* Stats */}
          <div className="flex gap-2 flex-wrap">
            <div className="flex items-center gap-1.5 bg-purple-100 text-purple-700 px-3 py-1.5 rounded-full text-sm font-semibold">
              <span>🎁</span><span>{totalItems} gesamt</span>
            </div>
            <div className="flex items-center gap-1.5 bg-amber-100 text-amber-700 px-3 py-1.5 rounded-full text-sm font-semibold">
              <span>⬜</span><span>{openItems} offen</span>
            </div>
            <div className="flex items-center gap-1.5 bg-blue-100 text-blue-700 px-3 py-1.5 rounded-full text-sm font-semibold">
              <span>🛒</span><span>{boughtItems} gekauft</span>
            </div>
            {itemsWithoutImage > 0 && (
              <button onClick={handleEnrichAll} disabled={enriching}
                className="flex items-center gap-1.5 bg-indigo-100 text-indigo-700 px-3 py-1.5 rounded-full text-sm font-semibold hover:bg-indigo-200 transition active:scale-95 disabled:opacity-50">
                {enriching ? <span className="animate-spin">⏳</span> : <span>🔍</span>}
                <span>{enriching ? 'Lade…' : `${itemsWithoutImage} anreichern`}</span>
              </button>
            )}
          </div>
          {enrichResult && (
            <p className="text-xs text-indigo-600 mt-2 font-medium">{enrichResult}</p>
          )}
        </div>
      </header>

      {/* ── Event Selector ── */}
      <div className="max-w-2xl mx-auto px-5 mb-4">
        <div className="flex gap-2 overflow-x-auto pb-2 -mx-1 px-1 scrollbar-hide">
          <button
            onClick={() => setSelectedEvent(null)}
            className={`flex-shrink-0 px-4 py-2.5 rounded-2xl text-sm font-semibold transition-all border ${
              !selectedEvent ? 'bg-purple-500 text-white border-purple-500 shadow-sm' : 'bg-white/60 text-[#8E8E93] border-purple-200/40 hover:border-purple-300'
            }`}
          >
            🎁 Alle
          </button>
          {events.map(ev => (
            <button
              key={ev.id}
              onClick={() => setSelectedEvent(ev.id)}
              className={`flex-shrink-0 px-4 py-2.5 rounded-2xl text-sm font-semibold transition-all border ${
                selectedEvent === ev.id ? 'bg-purple-500 text-white border-purple-500 shadow-sm' : 'bg-white/60 text-[#636366] border-purple-200/40 hover:border-purple-300'
              }`}
            >
              {ev.emoji} {ev.name}
              {ev.open_count > 0 && <span className="ml-1.5 text-[10px] opacity-80">({ev.open_count})</span>}
              {ev.date && <span className="ml-1">{countdownBadge(ev.date)}</span>}
              {ev.erinnerungen_aktiv === 0 && <span className="ml-1 text-[10px]">🔕</span>}
            </button>
          ))}
        </div>
      </div>

      <div className="max-w-2xl mx-auto px-5 pb-16 space-y-4">
        {/* ── Event Header ── */}
        {activeEvent && (
          <div className="bg-white/60 backdrop-blur-sm rounded-2xl border border-purple-200/40 p-4 shadow-sm">
            <div className="flex items-center justify-between">
              <div>
                <h2 className="text-lg font-bold text-[#1C1C1E]">{activeEvent.emoji} {activeEvent.name}</h2>
                <div className="flex gap-2 mt-1">
                  {activeEvent.date && <span className="text-xs text-[#8E8E93]">📅 {formatDate(activeEvent.date)}</span>}
                  {activeEvent.date && countdownBadge(activeEvent.date)}
                </div>
              </div>
              <button onClick={() => handleDeleteEvent(activeEvent.id)} className="text-xs py-1.5 px-3 rounded-xl bg-gray-100 text-gray-400 hover:bg-gray-200 transition active:scale-95">🗑️</button>
            </div>
            {/* Erinnerungen Toggle */}
            <div className="flex items-center justify-between mt-3 pt-3 border-t border-gray-100">
              <div className="flex items-center gap-2">
                <span className="text-sm">🔔</span>
                <span className="text-xs font-semibold text-[#636366]">Erinnerungen</span>
              </div>
              <button
                onClick={async () => {
                  const newVal = activeEvent.erinnerungen_aktiv === 1 ? 0 : 1;
                  try {
                    await fetch(`/api/wunschliste/events/${activeEvent.id}`, { method: 'PATCH', headers: {'Content-Type':'application/json'}, body: JSON.stringify({ erinnerungen_aktiv: newVal }) });
                    loadData();
                  } catch (err) { console.error(err); }
                }}
                className={`w-11 h-6 rounded-full transition-colors relative ${activeEvent.erinnerungen_aktiv !== 0 ? 'bg-purple-500' : 'bg-gray-300'}`}
              >
                <div className={`absolute w-5 h-5 bg-white rounded-full top-0.5 shadow-sm transition-all ${activeEvent.erinnerungen_aktiv !== 0 ? 'left-[22px]' : 'left-0.5'}`} />
              </button>
            </div>
          </div>
        )}

        {/* ── Items ── */}
        {loading ? (
          <div className="flex flex-col items-center justify-center py-16">
            <div className="text-4xl animate-bounce mb-3">🎁</div>
            <p className="text-[#8E8E93] font-medium">Lade Wunschliste…</p>
          </div>
        ) : items.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-12 text-center">
            <div className="text-5xl mb-3">🎀</div>
            <h3 className="text-lg font-bold text-[#1C1C1E] mb-1">Noch keine Geschenke</h3>
            <p className="text-[#8E8E93] text-sm max-w-[220px]">Füge unten das erste Geschenk hinzu!</p>
          </div>
        ) : (
          <div className="space-y-3">
            {!selectedEvent && items.length > 0 && (() => {
              const grouped = new Map<number, { event: WunschEvent | undefined; items: WunschItem[] }>();
              items.forEach(it => {
                if (!grouped.has(it.event_id)) {
                  grouped.set(it.event_id, { event: events.find(e => e.id === it.event_id), items: [] });
                }
                grouped.get(it.event_id)!.items.push(it);
              });
              return Array.from(grouped.values()).map(({ event, items: evItems }) => (
                <div key={event?.id || 0}>
                  <div className="flex items-center gap-2 mb-2 mt-2">
                    <span className="text-lg">{event?.emoji || '🎁'}</span>
                    <h3 className="text-sm font-bold text-[#1C1C1E]">{event?.name || 'Unbekannt'}</h3>
                    {event?.date && countdownBadge(event.date)}
                    <span className="text-[10px] text-[#C7C7CC]">({evItems.length})</span>
                  </div>
                  {evItems.map(it => <ItemCard key={it.id} item={it} eventName={event?.name} onUpdate={handleUpdateItem} onDelete={handleDeleteItem} />)}
                </div>
              ));
            })()}

            {selectedEvent && items.map(it => (
              <ItemCard key={it.id} item={it} eventName={activeEvent?.name} onUpdate={handleUpdateItem} onDelete={handleDeleteItem} />
            ))}
          </div>
        )}

        {/* ── Add Item ── */}
        {selectedEvent && (
          <AddItemForm eventId={selectedEvent} onAdded={loadData} />
        )}

        {/* ── Add Event ── */}
        <div className="pt-2">
          <AddEventForm onAdded={loadData} />
        </div>
      </div>
    </main>
  );
}
