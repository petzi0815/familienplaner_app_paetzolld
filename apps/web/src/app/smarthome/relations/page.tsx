'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';

interface Relationship {
  id: number;
  parent_entity_id: string;
  child_entity_id: string;
  parent_name: string | null;
  parent_state: string | null;
  parent_domain: string | null;
  child_name: string | null;
  type: string;
  auto_discovered: boolean;
  manually_verified: boolean;
}

interface Entity {
  entity_id: string;
  friendly_name: string;
}

interface GroupData {
  parent_entity_id: string;
  parent_name: string | null;
  parent_state: string | null;
  parent_domain: string | null;
  children: {
    child_entity_id: string;
    child_name: string | null;
    relationship_id: number;
  }[];
  auto_discovered: boolean;
  manually_verified: boolean;
  type: string;
}

export default function RelationsPage() {
  const [relationships, setRelationships] = useState<Relationship[]>([]);
  const [loading, setLoading] = useState(true);
  const [typeFilter, setTypeFilter] = useState<string>('all'); // 'all', 'auto', 'manual'
  const [searchTerm, setSearchTerm] = useState<string>('');
  const [sortBy, setSortBy] = useState<string>('name'); // 'name', 'members'
  const [showAddModal, setShowAddModal] = useState(false);
  const [entities, setEntities] = useState<Entity[]>([]);
  const [newRel, setNewRel] = useState({ parent: '', child: '', type: 'group_member' });

  useEffect(() => {
    loadRelationships();
    loadEntities();
  }, [typeFilter]);

  async function loadRelationships() {
    setLoading(true);
    try {
      const params = new URLSearchParams();
      if (typeFilter !== 'all') params.set('type', typeFilter);
      
      const res = await fetch(`/api/smarthome/relationships?${params}`);
      const data = await res.json();
      setRelationships(data.relationships || []);
    } catch (err) {
      console.error('Failed to load relationships:', err);
    } finally {
      setLoading(false);
    }
  }

  async function loadEntities() {
    try {
      const res = await fetch('/api/smarthome/entities');
      const data = await res.json();
      setEntities(data.entities || []);
    } catch (err) {
      console.error('Failed to load entities:', err);
    }
  }

  async function addRelationship() {
    if (!newRel.parent || !newRel.child || !newRel.type) {
      alert('Bitte alle Felder ausfüllen');
      return;
    }
    try {
      await fetch('/api/smarthome/relationships', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          parent_entity_id: newRel.parent,
          child_entity_id: newRel.child,
          type: newRel.type
        })
      });
      setShowAddModal(false);
      setNewRel({ parent: '', child: '', type: 'group_member' });
      loadRelationships();
    } catch (err) {
      console.error('Failed to add relationship:', err);
    }
  }

  async function deleteRelationship(id: number) {
    if (!confirm('Beziehung wirklich löschen?')) return;
    try {
      await fetch(`/api/smarthome/relationships?id=${id}`, { method: 'DELETE' });
      loadRelationships();
    } catch (err) {
      console.error('Failed to delete relationship:', err);
    }
  }

  async function toggleVerified(id: number, currentState: boolean) {
    try {
      await fetch(`/api/smarthome/relationships?id=${id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ manually_verified: !currentState })
      });
      loadRelationships();
    } catch (err) {
      console.error('Failed to toggle verified:', err);
    }
  }

  // Group relationships by parent entity
  const groupedRelations: GroupData[] = [];
  const parentMap = new Map<string, GroupData>();

  relationships.forEach((rel) => {
    if (!parentMap.has(rel.parent_entity_id)) {
      parentMap.set(rel.parent_entity_id, {
        parent_entity_id: rel.parent_entity_id,
        parent_name: rel.parent_name,
        parent_state: rel.parent_state,
        parent_domain: rel.parent_domain,
        children: [],
        auto_discovered: rel.auto_discovered,
        manually_verified: rel.manually_verified,
        type: rel.type
      });
    }
    const group = parentMap.get(rel.parent_entity_id)!;
    group.children.push({
      child_entity_id: rel.child_entity_id,
      child_name: rel.child_name,
      relationship_id: rel.id
    });
  });

  groupedRelations.push(...Array.from(parentMap.values()));

  // Filter by search term
  const filteredGroups = groupedRelations.filter((group) => {
    if (!searchTerm) return true;
    const term = searchTerm.toLowerCase();
    return (
      group.parent_name?.toLowerCase().includes(term) ||
      group.parent_entity_id.toLowerCase().includes(term) ||
      group.children.some(c => 
        c.child_name?.toLowerCase().includes(term) || 
        c.child_entity_id.toLowerCase().includes(term)
      )
    );
  });

  // Sort groups
  const sortedGroups = [...filteredGroups].sort((a, b) => {
    if (sortBy === 'members') {
      return b.children.length - a.children.length;
    }
    // default: sort by name
    const nameA = a.parent_name || a.parent_entity_id;
    const nameB = b.parent_name || b.parent_entity_id;
    return nameA.localeCompare(nameB);
  });

  const getStateColor = (state: string | null) => {
    if (!state) return 'bg-gray-400';
    switch (state) {
      case 'on': return 'bg-green-500';
      case 'off': return 'bg-gray-400';
      case 'unavailable': return 'bg-red-500';
      default: return 'bg-blue-500';
    }
  };

  const getDomainIcon = (domain: string | null) => {
    if (!domain) return '🏠';
    switch (domain) {
      case 'light': return '💡';
      case 'switch': return '🔌';
      case 'group': return '📦';
      case 'sensor': return '📊';
      case 'climate': return '🌡️';
      case 'cover': return '🪟';
      case 'lock': return '🔒';
      case 'media_player': return '📺';
      default: return '⚙️';
    }
  };

  const getTypeLabel = (type: string) => {
    switch (type) {
      case 'switch_controls_light': return 'Switch steuert Licht';
      case 'device_sibling': return 'Gleiche Gerät';
      case 'group_member': return 'Gruppenmitglied';
      default: return type;
    }
  };

  const autoCount = relationships.filter(r => r.auto_discovered && !r.manually_verified).length;
  const manualCount = relationships.filter(r => r.manually_verified).length;

  return (
    <main className="min-h-screen bg-gradient-to-br from-[#F2F2F7] via-[#E5E5EA] to-[#F2F2F7]">
      {/* Header */}
      <header className="pt-14 pb-6 px-5 safe-area-inset">
        <div className="max-w-5xl mx-auto">
          <Link href="/smarthome" className="inline-flex items-center text-[#007AFF] text-sm font-semibold mb-4 hover:underline">
            ← Zurück
          </Link>
          <h1 className="text-4xl font-extrabold text-[#1C1C1E] tracking-tight mb-2">
            Gruppen & Beziehungen
          </h1>
          <p className="text-[#8E8E93] text-base font-medium">
            {groupedRelations.length} Gruppen mit {relationships.length} Beziehungen
          </p>
        </div>
      </header>

      {/* Stats */}
      <div className="max-w-5xl mx-auto px-5 mb-6">
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
          <div className="bg-white rounded-2xl p-4 shadow-sm border border-black/5">
            <div className="text-2xl font-bold text-[#007AFF]">{groupedRelations.length}</div>
            <div className="text-xs text-[#8E8E93] font-medium mt-1">Gruppen</div>
          </div>
          <div className="bg-white rounded-2xl p-4 shadow-sm border border-black/5">
            <div className="text-2xl font-bold text-[#5856D6]">{relationships.length}</div>
            <div className="text-xs text-[#8E8E93] font-medium mt-1">Beziehungen</div>
          </div>
          <div className="bg-white rounded-2xl p-4 shadow-sm border border-black/5">
            <div className="text-2xl font-bold text-[#34C759]">{autoCount}</div>
            <div className="text-xs text-[#8E8E93] font-medium mt-1">Auto-entdeckt</div>
          </div>
          <div className="bg-white rounded-2xl p-4 shadow-sm border border-black/5">
            <div className="text-2xl font-bold text-[#AF52DE]">{manualCount}</div>
            <div className="text-xs text-[#8E8E93] font-medium mt-1">Manuell</div>
          </div>
        </div>
      </div>

      {/* Controls */}
      <div className="max-w-5xl mx-auto px-5 mb-6">
        <div className="bg-white rounded-2xl p-4 shadow-sm border border-black/5 space-y-3">
          <div className="flex items-center justify-between">
            <h3 className="text-sm font-bold text-[#1C1C1E]">Filter & Sortierung</h3>
            <button
              onClick={() => setShowAddModal(true)}
              className="px-4 py-2 bg-[#007AFF] text-white rounded-xl text-sm font-semibold hover:bg-[#0051D5] transition"
            >
              + Neue Beziehung
            </button>
          </div>

          {/* Search */}
          <input
            type="text"
            placeholder="Suche nach Gruppenname..."
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            className="w-full px-4 py-2 bg-[#F2F2F7] rounded-xl text-sm font-medium outline-none focus:ring-2 focus:ring-[#007AFF]"
          />

          {/* Filters */}
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <select
              value={typeFilter}
              onChange={(e) => setTypeFilter(e.target.value)}
              className="px-4 py-2 bg-[#F2F2F7] rounded-xl text-sm font-medium outline-none focus:ring-2 focus:ring-[#007AFF]"
            >
              <option value="all">Alle Beziehungen</option>
              <option value="auto">⚙ Aus Home Assistant</option>
              <option value="manual">✓ Selbst definiert</option>
            </select>

            <select
              value={sortBy}
              onChange={(e) => setSortBy(e.target.value)}
              className="px-4 py-2 bg-[#F2F2F7] rounded-xl text-sm font-medium outline-none focus:ring-2 focus:ring-[#007AFF]"
            >
              <option value="name">Sortierung: Name</option>
              <option value="members">Sortierung: Anzahl Mitglieder</option>
            </select>
          </div>
        </div>
      </div>

      {/* Groups */}
      <div className="max-w-5xl mx-auto px-5 pb-10">
        {loading ? (
          <div className="text-center py-10 text-[#8E8E93]">Lädt...</div>
        ) : sortedGroups.length === 0 ? (
          <div className="bg-white rounded-3xl shadow-lg border border-black/5 p-10 text-center">
            <div className="text-4xl mb-3">🔗</div>
            <p className="text-[#8E8E93] mb-2">Keine Gruppen gefunden</p>
            <p className="text-xs text-[#8E8E93]">
              {searchTerm ? 'Keine Treffer für deine Suche' : 'Führe ha-voice sync aus um Beziehungen zu entdecken'}
            </p>
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            {sortedGroups.map((group) => (
              <div
                key={group.parent_entity_id}
                className="bg-white rounded-3xl shadow-lg border border-black/5 overflow-hidden hover:shadow-xl transition"
              >
                {/* Header */}
                <div className="bg-gradient-to-r from-[#AF52DE]/10 to-[#5856D6]/10 px-5 py-4 border-b border-black/5">
                  <div className="flex items-start gap-3">
                    <div className="text-3xl mt-1">{getDomainIcon(group.parent_domain)}</div>
                    <div className="flex-1 min-w-0">
                      <div className="font-bold text-lg text-[#1C1C1E] truncate">
                        {group.parent_name || group.parent_entity_id}
                      </div>
                      <div className="text-xs text-[#8E8E93] truncate mt-0.5">
                        {group.parent_entity_id}
                      </div>
                      <div className="flex items-center gap-2 mt-2">
                        <div className={`w-3 h-3 rounded-full ${getStateColor(group.parent_state)}`} />
                        <span className="text-xs font-semibold text-[#8E8E93] uppercase">
                          {group.parent_state || 'unknown'}
                        </span>
                        <span className="text-xs text-[#8E8E93]">|</span>
                        {group.manually_verified ? (
                          <span className="px-2 py-0.5 bg-[#AF52DE]/20 text-[#AF52DE] rounded text-xs font-bold">
                            ✓ Manuell
                          </span>
                        ) : (
                          <span className="px-2 py-0.5 bg-[#FF9F0A]/20 text-[#FF9F0A] rounded text-xs font-bold">
                            ⚙ Auto
                          </span>
                        )}
                      </div>
                    </div>
                  </div>
                </div>

                {/* Members */}
                <div className="p-4">
                  <div className="text-xs font-bold text-[#8E8E93] mb-2 uppercase">
                    Mitglieder ({group.children.length})
                  </div>
                  <div className="flex flex-wrap gap-2">
                    {group.children.map((child) => (
                      <div
                        key={child.child_entity_id}
                        className="group relative inline-flex items-center gap-1.5 px-3 py-2 bg-[#F2F2F7] hover:bg-[#E5E5EA] rounded-xl text-sm transition"
                      >
                        <span className="font-medium text-[#1C1C1E]">
                          {child.child_name || child.child_entity_id}
                        </span>
                        <button
                          onClick={() => deleteRelationship(child.relationship_id)}
                          className="opacity-0 group-hover:opacity-100 ml-1 text-red-600 hover:text-red-800 font-bold transition"
                          title="Entfernen"
                        >
                          ×
                        </button>
                      </div>
                    ))}
                  </div>
                </div>

                {/* Footer */}
                <div className="px-5 py-3 bg-[#F2F2F7] border-t border-black/5">
                  <div className="flex items-center justify-between text-xs">
                    <span className="text-[#8E8E93] font-medium">
                      {getTypeLabel(group.type)}
                    </span>
                    <span className="text-[#8E8E93] font-semibold">
                      {group.children.length} {group.children.length === 1 ? 'Mitglied' : 'Mitglieder'}
                    </span>
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Add Relationship Modal */}
      {showAddModal && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-5">
          <div className="bg-white rounded-3xl shadow-2xl max-w-md w-full p-6">
            <h2 className="text-2xl font-bold text-[#1C1C1E] mb-4">Neue Beziehung</h2>
            
            <div className="space-y-4">
              <div>
                <label className="text-sm font-semibold text-[#1C1C1E] block mb-2">Parent Entity (Gruppe)</label>
                <select
                  value={newRel.parent}
                  onChange={(e) => setNewRel({ ...newRel, parent: e.target.value })}
                  className="w-full px-4 py-3 bg-[#F2F2F7] rounded-xl text-sm outline-none focus:ring-2 focus:ring-[#007AFF]"
                >
                  <option value="">-- Auswählen --</option>
                  {entities.map((e) => (
                    <option key={e.entity_id} value={e.entity_id}>
                      {e.friendly_name} ({e.entity_id})
                    </option>
                  ))}
                </select>
              </div>

              <div>
                <label className="text-sm font-semibold text-[#1C1C1E] block mb-2">Child Entity (Mitglied)</label>
                <select
                  value={newRel.child}
                  onChange={(e) => setNewRel({ ...newRel, child: e.target.value })}
                  className="w-full px-4 py-3 bg-[#F2F2F7] rounded-xl text-sm outline-none focus:ring-2 focus:ring-[#007AFF]"
                >
                  <option value="">-- Auswählen --</option>
                  {entities.map((e) => (
                    <option key={e.entity_id} value={e.entity_id}>
                      {e.friendly_name} ({e.entity_id})
                    </option>
                  ))}
                </select>
              </div>

              <div>
                <label className="text-sm font-semibold text-[#1C1C1E] block mb-2">Beziehungstyp</label>
                <select
                  value={newRel.type}
                  onChange={(e) => setNewRel({ ...newRel, type: e.target.value })}
                  className="w-full px-4 py-3 bg-[#F2F2F7] rounded-xl text-sm outline-none focus:ring-2 focus:ring-[#007AFF]"
                >
                  <option value="group_member">Group Member</option>
                  <option value="switch_controls_light">Switch steuert Light</option>
                  <option value="device_sibling">Device Sibling</option>
                  <option value="custom">Custom</option>
                </select>
              </div>
            </div>

            <div className="flex gap-3 mt-6">
              <button
                onClick={addRelationship}
                className="flex-1 px-4 py-3 bg-[#007AFF] text-white rounded-xl font-semibold hover:bg-[#0051D5] transition"
              >
                Erstellen
              </button>
              <button
                onClick={() => {
                  setShowAddModal(false);
                  setNewRel({ parent: '', child: '', type: 'group_member' });
                }}
                className="flex-1 px-4 py-3 bg-[#F2F2F7] text-[#1C1C1E] rounded-xl font-semibold hover:bg-[#E5E5EA] transition"
              >
                Abbrechen
              </button>
            </div>
          </div>
        </div>
      )}
    </main>
  );
}
