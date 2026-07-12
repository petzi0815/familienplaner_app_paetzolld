'use client';

import { useState, useEffect, useCallback } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { apiGet, apiSend } from '@/lib/api';

interface Trip {
  id: number; title: string; type: string; status: string; start_date: string | null; end_date: string | null;
  destination: string | null; country: string | null; region: string | null; lat: number | null; lng: number | null;
  hotel: string | null; hotel_url: string | null; booking_ref: string | null; booking_platform: string | null;
  flight: string | null; flight_ref: string | null; transport: string | null; budget: string | null; cost_total: string | null;
  participants: string; activities: string | null; highlights: string | null; rating: number | null;
  cover_image: string | null; notes: string | null; tags: string | null;
  doc_count?: number; link_count?: number; docs?: any[]; links?: any[];
}

interface WeekendTip {
  id: number; title: string; description: string | null; location: string | null; lat: number | null; lng: number | null;
  url: string | null; image_url: string | null; category: string | null; date_info: string | null; price: string | null; kid_friendly: number;
}

const TYPE_EMOJI: Record<string, string> = { urlaub: '🏖️', staedtereise: '🏙️', aktivitaet: '🎪', segeln: '⛵', tauchen: '🤿', wandern: '🥾', wellness: '🧖', kreuzfahrt: '🚢', tagesausflug: '🚗', wochenende: '💡' };
const DOC_EMOJI: Record<string, string> = { ticket: '🎫', buchung: '📄', rechnung: '💰', reisepass: '🛂', versicherung: '🛡️', karte: '🗺️', foto: '📸', sonstig: '📎' };

function mapsUrl(lat: number, lng: number) { return `https://www.google.com/maps?q=${lat},${lng}`; }
function routeUrl(lat: number, lng: number) { return `https://www.google.com/maps/dir/?api=1&destination=${lat},${lng}`; }
function formatDate(d: string | null) { return d ? new Date(d + 'T00:00:00').toLocaleDateString('de-DE', { day: '2-digit', month: 'short', year: 'numeric' }) : ''; }
function daysUntil(d: string) { const now = new Date(); now.setHours(0,0,0,0); return Math.ceil((new Date(d+'T00:00:00').getTime() - now.getTime()) / 86400000); }

