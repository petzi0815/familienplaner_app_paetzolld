import SwiftUI

// MARK: - Cover (mit Verlaufs-Fallback)

struct EbookCover: View {
    let path: String?
    var width: CGFloat = 66
    var height: CGFloat = 92
    var emoji: String = "📚"
    var body: some View {
        Group {
            if let path {
                AuthImage(path: path, contentMode: .fill)
            } else {
                Palette.gradient(for: "ebooks").opacity(0.85)
                    .overlay(Text(emoji).font(.system(size: height * 0.42)).opacity(0.9))
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Wunschlisten-Karte

struct EbookCard: View {
    let item: EbookItem
    var onOpen: () -> Void
    var onDelete: () -> Void
    var onCheck: () -> Void = {}
    var checking: Bool = false
    @State private var expanded = false

    private var canExpand: Bool { (item.descriptionText?.count ?? 0) > 100 }

    var body: some View {
        let info = EbookStyle.statusInfo(item.status)
        HStack(alignment: .top, spacing: 12) {
            EbookCover(path: item.coverPath)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                    Spacer(minLength: 4)
                    Pill(text: "\(info.emoji) \(info.label)", color: info.color)
                }
                if let a = item.author, !a.isEmpty {
                    Text(a).font(.caption).foregroundStyle(EbookStyle.rose).lineLimit(1)
                }
                metaChips
                if item.status == "gesucht" && item.attempts > 0 { attemptLine }
                if let d = item.descriptionText, !d.isEmpty { descriptionBlock(d) }
                provenance
                actionRow
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
        .contextMenu {
            Button(role: .destructive) { onDelete() } label: { Label("Löschen", systemImage: "trash") }
        }
    }

    @ViewBuilder private var metaChips: some View {
        let chips = EbookChipData.build(item)
        if !chips.isEmpty {
            EbookFlow(spacing: 6) {
                ForEach(chips) { chip in
                    Pill(text: chip.text, color: chip.color, filled: false)
                }
            }
        }
    }

    private var attemptLine: some View {
        var text = "🔄 \(item.attempts)× versucht"
        if let la = item.lastAttempt, !la.isEmpty { text += " · zuletzt \(DateText.pretty(la))" }
        return Text(text).font(.caption2).foregroundStyle(.secondary)
    }

    private func descriptionBlock(_ d: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(d).font(.caption).foregroundStyle(.secondary)
                .lineLimit(expanded ? nil : 2)
            if canExpand {
                Button { withAnimation(.snappy(duration: 0.2)) { expanded.toggle() } } label: {
                    Text(expanded ? "Weniger ▲" : "Mehr ▼").font(.caption2.weight(.semibold))
                }
                .buttonStyle(.plain).foregroundStyle(EbookStyle.rose)
            }
        }
    }

    @ViewBuilder private var provenance: some View {
        if let text = EbookChipData.provenance(item) {
            Text(text).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            if item.status == "gesucht" {
                Button { onCheck() } label: {
                    if checking { ProgressView() }
                    else { Label("Jetzt suchen & laden", systemImage: "arrow.down.circle").font(.caption.weight(.semibold)) }
                }
                .buttonStyle(.plain).foregroundStyle(EbookStyle.amber).disabled(checking)
                .accessibilityIdentifier("ebook-check-\(item.id)")
            }
            Spacer(minLength: 0)
            Button(role: .destructive) { onDelete() } label: {
                Image(systemName: "trash").foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 2)
    }
}

// MARK: - Detail-Sheet (Ansehen + Bearbeiten)

struct EbookDetailSheet: View {
    let itemID: Int
    @EnvironmentObject private var store: EbooksStore
    @Environment(\.dismiss) private var dismiss

    @State private var item: EbookItem?
    @State private var editMode = false
    @State private var deleteConfirm = false

    // Bearbeiten-Formular
    @State private var fTitle = ""; @State private var fAuthor = ""; @State private var fPublisher = ""
    @State private var fYear = ""; @State private var fCategory = ""; @State private var fLanguage = ""
    @State private var fISBN = ""; @State private var fDescription = ""; @State private var fNotes = ""
    @State private var fCover = ""; @State private var fStatus = "gesucht"

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
        .confirmationDialog("Wirklich löschen?", isPresented: $deleteConfirm, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                if let item { Task { await store.deleteItem(item); dismiss() } }
            }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    // ── Ansehen ──
    private func detail(_ item: EbookItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    EbookCover(path: item.coverPath, width: 96, height: 134)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.title).font(.title3.weight(.bold))
                        if let a = item.author, !a.isEmpty { Text(a).foregroundStyle(EbookStyle.rose) }
                        statusToggle(item)
                    }
                    Spacer(minLength: 0)
                }

                VStack(spacing: 0) {
                    if let v = item.publisher { InfoRow(icon: "🏢", label: "Verlag", value: v) }
                    if let v = item.year { InfoRow(icon: "📅", label: "Jahr", value: v) }
                    if let v = EbookStyle.langLabel(item.language) { InfoRow(icon: "🌐", label: "Sprache", value: v) }
                    if let v = item.category { InfoRow(icon: "🏷️", label: "Kategorie", value: v) }
                    if let v = item.isbn { InfoRow(icon: "🔖", label: "ISBN", value: v) }
                    if let v = item.requestedAt { InfoRow(icon: "📌", label: "Gewünscht", value: DateText.pretty(v)) }
                    if let v = item.requestedBy { InfoRow(icon: "🙋", label: "Von", value: v) }
                    if let v = item.downloadedAt { InfoRow(icon: "⬇️", label: "Geladen am", value: DateText.pretty(v)) }
                }
                .padding(.horizontal, 4)

                if item.status == "gesucht" && item.attempts > 0 {
                    Text("🔄 \(item.attempts)× gesucht" + (item.lastAttempt.map { " · zuletzt \(DateText.pretty($0))" } ?? ""))
                        .font(.caption).foregroundStyle(.secondary)
                }

                if let d = item.descriptionText, !d.isEmpty { NoteBlock(icon: "📖", text: d, tint: EbookStyle.rose) }
                if let n = item.notes, !n.isEmpty { NoteBlock(icon: "📝", text: n, tint: .yellow) }

                // Externe Aktionen (Shelfmark-Suche / Download) sind in dieser Version 501.
                Label("Externe Suche & Download sind in dieser Version nicht verfügbar.", systemImage: "wifi.slash")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.top, 4)

                Button(role: .destructive) { deleteConfirm = true } label: {
                    Label("Aus Wunschliste löschen", systemImage: "trash").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).tint(.red).padding(.top, 4)
            }
            .padding()
        }
    }

    private func statusToggle(_ item: EbookItem) -> some View {
        let info = EbookStyle.statusInfo(item.status)
        return Button { Task { _ = await store.toggleStatus(item); await load() } } label: {
            HStack(spacing: 4) {
                Text("\(info.emoji) \(info.label)").fontWeight(.semibold)
                Text("· wechseln").font(.caption).opacity(0.9)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(info.color, in: Capsule())
            .foregroundStyle(info.color.onFill)
        }
        .buttonStyle(.plain)
    }

    // ── Bearbeiten ──
    private var editForm: some View {
        Form {
            Section("Buch") {
                LabeledContent("Titel") { TextField("Titel", text: $fTitle) }
                LabeledContent("Autor") { TextField("Autor", text: $fAuthor) }
                LabeledContent("Verlag") { TextField("Verlag", text: $fPublisher) }
                LabeledContent("Jahr") { TextField("Jahr", text: $fYear).keyboardType(.numberPad) }
                LabeledContent("Kategorie") { TextField("Kategorie", text: $fCategory) }
                LabeledContent("Sprache") { TextField("de", text: $fLanguage).textInputAutocapitalization(.never) }
                LabeledContent("ISBN") { TextField("ISBN", text: $fISBN).keyboardType(.numbersAndPunctuation) }
            }
            Section("Status") {
                Picker("Status", selection: $fStatus) {
                    ForEach(EbookStyle.statusOrder, id: \.self) { s in
                        let i = EbookStyle.statusInfo(s); Text("\(i.emoji) \(i.label)").tag(s)
                    }
                }
            }
            Section("Cover-URL") {
                TextField("https://…", text: $fCover).textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            Section("Beschreibung") {
                TextField("Beschreibung", text: $fDescription, axis: .vertical).lineLimit(3...8)
            }
            Section("Notizen") {
                TextField("Notizen", text: $fNotes, axis: .vertical).lineLimit(2...5)
            }
        }
    }

    private func startEdit(_ item: EbookItem) {
        fTitle = item.title; fAuthor = item.author ?? ""; fPublisher = item.publisher ?? ""
        fYear = item.year ?? ""; fCategory = item.category ?? ""; fLanguage = item.language ?? ""
        fISBN = item.isbn ?? ""; fDescription = item.descriptionText ?? ""; fNotes = item.notes ?? ""
        fCover = item.coverURL ?? ""; fStatus = item.status
        editMode = true
    }

    private func save() async {
        guard let item else { return }
        let fields: [String: Any] = [
            "title": fTitle.trimmingCharacters(in: .whitespaces),
            "author": fAuthor, "publisher": fPublisher, "year": fYear, "category": fCategory,
            "language": fLanguage.isEmpty ? "de" : fLanguage, "isbn": fISBN,
            "description": fDescription, "notes": fNotes, "status": fStatus, "cover_url": fCover,
        ]
        if await store.saveItem(item.id, fields: fields) {
            editMode = false
            await load()
        }
    }

    private func load() async {
        if let fresh = try? await store.api.fetchItem(itemID) { item = fresh }
        else { item = store.items.first { $0.id == itemID } }
    }
}

// MARK: - Chip-Daten + Flow-Layout

struct EbookChip: Identifiable { let id = UUID(); let text: String; let color: Color }

enum EbookChipData {
    static func build(_ item: EbookItem) -> [EbookChip] {
        var chips: [EbookChip] = []
        if let p = item.publisher, !p.isEmpty { chips.append(EbookChip(text: p, color: EbookStyle.rose)) }
        if let y = item.year, !y.isEmpty { chips.append(EbookChip(text: "📅 \(y)", color: .gray)) }
        if let l = EbookStyle.langLabel(item.language) { chips.append(EbookChip(text: l, color: .gray)) }
        if let c = item.category, !c.isEmpty { chips.append(EbookChip(text: c, color: EbookStyle.purple)) }
        return chips
    }

    static func provenance(_ item: EbookItem) -> String? {
        guard let ra = item.requestedAt, !ra.isEmpty else { return nil }
        var text = "Gewünscht am \(DateText.pretty(ra))"
        if let by = item.requestedBy, !by.isEmpty { text += " von \(by)" }
        if let da = item.downloadedAt, !da.isEmpty { text += " · Geladen am \(DateText.pretty(da))" }
        return text
    }
}

/// Einfaches Fließ-Layout (umbrechende Chips) — vermeidet Overflow ohne horizontales Scrollen.
struct EbookFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        let width = maxWidth.isFinite ? maxWidth : x
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.width && x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            sub.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
