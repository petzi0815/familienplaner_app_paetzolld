'use client';

import { useState } from 'react';
import Link from 'next/link';
import rawData from '../../data/vertraege.json';

interface Contract {
  provider: string;
  type: string;
  contractNr: string;
  amount: number;
  interval: string;
  details: string;
}

interface Category {
  name: string;
  icon: string;
  color: string;
  contracts: Contract[];
}

const data = rawData as { lastUpdated: string; categories: Category[] };

function toMonthly(amount: number, interval: string): number {
  switch (interval) {
    case 'jährlich': return amount / 12;
    case 'halbjährlich': return amount / 6;
    case 'vierteljährlich': return amount / 3;
    default: return amount;
  }
}

function fmt(n: number): string {
  return n.toLocaleString('de-DE', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

function CopyButton({ text }: { text: string }) {
  const [copied, setCopied] = useState(false);
  if (!text) return null;

  return (
    <button
      onClick={(e) => {
        e.stopPropagation();
        navigator.clipboard.writeText(text).then(() => {
          setCopied(true);
          setTimeout(() => setCopied(false), 1500);
        });
      }}
      className="inline-flex items-center gap-1 px-2 py-0.5 bg-[#F2F2F7] rounded-lg text-[12px] font-mono text-[#3C3C43] active:bg-[#D1D1D6] transition-colors"
      title="Vertragsnr. kopieren"
    >
      {copied ? (
        <>
          <svg className="w-3 h-3 text-[#34C759]" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={3}>
            <path strokeLinecap="round" strokeLinejoin="round" d="M5 13l4 4L19 7" />
          </svg>
          <span className="text-[#34C759]">Kopiert!</span>
        </>
      ) : (
        <>
          <svg className="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
            <rect x="9" y="9" width="13" height="13" rx="2" ry="2" />
            <path d="M5 15H4a2 2 0 01-2-2V4a2 2 0 012-2h9a2 2 0 012 2v1" />
          </svg>
          {text}
        </>
      )}
    </button>
  );
}

function CategoryBar({ categories, total }: { categories: { name: string; color: string; monthly: number }[]; total: number }) {
  return (
    <div className="w-full">
      <div className="flex rounded-xl overflow-hidden h-6">
        {categories.map((cat) => {
          const pct = (cat.monthly / total) * 100;
          if (pct < 1) return null;
          return (
            <div
              key={cat.name}
              style={{ width: `${pct}%`, backgroundColor: cat.color }}
              className="relative"
              title={`${cat.name}: ${fmt(cat.monthly)} €/Mo (${pct.toFixed(1)}%)`}
            />
          );
        })}
      </div>
      <div className="flex flex-wrap gap-x-3 gap-y-1 mt-3">
        {categories.map((cat) => {
          const pct = (cat.monthly / total) * 100;
          if (pct < 1) return null;
          return (
            <div key={cat.name} className="flex items-center gap-1.5 text-[11px] text-[#3C3C43]">
              <div className="w-2.5 h-2.5 rounded-full" style={{ backgroundColor: cat.color }} />
              <span className="font-medium">{cat.name}</span>
              <span className="text-[#8E8E93]">{pct.toFixed(0)}%</span>
            </div>
          );
        })}
      </div>
    </div>
  );
}

export default function VertraegePage() {
  const [openCats, setOpenCats] = useState<Set<string>>(new Set());
  const categories = data.categories;

  const catMonthlies = categories.map((cat) => ({
    name: cat.name,
    color: cat.color,
    monthly: cat.contracts.reduce((sum, c) => sum + toMonthly(c.amount, c.interval), 0),
  })).sort((a, b) => b.monthly - a.monthly);

  const totalMonthly = catMonthlies.reduce((sum, c) => sum + c.monthly, 0);
  const totalYearly = totalMonthly * 12;

  const toggle = (name: string) => {
    setOpenCats(prev => {
      const next = new Set(prev);
      next.has(name) ? next.delete(name) : next.add(name);
      return next;
    });
  };

  return (
    <main className="min-h-screen bg-gradient-to-br from-[#F2F2F7] via-[#E5E5EA] to-[#F2F2F7]">
      <header className="pt-12 pb-4 px-4 safe-area-inset">
        <div className="max-w-2xl mx-auto">
          <Link href="/" className="inline-flex items-center gap-1 text-[#007AFF] text-sm font-medium mb-4">
            <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2.5}>
              <path strokeLinecap="round" strokeLinejoin="round" d="M15 19l-7-7 7-7" />
            </svg>
            Zurück
          </Link>
          <h1 className="text-3xl font-extrabold text-[#1C1C1E] tracking-tight">📋 Verträge</h1>
          <p className="text-[#8E8E93] text-sm font-medium mt-1">Stand: {data.lastUpdated}</p>
        </div>
      </header>

      <div className="max-w-2xl mx-auto px-4 pb-12 space-y-4">
        {/* Summary */}
        <div className="bg-white rounded-2xl shadow-sm border border-black/5 p-5">
          <div className="flex items-baseline justify-between mb-4">
            <div>
              <p className="text-[#8E8E93] text-xs font-medium uppercase tracking-wide">Monatlich</p>
              <p className="text-4xl font-extrabold text-[#1C1C1E] tracking-tight mt-1">
                {fmt(totalMonthly)}<span className="text-lg text-[#8E8E93] font-semibold ml-1">€</span>
              </p>
            </div>
            <div className="text-right">
              <p className="text-[#8E8E93] text-xs font-medium uppercase tracking-wide">Jährlich</p>
              <p className="text-xl font-bold text-[#3C3C43] mt-1">
                {fmt(totalYearly)}<span className="text-sm text-[#8E8E93] font-semibold ml-1">€</span>
              </p>
            </div>
          </div>
          <CategoryBar categories={catMonthlies} total={totalMonthly} />
        </div>

        {/* Top 5 */}
        <div className="bg-white rounded-2xl shadow-sm border border-black/5 p-5">
          <h2 className="text-sm font-bold text-[#8E8E93] uppercase tracking-wide mb-3">Top-Posten</h2>
          <div className="space-y-2.5">
            {catMonthlies.slice(0, 5).map((cat) => (
              <div key={cat.name} className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <div className="w-3 h-3 rounded-full" style={{ backgroundColor: cat.color }} />
                  <span className="text-[14px] font-semibold text-[#1C1C1E]">{cat.name}</span>
                </div>
                <span className="text-[14px] font-bold text-[#1C1C1E]">
                  {fmt(cat.monthly)} €<span className="text-[#8E8E93] font-medium">/Mo</span>
                </span>
              </div>
            ))}
          </div>
        </div>

        {/* Accordion */}
        {categories.map((cat) => {
          const isOpen = openCats.has(cat.name);
          const catMonthly = cat.contracts.reduce((s, c) => s + toMonthly(c.amount, c.interval), 0);
          return (
            <div key={cat.name} className="bg-white rounded-2xl shadow-sm border border-black/5 overflow-hidden">
              <button
                onClick={() => toggle(cat.name)}
                className="w-full flex items-center justify-between p-4 active:bg-[#F2F2F7] transition-colors"
              >
                <div className="flex items-center gap-3">
                  <div className="w-10 h-10 rounded-xl flex items-center justify-center text-xl" style={{ backgroundColor: cat.color + '18' }}>
                    {cat.icon}
                  </div>
                  <div className="text-left">
                    <h3 className="text-[16px] font-bold text-[#1C1C1E]">{cat.name}</h3>
                    <p className="text-[12px] text-[#8E8E93] font-medium">
                      {cat.contracts.length} {cat.contracts.length === 1 ? 'Vertrag' : 'Verträge'}
                    </p>
                  </div>
                </div>
                <div className="flex items-center gap-2">
                  <span className="text-[16px] font-bold text-[#1C1C1E]">
                    {fmt(catMonthly)} €<span className="text-[#8E8E93] text-[12px] font-medium">/Mo</span>
                  </span>
                  <svg className={`w-5 h-5 text-[#8E8E93] transition-transform ${isOpen ? 'rotate-90' : ''}`} fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                    <path strokeLinecap="round" strokeLinejoin="round" d="M9 5l7 7-7 7" />
                  </svg>
                </div>
              </button>

              {isOpen && (
                <div className="px-4 pb-4 space-y-3">
                  <div className="h-px bg-[#E5E5EA]" />
                  {cat.contracts.map((contract, idx) => (
                    <div key={idx} className="bg-[#F9F9FB] rounded-xl p-4">
                      <div className="flex items-start justify-between mb-1">
                        <div>
                          <p className="text-[15px] font-bold text-[#1C1C1E]">{contract.provider}</p>
                          <p className="text-[13px] text-[#8E8E93] font-medium">{contract.type}</p>
                        </div>
                        <div className="text-right">
                          <p className="text-[18px] font-extrabold text-[#1C1C1E]">{fmt(contract.amount)} €</p>
                          <p className="text-[11px] text-[#8E8E93] font-medium capitalize">{contract.interval}</p>
                        </div>
                      </div>
                      {contract.contractNr && (
                        <div className="mt-2">
                          <CopyButton text={contract.contractNr} />
                        </div>
                      )}
                      {contract.details && (
                        <p className="text-[12px] text-[#8E8E93] mt-2">{contract.details}</p>
                      )}
                    </div>
                  ))}
                </div>
              )}
            </div>
          );
        })}
      </div>
    </main>
  );
}