/* ── Trip Detail Modal ── */
function TripDetail({ trip, onClose, onUpdate, onDelete }: { trip: Trip; onClose: () => void; onUpdate: () => void; onDelete: () => void }) {
  const [detail, setDetail] = useState<Trip & { docs: any[]; links: any[] }>(trip as any);
  const [uploading, setUploading] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(0);
  const [editing, setEditing] = useState(false);
  const [editData, setEditData] = useState(trip);

  useEffect(() => {
    fetch(`/api/reisen/${trip.id}`).then(r => r.json()).then(setDetail).catch(console.error);
  }, [trip.id]);

  const handleUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setUploading(true);
    const fd = new FormData();
    fd.append('file', file);
    fd.append('name', file.name);
    fd.append('doc_type', file.type.includes('pdf') ? 'buchung' : 'sonstig');
    await fetch(`/api/reisen/${trip.id}/docs`, { method: 'POST', body: fd });
    const res = await fetch(`/api/reisen/${trip.id}`);
    setDetail(await res.json());
    setUploading(false);
  };

  const handleDeleteDoc = async (docId: number) => {
    await fetch(`/api/reisen/${trip.id}/docs/${docId}`, { method: 'DELETE' });
    const res = await fetch(`/api/reisen/${trip.id}`);
    setDetail(await res.json());
  };

  const handleDeleteTrip = async () => {
    if (confirmDelete < 2) { setConfirmDelete(c => c + 1); return; }
    await fetch(`/api/reisen/${trip.id}`, { method: 'DELETE' });
    onDelete();
    onClose();
  };

  const handleSaveEdit = async () => {
    await fetch(`/api/reisen/${trip.id}`, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(editData) });
    const res = await fetch(`/api/reisen/${trip.id}`);
    setDetail(await res.json());
    setEditing(false);
    onUpdate();
  };

  const emoji = TYPE_EMOJI[detail.type] || '🌍';
  const isPast = detail.status === 'vergangen';
  const countdown = detail.start_date && detail.status === 'geplant' ? daysUntil(detail.start_date) : null;

  return (
    <div className="fixed inset-0 z-50 bg-black/50 backdrop-blur-sm overflow-y-auto" onClick={onClose}>
      <div className="min-h-full flex items-start justify-center pt-8 pb-16 px-4" onClick={e => e.stopPropagation()}>
        <div className="w-full max-w-lg bg-white rounded-3xl shadow-2xl overflow-hidden">
          {/* Hero with Cover Image */}
          <div className="relative h-48 overflow-hidden">
            {detail.cover_image ? (
              <img src={detail.cover_image} alt={detail.title} className="w-full h-full object-cover" />
            ) : (
              <div className={`w-full h-full bg-gradient-to-br ${isPast ? 'from-gray-400 to-gray-600' : 'from-blue-500 via-indigo-500 to-purple-600'}`} />
            )}
            <div className="absolute inset-0 bg-gradient-to-t from-black/80 via-black/20 to-transparent" />
            <button onClick={onClose} className="absolute top-4 right-4 w-8 h-8 bg-black/30 backdrop-blur-md rounded-full text-white flex items-center justify-center text-lg">✕</button>
            {countdown !== null && countdown > 0 && (
              <div className="absolute top-4 left-4 bg-white/20 backdrop-blur-md rounded-full px-3 py-1 text-white text-xs font-bold">✈️ noch {countdown} Tage</div>
            )}
            <div className="absolute bottom-0 left-0 right-0 p-5">
              <span className="text-3xl drop-shadow-lg">{emoji}</span>
              <h2 className="text-xl font-extrabold text-white leading-tight mt-1 drop-shadow-md">{detail.title}</h2>
              {detail.destination && <p className="text-white/80 text-sm font-medium drop-shadow">{detail.destination}{detail.country ? `, ${detail.country}` : ''}</p>}
            </div>
          </div>

          <div className="p-5 space-y-4">
            {/* Dates + Status */}
            <div className="flex flex-wrap gap-2">
              {detail.start_date && <span className="text-xs bg-blue-100 text-blue-700 px-2.5 py-1 rounded-full font-semibold">📅 {formatDate(detail.start_date)}{detail.end_date && detail.end_date !== detail.start_date ? ` – ${formatDate(detail.end_date)}` : ''}</span>}
              <span className={`text-xs px-2.5 py-1 rounded-full font-semibold ${detail.status === 'geplant' ? 'bg-green-100 text-green-700' : 'bg-gray-100 text-gray-600'}`}>
                {detail.status === 'geplant' ? '🟢 Geplant' : '✅ Vergangen'}
              </span>
              {detail.participants && <span className="text-xs bg-purple-100 text-purple-700 px-2.5 py-1 rounded-full font-semibold">👥 {detail.participants}</span>}
            </div>

            {/* Geo + Route */}
            {detail.lat && detail.lng && (
              <div className="flex gap-2">
                <a href={mapsUrl(detail.lat, detail.lng)} target="_blank" rel="noopener" className="flex-1 text-center py-2.5 bg-blue-50 text-blue-600 text-sm font-semibold rounded-xl hover:bg-blue-100 transition">📍 Auf Karte</a>
                <a href={routeUrl(detail.lat, detail.lng)} target="_blank" rel="noopener" className="flex-1 text-center py-2.5 bg-green-50 text-green-600 text-sm font-semibold rounded-xl hover:bg-green-100 transition">🧭 Route planen</a>
              </div>
            )}

            {/* Details Grid */}
            <div className="grid grid-cols-2 gap-2 text-xs">
              {detail.hotel && <div className="bg-[#F2F2F7] rounded-xl p-2.5"><span className="text-[#8E8E93] block">🏨 Hotel</span><span className="font-semibold text-[#1C1C1E]">{detail.hotel}</span></div>}
              {detail.booking_ref && <div className="bg-[#F2F2F7] rounded-xl p-2.5"><span className="text-[#8E8E93] block">📋 Buchung</span><span className="font-semibold text-[#1C1C1E] font-mono">{detail.booking_ref}</span>{detail.booking_platform && <span className="text-[#8E8E93]"> ({detail.booking_platform})</span>}</div>}
              {detail.flight && <div className="bg-[#F2F2F7] rounded-xl p-2.5"><span className="text-[#8E8E93] block">✈️ Flug</span><span className="font-semibold text-[#1C1C1E]">{detail.flight}</span>{detail.flight_ref && <span className="text-[#8E8E93] font-mono"> ({detail.flight_ref})</span>}</div>}
              {detail.transport && <div className="bg-[#F2F2F7] rounded-xl p-2.5"><span className="text-[#8E8E93] block">🚆 Anreise</span><span className="font-semibold text-[#1C1C1E]">{detail.transport}</span></div>}
              {detail.cost_total && <div className="bg-[#F2F2F7] rounded-xl p-2.5"><span className="text-[#8E8E93] block">💰 Kosten</span><span className="font-semibold text-[#1C1C1E]">{detail.cost_total}</span></div>}
              {detail.activities && <div className="bg-[#F2F2F7] rounded-xl p-2.5 col-span-2"><span className="text-[#8E8E93] block">🎯 Aktivitäten</span><span className="font-semibold text-[#1C1C1E]">{detail.activities}</span></div>}
            </div>

            {detail.highlights && <div className="bg-amber-50 rounded-xl p-3 text-xs"><span className="font-bold text-amber-700">✨ Highlights:</span> <span className="text-amber-800">{detail.highlights}</span></div>}
            {detail.notes && <p className="text-xs text-[#636366] italic">{detail.notes}</p>}

            {/* Rating */}
            {detail.rating && (
              <div className="flex gap-0.5">{Array.from({length:5}).map((_,i) => <span key={i} className="text-lg">{i < detail.rating! ? '⭐' : '☆'}</span>)}</div>
            )}

            {/* Documents */}
            <div>
              <h3 className="text-sm font-bold text-[#1C1C1E] mb-2">📎 Dokumente ({detail.docs?.length || 0})</h3>
              {detail.docs?.map(doc => (
                <div key={doc.id} className="flex items-center gap-2 py-2 border-b border-gray-100 last:border-0">
                  <span className="text-lg">{DOC_EMOJI[doc.doc_type] || '📎'}</span>
                  <div className="flex-1 min-w-0">
                    <a href={`/api/reisen/${trip.id}/docs/${doc.id}`} target="_blank" className="text-xs font-semibold text-blue-600 hover:underline truncate block">{doc.name}</a>
                    {doc.file_size && <span className="text-[10px] text-[#8E8E93]">{(doc.file_size / 1024).toFixed(0)} KB</span>}
                  </div>
                  <button onClick={() => handleDeleteDoc(doc.id)} className="text-[10px] text-gray-400 hover:text-red-400">🗑️</button>
                </div>
              ))}
              <label className="mt-2 block">
                <span className="text-xs text-blue-500 font-semibold cursor-pointer hover:text-blue-600">＋ Dokument hochladen{uploading && ' ⏳'}</span>
                <input type="file" className="hidden" onChange={handleUpload} accept=".pdf,.jpg,.jpeg,.png,.doc,.docx" />
              </label>
            </div>

            {/* Links */}
            {detail.links && detail.links.length > 0 && (
              <div>
                <h3 className="text-sm font-bold text-[#1C1C1E] mb-2">🔗 Links</h3>
                {detail.links.map((link: any) => (
                  <a key={link.id} href={link.url} target="_blank" rel="noopener" className="flex items-center gap-2 py-1.5 text-xs text-blue-600 hover:text-blue-800 transition">
                    <span>🔗</span><span className="font-medium">{link.title}</span>
                  </a>
                ))}
              </div>
            )}

            {/* Actions */}
            <div className="flex gap-2 pt-2 border-t border-gray-100">
              <button onClick={() => setEditing(!editing)} className="flex-1 py-2.5 bg-blue-50 text-blue-600 text-sm font-semibold rounded-xl transition active:scale-95">✏️ Bearbeiten</button>
              <button onClick={handleDeleteTrip} className={`py-2.5 px-4 text-sm font-semibold rounded-xl transition active:scale-95 ${confirmDelete === 0 ? 'bg-gray-100 text-gray-400' : confirmDelete === 1 ? 'bg-red-100 text-red-500' : 'bg-red-500 text-white'}`}>
                {confirmDelete === 0 ? '🗑️' : confirmDelete === 1 ? '⚠️ Sicher?' : '🗑️ Endgültig'}
              </button>
            </div>

            {/* Edit form */}
            {editing && (
              <div className="bg-[#F2F2F7] rounded-2xl p-4 space-y-2">
                <input type="text" value={editData.title} onChange={e => setEditData(d => ({...d, title: e.target.value}))} placeholder="Titel" className="w-full bg-white rounded-xl px-3 py-2 text-sm outline-none" />
                <div className="flex gap-2">
                  <input type="text" value={editData.destination || ''} onChange={e => setEditData(d => ({...d, destination: e.target.value}))} placeholder="Zielort" className="flex-1 bg-white rounded-xl px-3 py-2 text-sm outline-none" />
                  <input type="text" value={editData.country || ''} onChange={e => setEditData(d => ({...d, country: e.target.value}))} placeholder="Land" className="flex-1 bg-white rounded-xl px-3 py-2 text-sm outline-none" />
                </div>
                <div className="flex gap-2">
                  <input type="date" value={editData.start_date || ''} onChange={e => setEditData(d => ({...d, start_date: e.target.value}))} className="flex-1 bg-white rounded-xl px-3 py-2 text-sm outline-none" />
                  <input type="date" value={editData.end_date || ''} onChange={e => setEditData(d => ({...d, end_date: e.target.value}))} className="flex-1 bg-white rounded-xl px-3 py-2 text-sm outline-none" />
                </div>
                <div className="flex gap-2">
                  <input type="text" value={editData.hotel || ''} onChange={e => setEditData(d => ({...d, hotel: e.target.value}))} placeholder="🏨 Hotel" className="flex-1 bg-white rounded-xl px-3 py-2 text-sm outline-none" />
                  <input type="text" value={editData.booking_ref || ''} onChange={e => setEditData(d => ({...d, booking_ref: e.target.value}))} placeholder="Buchungsnr." className="flex-1 bg-white rounded-xl px-3 py-2 text-sm outline-none" />
                </div>
                <div className="flex gap-2">
                  <input type="number" step="any" value={editData.lat || ''} onChange={e => setEditData(d => ({...d, lat: parseFloat(e.target.value) || null}))} placeholder="Lat" className="flex-1 bg-white rounded-xl px-3 py-2 text-sm outline-none" />
                  <input type="number" step="any" value={editData.lng || ''} onChange={e => setEditData(d => ({...d, lng: parseFloat(e.target.value) || null}))} placeholder="Lng" className="flex-1 bg-white rounded-xl px-3 py-2 text-sm outline-none" />
                </div>
                <textarea value={editData.activities || ''} onChange={e => setEditData(d => ({...d, activities: e.target.value}))} placeholder="Aktivitäten" rows={2} className="w-full bg-white rounded-xl px-3 py-2 text-sm outline-none resize-none" />
                <textarea value={editData.notes || ''} onChange={e => setEditData(d => ({...d, notes: e.target.value}))} placeholder="Notizen" rows={2} className="w-full bg-white rounded-xl px-3 py-2 text-sm outline-none resize-none" />
                <select value={editData.status} onChange={e => setEditData(d => ({...d, status: e.target.value}))} className="w-full bg-white rounded-xl px-3 py-2 text-sm outline-none">
                  <option value="geplant">🟢 Geplant</option>
                  <option value="vergangen">✅ Vergangen</option>
                </select>
                <button onClick={handleSaveEdit} className="w-full py-2.5 bg-blue-500 text-white text-sm font-semibold rounded-xl transition active:scale-95">💾 Speichern</button>
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

/* ── Trip Card (Bild-Kachel) ── */
function TripCard({ trip, onClick }: { trip: Trip; onClick: () => void }) {
  const emoji = TYPE_EMOJI[trip.type] || '🌍';
  const isPast = trip.status === 'vergangen';
  const countdown = trip.start_date && trip.status === 'geplant' ? daysUntil(trip.start_date) : null;

  return (
    <button onClick={onClick} className="w-full text-left overflow-hidden rounded-2xl shadow-md transition-all active:scale-[0.97] relative group">
      {/* Cover Image */}
      <div className="relative h-44 w-full overflow-hidden">
        {trip.cover_image ? (
          <img
            src={trip.cover_image}
            alt={trip.title}
            className={`w-full h-full object-cover transition-transform duration-300 group-hover:scale-105 ${isPast ? 'brightness-75 saturate-75' : ''}`}
            onError={e => { (e.target as HTMLImageElement).style.display = 'none'; }}
          />
        ) : (
          <div className={`w-full h-full bg-gradient-to-br ${isPast ? 'from-gray-400 to-gray-600' : 'from-blue-500 via-indigo-500 to-purple-600'}`} />
        )}
        {/* Gradient overlay for text */}
        <div className="absolute inset-0 bg-gradient-to-t from-black/80 via-black/30 to-transparent" />

        {/* Badges */}
        <div className="absolute top-3 left-3 flex gap-1.5">
          <span className="bg-black/30 backdrop-blur-md rounded-full px-2.5 py-1 text-white text-xs font-bold">{emoji}</span>
          {isPast && trip.rating && (
            <span className="bg-amber-500/90 backdrop-blur-md rounded-full px-2.5 py-1 text-white text-xs font-bold">{'⭐'.repeat(Math.min(trip.rating, 5))}</span>
          )}
        </div>
        {countdown !== null && countdown > 0 && (
          <div className="absolute top-3 right-3 bg-white/20 backdrop-blur-md rounded-full px-3 py-1 text-white text-xs font-bold">
            ✈️ noch {countdown} Tage
          </div>
        )}
        {isPast && (
          <div className="absolute top-3 right-3 bg-white/20 backdrop-blur-md rounded-full px-2.5 py-1 text-white/80 text-[10px] font-semibold">
            ✅ {trip.start_date ? new Date(trip.start_date + 'T00:00:00').getFullYear() : ''}
          </div>
        )}

        {/* Content over image */}
        <div className="absolute bottom-0 left-0 right-0 p-4">
          <h3 className="text-lg font-extrabold text-white leading-tight drop-shadow-md">{trip.title}</h3>
          <p className="text-white/80 text-xs font-medium mt-0.5 drop-shadow">
            📍 {trip.destination}{trip.country ? `, ${trip.country}` : ''}
            {trip.start_date && <span className="ml-1.5 text-white/60">· {formatDate(trip.start_date)}{trip.end_date && trip.end_date !== trip.start_date ? ` – ${formatDate(trip.end_date)}` : ''}</span>}
          </p>
          <div className="flex flex-wrap gap-1.5 mt-2">
            {trip.hotel && <span className="text-[10px] bg-white/20 backdrop-blur-sm text-white px-2 py-0.5 rounded-full font-medium">🏨 {trip.hotel.length > 25 ? trip.hotel.slice(0, 25) + '…' : trip.hotel}</span>}
            {trip.activities && <span className="text-[10px] bg-white/20 backdrop-blur-sm text-white px-2 py-0.5 rounded-full font-medium">🎯 {trip.activities.length > 28 ? trip.activities.slice(0, 28) + '…' : trip.activities}</span>}
            {(trip.doc_count || 0) > 0 && <span className="text-[10px] bg-white/25 backdrop-blur-sm text-white px-2 py-0.5 rounded-full font-bold">📎 {trip.doc_count}</span>}
            {trip.lat && trip.lng && <span className="text-[10px] bg-green-500/40 backdrop-blur-sm text-white px-2 py-0.5 rounded-full font-medium">🗺️</span>}
          </div>
        </div>
      </div>
    </button>
  );
}

/* ── Weekend Tip Card ── */
function WeekendTipCard({ tip, onClick }: { tip: WeekendTip; onClick?: () => void }) {
  const cat = (tip as any).category || 'event';
  const catEmoji: Record<string, string> = { event: '🎪', kultur: '🏛️', natur: '🌿', aktivitaet: '🏊', gastro: '🍽️' };
  return (
    <div onClick={onClick} className="bg-white/70 backdrop-blur-sm rounded-2xl border border-amber-200/60 p-3.5 shadow-sm cursor-pointer hover:shadow-md transition active:scale-[0.98]">
      <div className="flex items-start gap-3">
        {tip.image_url ? (
          <img src={tip.image_url} alt={tip.title} className="w-16 h-16 rounded-xl object-cover flex-shrink-0" onError={e => { (e.target as HTMLImageElement).style.display = 'none'; }} />
        ) : (
          <div className="w-16 h-16 rounded-xl bg-gradient-to-br from-amber-100 to-orange-100 flex items-center justify-center flex-shrink-0 text-2xl">{catEmoji[cat] || '💡'}</div>
        )}
        <div className="flex-1 min-w-0">
          <h3 className="text-sm font-bold text-[#1C1C1E] leading-tight">{tip.title}</h3>
          {tip.description && <p className="text-[11px] text-[#636366] mt-0.5 line-clamp-2">{tip.description}</p>}
          <div className="flex flex-wrap gap-1.5 mt-1.5">
            {tip.location && <span className="text-[10px] bg-blue-50 text-blue-600 px-1.5 py-0.5 rounded-full">📍 {tip.location}</span>}
            {tip.date_info && <span className="text-[10px] bg-purple-50 text-purple-600 px-1.5 py-0.5 rounded-full">📅 {tip.date_info}</span>}
            {tip.price && <span className="text-[10px] bg-green-50 text-green-600 px-1.5 py-0.5 rounded-full">💰 {tip.price}</span>}
            {tip.kid_friendly ? <span className="text-[10px] bg-pink-50 text-pink-600 px-1.5 py-0.5 rounded-full">👶</span> : null}
          </div>
        </div>
        <span className="text-[#C7C7CC] text-sm">▸</span>
      </div>
    </div>
  );
}

/* ── Add Trip Form ── */
function AddTripForm({ onAdded }: { onAdded: () => void }) {
  const [open, setOpen] = useState(false);
  const [title, setTitle] = useState('');
  const [type, setType] = useState('urlaub');
  const [dest, setDest] = useState('');
  const [country, setCountry] = useState('');
  const [startDate, setStartDate] = useState('');
  const [endDate, setEndDate] = useState('');
  const [hotel, setHotel] = useState('');
  const [bookingRef, setBookingRef] = useState('');
  const [activities, setActivities] = useState('');
  const [notes, setNotes] = useState('');
  const [status, setStatus] = useState('geplant');
  const [saving, setSaving] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!title.trim()) return;
    setSaving(true);
    try {
      await apiSend('/reisen', 'POST', { title: title.trim(), type, status, destination: dest.trim() || null, country: country.trim() || null, start_date: startDate || null, end_date: endDate || null, hotel: hotel.trim() || null, booking_ref: bookingRef.trim() || null, activities: activities.trim() || null, notes: notes.trim() || null });
      setTitle(''); setDest(''); setCountry(''); setStartDate(''); setEndDate(''); setHotel(''); setBookingRef(''); setActivities(''); setNotes('');
      setOpen(false);
      onAdded();
    } finally { setSaving(false); }
  };

  if (!open) {
    return <button onClick={() => setOpen(true)} className="w-full py-3.5 border-2 border-dashed border-blue-300/60 rounded-2xl text-sm font-semibold text-blue-400 hover:border-blue-400 hover:text-blue-500 transition-all active:scale-[0.98]">＋ Reise / Aktivität hinzufügen</button>;
  }

  return (
    <form onSubmit={handleSubmit} className="bg-white/80 backdrop-blur-sm rounded-2xl border border-blue-200/60 p-4 shadow-sm space-y-2.5">
      <h4 className="text-sm font-bold text-[#1C1C1E]">✈️ Neue Reise / Aktivität</h4>
      <div className="flex gap-2">
        <select value={type} onChange={e => setType(e.target.value)} className="bg-[#F2F2F7] rounded-xl px-3 py-2.5 text-sm outline-none">
          {Object.entries(TYPE_EMOJI).map(([k, v]) => <option key={k} value={k}>{v} {k}</option>)}
        </select>
        <select value={status} onChange={e => setStatus(e.target.value)} className="bg-[#F2F2F7] rounded-xl px-3 py-2.5 text-sm outline-none">
          <option value="geplant">🟢 Geplant</option>
          <option value="vergangen">✅ Vergangen</option>
        </select>
      </div>
      <input type="text" value={title} onChange={e => setTitle(e.target.value)} placeholder="Titel *" required autoFocus className="w-full bg-[#F2F2F7] rounded-xl px-4 py-2.5 text-sm outline-none focus:ring-2 focus:ring-blue-400" />
      <div className="flex gap-2">
        <input type="text" value={dest} onChange={e => setDest(e.target.value)} placeholder="📍 Zielort" className="flex-1 bg-[#F2F2F7] rounded-xl px-4 py-2.5 text-sm outline-none focus:ring-2 focus:ring-blue-400" />
        <input type="text" value={country} onChange={e => setCountry(e.target.value)} placeholder="🌍 Land" className="flex-1 bg-[#F2F2F7] rounded-xl px-4 py-2.5 text-sm outline-none focus:ring-2 focus:ring-blue-400" />
      </div>
      <div className="flex gap-2">
        <input type="date" value={startDate} onChange={e => setStartDate(e.target.value)} className="flex-1 bg-[#F2F2F7] rounded-xl px-4 py-2.5 text-sm outline-none focus:ring-2 focus:ring-blue-400" />
        <input type="date" value={endDate} onChange={e => setEndDate(e.target.value)} className="flex-1 bg-[#F2F2F7] rounded-xl px-4 py-2.5 text-sm outline-none focus:ring-2 focus:ring-blue-400" />
      </div>
      <div className="flex gap-2">
        <input type="text" value={hotel} onChange={e => setHotel(e.target.value)} placeholder="🏨 Hotel" className="flex-1 bg-[#F2F2F7] rounded-xl px-4 py-2.5 text-sm outline-none focus:ring-2 focus:ring-blue-400" />
        <input type="text" value={bookingRef} onChange={e => setBookingRef(e.target.value)} placeholder="Buchungsnr." className="flex-1 bg-[#F2F2F7] rounded-xl px-4 py-2.5 text-sm outline-none focus:ring-2 focus:ring-blue-400" />
      </div>
      <input type="text" value={activities} onChange={e => setActivities(e.target.value)} placeholder="🎯 Aktivitäten" className="w-full bg-[#F2F2F7] rounded-xl px-4 py-2.5 text-sm outline-none focus:ring-2 focus:ring-blue-400" />
      <textarea value={notes} onChange={e => setNotes(e.target.value)} placeholder="📝 Notizen" rows={2} className="w-full bg-[#F2F2F7] rounded-xl px-4 py-2.5 text-sm outline-none focus:ring-2 focus:ring-blue-400 resize-none" />
      <div className="flex gap-2 pt-1">
        <button type="submit" disabled={saving || !title.trim()} className="flex-1 py-2.5 bg-gradient-to-r from-blue-500 to-indigo-500 text-white text-sm font-semibold rounded-xl shadow-sm transition-all active:scale-95 disabled:opacity-50">{saving ? '⏳' : '✅ Speichern'}</button>
        <button type="button" onClick={() => setOpen(false)} className="px-4 py-2.5 bg-gray-100 text-gray-500 text-sm font-semibold rounded-xl transition active:scale-95">✕</button>
      </div>
    </form>
  );
}

/* ── Main Page ── */
export default function ReisenPage() {
  const router = useRouter();
  const [trips, setTrips] = useState<Trip[]>([]);
  const [filter, setFilter] = useState<string | null>(null);
  const [search, setSearch] = useState('');
  const [searchResults, setSearchResults] = useState<Trip[] | null>(null);
  const [weekendTips, setWeekendTips] = useState<WeekendTip[]>([]);
  const [weekendGroups, setWeekendGroups] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [tab, setTab] = useState<'urlaube' | 'aktivitaeten'>('urlaube');

  const loadData = useCallback(async () => {
    setLoading(true);
    try {
      const q = filter ? `&status=${filter}` : '';
      const tRes = await apiGet<{ data: Trip[] }>(`/reisen?limit=100&sort=start_date:desc${q}`);
      setTrips(tRes.data ?? []);
      // Wochenend-Tipps (KW-Gruppierung) folgt separat — Tab bleibt vorerst leer.
      setWeekendTips([]);
      setWeekendGroups([]);
    } catch (err) { console.error(err); }
    finally { setLoading(false); }
  }, [filter]);

  useEffect(() => { loadData(); }, [loadData]);

  const handleSearch = async (q: string) => {
    setSearch(q);
    if (!q.trim() || q.length < 2) { setSearchResults(null); return; }
    const res = await apiGet<{ data: Trip[] }>(`/reisen?search=${encodeURIComponent(q)}&limit=50`);
    setSearchResults(res.data ?? []);
  };

  const planned = trips.filter(t => t.status === 'geplant');
  const past = trips.filter(t => t.status === 'vergangen');

  return (
    <main className="min-h-screen bg-gradient-to-br from-[#F0F5FF] via-[#FFF5F0] to-[#F5F0FF]">
      {/* Header */}
      <header className="pt-12 pb-4 px-5 safe-area-inset">
        <div className="max-w-2xl mx-auto">
          <div className="flex items-center gap-3 mb-4">
            <Link href="/" className="flex items-center justify-center w-10 h-10 bg-white/70 backdrop-blur-sm rounded-2xl border border-blue-200/50 shadow-sm hover:bg-white transition active:scale-95">
              <svg className="w-5 h-5 text-blue-600" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2.5}><path strokeLinecap="round" strokeLinejoin="round" d="M15 19l-7-7 7-7" /></svg>
            </Link>
            <div>
              <h1 className="text-3xl font-extrabold text-[#1C1C1E] tracking-tight leading-tight">✈️ Reisen & Aktivitäten</h1>
              <p className="text-blue-600/80 text-sm font-medium mt-0.5">Familienplaner</p>
            </div>
          </div>

          {/* Tab Switcher */}
          <div className="flex bg-white/60 backdrop-blur-sm rounded-2xl p-1 border border-gray-200/50 mb-3">
            <button onClick={() => setTab('urlaube')} className={`flex-1 py-2 rounded-xl text-sm font-semibold transition ${tab === 'urlaube' ? 'bg-white text-blue-600 shadow-sm' : 'text-[#8E8E93]'}`}>🏖️ Urlaube</button>
            <button onClick={() => setTab('aktivitaeten')} className={`flex-1 py-2 rounded-xl text-sm font-semibold transition ${tab === 'aktivitaeten' ? 'bg-white text-orange-600 shadow-sm' : 'text-[#8E8E93]'}`}>🎪 Wochenend-Tipps</button>
          </div>
          {tab === 'urlaube' && (
            <div className="flex justify-end mb-2"><Link href="/reisen/vergleich" className="text-xs font-semibold text-purple-600 bg-purple-50 px-3 py-1.5 rounded-lg">🔄 Vergleich</Link></div>
          )}

          {/* Filter (only for Urlaube tab) */}
          {tab === 'urlaube' && (
            <div className="flex gap-2 flex-wrap">
              <button onClick={() => setFilter(null)} className={`px-3 py-1.5 rounded-full text-sm font-semibold transition ${!filter ? 'bg-blue-500 text-white' : 'bg-blue-100 text-blue-700'}`}>🌍 Alle ({trips.length})</button>
              <button onClick={() => setFilter('geplant')} className={`px-3 py-1.5 rounded-full text-sm font-semibold transition ${filter === 'geplant' ? 'bg-green-500 text-white' : 'bg-green-100 text-green-700'}`}>🟢 Geplant ({planned.length})</button>
              <button onClick={() => setFilter('vergangen')} className={`px-3 py-1.5 rounded-full text-sm font-semibold transition ${filter === 'vergangen' ? 'bg-gray-500 text-white' : 'bg-gray-100 text-gray-700'}`}>✅ Vergangen ({past.length})</button>
            </div>
          )}
        </div>
      </header>

      {/* Search */}
      <div className="max-w-2xl mx-auto px-5 mb-4">
        <input type="text" value={search} onChange={e => handleSearch(e.target.value)} placeholder="🔍 Reise suchen…"
          className="w-full bg-white/70 backdrop-blur-sm border border-blue-200/40 rounded-2xl px-4 py-2.5 text-sm text-[#1C1C1E] placeholder:text-[#C7C7CC] outline-none focus:ring-2 focus:ring-blue-400" />
        {searchResults && (
          <div className="mt-2 space-y-2">
            {searchResults.length === 0 ? <p className="text-xs text-[#8E8E93]">Keine Treffer</p> :
              searchResults.map(t => <TripCard key={t.id} trip={t} onClick={() => router.push(`/reisen/${t.id}`)} />)}
          </div>
        )}
      </div>

      <div className="max-w-2xl mx-auto px-5 pb-16 space-y-4">
        {tab === 'aktivitaeten' ? (
          /* Weekend Groups Tab */
          weekendGroups.length > 0 ? (
            <div className="space-y-4">
              {weekendGroups.map(g => (
                <div key={`${g.year}-${g.week}`} onClick={() => router.push(`/reisen/wochenende/${g.year}-${g.week}`)} className="bg-white/80 backdrop-blur-sm rounded-2xl border border-amber-200/40 shadow-sm overflow-hidden cursor-pointer hover:shadow-md transition active:scale-[0.98]">
                  {/* Header */}
                  <div className="bg-gradient-to-r from-amber-50 to-orange-50 px-4 py-3 flex items-center gap-3 border-b border-amber-100/50">
                    <div className="w-12 h-12 bg-gradient-to-br from-amber-400 to-orange-500 rounded-xl flex items-center justify-center shadow-sm">
                      <span className="text-white text-lg font-black">KW{g.week}</span>
                    </div>
                    <div className="flex-1">
                      <h3 className="text-sm font-bold text-[#1C1C1E]">Wochenende {g.dateRange}</h3>
                      <div className="flex gap-2 mt-0.5">
                        {g.events.length > 0 && <span className="text-[10px] bg-purple-100 text-purple-700 px-1.5 py-0.5 rounded-full font-semibold">🎪 {g.events.length} Event{g.events.length > 1 ? 's' : ''}</span>}
                        {g.evergreen.length > 0 && <span className="text-[10px] bg-green-100 text-green-700 px-1.5 py-0.5 rounded-full font-semibold">🌿 {g.evergreen.length} Tipp{g.evergreen.length > 1 ? 's' : ''}</span>}
                      </div>
                    </div>
                    <span className="text-[#C7C7CC] text-sm">▸</span>
                  </div>
                  {/* Preview */}
                  <div className="px-4 py-3 space-y-1.5">
                    {g.events.slice(0, 2).map((t: any) => (
                      <div key={t.id} className="flex items-center gap-2">
                        <span className="text-xs">🎪</span>
                        <span className="text-xs font-semibold text-purple-700 truncate">{t.title}</span>
                        {t.location && <span className="text-[10px] text-[#8E8E93] truncate">· {t.location}</span>}
                      </div>
                    ))}
                    {g.evergreen.slice(0, 2).map((t: any) => (
                      <div key={t.id} className="flex items-center gap-2">
                        <span className="text-xs">🌿</span>
                        <span className="text-xs text-[#636366] truncate">{t.title}</span>
                      </div>
                    ))}
                    {(g.events.length + g.evergreen.length) > 4 && (
                      <span className="text-[10px] text-[#8E8E93]">+{g.events.length + g.evergreen.length - 4} weitere…</span>
                    )}
                  </div>
                </div>
              ))}
            </div>
          ) : (
            <div className="flex flex-col items-center justify-center py-12 text-center">
              <div className="text-5xl mb-3">🎪</div>
              <h3 className="text-lg font-bold text-[#1C1C1E] mb-1">Noch keine Wochenend-Tipps</h3>
              <p className="text-[#8E8E93] text-sm">Ole recherchiert jeden Donnerstag neue Vorschläge!</p>
            </div>
          )
        ) : (
          /* Urlaube Tab */
          <>
            {loading ? (
              <div className="flex flex-col items-center justify-center py-16"><div className="text-4xl animate-bounce mb-3">✈️</div><p className="text-[#8E8E93] font-medium">Lade Reisen…</p></div>
            ) : trips.length === 0 ? (
              <div className="flex flex-col items-center justify-center py-12 text-center"><div className="text-5xl mb-3">🌍</div><h3 className="text-lg font-bold text-[#1C1C1E] mb-1">Noch keine Reisen</h3><p className="text-[#8E8E93] text-sm">Lege die erste Reise an!</p></div>
            ) : (
              <>
                {planned.length > 0 && (!filter || filter === 'geplant') && (
                  <div><h3 className="text-xs font-bold text-[#8E8E93] uppercase tracking-wider mb-2 px-1">🟢 Geplant</h3><div className="space-y-2.5">{planned.map(t => <TripCard key={t.id} trip={t} onClick={() => router.push(`/reisen/${t.id}`)} />)}</div></div>
                )}
                {past.length > 0 && (!filter || filter === 'vergangen') && (
                  <div><h3 className="text-xs font-bold text-[#8E8E93] uppercase tracking-wider mb-2 px-1">✅ Vergangen</h3><div className="space-y-2.5">{past.map(t => <TripCard key={t.id} trip={t} onClick={() => router.push(`/reisen/${t.id}`)} />)}</div></div>
                )}
              </>
            )}
            <AddTripForm onAdded={loadData} />
          </>
        )}
      </div>

      {/* Detail view is now a separate page at /reisen/[id] */}
    </main>
  );
}
