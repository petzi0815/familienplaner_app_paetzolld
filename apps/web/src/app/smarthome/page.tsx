'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';

interface Entity {
  entity_id: string;
  friendly_name: string;
  domain: string;
  state: string;
  area_name: string | null;
  disabled: boolean;
  usage_count?: number;
}

interface Alias {
  id: number;
  entity_id: string;
  alias: string;
}

interface Stats {
  totalEntities: number;
  totalRelationships: number;
  totalAreas: number;
  totalGroups: number;
  byDomain: { domain: string; count: number }[];
}

export default function SmartHome() {
  const [entities, setEntities] = useState<Entity[]>([]);
  const [stats, setStats] = useState<Stats | null>(null);
  const [filter, setFilter] = useState<string>('');
  const [domainFilter, setDomainFilter] = useState<string>('');
  const [areaFilter, setAreaFilter] = useState<string>('all');
  const [disabledFilter, setDisabledFilter] = useState<string>('0'); // '0' = active, '1' = disabled, 'all' = all
  const [sortBy, setSortBy] = useState<string>('name'); // 'name', 'domain', 'usage'
  const [loading, setLoading] = useState(true);
  const [aliases, setAliases] = useState<Record<string, string[]>>({});
  const [editingAlias, setEditingAlias] = useState<string | null>(null);
  const [newAlias, setNewAlias] = useState<string>('');
  const [showPrompt, setShowPrompt] = useState(false);
  const [prompt, setPrompt] = useState<string>('');
  const [promptLoading, setPromptLoading] = useState(false);
  const [copied, setCopied] = useState(false);
  const [availableAreas, setAvailableAreas] = useState<string[]>([]);

  useEffect(() => {
    loadData();
  }, [domainFilter, areaFilter, disabledFilter, sortBy]);

  async function loadData() {
    setLoading(true);
    try {
      // Build query params
      const params = new URLSearchParams();
      if (domainFilter) params.set('domain', domainFilter);
      if (areaFilter !== 'all') params.set('area', areaFilter);
      if (disabledFilter !== 'all') params.set('disabled', disabledFilter);
      params.set('sort', sortBy);

      const [entitiesRes, statsRes, aliasesRes] = await Promise.all([
        fetch(`/api/smarthome/entities?${params}`),
        fetch('/api/smarthome/stats'),
        fetch('/api/smarthome/aliases')
      ]);

      const entitiesData = await entitiesRes.json();
      const statsData = await statsRes.json();
      const aliasesData = await aliasesRes.json();

      setEntities(entitiesData.entities || []);
      setStats(statsData);

      // Group aliases by entity_id
      const aliasMap: Record<string, string[]> = {};
      (aliasesData.aliases || []).forEach((a: Alias) => {
        if (!aliasMap[a.entity_id]) aliasMap[a.entity_id] = [];
        aliasMap[a.entity_id].push(a.alias);
      });
      setAliases(aliasMap);

      // Extract available areas
      const areasSet = new Set<string>();
      entitiesData.entities.forEach((e: Entity) => {
        if (e.area_name) areasSet.add(e.area_name);
      });
      setAvailableAreas(Array.from(areasSet).sort());
    } catch (err) {
      console.error('Failed to load data:', err);
    } finally {
      setLoading(false);
    }
  }

  async function toggleDisabled(entityId: string) {
    try {
      await fetch('/api/smarthome/entities/toggle-disabled', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ entity_id: entityId })
      });
      loadData();
    } catch (err) {
      console.error('Failed to toggle disabled:', err);
    }
  }

  async function addAlias(entityId: string) {
    if (!newAlias.trim()) return;
    try {
      await fetch('/api/smarthome/aliases', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ entity_id: entityId, alias: newAlias.trim() })
      });
      setNewAlias('');
      setEditingAlias(null);
      loadData();
    } catch (err) {
      console.error('Failed to add alias:', err);
    }
  }

  async function removeAlias(entityId: string, alias: string) {
    try {
      await fetch(`/api/smarthome/aliases?entity_id=${entityId}&alias=${encodeURIComponent(alias)}`, {
        method: 'DELETE'
      });
      loadData();
    } catch (err) {
      console.error('Failed to remove alias:', err);
    }
  }

  async function loadPrompt() {
    setPromptLoading(true);
    try {
      const res = await fetch('/api/smarthome/prompt');
      const data = await res.json();
      setPrompt(data.prompt);
    } catch (err) {
      console.error('Failed to load prompt:', err);
    } finally {
      setPromptLoading(false);
    }
  }

  async function copyPrompt() {
    try {
      await navigator.clipboard.writeText(prompt);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch (err) {
      console.error('Failed to copy:', err);
    }
  }

  function togglePrompt() {
    setShowPrompt(!showPrompt);
    if (!showPrompt && !prompt) {
      loadPrompt();
    }
  }

  // Separate groups from regular entities
  const groups = entities.filter(e => e.domain === 'group');
  const regularEntities = entities.filter(e => e.domain !== 'group');

  const groupedByArea = regularEntities.reduce((acc, entity) => {
    const area = entity.area_name || 'Ohne Raum';
    if (!acc[area]) acc[area] = [];
    acc[area].push(entity);
    return acc;
  }, {} as Record<string, Entity[]>);

  const filteredAreas = Object.entries(groupedByArea).filter(([area, entities]) => {
    if (!filter) return true;
    return area.toLowerCase().includes(filter.toLowerCase()) ||
           entities.some(e => e.friendly_name.toLowerCase().includes(filter.toLowerCase()));
  });

  const getStateColor = (state: string) => {
    switch (state) {
      case 'on': return 'bg-green-500';
      case 'off': return 'bg-gray-400';
      case 'unavailable': return 'bg-red-500';
      default: return 'bg-blue-500';
    }
  };

  const getDomainIcon = (domain: string) => {
    switch (domain) {
      case 'light': return '💡';
      case 'switch': return '🔌';
      case 'sensor': return '📊';
      case 'climate': return '🌡️';
      case 'cover': return '🪟';
      case 'lock': return '🔒';
      case 'media_player': return '📺';
      default: return '⚙️';
    }
  };

  return (
    <main className="min-h-screen bg-gradient-to-br from-[#F2F2F7] via-[#E5E5EA] to-[#F2F2F7]">
      {/* Header */}
      <header className="pt-14 pb-6 px-5 safe-area-inset">
        <div className="max-w-5xl mx-auto">
          <Link href="/" className="inline-flex items-center text-[#007AFF] text-sm font-semibold mb-4 hover:underline">
            ← Zurück
          </Link>
          <h1 className="text-4xl font-extrabold text-[#1C1C1E] tracking-tight mb-2">
            Smart Home
          </h1>
          <p className="text-[#8E8E93] text-base font-medium">
            Home Assistant Übersicht
          </p>
        </div>
      </header>

      {/* Stats Cards */}
      {stats && (
        <div className="max-w-5xl mx-auto px-5 mb-6">
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
            <div className="bg-white rounded-2xl p-4 shadow-sm border border-black/5">
              <div className="text-2xl font-bold text-[#007AFF]">{stats.totalEntities}</div>
              <div className="text-xs text-[#8E8E93] font-medium mt-1">Entities</div>
            </div>
            <div className="bg-white rounded-2xl p-4 shadow-sm border border-black/5">
              <div className="text-2xl font-bold text-[#34C759]">{stats.totalAreas}</div>
              <div className="text-xs text-[#8E8E93] font-medium mt-1">Räume</div>
            </div>
            <div className="bg-white rounded-2xl p-4 shadow-sm border border-black/5">
              <div className="text-2xl font-bold text-[#AF52DE]">{stats.totalGroups}</div>
              <div className="text-xs text-[#8E8E93] font-medium mt-1">Gruppen</div>
            </div>
            <div className="bg-white rounded-2xl p-4 shadow-sm border border-black/5">
              <div className="text-2xl font-bold text-[#FF9F0A]">{stats.byDomain[0]?.count || 0}</div>
              <div className="text-xs text-[#8E8E93] font-medium mt-1">{stats.byDomain[0]?.domain || 'N/A'}</div>
            </div>
          </div>
        </div>
      )}

      {/* Navigation */}
      <div className="max-w-5xl mx-auto px-5 mb-6">
        <div className="flex gap-3 flex-wrap">
          <Link href="/smarthome/log" className="px-4 py-2 bg-white rounded-xl text-sm font-semibold text-[#007AFF] shadow-sm border border-black/5 hover:bg-[#007AFF] hover:text-white transition">
            📋 Command Log
          </Link>
          <Link href="/smarthome/relations" className="px-4 py-2 bg-white rounded-xl text-sm font-semibold text-[#007AFF] shadow-sm border border-black/5 hover:bg-[#007AFF] hover:text-white transition">
            🔗 Beziehungen
          </Link>
          <button
            onClick={togglePrompt}
            className="px-4 py-2 bg-white rounded-xl text-sm font-semibold text-[#007AFF] shadow-sm border border-black/5 hover:bg-[#007AFF] hover:text-white transition"
          >
            🤖 System Prompt
          </button>
        </div>
      </div>

      {/* System Prompt Section */}
      {showPrompt && (
        <div className="max-w-5xl mx-auto px-5 mb-6">
          <div className="bg-white rounded-3xl shadow-lg border border-black/5 overflow-hidden">
            <div className="bg-gradient-to-r from-[#5856D6]/10 to-[#AF52DE]/10 px-6 py-4 border-b border-black/5">
              <div className="flex items-center justify-between">
                <div>
                  <h2 className="text-xl font-bold text-[#1C1C1E]">🤖 System Prompt für Home Assistant</h2>
                  <p className="text-xs text-[#8E8E93] font-medium mt-1">
                    Kopiere diesen Prompt in die OpenClaw Conversation Integration
                  </p>
                </div>
                <button
                  onClick={copyPrompt}
                  className={`px-4 py-2 rounded-xl text-sm font-semibold transition ${
                    copied
                      ? 'bg-green-100 text-green-700'
                      : 'bg-[#007AFF] text-white hover:bg-[#0051D5]'
                  }`}
                >
                  {copied ? '✓ Kopiert!' : '📋 Kopieren'}
                </button>
              </div>
            </div>
            <div className="p-6">
              {promptLoading ? (
                <div className="text-center py-10 text-[#8E8E93]">Generiere Prompt...</div>
              ) : (
                <pre className="bg-[#F2F2F7] rounded-xl p-4 text-xs font-mono overflow-x-auto whitespace-pre-wrap break-words text-[#1C1C1E] leading-relaxed">
                  {prompt}
                </pre>
              )}
            </div>
          </div>
        </div>
      )}

      {/* Filters */}
      <div className="max-w-5xl mx-auto px-5 mb-6">
        <div className="bg-white rounded-2xl p-4 shadow-sm border border-black/5 space-y-3">
          {/* Search */}
          <input
            type="text"
            placeholder="Suche..."
            value={filter}
            onChange={(e) => setFilter(e.target.value)}
            className="w-full px-4 py-2 bg-[#F2F2F7] rounded-xl text-sm font-medium outline-none focus:ring-2 focus:ring-[#007AFF]"
          />

          {/* Filters Row */}
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">
            {/* Area Filter */}
            <select
              value={areaFilter}
              onChange={(e) => setAreaFilter(e.target.value)}
              className="px-4 py-2 bg-[#F2F2F7] rounded-xl text-sm font-medium outline-none focus:ring-2 focus:ring-[#007AFF]"
            >
              <option value="all">Alle Räume</option>
              {availableAreas.map((area) => (
                <option key={area} value={area}>
                  {area}
                </option>
              ))}
              <option value="">Ohne Raum</option>
            </select>

            {/* Domain Filter */}
            <select
              value={domainFilter}
              onChange={(e) => setDomainFilter(e.target.value)}
              className="px-4 py-2 bg-[#F2F2F7] rounded-xl text-sm font-medium outline-none focus:ring-2 focus:ring-[#007AFF]"
            >
              <option value="">Alle Domains</option>
              {stats?.byDomain.map((d) => (
                <option key={d.domain} value={d.domain}>
                  {d.domain} ({d.count})
                </option>
              ))}
            </select>

            {/* Status Filter */}
            <select
              value={disabledFilter}
              onChange={(e) => setDisabledFilter(e.target.value)}
              className="px-4 py-2 bg-[#F2F2F7] rounded-xl text-sm font-medium outline-none focus:ring-2 focus:ring-[#007AFF]"
            >
              <option value="0">✓ Aktive</option>
              <option value="1">⊗ Deaktivierte</option>
              <option value="all">Alle Status</option>
            </select>

            {/* Sort */}
            <select
              value={sortBy}
              onChange={(e) => setSortBy(e.target.value)}
              className="px-4 py-2 bg-[#F2F2F7] rounded-xl text-sm font-medium outline-none focus:ring-2 focus:ring-[#007AFF]"
            >
              <option value="name">Sort: Name</option>
              <option value="domain">Sort: Domain</option>
              <option value="usage">Sort: Häufig geschaltet</option>
            </select>
          </div>
        </div>
      </div>

      {/* Groups Section */}
      {groups.length > 0 && (
        <div className="max-w-5xl mx-auto px-5 mb-6">
          <h2 className="text-2xl font-bold text-[#1C1C1E] mb-4">📦 Gruppen</h2>
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
            {groups.map((group) => (
              <div
                key={group.entity_id}
                className="bg-gradient-to-br from-purple-50 to-blue-50 rounded-2xl p-4 border-2 border-purple-200 shadow-sm"
              >
                <div className="flex items-center justify-between mb-3">
                  <div className="text-lg font-bold text-purple-900">{group.friendly_name}</div>
                  <div className={`w-4 h-4 rounded-full ${getStateColor(group.state)}`} />
                </div>
                <div className="text-xs text-purple-600 mb-2">{group.entity_id}</div>
                <div className="text-xs text-purple-700 font-semibold">
                  {group.state === 'on' ? '✓ Aktiv' : '○ Inaktiv'}
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Entities by Area */}
      <div className="max-w-5xl mx-auto px-5 pb-10">
        {loading ? (
          <div className="text-center py-10 text-[#8E8E93]">Lädt...</div>
        ) : (
          <div className="space-y-6">
            {filteredAreas.map(([area, areaEntities]) => (
              <div key={area} className="bg-white rounded-3xl shadow-lg border border-black/5 overflow-hidden">
                <div className="bg-gradient-to-r from-[#007AFF]/10 to-[#5856D6]/10 px-6 py-4 border-b border-black/5">
                  <h2 className="text-xl font-bold text-[#1C1C1E]">{area}</h2>
                  <p className="text-xs text-[#8E8E93] font-medium mt-1">{areaEntities.length} Geräte</p>
                </div>
                <div className="p-4 space-y-2">
                  {areaEntities.map((entity) => (
                    <div
                      key={entity.entity_id}
                      className={`p-3 bg-[#F2F2F7] rounded-xl hover:bg-[#E5E5EA] transition ${entity.disabled ? 'opacity-50' : ''}`}
                    >
                      <div className="flex items-center gap-3">
                        <div className="text-2xl">{getDomainIcon(entity.domain)}</div>
                        <div className="flex-1 min-w-0">
                          <div className="font-semibold text-sm text-[#1C1C1E] truncate">
                            {entity.friendly_name}
                            {entity.disabled && <span className="ml-2 text-xs text-red-600">(deaktiviert)</span>}
                            {entity.usage_count !== undefined && entity.usage_count > 0 && (
                              <span className="ml-2 px-2 py-0.5 bg-orange-100 text-orange-700 rounded-lg text-xs font-bold">
                                {entity.usage_count}× geschaltet
                              </span>
                            )}
                          </div>
                          <div className="text-xs text-[#8E8E93] truncate">
                            {entity.entity_id}
                          </div>
                          {aliases[entity.entity_id] && aliases[entity.entity_id].length > 0 && (
                            <div className="mt-1 flex flex-wrap gap-1">
                              {aliases[entity.entity_id].map((alias) => (
                                <span key={alias} className="inline-flex items-center gap-1 px-2 py-0.5 bg-blue-100 text-blue-700 rounded-lg text-xs">
                                  🏷️ {alias}
                                  <button
                                    onClick={() => removeAlias(entity.entity_id, alias)}
                                    className="text-blue-900 hover:text-red-600"
                                  >
                                    ×
                                  </button>
                                </span>
                              ))}
                            </div>
                          )}
                        </div>
                        <div className="flex items-center gap-2">
                          <div className={`w-3 h-3 rounded-full ${getStateColor(entity.state)}`} />
                          <span className="text-xs font-semibold text-[#8E8E93] uppercase">
                            {entity.state}
                          </span>
                        </div>
                      </div>

                      {/* Action Buttons */}
                      <div className="mt-3 flex gap-2 flex-wrap">
                        <button
                          onClick={() => toggleDisabled(entity.entity_id)}
                          className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition ${
                            entity.disabled
                              ? 'bg-green-100 text-green-700 hover:bg-green-200'
                              : 'bg-red-100 text-red-700 hover:bg-red-200'
                          }`}
                        >
                          {entity.disabled ? '✓ Aktivieren' : '⊗ Deaktivieren'}
                        </button>

                        {editingAlias === entity.entity_id ? (
                          <>
                            <input
                              type="text"
                              value={newAlias}
                              onChange={(e) => setNewAlias(e.target.value)}
                              placeholder="Neuer Alias..."
                              className="flex-1 min-w-[120px] px-3 py-1.5 bg-white rounded-lg text-xs outline-none focus:ring-2 focus:ring-blue-500"
                              onKeyPress={(e) => e.key === 'Enter' && addAlias(entity.entity_id)}
                            />
                            <button
                              onClick={() => addAlias(entity.entity_id)}
                              className="px-3 py-1.5 bg-blue-500 text-white rounded-lg text-xs font-semibold hover:bg-blue-600"
                            >
                              ✓
                            </button>
                            <button
                              onClick={() => { setEditingAlias(null); setNewAlias(''); }}
                              className="px-3 py-1.5 bg-gray-300 text-gray-700 rounded-lg text-xs font-semibold hover:bg-gray-400"
                            >
                              ✕
                            </button>
                          </>
                        ) : (
                          <button
                            onClick={() => setEditingAlias(entity.entity_id)}
                            className="px-3 py-1.5 bg-blue-100 text-blue-700 rounded-lg text-xs font-semibold hover:bg-blue-200"
                          >
                            + Alias
                          </button>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </main>
  );
}
