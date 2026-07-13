import SwiftUI

/// Dünger-Tab: Suche + Typ-Pills + Vorrätig-Pills, Inline-Add, Stats-Leiste, 2-spaltiges Raster,
/// Detail-Sheet mit Vorrätig-Umschalter + Kauflink + Löschen.
struct GartenDuengerView: View {
    @EnvironmentObject private var store: GartenStore
    @State private var detail: GartenDuenger?
    @State private var showAdd = false
    private let brown = Color(hex: "A0522D")
    private let cols = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                AreaSearchField(placeholder: "Dünger suchen …", text: $store.duengerFilter.search)
                typPills
                vorraetigPills
                addSection
                statsBar
                grid
            }
            .padding(.bottom, 24)
        }
        .refreshable { await store.reloadDuenger() }
        .task(id: store.duengerFilter) {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if !Task.isCancelled { await store.reloadDuenger() }
        }
        .sheet(item: $detail) { d in
            GartenDuengerDetailSheet(initial: d).environmentObject(store)
        }
    }

    private var typPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterPill(label: "Alle Typen", selected: store.duengerFilter.typ.isEmpty, color: brown) {
                    store.duengerFilter.typ = ""
                }
                ForEach(GartenStyle.duengerTypen, id: \.self) { t in
                    FilterPill(label: "\(GartenStyle.duengerTypEmoji[t] ?? "💩") \(GartenStyle.cap(t))",
                               selected: store.duengerFilter.typ == t,
                               color: GartenStyle.duengerTypColor[t] ?? brown) {
                        store.duengerFilter.typ = (store.duengerFilter.typ == t) ? "" : t
                    }
                }
            }
            .padding(.horizontal, 14)
        }
    }

    private var vorraetigPills: some View {
        HStack(spacing: 8) {
            FilterPill(label: "✅ Vorrätig", selected: store.duengerFilter.vorraetig == 1, color: Color(hex: "16A34A")) {
                store.duengerFilter.vorraetig = (store.duengerFilter.vorraetig == 1) ? -1 : 1
            }
            FilterPill(label: "❌ Fehlt", selected: store.duengerFilter.vorraetig == 0, color: Color(hex: "DC2626")) {
                store.duengerFilter.vorraetig = (store.duengerFilter.vorraetig == 0) ? -1 : 0
            }
            Spacer()
        }
        .padding(.horizontal, 14)
    }

    @ViewBuilder private var addSection: some View {
        if showAdd {
            GartenNameAddForm(title: "💩 Neuen Dünger hinzufügen", accent: brown, placeholder: "Name eingeben …",
                              onCancel: { showAdd = false }) { name in
                let ok = await store.addDuenger(name: name)
                if ok { showAdd = false }
                return ok
            }
            .padding(.horizontal, 14)
        } else {
            Button { withAnimation { showAdd = true } } label: {
                Label("Neuen Dünger hinzufügen", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(brown, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(brown.onFill)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
        }
    }

    @ViewBuilder private var statsBar: some View {
        if let s = store.stats {
            HStack(spacing: 10) {
                AreaStatTile(value: "\(s.duengerGesamt)", label: "Gesamt", color: brown)
                AreaStatTile(value: "\(s.duengerVorraetig)", label: "Vorrätig", color: Color(hex: "16A34A"))
                AreaStatTile(value: "\(s.duengerFehlend)", label: "Bedarf fehlt", color: Color(hex: "EA580C"))
            }
            .padding(.horizontal, 14)
        }
    }

    @ViewBuilder private var grid: some View {
        if store.duenger.isEmpty {
            AreaEmptyState(emoji: "💩", title: "Noch kein Dünger erfasst!", hint: "Füge deinen ersten Dünger hinzu")
                .frame(minHeight: 220)
        } else {
            LazyVGrid(columns: cols, spacing: 12) {
                ForEach(store.duenger) { d in
                    GartenDuengerCard(duenger: d) { detail = d }
                }
            }
            .padding(.horizontal, 14).padding(.top, 4)
        }
    }
}

// MARK: - Karte

struct GartenDuengerCard: View {
    let duenger: GartenDuenger
    var onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                Group {
                    if let path = duenger.firstImagePath {
                        AuthImage(path: path, contentMode: .fill)
                    } else {
                        LinearGradient(colors: [Color(hex: "FEF3C7"), Color(hex: "FDE68A")], startPoint: .topLeading, endPoint: .bottomTrailing)
                            .overlay(Text(duenger.typEmoji).font(.system(size: 46)).opacity(0.7))
                    }
                }
                .frame(height: 130).frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text(duenger.vorraetig ? "✅ Vorrätig" : "❌ Fehlt")
                    .font(.caption2.weight(.bold)).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(duenger.vorraetig ? Color(hex: "16A34A") : Color(hex: "EF4444"), in: Capsule())
                    .padding(6)
            }
            Text(duenger.name).font(.subheadline.weight(.semibold)).lineLimit(1)
            if let m = duenger.marke, !m.isEmpty { Text(m).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            if duenger.typ != nil {
                Pill(text: "\(duenger.typEmoji) \(duenger.typLabel)", color: duenger.typColor)
            }
            if let n = duenger.naehrstoffe, !n.isEmpty {
                Text(n).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

// MARK: - Detail

struct GartenDuengerDetailSheet: View {
    @State private var duenger: GartenDuenger
    @EnvironmentObject private var store: GartenStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    init(initial: GartenDuenger) { _duenger = State(initialValue: initial) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    hero
                    VStack(alignment: .leading, spacing: 6) {
                        Text(duenger.name).font(.title2.weight(.bold))
                        if let m = duenger.marke, !m.isEmpty { Text(m).foregroundStyle(.secondary) }
                    }
                    badges
                    infoRows
                    if let b = duenger.beschreibung, !b.isEmpty { NoteBlock(icon: "📝", text: b, tint: Color(hex: "F59E0B")) }
                    if let n = duenger.notizen, !n.isEmpty { NoteBlock(icon: "📝", text: n, tint: .yellow) }
                    if let url = duenger.kauflinkURL {
                        Link(destination: url) {
                            Label("Kauflink öffnen", systemImage: "cart")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity).padding(.vertical, 13)
                                .background(Color(hex: "A0522D"), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .foregroundStyle(.white)
                        }
                    }
                    deleteButton
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } } }
            .confirmationDialog("Dünger wirklich löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) { Task { await store.deleteDuenger(duenger.id); dismiss() } }
                Button("Abbrechen", role: .cancel) {}
            }
        }
    }

    @ViewBuilder private var hero: some View {
        Group {
            if let path = duenger.firstImagePath {
                AuthImage(path: path, contentMode: .fill)
            } else {
                LinearGradient(colors: [Color(hex: "FEF3C7"), Color(hex: "FDE68A")], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(Text(duenger.typEmoji).font(.system(size: 80)).opacity(0.6))
            }
        }
        .frame(height: 200).frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var badges: some View {
        HStack(spacing: 8) {
            if duenger.typ != nil {
                Pill(text: "\(duenger.typEmoji) \(duenger.typLabel)", color: duenger.typColor)
            }
            Button {
                let nv = !duenger.vorraetig
                duenger.vorraetig = nv   // optimistisch
                Task { await store.setDuengerVorraetig(duenger.id, to: nv) }
            } label: {
                Text(duenger.vorraetig ? "✅ Vorrätig (tippen zum Wechseln)" : "❌ Nicht vorrätig (tippen zum Wechseln)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background((duenger.vorraetig ? Color(hex: "16A34A") : Color(hex: "DC2626")).opacity(0.15), in: Capsule())
                    .foregroundStyle(duenger.vorraetig ? Color(hex: "15803D") : Color(hex: "B91C1C"))
            }
            .buttonStyle(.plain)
        }
    }

    private var infoRows: some View {
        VStack(spacing: 0) {
            if let v = duenger.naehrstoffe { InfoRow(icon: "🧪", label: "Nährstoffe (NPK)", value: v) }
            if let v = duenger.dosierung { InfoRow(icon: "⚖️", label: "Dosierung", value: v) }
            if let v = duenger.intervallWochen { InfoRow(icon: "🗓️", label: "Intervall", value: "alle \(v) Wochen") }
            if let v = GartenStyle.rangeText(duenger.saisonVon, duenger.saisonBis, long: false) { InfoRow(icon: "🌤️", label: "Saison", value: v) }
            if let v = duenger.geeignetFuer { InfoRow(icon: "🌿", label: "Geeignet für", value: v) }
            if let v = duenger.erfasstAm { InfoRow(icon: "📅", label: "Erfasst", value: DateText.longNoWeekday(v)) }
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) { confirmDelete = true } label: {
            Label("Dünger löschen", systemImage: "trash")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(Color.red, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}
