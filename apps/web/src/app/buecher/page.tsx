'use client';

import { useState, useEffect, useCallback } from 'react';
import Link from 'next/link';

interface Book {
  id: number;
  title: string;
  author?: string;
  publisher?: string;
  year?: string;
  category?: string;
  description?: string;
  cover_url?: string;
  isbn?: string;
  language?: string;
  status: 'gesucht' | 'heruntergeladen';
  source_id?: string;
  requested_by?: string;
  requested_at?: string;
  downloaded_at?: string;
  attempts: number;
  last_attempt?: string;
  notes?: string;
  reviews?: string;
  created_at: string;
  updated_at: string;
}

interface SearchResult {
  source_id: string;
  title: string;
  format: string;
  size: string;
  info_url: string;
  content_type: string;
  author: string | null;
  language: string | null;
  publisher: string | null;
  year: string | null;
  preview: string | null;
  description: string | null;
  _raw: any;
}

type StatusFilter = 'alle' | 'gesucht' | 'heruntergeladen';
type ActiveTab = 'wishlist' | 'suche';

function formatDate(dateStr: string) {
  return new Date(dateStr).toLocaleDateString('de-DE', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
  });
}

function langFlag(lang: string | null | undefined): string {
  if (!lang) return '';
  const l = lang.toLowerCase();
  if (l.includes('de')) return '🇩🇪';
  if (l.includes('en')) return '🇬🇧';
  if (l.includes('fr')) return '🇫🇷';
  if (l.includes('es')) return '🇪🇸';
  if (l.includes('it')) return '🇮🇹';
  return '🌐';
}

function formatBadge(format: string | null | undefined): string {
  if (!format) return '';
  const f = format.toLowerCase();
  if (f === 'epub') return '📱 EPUB';
  if (f === 'pdf') return '📄 PDF';
  if (f === 'mobi') return '📖 MOBI';
  if (f === 'azw3') return '📖 AZW3';
  return f.toUpperCase();
}

