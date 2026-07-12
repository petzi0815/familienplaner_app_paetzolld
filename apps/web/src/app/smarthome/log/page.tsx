'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';

interface CommandLog {
  id: number;
  timestamp: string;
  input_text: string;
  matched_entity_id: string;
  friendly_name: string | null;
  match_score: number;
  action: string;
  dependencies_triggered: string | null;
  result: string;
  duration_ms: number;
  success: boolean;
}

export default function CommandLogPage() {
  const [logs, setLogs] = useState<CommandLog[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    loadLogs();
  }, []);

  async function loadLogs() {
    try {
      const res = await fetch('/api/smarthome/log?limit=100');
      const data = await res.json();
      setLogs(data.logs || []);
    } catch (err) {
      console.error('Failed to load logs:', err);
    } finally {
      setLoading(false);
    }
  }

  const getDurationColor = (ms: number) => {
    if (ms < 500) return 'text-green-600 bg-green-50';
    if (ms < 2000) return 'text-yellow-600 bg-yellow-50';
    return 'text-red-600 bg-red-50';
  };

  const formatTimestamp = (ts: string) => {
    const date = new Date(ts);
    return new Intl.DateTimeFormat('de-DE', {
      day: '2-digit',
      month: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit'
    }).format(date);
  };

  // Calculate average response time
  const avgResponseTime = logs.length > 0
    ? Math.round(logs.reduce((sum, log) => sum + log.duration_ms, 0) / logs.length)
    : 0;

  const successRate = logs.length > 0
    ? Math.round((logs.filter(l => l.success).length / logs.length) * 100)
    : 0;

  // Chart data (last 20 commands)
  const chartData = logs.slice(0, 20).reverse();
  const maxDuration = Math.max(...chartData.map(l => l.duration_ms), 1000);

  return (
    <main className="min-h-screen bg-gradient-to-br from-[#F2F2F7] via-[#E5E5EA] to-[#F2F2F7]">
      {/* Header */}
      <header className="pt-14 pb-6 px-5 safe-area-inset">
        <div className="max-w-5xl mx-auto">
          <Link href="/smarthome" className="inline-flex items-center text-[#007AFF] text-sm font-semibold mb-4 hover:underline">
            ← Zurück
          </Link>
          <h1 className="text-4xl font-extrabold text-[#1C1C1E] tracking-tight mb-2">
            Command Log
          </h1>
          <p className="text-[#8E8E93] text-base font-medium">
            Letzte {logs.length} Voice-Befehle
          </p>
        </div>
      </header>

      {/* Stats */}
      <div className="max-w-5xl mx-auto px-5 mb-6">
        <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
          <div className="bg-white rounded-2xl p-4 shadow-sm border border-black/5">
            <div className="text-2xl font-bold text-[#007AFF]">{logs.length}</div>
            <div className="text-xs text-[#8E8E93] font-medium mt-1">Total Commands</div>
          </div>
          <div className="bg-white rounded-2xl p-4 shadow-sm border border-black/5">
            <div className="text-2xl font-bold text-[#34C759]">{successRate}%</div>
            <div className="text-xs text-[#8E8E93] font-medium mt-1">Success Rate</div>
          </div>
          <div className="bg-white rounded-2xl p-4 shadow-sm border border-black/5">
            <div className="text-2xl font-bold text-[#FF9F0A]">{avgResponseTime}ms</div>
            <div className="text-xs text-[#8E8E93] font-medium mt-1">Avg Response</div>
          </div>
        </div>
      </div>

      {/* Response Time Chart */}
      {chartData.length > 0 && (
        <div className="max-w-5xl mx-auto px-5 mb-6">
          <div className="bg-white rounded-3xl shadow-lg border border-black/5 p-6">
            <h2 className="text-lg font-bold text-[#1C1C1E] mb-4">Antwortzeiten (letzte 20)</h2>
            <div className="flex items-end gap-1 h-32">
              {chartData.map((log, i) => (
                <div key={log.id} className="flex-1 flex flex-col items-center justify-end">
                  <div
                    className={`w-full rounded-t ${log.success ? 'bg-[#007AFF]' : 'bg-red-500'} transition-all hover:opacity-80`}
                    style={{ height: `${(log.duration_ms / maxDuration) * 100}%` }}
                    title={`${log.action} - ${log.duration_ms}ms`}
                  />
                </div>
              ))}
            </div>
            <div className="flex justify-between mt-2 text-xs text-[#8E8E93]">
              <span>Älteste</span>
              <span>Neueste</span>
            </div>
          </div>
        </div>
      )}

      {/* Log Table */}
      <div className="max-w-5xl mx-auto px-5 pb-10">
        {loading ? (
          <div className="text-center py-10 text-[#8E8E93]">Lädt...</div>
        ) : logs.length === 0 ? (
          <div className="bg-white rounded-3xl shadow-lg border border-black/5 p-10 text-center">
            <div className="text-4xl mb-3">📋</div>
            <p className="text-[#8E8E93]">Noch keine Commands ausgeführt</p>
          </div>
        ) : (
          <div className="bg-white rounded-3xl shadow-lg border border-black/5 overflow-hidden">
            <div className="overflow-x-auto">
              <table className="w-full">
                <thead className="bg-[#F2F2F7] border-b border-black/5">
                  <tr>
                    <th className="px-4 py-3 text-left text-xs font-semibold text-[#8E8E93] uppercase">Zeit</th>
                    <th className="px-4 py-3 text-left text-xs font-semibold text-[#8E8E93] uppercase">Input</th>
                    <th className="px-4 py-3 text-left text-xs font-semibold text-[#8E8E93] uppercase">Entity</th>
                    <th className="px-4 py-3 text-left text-xs font-semibold text-[#8E8E93] uppercase">Action</th>
                    <th className="px-4 py-3 text-left text-xs font-semibold text-[#8E8E93] uppercase">Dauer</th>
                    <th className="px-4 py-3 text-left text-xs font-semibold text-[#8E8E93] uppercase">Status</th>
                  </tr>
                </thead>
                <tbody>
                  {logs.map((log) => (
                    <tr key={log.id} className="border-b border-black/5 hover:bg-[#F2F2F7]/50 transition">
                      <td className="px-4 py-3 text-xs text-[#8E8E93]">
                        {formatTimestamp(log.timestamp)}
                      </td>
                      <td className="px-4 py-3 text-sm font-medium text-[#1C1C1E]">
                        {log.input_text}
                      </td>
                      <td className="px-4 py-3 text-xs text-[#8E8E93]">
                        <div className="font-semibold text-[#1C1C1E]">{log.friendly_name || log.matched_entity_id}</div>
                        <div className="text-[10px] text-[#8E8E93] mt-0.5">Score: {log.match_score.toFixed(3)}</div>
                      </td>
                      <td className="px-4 py-3">
                        <span className="px-2 py-1 bg-[#007AFF]/10 text-[#007AFF] rounded-lg text-xs font-semibold uppercase">
                          {log.action}
                        </span>
                      </td>
                      <td className="px-4 py-3">
                        <span className={`px-2 py-1 rounded-lg text-xs font-semibold ${getDurationColor(log.duration_ms)}`}>
                          {log.duration_ms}ms
                        </span>
                      </td>
                      <td className="px-4 py-3">
                        {log.success ? (
                          <span className="text-green-600 font-bold text-lg">✓</span>
                        ) : (
                          <span className="text-red-600 font-bold text-lg">✗</span>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        )}
      </div>
    </main>
  );
}
