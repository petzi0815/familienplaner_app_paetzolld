import SwiftUI

/// Bedarf-Tab: Einkaufsliste (offen/erledigt), Neuer-Bedarf-Formular, Erledigt-Toggle, Löschen.
struct SamuBedarfView: View {
    @EnvironmentObject private var store: SamuStore
    @State private var filter: BedarfFilter = .offen
    @State private var showAdd = false
    @State private var deleteTarget: SamuBedarf?

    enum BedarfFilter: String, CaseIterable { case offen, alle, erledigt
        var label: String { switch self { case .offen: return "Offen"; case .alle: return "Alle"; case .erledigt: return "Erledigt" } }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                if store.bedarf.isEmpty {
                    ScrollView {
                        AreaEmptyState(emoji: "🎉", title: "Nichts auf der Liste!", hint: "Alles vorhanden 👍",
                                       actionLabel: "Bedarf hinzufügen", action: { withAnimation { showAdd = true } })
                            .frame(minHeight: 320)
                    }
                    .refreshable { await store.reloadBedarf() }
                } else {
                    List {
                        if filter != .erledigt && !store.offeneBedarf.isEmpty {
                            bedarfSection(title: filter == .alle ? "Offen" : nil, items: store.offeneBedarf)
                        }
                        if filter != .offen && !store.erledigteBedarf.isEmpty {
                            bedarfSection(title: filter == .alle ? "Erledigt" : nil, items: store.erledigteBedarf)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .refreshable { await store.reloadBedarf() }
                }
            }
        }
        .confirmationDialog("Wirklich löschen?", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }), titleVisibility: .visible) {
            Button("Löschen", role: .destructive) { if let t = deleteTarget { Task { await store.deleteBedarf(t) } }; deleteTarget = nil }
            Button("Abbrechen", role: .cancel) { deleteTarget = nil }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack {
                ForEach(BedarfFilter.allCases, id: \.self) { f in
                    FilterPill(label: f.label, selected: filter == f) { filter = f }
                }
                Spacer()
                Button { withAnimation { showAdd.toggle() } } label: {
                    Label("Neuer Bedarf", systemImage: "plus.circle.fill").font(.subheadline.weight(.semibold))
                }
            }
            .padding(.horizontal, 14).padding(.top, 8)

            if showAdd { SamuBedarfAddForm(onDone: { showAdd = false }).environmentObject(store) }
        }
    }

    private func bedarfSection(title: String?, items: [SamuBedarf]) -> some View {
        Section {
            ForEach(items) { b in
                SamuBedarfCard(b: b, onToggle: { Task { await store.toggleBedarf(b) } }, onDelete: { deleteTarget = b })
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { deleteTarget = b } label: {
                            Label("Löschen", systemImage: "trash")
                        }
                        Button { Task { await store.toggleBedarf(b) } } label: {
                            Label(b.erledigt ? "Offen" : "Erledigt", systemImage: b.erledigt ? "arrow.uturn.left" : "checkmark")
                        }.tint(b.erledigt ? .orange : .green)
                    }
            }
        } header: {
            if let title { Text(title).font(.subheadline.weight(.bold)).foregroundStyle(.secondary) }
        }
        .textCase(nil)
    }
}

// MARK: - Bedarf-Karte

struct SamuBedarfCard: View {
    let b: SamuBedarf
    var onToggle: () -> Void
    var onDelete: () -> Void

    var body: some View {
        let prio = SamuStyle.prioInfo(b.prioritaet)
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: b.erledigt ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(b.erledigt ? Color.green : .secondary)
            }.buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(b.beschreibung)
                    .font(.subheadline.weight(.semibold))
                    .strikethrough(b.erledigt).foregroundStyle(b.erledigt ? .secondary : .primary)
                HStack(spacing: 6) {
                    Pill(text: "\(prio.emoji) \(prio.label)", color: prio.color, filled: false)
                    if let k = b.kategorie, !k.isEmpty { Pill(text: k, color: .gray, filled: false) }
                    if let g = b.groesse, !g.isEmpty { Pill(text: "Gr. \(g)", color: .gray, filled: false) }
                }
                if let n = b.notizen, !n.isEmpty { Text(n).font(.caption).foregroundStyle(.secondary) }
                if b.erledigt, let am = b.erledigtAm { Text("✓ Erledigt: \(DateText.pretty(am))").font(.caption2).foregroundStyle(.green) }
            }
            Spacer(minLength: 0)
            if b.erledigt {
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash").foregroundStyle(.red) }
                    .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .opacity(b.erledigt ? 0.7 : 1)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(b.erledigt ? Color.green.opacity(0.4) : .clear, lineWidth: 1))
    }
}

// MARK: - Neuer Bedarf

struct SamuBedarfAddForm: View {
    @EnvironmentObject private var store: SamuStore
    var onDone: () -> Void
    @State private var beschreibung = ""; @State private var kategorie = ""
    @State private var groesse = ""; @State private var prioritaet = "normal"; @State private var notizen = ""
    @State private var saving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Was wird gebraucht?").font(.headline)
            TextField("z.B. Winterjacke, Gummistiefel …", text: $beschreibung).textFieldStyle(.roundedBorder)
            HStack {
                TextField("Kategorie", text: $kategorie).textFieldStyle(.roundedBorder)
                TextField("Größe", text: $groesse).textFieldStyle(.roundedBorder)
            }
            Picker("Priorität", selection: $prioritaet) {
                ForEach(SamuStyle.prioOrder, id: \.self) { p in
                    let i = SamuStyle.prioInfo(p); Text("\(i.emoji) \(i.label)").tag(p)
                }
            }
            .pickerStyle(.segmented)
            TextField("Notizen", text: $notizen, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(2...4)
            HStack {
                Button("Abbrechen") { onDone() }.buttonStyle(.bordered)
                Spacer()
                Button {
                    Task {
                        saving = true
                        let ok = await store.addBedarf(beschreibung: beschreibung, kategorie: kategorie, groesse: groesse, prioritaet: prioritaet, notizen: notizen)
                        saving = false
                        if ok { onDone() }
                    }
                } label: { Label("Hinzufügen", systemImage: "checkmark") }
                    .buttonStyle(.borderedProminent)
                    .disabled(beschreibung.trimmingCharacters(in: .whitespaces).isEmpty || saving)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 14)
    }
}
