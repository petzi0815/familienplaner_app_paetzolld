import SwiftUI

/// Pflanzen-Tab: Suche + Art-Pills + Bewässerungs-Pills, 2-spaltiges Kartenraster (Art-Emoji, kein Foto),
/// read-only Detail-Sheet (Pflanzen werden via Telegram/Ole erfasst).
struct GartenPflanzenView: View {
    @EnvironmentObject private var store: GartenStore
    @State private var detail: GartenPflanze?
    private let cols = [GridItem(.adaptive(minimum: 150), spacing: 12)]
    private let green = Color(hex: "34C759")

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                AreaSearchField(placeholder: "Pflanzen suchen …", text: $store.pflanzenFilter.search)
                artPills
                bewaesserungPills
                grid
            }
            .padding(.bottom, 24)
        }
        .refreshable { await store.reloadPflanzen() }
        .task(id: store.pflanzenFilter) {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if !Task.isCancelled { await store.reloadPflanzen() }
        }
        .sheet(item: $detail) { p in
            GartenPflanzeDetailSheet(pflanze: p)
        }
    }

    private var artPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterPill(label: "Alle", selected: store.pflanzenFilter.art == nil, color: green) {
                    store.pflanzenFilter.art = nil
                }
                ForEach(store.arten, id: \.self) { art in
                    FilterPill(label: "\(GartenStyle.artEmoji(art)) \(GartenStyle.cap(art))",
                               selected: store.pflanzenFilter.art == art, color: green) {
                        store.pflanzenFilter.art = (store.pflanzenFilter.art == art) ? nil : art
                    }
                }
            }
            .padding(.horizontal, 14)
        }
    }

    private var bewaesserungPills: some View {
        HStack(spacing: 8) {
            FilterPill(label: "💧 Hunter", selected: store.pflanzenFilter.bewaesserung == "hunter", color: Color(hex: "2563EB")) {
                toggleBew("hunter")
            }
            FilterPill(label: "🪣 Manuell", selected: store.pflanzenFilter.bewaesserung == "manuell", color: Color(hex: "D97706")) {
                toggleBew("manuell")
            }
            Spacer()
        }
        .padding(.horizontal, 14)
    }

    private func toggleBew(_ v: String) {
        store.pflanzenFilter.bewaesserung = (store.pflanzenFilter.bewaesserung == v) ? nil : v
    }

    @ViewBuilder private var grid: some View {
        if store.pflanzen.isEmpty {
            AreaEmptyState(emoji: "🔍", title: "Keine Pflanzen gefunden!", hint: "Versuch andere Filter 🎯")
                .frame(minHeight: 260)
        } else {
            LazyVGrid(columns: cols, spacing: 12) {
                ForEach(store.pflanzen) { p in
                    GartenPflanzeCard(pflanze: p) { detail = p }
                }
            }
            .padding(.horizontal, 14).padding(.top, 4)
        }
    }
}

// MARK: - Karte

struct GartenPflanzeCard: View {
    let pflanze: GartenPflanze
    var onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [Color(hex: "D1FAE5"), Color(hex: "DCFCE7")], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(Text(pflanze.emoji).font(.system(size: 52)).opacity(0.6))
                    .frame(height: 130)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text(pflanze.bewaesserungBadge)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(pflanze.bewaesserungColor.onFill)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(pflanze.bewaesserungColor, in: Capsule())
                    .padding(6)
            }
            Text(pflanze.name).font(.subheadline.weight(.semibold)).lineLimit(1)
            HStack(spacing: 3) {
                Text("\(pflanze.emoji) \(pflanze.artLabel)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if let s = pflanze.standort, !s.isEmpty {
                    Text("· \(s)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

// MARK: - Detail (read-only)

struct GartenPflanzeDetailSheet: View {
    let pflanze: GartenPflanze
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    LinearGradient(colors: [Color(hex: "D1FAE5"), Color(hex: "DCFCE7")], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .frame(height: 200)
                        .overlay(Text(pflanze.emoji).font(.system(size: 90)).opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(pflanze.name).font(.title2.weight(.bold))
                        if let s = pflanze.sorte, !s.isEmpty { Text(s).foregroundStyle(.secondary) }
                    }

                    HStack(spacing: 8) {
                        Pill(text: "\(pflanze.emoji) \(pflanze.artLabel)", color: Color(hex: "10B981"), filled: false)
                        Pill(text: pflanze.bewaesserungBadge, color: pflanze.bewaesserungColor)
                    }

                    VStack(spacing: 0) {
                        if let v = pflanze.standort, !v.isEmpty { InfoRow(icon: "📍", label: "Standort", value: v) }
                        if let v = pflanze.erfasstAm { InfoRow(icon: "📅", label: "Erfasst", value: DateText.longNoWeekday(v)) }
                    }

                    if let b = pflanze.beschreibung, !b.isEmpty { NoteBlock(icon: "📝", text: b, tint: Color(hex: "10B981")) }
                    if let n = pflanze.notizen, !n.isEmpty { NoteBlock(icon: "📝", text: n, tint: .yellow) }
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } }
            }
        }
    }
}
