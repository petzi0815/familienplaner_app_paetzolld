import SwiftUI

// Die drei listenbasierten Tabs (Vorrat / Einkauf / Ablaufend) + geteilte Bausteine.

// MARK: - Geteiltes Thumbnail

struct VorratThumb: View {
    let item: VorratItem
    var size: CGFloat = 44
    var body: some View {
        Group {
            if let path = item.imagePath {
                AuthImage(path: path, contentMode: .fill)
            } else {
                Palette.gradient(for: "vorratskammer").opacity(0.18)
                    .overlay(Text(VorratKat.info(item.kategorie).emoji).font(.title3))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - MHD-Pille (luminanz-sicherer Text auf datengetriebener Farbe)

struct VorratMhdPill: View {
    let info: VorratMhd.Info
    var date: String? = nil
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: info.expired ? "exclamationmark.triangle.fill" : "calendar")
            if let date { Text("MHD \(date) · \(info.label)") } else { Text(info.label) }
        }
        .font(.caption2.weight(.bold))
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(info.color, in: Capsule())
        .foregroundStyle(info.color.onFill)
    }
}

// MARK: - Vorrat-Tab (nach Kategorie gruppiert)

struct VorratVorratView: View {
    @EnvironmentObject private var store: VorratStore
    @State private var showCreate = false
    @State private var editItem: VorratItem?
    @State private var deleteTarget: VorratItem?

    var body: some View {
        VStack(spacing: 0) {
            toolbar.padding(.top, 8).padding(.bottom, 6)
            if store.groupedItems.isEmpty {
                ScrollView {
                    AreaEmptyState(emoji: "🗄️", title: "Noch keine Lebensmittel erfasst",
                                   hint: "Tippe auf + Neu, um etwas hinzuzufügen.")
                        .frame(maxWidth: .infinity).frame(minHeight: 260)
                }
                .refreshable { await store.loadAll() }
            } else {
                // List statt ScrollView → native Wisch-Aktionen (Verbraucht/Löschen); Karten-Look via clear rows.
                List {
                    ForEach(store.groupedItems, id: \.kategorie) { group in
                        Section {
                            ForEach(group.items) { item in row(item) }
                        } header: { sectionHeader(group.kategorie, group.items.count) }
                        .textCase(nil)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshable { await store.loadAll() }
            }
        }
        .task(id: store.filters.search) {
            try? await Task.sleep(nanoseconds: 350_000_000)
            if !Task.isCancelled { await store.applySearch() }
        }
        .sheet(isPresented: $showCreate) { VorratItemFormSheet(item: nil).environmentObject(store) }
        .sheet(item: $editItem) { it in VorratItemFormSheet(item: it).environmentObject(store) }
        .confirmationDialog("Wirklich löschen? Das Lebensmittel wird unwiderruflich gelöscht.",
                            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
                            titleVisibility: .visible) {
            Button("Löschen", role: .destructive) { if let t = deleteTarget { Task { await store.delete(t) } }; deleteTarget = nil }
            Button("Abbrechen", role: .cancel) { deleteTarget = nil }
        }
    }

    private var toolbar: some View {
        VStack(spacing: 8) {
            AreaSearchField(placeholder: "Suchen …", text: $store.filters.search)
            HStack {
                Spacer()
                Button { showCreate = true } label: {
                    Label("Neu", systemImage: "plus.circle.fill").font(.subheadline.weight(.semibold))
                }
            }
            .padding(.horizontal, 14)
        }
    }

    private func sectionHeader(_ kat: String, _ count: Int) -> some View {
        let info = VorratKat.info(kat)
        return Text("\(info.emoji) \(info.label) (\(String(count)))")
            .font(.caption.weight(.bold)).textCase(.uppercase).foregroundStyle(.secondary)
    }

    /// Item-Karte als List-Zeile (transparente Zeile) mit nativen Wisch-Aktionen (Verbraucht + Löschen).
    private func row(_ item: VorratItem) -> some View {
        VorratItemCard(item: item,
                       onConsume: { Task { await store.consume(item) } },
                       onEdit: { editItem = item },
                       onDelete: { deleteTarget = item })
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 14))
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) { deleteTarget = item } label: {
                    Label("Löschen", systemImage: "trash")
                }
                Button { Task { await store.consume(item) } } label: {
                    Label("Verbraucht", systemImage: "checkmark.circle.fill")
                }
                .tint(Color(hex: "F97316"))
            }
    }
}

// MARK: - Item-Karte (Vorrat)

struct VorratItemCard: View {
    let item: VorratItem
    var onConsume: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VorratThumb(item: item, size: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                if item.marke != nil || item.menge != nil {
                    HStack(spacing: 4) {
                        if let m = item.marke { Text(m) }
                        if let q = item.menge { Text("· \(q)") }
                    }
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                if let info = VorratMhd.info(item.mhd) {
                    VorratMhdPill(info: info, date: VorratMhd.formatDate(item.mhd))
                }
            }
            Spacer(minLength: 4)
            HStack(spacing: 10) {
                iconButton("checkmark.circle.fill", Color(hex: "F97316"), "Als verbraucht markieren", onConsume)
                iconButton("pencil.circle.fill", Color(hex: "2563EB"), "Bearbeiten", onEdit)
                iconButton("trash.circle.fill", Color(hex: "EF4444"), "Löschen", onDelete)
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func iconButton(_ name: String, _ color: Color, _ hint: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.title3).foregroundStyle(color)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hint)
    }
}

// MARK: - Einkauf-Tab (Einkaufsliste)

struct VorratEinkaufView: View {
    @EnvironmentObject private var store: VorratStore

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if store.einkauf.isEmpty {
                    AreaEmptyState(emoji: "🛒", title: "Einkaufsliste ist leer — alles da!").frame(minHeight: 260)
                } else {
                    ForEach(store.einkauf) { item in row(item) }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
        }
        .refreshable { await store.loadAll() }
    }

    private func row(_ item: VorratItem) -> some View {
        HStack(spacing: 12) {
            VorratThumb(item: item, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                if item.marke != nil || item.menge != nil {
                    HStack(spacing: 4) {
                        if let m = item.marke { Text(m) }
                        if let q = item.menge { Text("· \(q)") }
                    }
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            VStack(spacing: 6) {
                Button { Task { await store.wiederDa(item) } } label: {
                    Text("Wieder da!").font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent).tint(.green)
                Button { Task { await store.keinRestock(item) } } label: {
                    Text("Kein Restock").font(.caption)
                }
                .buttonStyle(.bordered).tint(.gray)
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Ablaufend-Tab (nur lesend)

struct VorratAblaufendView: View {
    @EnvironmentObject private var store: VorratStore

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if store.ablaufend.isEmpty {
                    AreaEmptyState(emoji: "✅", title: "Nichts läuft demnächst ab!").frame(minHeight: 260)
                } else {
                    ForEach(store.ablaufend) { item in row(item) }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
        }
        .refreshable { await store.loadAll() }
    }

    private func row(_ item: VorratItem) -> some View {
        let kat = VorratKat.info(item.kategorie)
        return HStack(spacing: 12) {
            VorratThumb(item: item, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                if let m = item.marke { Text(m).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                Text("\(kat.emoji) \(kat.label)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 3) {
                if let info = VorratMhd.info(item.mhd) { VorratMhdPill(info: info) }
                if let d = VorratMhd.formatDate(item.mhd) { Text("MHD: \(d)").font(.caption2).foregroundStyle(.secondary) }
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
