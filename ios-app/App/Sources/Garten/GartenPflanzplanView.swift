import SwiftUI

/// Pflanzplan-Tab: Pivot-Matrix (aktive Samen × 12 Monate) mit Vorziehen/Aussaat/Ernte-Färbung
/// + aktueller-Monat-Ring, darunter Detailkarten je Samen. Horizontal scrollbar.
struct GartenPflanzplanView: View {
    @EnvironmentObject private var store: GartenStore
    private var currentMonth: Int { Calendar.current.component(.month, from: Date()) }
    private let nameWidth: CGFloat = 108
    private let cellWidth: CGFloat = 24

    private struct SeedPlan {
        let vorzieh: Int?
        let pflanz: Int?
        let ernte: Int?
        let ernteEnd: Int
    }

    private func plan(for s: GartenSamen) -> SeedPlan {
        let tasks = store.samenAufgaben.filter { $0.samenId == s.id }
        let vorzieh = tasks.first { $0.kategorie == "vorziehen" }?.computedMonat ?? s.vorziehenAb
        let pflanz = tasks.first { $0.kategorie == "pflanzen" }?.computedMonat ?? s.pflanzVon
        let ernte = tasks.first { $0.kategorie == "ernten" }?.computedMonat ?? s.ernteVon
        let ernteEnd: Int
        if let em = ernte, let eb = s.ernteBis { ernteEnd = em + (eb - (s.ernteVon ?? 0)) } else { ernteEnd = ernte ?? 12 }
        return SeedPlan(vorzieh: vorzieh, pflanz: pflanz, ernte: ernte, ernteEnd: ernteEnd)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if store.aktiveSamen.isEmpty {
                    AreaEmptyState(emoji: "🌱", title: "Keine aktiven Samen!", hint: "Schalte Samen auf aktiv um sie hier zu sehen.")
                        .frame(minHeight: 240)
                } else {
                    intro
                    matrix
                    legend
                    detailCards
                }
            }
            .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 24)
        }
        .task {
            await store.reloadSamen()
            await store.reloadAufgaben()
        }
    }

    private var intro: some View {
        Text("🗓️ Übersicht aller aktiven Samen — Vorziehen → Aussaat → Ernte auf einen Blick")
            .font(.caption).foregroundStyle(Color(hex: "2563EB"))
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    private var matrix: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(spacing: 4) {
                // Kopfzeile
                HStack(spacing: 2) {
                    Text("Samen").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                        .frame(width: nameWidth, alignment: .leading)
                    ForEach(1...12, id: \.self) { m in
                        Text(GartenStyle.monatInitial[m - 1])
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(m == currentMonth ? Color.blue : Color.secondary)
                            .frame(width: cellWidth)
                    }
                }
                ForEach(Array(store.aktiveSamen.enumerated()), id: \.element.id) { idx, s in
                    row(s, GartenStyle.samenColor(idx))
                }
            }
            .padding(12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func row(_ s: GartenSamen, _ colors: GartenStyle.SamenColorSet) -> some View {
        let p = plan(for: s)
        return HStack(spacing: 2) {
            HStack(spacing: 5) {
                if let path = s.firstImagePath {
                    AuthImage(path: path, contentMode: .fill).frame(width: 22, height: 22).clipShape(Circle())
                } else {
                    Circle().fill(Color(hex: "D1FAE5")).frame(width: 22, height: 22)
                        .overlay(Text("🌱").font(.system(size: 10)))
                }
                Text(s.name).font(.system(size: 10, weight: .semibold)).lineLimit(1)
            }
            .frame(width: nameWidth, alignment: .leading)

            ForEach(1...12, id: \.self) { m in cell(s, m, colors, p) }
        }
    }

    private func cell(_ s: GartenSamen, _ m: Int, _ colors: GartenStyle.SamenColorSet, _ p: SeedPlan) -> some View {
        let isVorziehen = (p.vorzieh != nil && p.pflanz != nil && m >= p.vorzieh! && m < p.pflanz!)
        let isAussaat = (p.pflanz != nil && m == p.pflanz!)
        let isErnte = (p.ernte != nil && m >= p.ernte! && m <= min(p.ernteEnd, 12))
        let isAussaat2 = (s.aussaat2Von != nil && s.aussaat2Bis != nil && m >= s.aussaat2Von! && m <= s.aussaat2Bis!)
        let isErnte2 = (s.ernte2Von != nil && s.ernte2Bis != nil && m >= s.ernte2Von! && m <= s.ernte2Bis!)
        let isCurrent = m == currentMonth
        let isShifted = (isVorziehen && p.vorzieh != s.vorziehenAb) || (isAussaat && p.pflanz != s.pflanzVon) || (isErnte && p.ernte != s.ernteVon)

        var fill = AnyShapeStyle(Color(.systemGray6))
        var content = ""
        if isVorziehen { fill = AnyShapeStyle(colors.vorziehen); content = "🏠" }
        if isAussaat { fill = AnyShapeStyle(colors.aussaat); content = "🌱" }
        if isErnte { fill = AnyShapeStyle(colors.ernte); content = "🌾" }
        if isAussaat2 { fill = AnyShapeStyle(colors.aussaat.opacity(0.45)); content = "🌱" }
        if isErnte2 { fill = AnyShapeStyle(colors.ernte.opacity(0.45)); content = "🌾" }
        if isAussaat && isErnte {
            fill = AnyShapeStyle(LinearGradient(colors: [Color(hex: "34D399"), Color(hex: "FBBF24")], startPoint: .top, endPoint: .bottom))
            content = "✨"
        }

        let ring: Color? = isCurrent ? Color(hex: "3B82F6") : (isShifted ? Color(hex: "93C5FD") : nil)

        return RoundedRectangle(cornerRadius: 4).fill(fill)
            .frame(width: cellWidth, height: 28)
            .overlay(Text(content).font(.system(size: 9)))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(ring ?? .clear, lineWidth: 1))
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                legendItem(Color(hex: "A855F7"), "🏠 Vorziehen")
                legendItem(Color(hex: "10B981"), "🌱 Aussaat 1")
                legendItem(Color(hex: "F59E0B"), "🌾 Ernte 1")
            }
            HStack(spacing: 12) {
                legendItem(Color(hex: "10B981").opacity(0.45), "🌱 Aussaat 2")
                legendItem(Color(hex: "F59E0B").opacity(0.45), "🌾 Ernte 2")
                legendItem(Color.white, "Aktuell", ring: Color(hex: "3B82F6"))
            }
        }
    }

    private func legendItem(_ c: Color, _ label: String, ring: Color? = nil) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(c).frame(width: 12, height: 12)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(ring ?? .clear, lineWidth: 1))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var detailCards: some View {
        VStack(spacing: 12) {
            ForEach(Array(store.aktiveSamen.enumerated()), id: \.element.id) { idx, s in
                detailCard(s, GartenStyle.samenColor(idx))
            }
        }
    }

    private func detailCard(_ s: GartenSamen, _ colors: GartenStyle.SamenColorSet) -> some View {
        let p = plan(for: s)
        let keimWochen = s.keimzeitTage.map { Int(ceil(Double($0) / 7)) }
        let has2nd = s.aussaat2Von != nil || s.ernte2Von != nil
        var pflanzExtras: [String] = []
        if let t = s.tiefeCm { pflanzExtras.append("· \(GartenStyle.trimDouble(t))cm tief") }
        if let a = s.abstandCm { pflanzExtras.append("· \(a)cm Abstand") }
        let pflanzExtra = pflanzExtras.isEmpty ? nil : pflanzExtras.joined(separator: " ")
        return VStack(alignment: .leading, spacing: 6) {
            Text(s.name).font(.subheadline.weight(.bold)).foregroundStyle(colors.text)
            if let v = p.vorzieh {
                planLine("🏠", "Vorziehen: ab \(GartenStyle.lang(v))",
                         shiftedFrom: (v != s.vorziehenAb) ? s.vorziehenAb : nil,
                         extra: keimWochen.map { "· Keimzeit ~\($0) Wo." })
            }
            if let v = p.pflanz {
                planLine("🌱", "Auspflanzen: \(GartenStyle.lang(v))",
                         shiftedFrom: (v != s.pflanzVon) ? s.pflanzVon : nil,
                         extra: pflanzExtra)
            }
            if let v = p.ernte {
                planLine("🌾", "Ernte: ab \(GartenStyle.lang(v))",
                         shiftedFrom: (v != s.ernteVon) ? s.ernteVon : nil, extra: nil)
            }
            if let r = GartenStyle.rangeText(s.aussaat2Von, s.aussaat2Bis) {
                Text("🔄 2. Aussaat: \(r)").font(.caption).foregroundStyle(Color(hex: "059669"))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color(hex: "10B981").opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            }
            if let r = GartenStyle.rangeText(s.ernte2Von, s.ernte2Bis) {
                Text("🔄 2. Ernte: \(r)").font(.caption).foregroundStyle(Color(hex: "B45309"))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color(hex: "F59E0B").opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            }
            if let se = s.standortEmpfehlung { Text("☀️ \(se)").font(.caption).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(colors.bg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(has2nd ? Color(hex: "FCD34D") : Color.clear, lineWidth: 2))
    }

    private func planLine(_ emoji: String, _ text: String, shiftedFrom: Int?, extra: String?) -> some View {
        var line = Text("\(emoji) ").font(.caption) + Text(text).font(.caption)
        if let from = shiftedFrom {
            line = line + Text(" (verschoben von \(GartenStyle.lang(from)))").font(.caption).foregroundStyle(.blue)
        }
        if let e = extra {
            line = line + Text(" \(e)").font(.caption).foregroundStyle(.secondary)
        }
        return line.frame(maxWidth: .infinity, alignment: .leading)
    }
}
