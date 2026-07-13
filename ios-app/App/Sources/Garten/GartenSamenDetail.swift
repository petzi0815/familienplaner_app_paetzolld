import SwiftUI

/// Reiches Samen-Detail: Fotos (Vorne/Hinten), interaktiver Jahresverlauf, alle Infozeilen,
/// 2. Aussaatzeitraum, Besonderheiten, Botanische Details (aus metadata), Notizen, Löschen.
struct GartenSamenDetailSheet: View {
    let samen: GartenSamen
    @EnvironmentObject private var store: GartenStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    images
                    header
                    if samen.vorziehenAb != nil || samen.pflanzVon != nil || samen.ernteVon != nil {
                        GartenSamenTimeline(samen: samen)
                    }
                    infoRows
                    zweiterZeitraum
                    besonderheiten
                    botanischeDetails
                    if let n = samen.notizen, !n.isEmpty { NoteBlock(icon: "📝", text: n, tint: .yellow) }
                    deleteButton
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } } }
            .confirmationDialog("Samen wirklich löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) {
                    Task { await store.deleteSamen(samen.id); dismiss() }
                }
                Button("Abbrechen", role: .cancel) {}
            }
        }
    }

    // ── Bilder ──
    @ViewBuilder private var images: some View {
        let urls = samen.imagePaths
        if urls.count > 1 {
            HStack(spacing: 8) {
                ForEach(Array(urls.prefix(2).enumerated()), id: \.offset) { i, url in
                    ZStack(alignment: .bottomLeading) {
                        AuthImage(path: url, contentMode: .fill)
                            .frame(maxWidth: .infinity)
                            .frame(height: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        Text(i == 0 ? "📸 Vorne" : "📋 Hinten")
                            .font(.caption2).foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(.black.opacity(0.4), in: Capsule())
                            .padding(8)
                    }
                }
            }
        } else if let url = urls.first {
            AuthImage(path: url, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else {
            LinearGradient(colors: [Color(hex: "D1FAE5"), Color(hex: "DCFCE7")], startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(height: 180)
                .overlay(Text(samen.emoji).font(.system(size: 80)).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    // ── Titel + Badges ──
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(samen.name).font(.title2.weight(.bold))
            if let s = samen.sorte, !s.isEmpty { Text(s).foregroundStyle(.secondary) }
            HStack(spacing: 8) {
                if let art = samen.art, !art.isEmpty {
                    Pill(text: "\(samen.emoji) \(art)", color: Color(hex: "10B981"), filled: false)
                }
                Pill(text: samen.aktiv ? "✅ Aktiv" : "⏸️ Inaktiv",
                     color: samen.aktiv ? Color(hex: "16A34A") : Color(hex: "EA580C"), filled: false)
            }
        }
    }

    // ── Infozeilen ──
    private var infoRows: some View {
        VStack(spacing: 0) {
            if let v = GartenStyle.rangeText(samen.pflanzVon, samen.pflanzBis) { InfoRow(icon: "🌱", label: "Aussaat", value: v) }
            if let m = samen.vorziehenAb { InfoRow(icon: "🏠", label: "Vorziehen ab", value: GartenStyle.lang(m)) }
            if let v = GartenStyle.rangeText(samen.ernteVon, samen.ernteBis) { InfoRow(icon: "🌾", label: "Ernte", value: v) }
            if let v = samen.standortEmpfehlung { InfoRow(icon: "☀️", label: "Standort", value: v) }
            if let v = samen.abstandCm { InfoRow(icon: "📏", label: "Abstand", value: "\(v) cm") }
            if let v = samen.tiefeCm { InfoRow(icon: "📐", label: "Saattiefe", value: "\(GartenStyle.trimDouble(v)) cm") }
            if let v = samen.keimzeitTage { InfoRow(icon: "⏱️", label: "Keimzeit", value: "\(v) Tage") }
            if let v = samen.hersteller { InfoRow(icon: "🏭", label: "Hersteller", value: v) }
            if let v = samen.bio { InfoRow(icon: "🌿", label: "Bio-Zertifizierung", value: v) }
            if samen.isSamenfest { InfoRow(icon: "🌱", label: "Samenfest", value: "Ja") }
            if let v = samen.botanisch { InfoRow(icon: "🔬", label: "Botanisch", value: v) }
            if let v = samen.keimtemp { InfoRow(icon: "🌡️", label: "Keimtemperatur", value: v) }
            if let v = samen.keimfaehigBis {
                InfoRow(icon: samen.isKeimfaehigExpired ? "⚠️" : "✅", label: "Keimfähig bis",
                        value: v + (samen.isKeimfaehigExpired ? " (⚠️ abgelaufen)" : ""))
            }
            if let v = samen.inhalt { InfoRow(icon: "📦", label: "Inhalt", value: v) }
            if let v = samen.typ { InfoRow(icon: "🏷️", label: "Typ", value: v) }
            if let v = samen.herkunft { InfoRow(icon: "🌍", label: "Herkunft", value: v) }
            if let v = samen.verwendung { InfoRow(icon: "🍽️", label: "Verwendung", value: v) }
            if let v = samen.erfasstAm { InfoRow(icon: "📅", label: "Erfasst", value: DateText.longNoWeekday(v)) }
        }
        .padding(.horizontal, 4)
    }

    // ── 2. Aussaatzeitraum ──
    @ViewBuilder private var zweiterZeitraum: some View {
        if samen.aussaat2Von != nil || samen.ernte2Von != nil {
            VStack(alignment: .leading, spacing: 8) {
                Text("🔄 2. Aussaatzeitraum").font(.caption.weight(.bold)).foregroundStyle(Color(hex: "B45309"))
                if let v = GartenStyle.rangeText(samen.aussaat2Von, samen.aussaat2Bis, long: true) {
                    Text("🌱 Aussaat: \(v)").font(.subheadline)
                }
                if let v = GartenStyle.rangeText(samen.ernte2Von, samen.ernte2Bis, long: true) {
                    Text("🌾 Ernte: \(v)").font(.subheadline)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(hex: "F59E0B").opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    @ViewBuilder private var besonderheiten: some View {
        if let b = samen.besonderheiten, !b.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("✨ Besonderheiten").font(.caption.weight(.bold)).foregroundStyle(Color(hex: "7E22CE"))
                Text(b).font(.subheadline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(hex: "A855F7").opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    // ── Botanische Details (aus metadata) ──
    @ViewBuilder private var botanischeDetails: some View {
        let m = samen.metadata
        let rows: [(String, String, Bool)] = [
            ("Botanischer Name", m["botanischer_name"] ?? "", true),
            ("Familie", m["familie"] ?? "", false),
            ("Lebensdauer", m["lebensdauer"] ?? "", false),
            ("Wuchshöhe", m["wuchshoehe"] ?? "", false),
            ("Boden", m["boden"] ?? "", false),
            ("Keimtemperatur", m["keimtemperatur"] ?? "", false),
            ("Besonderheiten", m["besonderheiten"] ?? "", false),
            ("Verwendung", m["verwendung"] ?? "", false),
            ("Ernte-Hinweis", m["ernte_hinweis"] ?? "", false),
        ].filter { !$0.1.isEmpty }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("🔬 Botanische Details").font(.caption.weight(.bold)).foregroundStyle(Color(hex: "059669"))
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: 8) {
                        Text(row.0).font(.subheadline).foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Text(row.1)
                            .font(row.2 ? .subheadline.italic() : .subheadline)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) { confirmDelete = true } label: {
            Label("Samen löschen", systemImage: "trash")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Color.red, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }
}

// MARK: - Interaktiver Jahresverlauf

struct GartenSamenTimeline: View {
    let samen: GartenSamen
    @State private var selectedStartMonth: Int?

    private var currentMonth: Int { Calendar.current.component(.month, from: Date()) }
    private var keimMonate: Int { samen.keimzeitTage.map { Int(ceil(Double($0) / 30)) } ?? 1 }
    private var projAussaat: Int? { selectedStartMonth.map { min($0 + keimMonate, 12) } }
    private var ernteOffset: Int {
        if let ev = samen.ernteVon, let pv = samen.pflanzVon { return ev - pv }
        return 3
    }
    private var projErnte: Int? { projAussaat.map { min($0 + ernteOffset, 12) } }
    private var projErnteEnd: Int? {
        guard let pe = projErnte else { return nil }
        if let eb = samen.ernteBis, let ev = samen.ernteVon { return min(pe + (eb - ev), 12) }
        return min(pe + 5, 12)
    }
    private var clickableFrom: Int { samen.vorziehenAb ?? samen.pflanzVon ?? 1 }
    private var clickableTo: Int { samen.pflanzBis ?? samen.pflanzVon ?? 12 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("📅 Jahresverlauf").font(.caption.weight(.bold)).foregroundStyle(Color(hex: "059669"))
                Spacer()
                if selectedStartMonth != nil {
                    Button("✕ Reset") { selectedStartMonth = nil }
                        .font(.caption2.weight(.semibold)).foregroundStyle(.blue)
                }
            }

            if selectedStartMonth == nil {
                Text("👆 Tippe auf einen Monat um deinen Start zu markieren — Aussaat & Ernte werden berechnet")
                    .font(.caption2).foregroundStyle(.blue)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            }

            HStack(spacing: 2) {
                ForEach(1...12, id: \.self) { m in monthCell(m) }
            }

            legend

            if let start = selectedStartMonth { plan(start) }
            else { defaultHint }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func monthCell(_ m: Int) -> some View {
        let isVorziehen = (samen.vorziehenAb != nil && samen.pflanzVon != nil && m >= samen.vorziehenAb! && m < samen.pflanzVon!)
        let isAussaat = (samen.pflanzVon != nil && samen.pflanzBis != nil && m >= samen.pflanzVon! && m <= samen.pflanzBis!)
        let isErnte = (samen.ernteVon != nil && samen.ernteBis != nil && m >= samen.ernteVon! && m <= samen.ernteBis!)
        let isCurrent = m == currentMonth
        let isClickable = m >= clickableFrom && m <= clickableTo
        let isSelected = m == selectedStartMonth
        let isProjAussaat = projAussaat != nil && m == projAussaat
        let isProjErnte = projErnte != nil && projErnteEnd != nil && m >= projErnte! && m <= projErnteEnd!

        var fill = AnyShapeStyle(Color(.systemGray5))
        if isVorziehen { fill = AnyShapeStyle(Color(hex: "C4B5FD").opacity(0.6)) }
        if isAussaat { fill = AnyShapeStyle(Color(hex: "6EE7B7").opacity(0.6)) }
        if isErnte { fill = AnyShapeStyle(Color(hex: "FCD34D").opacity(0.6)) }
        if isAussaat && isErnte {
            fill = AnyShapeStyle(LinearGradient(colors: [Color(hex: "6EE7B7").opacity(0.6), Color(hex: "FCD34D").opacity(0.6)], startPoint: .top, endPoint: .bottom))
        }
        if selectedStartMonth != nil {
            if isSelected { fill = AnyShapeStyle(Color(hex: "9333EA")) }
            else if isProjAussaat { fill = AnyShapeStyle(Color(hex: "059669")) }
            else if isProjErnte { fill = AnyShapeStyle(Color(hex: "F59E0B")) }
        }

        var ring: Color? = nil
        if isCurrent { ring = Color(hex: "3B82F6") }
        if isProjAussaat { ring = Color(hex: "047857") }
        if isSelected { ring = Color(hex: "6B21A8") }

        return VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 4).fill(fill)
                if isSelected { Text("🏠").font(.system(size: 11)) }
                else if isProjAussaat == true { Text("🌱").font(.system(size: 11)) }
                else if isProjErnte && m == projErnte { Text("🌾").font(.system(size: 11)) }
            }
            .frame(height: 40)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(ring ?? .clear, lineWidth: 2))
            Text(GartenStyle.monatInitial[m - 1])
                .font(.system(size: 8, weight: isCurrent || isSelected ? .bold : .regular))
                .foregroundStyle(isCurrent ? Color.blue : (isSelected ? Color(hex: "7E22CE") : Color.secondary))
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            if isClickable { selectedStartMonth = (m == selectedStartMonth) ? nil : m }
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            if samen.vorziehenAb != nil { legendItem(Color(hex: "A78BFA"), "🏠 Vorziehen") }
            legendItem(Color(hex: "34D399"), "🌱 Aussaat")
            legendItem(Color(hex: "FBBF24"), "🌾 Ernte")
            Spacer(minLength: 0)
        }
    }

    private func legendItem(_ c: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(c).frame(width: 12, height: 12)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func plan(_ start: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("📌 Dein Plan:").font(.caption.weight(.bold)).foregroundStyle(Color(hex: "7E22CE"))
            (Text("🏠 Vorziehen im ").font(.caption2) + Text(GartenStyle.lang(start)).font(.caption2.weight(.bold)))
                .foregroundStyle(Color(hex: "6D28D9"))
            if let pa = projAussaat {
                (Text("🌱 Auspflanzen ab ").font(.caption2) + Text(GartenStyle.lang(pa)).font(.caption2.weight(.bold)))
                    .foregroundStyle(Color(hex: "047857"))
            }
            if let pe = projErnte {
                (Text("🌾 Ernte ab ").font(.caption2) + Text(GartenStyle.lang(pe)).font(.caption2.weight(.bold))
                    + Text((projErnteEnd != nil && projErnteEnd != pe) ? " bis \(GartenStyle.lang(projErnteEnd))" : "").font(.caption2))
                    .foregroundStyle(Color(hex: "B45309"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(hex: "A855F7").opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private var defaultHint: some View {
        if let kt = samen.keimzeitTage, let pv = samen.pflanzVon, let ev = samen.ernteVon {
            Text("⏱️ Bei Aussaat im \(GartenStyle.lang(pv)): Keimung nach ~\(kt) Tagen, erste Ernte ab \(GartenStyle.lang(ev))")
                .font(.caption2).foregroundStyle(.secondary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