/* ── Search Result Card (shared between search tab and retry modal) ── */
function SearchResultCard({
  result,
  onDownload,
  onAdd,
  busy,
  hideAdd,
}: {
  result: SearchResult;
  onDownload: (r: SearchResult) => void;
  onAdd?: (r: SearchResult) => void;
  busy: string | null;
  hideAdd?: boolean;
}) {
  const isBusy = busy === result.source_id;

  return (
    <div className="relative overflow-hidden bg-white/70 backdrop-blur-sm rounded-2xl border border-indigo-200/60 shadow-sm transition-all duration-300">
      <div className="flex items-start gap-3 p-4">
        <div className="flex-shrink-0 w-[60px] h-[84px] rounded-lg overflow-hidden bg-gradient-to-br from-indigo-100 to-purple-100 flex items-center justify-center border border-indigo-200/40">
          {result.preview ? (
            <img src={result.preview.startsWith('http') ? result.preview : `https://bookdl.yagemi.synology.me:1443${result.preview}`} alt={result.title} className="w-full h-full object-cover" />
          ) : (
            <span className="text-2xl">📕</span>
          )}
        </div>
        <div className="flex-1 min-w-0">
          <h3 className="text-sm font-bold text-[#1C1C1E] leading-tight line-clamp-2">{result.title}</h3>
          {result.author && <p className="text-xs text-indigo-600 font-medium mt-0.5 truncate">{result.author}</p>}
          <div className="flex flex-wrap gap-1.5 mt-2">
            {result.format && (
              <span className={`text-[11px] font-bold px-2 py-0.5 rounded-full ${result.format === 'epub' ? 'bg-green-100 text-green-700' : 'bg-blue-100 text-blue-700'}`}>
                {formatBadge(result.format)}
              </span>
            )}
            {result.size && <span className="text-[11px] text-[#8E8E93] bg-[#F2F2F7] px-2 py-0.5 rounded-full">💾 {result.size}</span>}
            {result.language && <span className="text-[11px] text-[#8E8E93] bg-[#F2F2F7] px-2 py-0.5 rounded-full">{langFlag(result.language)} {result.language}</span>}
            {result.year && <span className="text-[11px] text-[#8E8E93] bg-[#F2F2F7] px-2 py-0.5 rounded-full">📅 {result.year}</span>}
            {result.publisher && <span className="text-[11px] font-medium bg-purple-50 text-purple-600 px-2 py-0.5 rounded-full truncate max-w-[160px]">{result.publisher}</span>}
          </div>
          {result.content_type && <p className="text-[10px] text-[#C7C7CC] mt-1.5">{result.content_type}</p>}
          <div className="flex gap-2 mt-3">
            <button
              onClick={() => onDownload(result)}
              disabled={isBusy}
              className="flex-1 text-[12px] font-semibold py-2 px-3 rounded-xl bg-gradient-to-r from-green-500 to-emerald-500 text-white shadow-sm hover:shadow-md transition-all active:scale-95 disabled:opacity-50"
            >
              {isBusy ? '⏳ Lädt…' : '📥 Download → Calibre'}
            </button>
            {!hideAdd && onAdd && (
              <button
                onClick={() => onAdd(result)}
                disabled={isBusy}
                className="text-[12px] font-semibold py-2 px-3 rounded-xl bg-amber-100 text-amber-700 hover:bg-amber-200 transition-all active:scale-95 disabled:opacity-50"
              >
                📋 Merken
              </button>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

/* ── Book Card (Wishlist) with Retry ── */
function BookCard({
  book,
  onDelete,
  onRetry,
}: {
  book: Book;
  onDelete: (id: number) => void;
  onRetry: (book: Book) => void;
}) {
  const [deleting, setDeleting] = useState(false);
  const [expanded, setExpanded] = useState(false);

  const handleDelete = async () => {
    if (deleting) return;
    if (!confirm(`"${book.title}" wirklich löschen?`)) return;
    setDeleting(true);
    await onDelete(book.id);
    setDeleting(false);
  };

  return (
    <div className="relative overflow-hidden bg-white/70 backdrop-blur-sm rounded-2xl border border-rose-200/60 shadow-sm transition-all duration-300">
      <div className="flex items-start gap-3 p-4">
        <div className="flex-shrink-0 w-[72px] h-[100px] rounded-xl overflow-hidden bg-gradient-to-br from-rose-100 to-orange-100 flex items-center justify-center border border-rose-200/40">
          {book.cover_url ? (
            <img src={book.cover_url} alt={book.title} className="w-full h-full object-cover" />
          ) : (
            <span className="text-3xl">📚</span>
          )}
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex items-start justify-between gap-2">
            <div className="min-w-0">
              <h3 className="text-sm font-bold text-[#1C1C1E] leading-tight line-clamp-2">{book.title}</h3>
              {book.author && <p className="text-xs text-rose-600 font-medium mt-0.5 truncate">{book.author}</p>}
            </div>
            <span className={`flex-shrink-0 text-[10px] font-bold px-2 py-0.5 rounded-full whitespace-nowrap ${book.status === 'heruntergeladen' ? 'bg-green-100 text-green-700' : 'bg-amber-100 text-amber-700'}`}>
              {book.status === 'heruntergeladen' ? '✅ Geladen' : '🔍 Gesucht'}
            </span>
          </div>
          <div className="flex flex-wrap gap-1.5 mt-2">
            {book.publisher && <span className="text-[11px] font-medium bg-rose-50 text-rose-600 px-2 py-0.5 rounded-full truncate max-w-[140px]">{book.publisher}</span>}
            {book.year && <span className="text-[11px] text-[#8E8E93] bg-[#F2F2F7] px-2 py-0.5 rounded-full">📅 {book.year}</span>}
            {book.language && <span className="text-[11px] text-[#8E8E93] bg-[#F2F2F7] px-2 py-0.5 rounded-full">{langFlag(book.language)} {book.language}</span>}
            {book.category && <span className="text-[11px] font-medium bg-purple-50 text-purple-600 px-2 py-0.5 rounded-full truncate max-w-[120px]">{book.category}</span>}
          </div>
          {book.status === 'gesucht' && book.attempts > 0 && (
            <p className="text-[10px] text-[#8E8E93] mt-1.5">🔄 {book.attempts}× versucht{book.last_attempt && ` · zuletzt ${formatDate(book.last_attempt)}`}</p>
          )}
          {book.description && (
            <div className="mt-2">
              <p className={`text-[11px] text-[#636366] leading-relaxed ${expanded ? '' : 'line-clamp-2'}`}>{book.description}</p>
              {book.description.length > 100 && (
                <button onClick={() => setExpanded(!expanded)} className="text-[11px] text-rose-500 font-medium mt-0.5">{expanded ? 'Weniger ▲' : 'Mehr ▼'}</button>
              )}
            </div>
          )}
          {book.requested_at && (
            <p className="text-[10px] text-[#C7C7CC] mt-1.5">
              Gewünscht am {formatDate(book.requested_at)}
              {book.requested_by && ` von ${book.requested_by}`}
              {book.downloaded_at && ` · Geladen am ${formatDate(book.downloaded_at)}`}
            </p>
          )}
          <div className="flex justify-end gap-2 mt-2">
            {book.status === 'gesucht' && (
              <button
                onClick={() => onRetry(book)}
                className="text-[12px] font-semibold py-1.5 px-3 rounded-xl bg-indigo-100 text-indigo-600 hover:bg-indigo-200 transition-all active:scale-95"
              >
                🔎 Jetzt suchen
              </button>
            )}
            <button onClick={handleDelete} disabled={deleting} className="text-[12px] font-semibold py-1.5 px-3 rounded-xl bg-gray-100 text-gray-500 hover:bg-gray-200 transition-all active:scale-95">
              {deleting ? '⏳' : '🗑️'}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

/* ── Enriched Book Result (from Google Books) ── */
interface EnrichedBook {
  title: string;
  author: string | null;
  publisher: string | null;
  year: string | null;
  description: string | null;
  cover_url: string | null;
  isbn: string | null;
  language: string | null;
  category: string | null;
  page_count: number | null;
}

/* ── Manual Add Form with auto-enrichment ── */
function ManualAddForm({
  prefillTitle,
  onAdded,
}: {
  prefillTitle: string;
  onAdded: (msg: string) => void;
}) {
  const [query, setQuery] = useState(prefillTitle);
  const [enrichResults, setEnrichResults] = useState<EnrichedBook[]>([]);
  const [enriching, setEnriching] = useState(false);
  const [enrichDone, setEnrichDone] = useState(false);
  const [selected, setSelected] = useState<EnrichedBook | null>(null);

  // Manual override fields (only if user wants to edit)
  const [manualNotes, setManualNotes] = useState('');
  const [saving, setSaving] = useState(false);

  // Auto-enrich on mount if prefillTitle is set
  useEffect(() => {
    if (prefillTitle.trim().length >= 2) {
      doEnrich(prefillTitle);
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const doEnrich = async (searchTerm: string) => {
    if (searchTerm.trim().length < 2) return;
    setEnriching(true);
    setEnrichResults([]);
    setEnrichDone(false);
    setSelected(null);
    try {
      const res = await fetch(`/api/buecher/enrich?q=${encodeURIComponent(searchTerm.trim())}`);
      const data = await res.json();
      const results = data.results || [];
      setEnrichResults(results);
      setEnrichDone(true);
      // Auto-select first result
      if (results.length > 0) {
        setSelected(results[0]);
      }
    } catch {
      setEnrichDone(true);
    } finally {
      setEnriching(false);
    }
  };

  const handleSave = async () => {
    const bookData = selected || { title: query.trim(), author: null, publisher: null, year: null, description: null, cover_url: null, isbn: null, language: 'de', category: null };
    if (!bookData.title) return;
    setSaving(true);
    try {
      const res = await fetch('/api/buecher', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          title: bookData.title,
          author: bookData.author || null,
          publisher: bookData.publisher || null,
          year: bookData.year || null,
          category: bookData.category || null,
          description: bookData.description || null,
          cover_url: bookData.cover_url || null,
          isbn: bookData.isbn || null,
          language: bookData.language || 'de',
          notes: manualNotes.trim() || null,
          status: 'gesucht',
          requested_by: 'Manuell',
          requested_at: new Date().toISOString().split('T')[0],
        }),
      });
      const data = await res.json();
      if (data.id || data.success) {
        onAdded(`📋 "${bookData.title}" auf die Wishlist gesetzt! Ole sucht regelmäßig danach.`);
      } else {
        onAdded(`❌ Fehler: ${data.error || 'Unbekannt'}`);
      }
    } catch (err: any) {
      onAdded(`❌ ${err.message}`);
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="bg-white/70 backdrop-blur-sm rounded-2xl border border-amber-200/60 p-4 shadow-sm space-y-3">
      <div className="flex items-center gap-2 mb-1">
        <span className="text-lg">📝</span>
        <h3 className="text-sm font-bold text-[#1C1C1E]">Auf Wishlist setzen</h3>
      </div>
      <p className="text-[11px] text-[#8E8E93]">
        Buch nicht in Shelfmark gefunden? Hier eintragen — Metadaten werden automatisch von Google Books geholt. Ole sucht wöchentlich danach.
      </p>

      {/* Search / Enrich bar */}
      <div className="flex gap-2">
        <input
          type="text"
          value={query}
          onChange={e => setQuery(e.target.value)}
          onKeyDown={e => { if (e.key === 'Enter') { e.preventDefault(); doEnrich(query); } }}
          placeholder="Buchtitel (+ Autor)…"
          className="flex-1 bg-[#F2F2F7] rounded-xl px-4 py-2.5 text-sm text-[#1C1C1E] placeholder:text-[#C7C7CC] outline-none focus:ring-2 focus:ring-amber-400"
        />
        <button
          onClick={() => doEnrich(query)}
          disabled={enriching || query.trim().length < 2}
          className="px-4 py-2.5 bg-amber-500 text-white text-sm font-semibold rounded-xl shadow-sm hover:shadow-md transition-all active:scale-95 disabled:opacity-50"
        >
          {enriching ? '⏳' : '🔍'}
        </button>
      </div>

      {/* Loading */}
      {enriching && (
        <div className="flex items-center justify-center py-4">
          <p className="text-sm text-[#8E8E93]">📚 Suche Buchinfos bei Google Books…</p>
        </div>
      )}

      {/* Enrich results — pick one */}
      {enrichDone && enrichResults.length > 0 && (
        <div className="space-y-2">
          <p className="text-[11px] text-[#8E8E93] font-medium">{enrichResults.length} Treffer — wähle das richtige Buch:</p>
          {enrichResults.map((book, i) => (
            <button
              key={i}
              onClick={() => setSelected(book)}
              className={`w-full text-left flex items-start gap-3 p-3 rounded-xl border transition-all ${
                selected === book
                  ? 'border-amber-400 bg-amber-50 shadow-sm'
                  : 'border-gray-200 bg-white/50 hover:border-amber-300'
              }`}
            >
              <div className="flex-shrink-0 w-[48px] h-[68px] rounded-lg overflow-hidden bg-gradient-to-br from-amber-100 to-orange-100 flex items-center justify-center">
                {book.cover_url ? (
                  <img src={book.cover_url} alt={book.title} className="w-full h-full object-cover" />
                ) : (
                  <span className="text-xl">📕</span>
                )}
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-sm font-bold text-[#1C1C1E] line-clamp-1">{book.title}</p>
                {book.author && <p className="text-xs text-amber-700 truncate">{book.author}</p>}
                <div className="flex flex-wrap gap-1 mt-1">
                  {book.publisher && <span className="text-[10px] bg-gray-100 text-gray-600 px-1.5 py-0.5 rounded-full truncate max-w-[120px]">{book.publisher}</span>}
                  {book.year && <span className="text-[10px] bg-gray-100 text-gray-600 px-1.5 py-0.5 rounded-full">{book.year}</span>}
                  {book.isbn && <span className="text-[10px] bg-gray-100 text-gray-600 px-1.5 py-0.5 rounded-full">ISBN: {book.isbn}</span>}
                  {book.language && <span className="text-[10px] bg-gray-100 text-gray-600 px-1.5 py-0.5 rounded-full">{langFlag(book.language)} {book.language}</span>}
                </div>
                {book.description && <p className="text-[10px] text-[#8E8E93] mt-1 line-clamp-2">{book.description}</p>}
              </div>
              {selected === book && <span className="text-amber-500 text-lg flex-shrink-0 mt-1">✓</span>}
            </button>
          ))}
        </div>
      )}

      {/* No enrichment results */}
      {enrichDone && enrichResults.length === 0 && (
        <div className="text-center py-3">
          <p className="text-sm text-[#8E8E93]">Keine Buchinfos gefunden — wird trotzdem mit Titel gespeichert.</p>
        </div>
      )}

      {/* Selected preview */}
      {selected && (
        <div className="flex items-start gap-3 p-3 bg-green-50 border border-green-200/60 rounded-xl">
          {selected.cover_url && (
            <img src={selected.cover_url} alt="" className="w-[48px] h-[68px] rounded-lg object-cover flex-shrink-0" />
          )}
          <div className="flex-1 min-w-0">
            <p className="text-xs font-bold text-green-800">✅ Wird hinzugefügt:</p>
            <p className="text-sm font-semibold text-[#1C1C1E] line-clamp-1">{selected.title}</p>
            {selected.author && <p className="text-xs text-green-700">{selected.author}</p>}
          </div>
        </div>
      )}

      {/* Notes */}
      <input
        type="text"
        value={manualNotes}
        onChange={e => setManualNotes(e.target.value)}
        placeholder="Notizen (optional)"
        className="w-full bg-[#F2F2F7] rounded-xl px-4 py-2.5 text-sm text-[#1C1C1E] placeholder:text-[#C7C7CC] outline-none focus:ring-2 focus:ring-amber-400"
      />

      {/* Save button */}
      <button
        onClick={handleSave}
        disabled={saving || (!selected && query.trim().length < 2)}
        className="w-full py-2.5 bg-gradient-to-r from-amber-500 to-orange-500 text-white text-sm font-semibold rounded-xl shadow-sm hover:shadow-md transition-all active:scale-95 disabled:opacity-50"
      >
        {saving ? '⏳ Speichern…' : '📋 Auf Wishlist setzen'}
      </button>
    </div>
  );
}

/* ── Retry Modal (search results for a wishlist book) ── */
function RetryModal({
  book,
  results,
  loading,
  busyId,
  onDownload,
  onClose,
}: {
  book: Book;
  results: SearchResult[];
  loading: boolean;
  busyId: string | null;
  onDownload: (bookId: number, r: SearchResult) => void;
  onClose: () => void;
}) {
  return (
    <div className="fixed inset-0 z-50 bg-black/40 backdrop-blur-sm flex items-end sm:items-center justify-center" onClick={onClose}>
      <div
        className="bg-gradient-to-br from-[#FFF5F5] via-[#FFF0EA] to-[#FFF5F5] w-full max-w-lg max-h-[80vh] rounded-t-3xl sm:rounded-3xl overflow-hidden shadow-xl"
        onClick={e => e.stopPropagation()}
      >
        {/* Header */}
        <div className="flex items-center justify-between px-5 pt-5 pb-3 border-b border-rose-200/40">
          <div className="min-w-0 flex-1">
            <h3 className="text-base font-bold text-[#1C1C1E] truncate">🔎 Suche: {book.title}</h3>
            {book.author && <p className="text-xs text-rose-600 truncate">{book.author}</p>}
          </div>
          <button onClick={onClose} className="ml-3 w-8 h-8 flex items-center justify-center rounded-full bg-gray-100 text-gray-500 hover:bg-gray-200 transition">✕</button>
        </div>

        {/* Content */}
        <div className="overflow-y-auto max-h-[calc(80vh-80px)] p-5 space-y-3">
          {loading ? (
            <div className="flex flex-col items-center justify-center py-12">
              <div className="text-3xl animate-spin mb-3">🔎</div>
              <p className="text-[#8E8E93] text-sm font-medium">Suche in Shelfmark…</p>
            </div>
          ) : results.length > 0 ? (
            <>
              <p className="text-xs text-[#8E8E93] font-medium">{results.length} Ergebnis{results.length !== 1 ? 'se' : ''} gefunden</p>
              {results.map((r, i) => (
                <SearchResultCard
                  key={`${r.source_id}-${i}`}
                  result={r}
                  onDownload={(rel) => onDownload(book.id, rel)}
                  busy={busyId}
                  hideAdd
                />
              ))}
            </>
          ) : (
            <div className="flex flex-col items-center justify-center py-12 text-center">
              <div className="text-4xl mb-3">😕</div>
              <h3 className="text-base font-bold text-[#1C1C1E] mb-1">Noch nicht verfügbar</h3>
              <p className="text-[#8E8E93] text-sm max-w-[240px]">
                &quot;{book.title}&quot; ist bei Shelfmark noch nicht vorhanden. Ole sucht weiterhin automatisch.
              </p>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

/* ── Main Page ── */
export default function BuecherPage() {
  const [books, setBooks] = useState<Book[]>([]);
  const [categories, setCategories] = useState<string[]>([]);
  const [years, setYears] = useState<string[]>([]);
  const [loading, setLoading] = useState(true);

  // Wishlist filters
  const [statusFilter, setStatusFilter] = useState<StatusFilter>('alle');
  const [yearFilter, setYearFilter] = useState('');
  const [categoryFilter, setCategoryFilter] = useState('');
  const [searchQuery, setSearchQuery] = useState('');
  const [debouncedQuery, setDebouncedQuery] = useState('');

  // Tab
  const [activeTab, setActiveTab] = useState<ActiveTab>('wishlist');

  // Shelfmark search
  const [shelfmarkQuery, setShelfmarkQuery] = useState('');
  const [searchResults, setSearchResults] = useState<SearchResult[]>([]);
  const [searching, setSearching] = useState(false);
  const [searchError, setSearchError] = useState('');
  const [searchDone, setSearchDone] = useState(false);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [toast, setToast] = useState<{ msg: string; type: 'ok' | 'err' | 'info' } | null>(null);

  // Retry modal
  const [retryBook, setRetryBook] = useState<Book | null>(null);
  const [retryResults, setRetryResults] = useState<SearchResult[]>([]);
  const [retryLoading, setRetryLoading] = useState(false);

  // Toast auto-dismiss
  useEffect(() => {
    if (toast) {
      const t = setTimeout(() => setToast(null), 4000);
      return () => clearTimeout(t);
    }
  }, [toast]);

  // Debounce wishlist search
  useEffect(() => {
    const timer = setTimeout(() => setDebouncedQuery(searchQuery), 300);
    return () => clearTimeout(timer);
  }, [searchQuery]);

  const loadData = useCallback(async () => {
    setLoading(true);
    try {
      const params = new URLSearchParams();
      if (statusFilter !== 'alle') params.set('status', statusFilter);
      if (yearFilter) params.set('year', yearFilter);
      if (categoryFilter) params.set('category', categoryFilter);
      if (debouncedQuery) params.set('q', debouncedQuery);

      const [booksRes, categoriesRes, yearsRes] = await Promise.all([
        fetch(`/api/buecher?${params.toString()}`),
        fetch('/api/buecher?categories=true'),
        fetch('/api/buecher?years=true'),
      ]);

      const [booksData, categoriesData, yearsData] = await Promise.all([
        booksRes.json(),
        categoriesRes.json(),
        yearsRes.json(),
      ]);

      setBooks(booksData);
      setCategories(categoriesData);
      setYears(yearsData);
    } catch (err) {
      console.error('Fehler beim Laden:', err);
    } finally {
      setLoading(false);
    }
  }, [statusFilter, yearFilter, categoryFilter, debouncedQuery]);

  useEffect(() => {
    loadData();
  }, [loadData]);

  const handleDelete = async (id: number) => {
    try {
      const res = await fetch(`/api/buecher/${id}`, { method: 'DELETE' });
      if (res.ok) await loadData();
    } catch (err) {
      console.error('Fehler beim Löschen:', err);
    }
  };

  /* ── Shelfmark Search ── */
  const doSearch = async () => {
    if (!shelfmarkQuery.trim() || shelfmarkQuery.trim().length < 2) return;
    setSearching(true);
    setSearchError('');
    setSearchResults([]);
    setSearchDone(false);
    try {
      const res = await fetch(`/api/buecher/search?q=${encodeURIComponent(shelfmarkQuery.trim())}`);
      const data = await res.json();
      if (!res.ok) {
        setSearchError(data.error || 'Suche fehlgeschlagen');
        return;
      }
      setSearchResults(data.results || []);
      setSearchDone(true);
      if ((data.results || []).length === 0) {
        setSearchError('Keine Ergebnisse in Shelfmark gefunden.');
      }
    } catch (err: any) {
      setSearchError(err.message || 'Netzwerkfehler');
    } finally {
      setSearching(false);
    }
  };

  const handleDownload = async (result: SearchResult) => {
    setBusyId(result.source_id);
    try {
      const res = await fetch('/api/buecher/download', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ release: result, addOnly: false }),
      });
      const data = await res.json();
      if (data.success) {
        setToast({ msg: data.message || `✅ "${result.title}" wird heruntergeladen!`, type: 'ok' });
        await loadData();
      } else {
        setToast({ msg: data.error || 'Download fehlgeschlagen', type: 'err' });
      }
    } catch (err: any) {
      setToast({ msg: err.message || 'Fehler', type: 'err' });
    } finally {
      setBusyId(null);
    }
  };

  const handleAdd = async (result: SearchResult) => {
    setBusyId(result.source_id);
    try {
      const res = await fetch('/api/buecher/download', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ release: result, addOnly: true }),
      });
      const data = await res.json();
      if (data.success) {
        setToast({
          msg: data.duplicate
            ? `ℹ️ "${result.title}" ist bereits in der Wishlist.`
            : `📋 "${result.title}" zur Wishlist hinzugefügt!`,
          type: data.duplicate ? 'info' : 'ok',
        });
        if (!data.duplicate) await loadData();
      } else {
        setToast({ msg: data.error || 'Fehler', type: 'err' });
      }
    } catch (err: any) {
      setToast({ msg: err.message || 'Fehler', type: 'err' });
    } finally {
      setBusyId(null);
    }
  };

  /* ── Retry (ad-hoc search for a wishlist book) ── */
  const handleRetry = async (book: Book) => {
    setRetryBook(book);
    setRetryResults([]);
    setRetryLoading(true);
    try {
      const res = await fetch('/api/buecher/retry', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ bookId: book.id }),
      });
      const data = await res.json();
      setRetryResults(data.results || []);
      await loadData(); // Refresh attempt counter
    } catch (err: any) {
      setToast({ msg: err.message || 'Suche fehlgeschlagen', type: 'err' });
      setRetryBook(null);
    } finally {
      setRetryLoading(false);
    }
  };

  const handleRetryDownload = async (bookId: number, result: SearchResult) => {
    setBusyId(result.source_id);
    try {
      const res = await fetch('/api/buecher/retry', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ bookId, release: result }),
      });
      const data = await res.json();
      if (data.success) {
        setToast({ msg: data.message || '📥 Download gestartet!', type: 'ok' });
        setRetryBook(null);
        await loadData();
      } else {
        setToast({ msg: data.error || 'Download fehlgeschlagen', type: 'err' });
      }
    } catch (err: any) {
      setToast({ msg: err.message || 'Fehler', type: 'err' });
    } finally {
      setBusyId(null);
    }
  };

  const totalCount = books.length;
  const gesuchtCount = books.filter(b => b.status === 'gesucht').length;
  const geladenCount = books.filter(b => b.status === 'heruntergeladen').length;

  return (
    <main className="min-h-screen bg-gradient-to-br from-[#FFF5F5] via-[#FFF0EA] to-[#FFF5F5]">
      {/* ── Toast ── */}
      {toast && (
        <div className={`fixed top-4 left-1/2 -translate-x-1/2 z-50 max-w-sm w-[90%] px-4 py-3 rounded-2xl shadow-lg text-sm font-semibold text-center transition-all ${
          toast.type === 'ok' ? 'bg-green-500 text-white' :
          toast.type === 'err' ? 'bg-red-500 text-white' :
          'bg-blue-500 text-white'
        }`}>
          {toast.msg}
        </div>
      )}

      {/* ── Retry Modal ── */}
      {retryBook && (
        <RetryModal
          book={retryBook}
          results={retryResults}
          loading={retryLoading}
          busyId={busyId}
          onDownload={handleRetryDownload}
          onClose={() => setRetryBook(null)}
        />
      )}

      {/* ── Header ── */}
      <header className="pt-12 pb-4 px-5 safe-area-inset">
        <div className="max-w-2xl mx-auto">
          <div className="flex items-center gap-3 mb-4">
            <Link href="/" className="flex items-center justify-center w-10 h-10 bg-white/70 backdrop-blur-sm rounded-2xl border border-rose-200/50 shadow-sm hover:bg-white transition active:scale-95">
              <svg className="w-5 h-5 text-rose-600" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2.5}>
                <path strokeLinecap="round" strokeLinejoin="round" d="M15 19l-7-7 7-7" />
              </svg>
            </Link>
            <div>
              <h1 className="text-3xl font-extrabold text-[#1C1C1E] tracking-tight leading-tight">📚 Elitas Bücher</h1>
              <p className="text-rose-600/80 text-sm font-medium mt-0.5">Wishlist · Suche · Downloads</p>
            </div>
          </div>

          {/* Stats pills */}
          <div className="flex gap-2 flex-wrap">
            <div className="flex items-center gap-1.5 bg-rose-100 text-rose-700 px-3 py-1.5 rounded-full text-sm font-semibold">
              <span>📚</span><span>{totalCount} gesamt</span>
            </div>
            <div className="flex items-center gap-1.5 bg-amber-100 text-amber-700 px-3 py-1.5 rounded-full text-sm font-semibold">
              <span>🔍</span><span>{gesuchtCount} gesucht</span>
            </div>
            <div className="flex items-center gap-1.5 bg-green-100 text-green-700 px-3 py-1.5 rounded-full text-sm font-semibold">
              <span>✅</span><span>{geladenCount} geladen</span>
            </div>
          </div>
        </div>
      </header>

      {/* ── Tab Switcher ── */}
      <div className="max-w-2xl mx-auto px-5 mb-4">
        <div className="flex bg-white/60 backdrop-blur-sm rounded-2xl border border-rose-200/40 p-1 shadow-sm">
          <button
            onClick={() => setActiveTab('wishlist')}
            className={`flex-1 py-2.5 px-4 rounded-xl text-sm font-semibold transition-all ${
              activeTab === 'wishlist' ? 'bg-rose-500 text-white shadow-sm' : 'text-[#8E8E93] hover:text-[#636366]'
            }`}
          >
            📋 Wishlist
          </button>
          <button
            onClick={() => setActiveTab('suche')}
            className={`flex-1 py-2.5 px-4 rounded-xl text-sm font-semibold transition-all ${
              activeTab === 'suche' ? 'bg-indigo-500 text-white shadow-sm' : 'text-[#8E8E93] hover:text-[#636366]'
            }`}
          >
            🔎 Buch suchen
          </button>
        </div>
      </div>

      {/* ── WISHLIST TAB ── */}
      {activeTab === 'wishlist' && (
        <>
          <div className="max-w-2xl mx-auto px-5 mb-4">
            <div className="bg-white/60 backdrop-blur-sm rounded-2xl border border-rose-200/40 p-4 shadow-sm space-y-3">
              <div className="relative">
                <span className="absolute left-3 top-1/2 -translate-y-1/2 text-[#C7C7CC]">🔎</span>
                <input type="text" value={searchQuery} onChange={e => setSearchQuery(e.target.value)} placeholder="In Wishlist suchen…" className="w-full bg-[#F2F2F7] rounded-xl pl-10 pr-4 py-2.5 text-sm text-[#1C1C1E] placeholder:text-[#C7C7CC] outline-none focus:ring-2 focus:ring-rose-400" />
              </div>
              <div className="flex gap-2">
                {(['alle', 'gesucht', 'heruntergeladen'] as StatusFilter[]).map(s => (
                  <button key={s} onClick={() => setStatusFilter(s)} className={`flex-1 text-xs font-semibold py-2 px-3 rounded-xl transition-all ${statusFilter === s ? (s === 'alle' ? 'bg-rose-500 text-white shadow-sm' : s === 'gesucht' ? 'bg-amber-500 text-white shadow-sm' : 'bg-green-500 text-white shadow-sm') : 'bg-[#F2F2F7] text-[#8E8E93] hover:bg-[#E5E5EA]'}`}>
                    {s === 'alle' ? '📚 Alle' : s === 'gesucht' ? '🔍 Gesucht' : '✅ Geladen'}
                  </button>
                ))}
              </div>
              <div className="flex gap-2">
                <select value={yearFilter} onChange={e => setYearFilter(e.target.value)} className="flex-1 bg-[#F2F2F7] rounded-xl px-3 py-2 text-sm text-[#1C1C1E] outline-none focus:ring-2 focus:ring-rose-400">
                  <option value="">Alle Jahre</option>
                  {years.map(y => <option key={y} value={y}>{y}</option>)}
                </select>
                <select value={categoryFilter} onChange={e => setCategoryFilter(e.target.value)} className="flex-1 bg-[#F2F2F7] rounded-xl px-3 py-2 text-sm text-[#1C1C1E] outline-none focus:ring-2 focus:ring-rose-400">
                  <option value="">Alle Kategorien</option>
                  {categories.map(c => <option key={c} value={c}>{c}</option>)}
                </select>
                {(yearFilter || categoryFilter || searchQuery) && (
                  <button onClick={() => { setYearFilter(''); setCategoryFilter(''); setSearchQuery(''); }} className="px-3 py-2 bg-[#F2F2F7] rounded-xl text-sm text-[#8E8E93] hover:bg-[#E5E5EA] transition">✕</button>
                )}
              </div>
            </div>
          </div>

          <div className="max-w-2xl mx-auto px-5 pb-16">
            {loading ? (
              <div className="flex flex-col items-center justify-center py-16">
                <div className="text-4xl animate-bounce mb-3">📚</div>
                <p className="text-[#8E8E93] font-medium">Lade Bücher…</p>
              </div>
            ) : books.length === 0 ? (
              <div className="flex flex-col items-center justify-center py-16 text-center">
                <div className="text-6xl mb-4">📖</div>
                <h3 className="text-xl font-bold text-[#1C1C1E] mb-2">Keine Bücher gefunden</h3>
                <p className="text-[#8E8E93] text-sm max-w-[220px]">{searchQuery || statusFilter !== 'alle' || yearFilter || categoryFilter ? 'Versuche andere Filter.' : 'Die Wishlist ist noch leer.'}</p>
              </div>
            ) : (
              <div className="space-y-3">
                {books.map(b => <BookCard key={b.id} book={b} onDelete={handleDelete} onRetry={handleRetry} />)}
              </div>
            )}
          </div>
        </>
      )}

      {/* ── SEARCH TAB ── */}
      {activeTab === 'suche' && (
        <div className="max-w-2xl mx-auto px-5 pb-16">
          {/* Search Input */}
          <div className="bg-white/60 backdrop-blur-sm rounded-2xl border border-indigo-200/40 p-4 shadow-sm mb-4">
            <p className="text-xs text-[#8E8E93] mb-3">
              Suche in der Shelfmark-Bibliothek nach Büchern zum Herunterladen. Tipp: Englische Titel liefern oft mehr Ergebnisse.
            </p>
            <form onSubmit={e => { e.preventDefault(); doSearch(); }} className="flex gap-2">
              <div className="relative flex-1">
                <span className="absolute left-3 top-1/2 -translate-y-1/2 text-indigo-400">📖</span>
                <input type="text" value={shelfmarkQuery} onChange={e => setShelfmarkQuery(e.target.value)} placeholder="Titel, Autor oder ISBN…" className="w-full bg-[#F2F2F7] rounded-xl pl-10 pr-4 py-2.5 text-sm text-[#1C1C1E] placeholder:text-[#C7C7CC] outline-none focus:ring-2 focus:ring-indigo-400" autoFocus />
              </div>
              <button type="submit" disabled={searching || shelfmarkQuery.trim().length < 2} className="px-5 py-2.5 bg-gradient-to-r from-indigo-500 to-purple-500 text-white text-sm font-semibold rounded-xl shadow-sm hover:shadow-md transition-all active:scale-95 disabled:opacity-50">
                {searching ? '⏳' : '🔎'}
              </button>
            </form>
          </div>

          {/* Search Error */}
          {searchError && !searching && (
            <div className="bg-amber-50 border border-amber-200/60 rounded-2xl p-4 mb-4 text-sm text-amber-700">
              {searchError}
            </div>
          )}

          {/* Search Results */}
          {searching ? (
            <div className="flex flex-col items-center justify-center py-16">
              <div className="text-4xl animate-spin mb-3">🔎</div>
              <p className="text-[#8E8E93] font-medium">Suche in Shelfmark…</p>
            </div>
          ) : searchResults.length > 0 ? (
            <>
              <p className="text-xs text-[#8E8E93] font-medium mb-3 px-1">
                {searchResults.length} Ergebnis{searchResults.length !== 1 ? 'se' : ''} für &quot;{shelfmarkQuery}&quot;
              </p>
              <div className="space-y-3">
                {searchResults.map((r, i) => (
                  <SearchResultCard key={`${r.source_id}-${i}`} result={r} onDownload={handleDownload} onAdd={handleAdd} busy={busyId} />
                ))}
              </div>
            </>
          ) : searchDone && searchResults.length === 0 ? (
            /* No results → show manual add form */
            <div className="space-y-4">
              <div className="flex flex-col items-center justify-center py-8 text-center">
                <div className="text-4xl mb-3">🤷</div>
                <h3 className="text-base font-bold text-[#1C1C1E] mb-1">Nicht in Shelfmark gefunden</h3>
                <p className="text-[#8E8E93] text-sm max-w-[280px]">
                  Setz das Buch auf die Wishlist — Ole sucht automatisch wöchentlich danach!
                </p>
              </div>
              <ManualAddForm
                prefillTitle={shelfmarkQuery}
                onAdded={(msg) => {
                  setToast({ msg, type: msg.startsWith('❌') ? 'err' : 'ok' });
                  if (!msg.startsWith('❌')) {
                    loadData();
                    setSearchDone(false);
                    setSearchResults([]);
                    setShelfmarkQuery('');
                  }
                }}
              />
            </div>
          ) : (
            <div className="flex flex-col items-center justify-center py-16 text-center">
              <div className="text-5xl mb-4">📚</div>
              <h3 className="text-lg font-bold text-[#1C1C1E] mb-2">Buch suchen & hinzufügen</h3>
              <p className="text-[#8E8E93] text-sm max-w-[280px]">
                Gib einen Buchtitel oder Autornamen ein und suche in der Shelfmark-Bibliothek. Du kannst direkt herunterladen oder zur Wishlist hinzufügen.
              </p>
            </div>
          )}
        </div>
      )}
    </main>
  );
}
