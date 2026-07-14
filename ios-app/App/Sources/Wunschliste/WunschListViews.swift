import SwiftUI

// MARK: - Event-Chipleiste (primärer Ansichtswechsel: Alle ↔ einzelner Anlass)

struct WunschEventChipBar: View {
    @ObservedObject var store: WunschlisteStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(selected: store.selectedEventID == nil) {
                    Text("🎁 Alle").font(.footnote.weight(.semibold))
                } action: { Task { await store.selectEvent(nil) } }

                ForEach(store.events) { ev in
                    let sel = store.selectedEventID == ev.id
                    chip(selected: sel) {
                        HStack(spacing: 5) {
                            Text("\(ev.emoji) \(ev.name)").font(.footnote.weight(.semibold)).lineLimit(1)
                            if ev.openCount > 0 {
                                Text("\(ev.openCount)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(sel ? Color.white.opacity(0.9) : .secondary)
                            }
                            if !ev.erinnerungenAktiv { Text("🔕").font(.system(size: 10)) }
                            if let cd = ev.countdown { countdownBadge(cd) }
                        }
                    } action: { Task { await store.selectEvent(ev.id) } }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func chip<Content: View>(selected: Bool, @ViewBuilder content: () -> Content,
                                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            content()
                .padding(.horizontal, 13).padding(.vertical, 8)
                .background(selected ? AnyShapeStyle(Palette.gradient(for: "wunschliste"))
                                     : AnyShapeStyle(Color(.secondarySystemBackground)), in: Capsule())
                .foregroundStyle(selected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private func countdownBadge(_ cd: WunschCountdown) -> some View {
        Text(cd.text)
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(cd.color, in: Capsule())
            .foregroundStyle(cd.color.onFill)
    }
}

// MARK: - Inhalt (aktive-Event-Karte, Stats-Filter, Suche, Item-Liste)

struct WunschItemsView: View {
    @EnvironmentObject private var store: WunschlisteStore
    var onAddItem: () -> Void

    @State private var detail: WunschItem?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let ev = store.selectedEvent {
                    WunschActiveEventCard(event: ev).environmentObject(store)
                }
                WunschStatPills().environmentObject(store)
                AreaSearchField(placeholder: "Geschenke suchen …", text: $store.search)

                if store.selectedEventID != nil {
                    addItemButton
                }
                itemList
            }
            .padding(.bottom, 28)
        }
        .refreshable { await store.loadAll() }
        .sheet(item: $detail) { it in
            WunschItemDetailSheet(itemID: it.id).environmentObject(store)
        }
    }

    private var addItemButton: some View {
        Button(action: onAddItem) {
            Label("Geschenk hinzufügen", systemImage: "plus")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(WunschStyle.accent.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                }
                .foregroundStyle(WunschStyle.accent)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
    }

    @ViewBuilder private var itemList: some View {
        let visible = store.visibleItems
        if visible.isEmpty {
            emptyState
        } else if store.selectedEventID == nil {
            // Alle-Modus: nach Event gruppiert.
            LazyVStack(spacing: 16) {
                ForEach(store.groupedItems) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Text("\(group.emoji) \(group.name)").font(.headline)
                            if let cd = group.event?.countdown {
                                Text(cd.text).font(.caption2.weight(.bold))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(cd.color, in: Capsule()).foregroundStyle(cd.color.onFill)
                            }
                            Text("(\(group.items.count))").font(.caption).foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        ForEach(group.items) { it in card(it) }
                    }
                }
            }
        } else {
            LazyVStack(spacing: 10) {
                ForEach(visible) { it in card(it) }
            }
        }
    }

    private func card(_ it: WunschItem) -> some View {
        WunschItemCard(item: it,
                       onOpen: { detail = it },
                       onCycle: { Task { await store.cycleStatus(it) } },
                       onDelete: { Task { await store.deleteItem(it) } })
            .padding(.horizontal, 14)
    }

    @ViewBuilder private var emptyState: some View {
        if store.events.isEmpty {
            AreaEmptyState(emoji: "🎀", title: "Noch keine Anlässe",
                           hint: "Lege oben mit + einen neuen Anlass an (Ostern, Geburtstag …).")
                .frame(minHeight: 240)
        } else if !store.search.isEmpty || store.statusFilter != nil {
            AreaEmptyState(emoji: "🔍", title: "Nichts gefunden", hint: "Andere Suche oder anderen Status probieren.")
                .frame(minHeight: 240)
        } else {
            AreaEmptyState(emoji: "🎀", title: "Noch keine Geschenke",
                           hint: store.selectedEventID != nil ? "Füge oben das erste Geschenk hinzu!" : "Wähle einen Anlass und füge Geschenke hinzu.")
                .frame(minHeight: 240)
        }
    }
}

// MARK: - Stats-Pillen (zugleich Status-Filter)

struct WunschStatPills: View {
    @EnvironmentObject private var store: WunschlisteStore

    var body: some View {
        let s = store.stats
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                pill(emoji: "🎁", count: s.total, label: "Gesamt", color: WunschStyle.accent,
                     selected: store.statusFilter == nil) { store.statusFilter = nil }
                pill(emoji: "⬜", count: s.offen, label: "Offen", color: WunschStyle.statusInfo("offen").color,
                     selected: store.statusFilter == "offen") { store.toggleStatusFilter("offen") }
                pill(emoji: "🛒", count: s.gekauft, label: "Gekauft", color: WunschStyle.statusInfo("gekauft").color,
                     selected: store.statusFilter == "gekauft") { store.toggleStatusFilter("gekauft") }
                pill(emoji: "✅", count: s.geschenkt, label: "Geschenkt", color: WunschStyle.statusInfo("geschenkt").color,
                     selected: store.statusFilter == "geschenkt") { store.toggleStatusFilter("geschenkt") }
            }
            .padding(.horizontal, 14)
        }
    }

    private func pill(emoji: String, count: Int, label: String, color: Color,
                      selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text("\(emoji) \(count)").font(.subheadline.weight(.bold))
                Text(label.uppercased()).font(.caption2)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(selected ? AnyShapeStyle(color) : AnyShapeStyle(Color(.secondarySystemBackground)), in: Capsule())
            .foregroundStyle(selected ? color.onFill : .primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Aktive-Event-Karte (nur im Einzel-Anlass-Modus)

struct WunschActiveEventCard: View {
    let event: WunschEvent
    @EnvironmentObject private var store: WunschlisteStore
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(event.emoji) \(event.name)").font(.title3.weight(.bold))
                    if let d = event.date {
                        HStack(spacing: 6) {
                            Text("📅 \(DateText.pretty(d))").font(.caption).foregroundStyle(.secondary)
                            if let cd = event.countdown {
                                Text(cd.text).font(.caption2.weight(.bold))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(cd.color, in: Capsule()).foregroundStyle(cd.color.onFill)
                            }
                        }
                    }
                }
                Spacer(minLength: 8)
                Button(role: .destructive) { confirmDelete = true } label: {
                    Image(systemName: "trash").foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
            Divider()
            Toggle(isOn: Binding(
                get: { event.erinnerungenAktiv },
                set: { _ in Task { await store.toggleReminders(event) } }
            )) {
                Label("Erinnerungen", systemImage: event.erinnerungenAktiv ? "bell.fill" : "bell.slash")
                    .font(.subheadline)
            }
            .tint(WunschStyle.accent)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 14)
        .confirmationDialog("Event und alle Geschenke löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) { Task { await store.deleteEvent(event) } }
            Button("Abbrechen", role: .cancel) {}
        }
    }
}
