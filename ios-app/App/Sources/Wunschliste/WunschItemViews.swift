import SwiftUI

// MARK: - Item-Karte (Listenzeile)

struct WunschItemCard: View {
    let item: WunschItem
    var onOpen: () -> Void
    var onCycle: () -> Void
    var onDelete: () -> Void

    @State private var confirmDelete = false

    private var isGifted: Bool { item.status == "geschenkt" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                imageTile
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .top, spacing: 6) {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                            .strikethrough(isGifted, color: .secondary)
                            .foregroundStyle(isGifted ? .secondary : .primary)
                            .lineLimit(2)
                        Spacer(minLength: 4)
                        statusButton
                    }
                    if let d = item.description, !d.isEmpty {
                        Text(d).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    badges
                    if let ean = item.ean, !ean.isEmpty {
                        Text("EAN: \(ean)").font(.caption2.monospaced()).foregroundStyle(.secondary)
                    }
                    if let n = item.notes, !n.isEmpty {
                        Text(n).font(.caption2).italic().foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onOpen() }

            actionBar
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isGifted ? Color.green.opacity(0.5) : WunschStyle.accent.opacity(0.25), lineWidth: 1)
        )
        .opacity(isGifted ? 0.75 : 1)
        .confirmationDialog("\"\(item.title)\" löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive, action: onDelete)
            Button("Abbrechen", role: .cancel) {}
        }
    }

    // ── Bild-Tile (externe URL via AuthImage, sonst Emoji-Fallback) ──
    private var imageTile: some View {
        Group {
            if let u = item.imageURL, !u.isEmpty {
                AuthImage(path: u, contentMode: .fill)
            } else {
                Palette.gradient(for: "wunschliste").opacity(0.2)
                    .overlay(Text(item.fallbackEmoji).font(.system(size: 28)))
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var statusButton: some View {
        let info = WunschStyle.statusInfo(item.status)
        return Button(action: onCycle) {
            Text("\(info.emoji) \(info.label)")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(info.color, in: Capsule())
                .foregroundStyle(info.color.onFill)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var badges: some View {
        let hasAny = (item.price?.isEmpty == false) || item.showCategoryPill || item.hasURL || (item.purchasedBy?.isEmpty == false)
        if hasAny {
            FlowLayout(spacing: 6) {
                if let p = item.price, !p.isEmpty { Pill(text: "💰 \(p)", color: .green, filled: false) }
                if item.showCategoryPill, let c = item.category { Pill(text: c, color: WunschStyle.accent, filled: false) }
                if let u = item.url, !u.isEmpty, let link = URL(string: u.hasPrefix("http") ? u : "https://\(u)") {
                    Link(destination: link) { Pill(text: "🔗 Link", color: Color(hex: "4F46E5"), filled: false) }
                        .buttonStyle(.plain)
                }
                if let b = item.purchasedBy, !b.isEmpty { Pill(text: "👤 \(b)", color: Color(hex: "2563EB"), filled: false) }
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 14) {
            ShareLink(item: WunschShare.text(item: item, eventName: item.eventName)) {
                Label("Teilen", systemImage: "square.and.arrow.up").font(.caption.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(WunschStyle.accent)

            Spacer(minLength: 0)

            Menu {
                Button { onOpen() } label: { Label("Öffnen / Bearbeiten", systemImage: "pencil") }
                // Externer Preisvergleich ist nicht migriert (501) → deaktiviert.
                Button {} label: { Label("Preisvergleich (nicht verfügbar)", systemImage: "eurosign.circle") }
                    .disabled(true)
                Divider()
                Button(role: .destructive) { confirmDelete = true } label: { Label("Löschen", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis.circle").font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 2)
    }
}

// MARK: - Detail-Sheet (Ansehen + Bearbeiten)

struct WunschItemDetailSheet: View {
    let itemID: Int
    @EnvironmentObject private var store: WunschlisteStore
    @Environment(\.dismiss) private var dismiss

    @State private var item: WunschItem?
    @State private var editMode = false
    @State private var fullscreen: WunschImageRef?
    @State private var confirmDelete = false

    // Bearbeiten-Formular (Kategorie hier als Freitext, wie im Original-Edit)
    @State private var fTitle = ""; @State private var fDesc = ""; @State private var fPrice = ""
    @State private var fCategory = ""; @State private var fURL = ""; @State private var fEAN = ""
    @State private var fNotes = ""

    var body: some View {
        NavigationStack {
            Group {
                if let item {
                    if editMode { editForm } else { detail(item) }
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(editMode ? "Abbrechen" : "Schließen") {
                        if editMode { editMode = false } else { dismiss() }
                    }
                }
                if let item, !editMode {
                    ToolbarItem(placement: .primaryAction) {
                        Button { startEdit(item) } label: { Label("Bearbeiten", systemImage: "pencil") }
                    }
                }
                if editMode {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Speichern") { Task { await save() } }
                            .disabled(fTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
        .task { await load() }
        .fullScreenCover(item: $fullscreen) { ref in WunschFullscreenImage(path: ref.path) }
    }

    // ── Ansehen ──
    private func detail(_ item: WunschItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let u = item.imageURL, !u.isEmpty {
                    AuthImage(path: u, contentMode: .fit)
                        .frame(maxHeight: 260).frame(maxWidth: .infinity)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                        .onTapGesture { fullscreen = WunschImageRef(path: u) }
                } else {
                    Palette.gradient(for: "wunschliste").opacity(0.18)
                        .frame(height: 160)
                        .overlay(Text(item.fallbackEmoji).font(.system(size: 60)).opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                Text(item.title)
                    .font(.title2.weight(.bold))
                    .strikethrough(item.status == "geschenkt", color: .secondary)

                if let e = item.eventName {
                    Text("\(item.eventEmoji ?? "🎁") \(e)").font(.subheadline).foregroundStyle(.secondary)
                }

                // Status-Zyklus (tippen zum Wechseln)
                let info = WunschStyle.statusInfo(item.status)
                Button { Task { await store.cycleStatus(item); await load() } } label: {
                    HStack {
                        Text("\(info.emoji) \(info.label)").fontWeight(.semibold)
                        Text("· tippen zum Wechseln").font(.caption).opacity(0.9)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(info.color, in: Capsule())
                    .foregroundStyle(info.color.onFill)
                }
                .buttonStyle(.plain)

                VStack(spacing: 0) {
                    if let v = item.price, !v.isEmpty { InfoRow(icon: "💰", label: "Preis", value: v, valueColor: .green) }
                    if let v = item.category, !v.isEmpty { InfoRow(icon: "🏷️", label: "Kategorie", value: v) }
                    if let v = item.purchasedBy, !v.isEmpty { InfoRow(icon: "👤", label: "Gekauft von", value: v) }
                    if let v = item.ean, !v.isEmpty { InfoRow(icon: "📊", label: "EAN / ISBN", value: v) }
                }
                .padding(.horizontal, 4)

                if let u = item.url, !u.isEmpty, let link = URL(string: u.hasPrefix("http") ? u : "https://\(u)") {
                    Link(destination: link) { Label("Link öffnen", systemImage: "link") }
                }

                Group {
                    if let d = item.description, !d.isEmpty { NoteBlock(icon: "📝", text: d, tint: Color(hex: "F59E0B")) }
                    if let n = item.notes, !n.isEmpty { NoteBlock(icon: "📝", text: n, tint: .yellow) }
                }

                WunschPricePanel(entries: item.priceComparison)

                ShareLink(item: WunschShare.text(item: item, eventName: item.eventName)) {
                    Label("Teilen", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("Geschenk löschen", systemImage: "trash").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            .padding()
        }
        .confirmationDialog("\"\(item.title)\" löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) { Task { await store.deleteItem(item); dismiss() } }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    // ── Bearbeiten ──
    private var editForm: some View {
        Form {
            Section("Geschenk") {
                TextField("Titel *", text: $fTitle)
                TextField("Beschreibung", text: $fDesc, axis: .vertical).lineLimit(2...5)
            }
            Section("Details") {
                TextField("💰 Preis (z.B. ~9,99€)", text: $fPrice)
                TextField("Kategorie", text: $fCategory)
                TextField("🔗 Link", text: $fURL)
                    .keyboardType(.URL).autocorrectionDisabled().textInputAutocapitalization(.never)
                TextField("📊 EAN / ISBN", text: $fEAN).font(.body.monospaced())
            }
            Section("Notizen") {
                TextField("Notizen", text: $fNotes, axis: .vertical).lineLimit(2...5)
            }
        }
    }

    private func startEdit(_ item: WunschItem) {
        fTitle = item.title; fDesc = item.description ?? ""; fPrice = item.price ?? ""
        fCategory = item.category ?? ""; fURL = item.url ?? ""; fEAN = item.ean ?? ""
        fNotes = item.notes ?? ""
        editMode = true
    }

    private func save() async {
        guard let item else { return }
        let ok = await store.saveItem(item.id, title: fTitle, description: fDesc, price: fPrice,
                                      category: fCategory, url: fURL, ean: fEAN, notes: fNotes)
        if ok { editMode = false; await load() }
    }

    private func load() async {
        if let fresh = try? await store.api.fetchItem(itemID) { item = fresh }
        else { item = store.items.first { $0.id == itemID } }
    }
}

// MARK: - Preisvergleich-Panel (gespeicherte price_comparison-Daten)

struct WunschPricePanel: View {
    let entries: [WunschPriceEntry]
    var body: some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("💰 Preisvergleich").font(.subheadline.weight(.semibold))
                ForEach(entries) { e in
                    HStack {
                        Text(e.shop).font(.subheadline)
                        Spacer()
                        Text(e.price).font(.subheadline.weight(.semibold)).foregroundStyle(.green)
                        if let u = e.url, let link = URL(string: u.hasPrefix("http") ? u : "https://\(u)") {
                            Link(destination: link) { Image(systemName: "arrow.up.right.square") }
                        }
                    }
                    .padding(.vertical, 2)
                }
                Text("Live-Preisvergleich nicht verfügbar.").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

// MARK: - Vollbild

struct WunschFullscreenImage: View {
    let path: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            AuthImage(path: path, contentMode: .fit).ignoresSafeArea()
            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill").font(.title).foregroundStyle(.white.opacity(0.9))
                    }.padding()
                }
                Spacer()
            }
        }
    }
}

// MARK: - Teilen-Text (nativer Share-Sheet ersetzt die Fake-Kontaktliste)

enum WunschShare {
    static func text(item: WunschItem, eventName: String?) -> String {
        var lines = ["🎁 Geschenkidee für Samu (\(eventName ?? item.eventName ?? "")):", "", item.title]
        if let d = item.description, !d.isEmpty { lines.append(d) }
        if let p = item.price, !p.isEmpty { lines.append("💰 \(p)") }
        if let u = item.url, !u.isEmpty { lines.append("🔗 \(u)") }
        return lines.joined(separator: "\n")
    }
}
