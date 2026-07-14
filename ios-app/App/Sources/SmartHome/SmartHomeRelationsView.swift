import SwiftUI

/// Beziehungen-Tab: Stats, Typ-Filter + Sortierung + Suche, nach Parent gruppierte Beziehungskarten
/// (Mitglieder-Chips mit Loeschen/Verifizieren via Kontextmenue), plus Modal zum Anlegen.
struct SmartHomeRelationsView: View {
    @EnvironmentObject private var store: SmartHomeStore
    @State private var showAdd = false
    @State private var deleteTarget: HARelationship?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                statsRow
                controls
                AreaSearchField(placeholder: "Suche nach Gruppenname …", text: $store.relationFilters.search)
                groups
            }
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .refreshable { await store.reloadRelationships() }
        .sheet(isPresented: $showAdd) {
            SmartHomeAddRelationSheet().environmentObject(store)
        }
        .confirmationDialog("Beziehung wirklich löschen?",
                            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
                            titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                if let t = deleteTarget { Task { await store.deleteRelationship(t.id) } }
                deleteTarget = nil
            }
            Button("Abbrechen", role: .cancel) { deleteTarget = nil }
        }
    }

    // MARK: - Stats

    private var statsRow: some View {
        let s = store.relationStats
        return HStack(spacing: 10) {
            AreaStatTile(value: "\(s.groups)", label: "Gruppen", color: SmartHomeStyle.blue)
            AreaStatTile(value: "\(s.total)", label: "Beziehungen", color: SmartHomeStyle.indigo)
            AreaStatTile(value: "\(s.auto)", label: "Auto-entdeckt", color: SmartHomeStyle.green)
            AreaStatTile(value: "\(s.manual)", label: "Manuell", color: SmartHomeStyle.purple)
        }
        .padding(.horizontal, 14)
    }

    // MARK: - Filter/Sort/Aktion

    private var controls: some View {
        HStack(spacing: 8) {
            FilterPill(label: "Alle", selected: store.relationFilters.type == "all", color: Theme.accent) {
                Task { await store.setRelationType("all") }
            }
            FilterPill(label: "⚙ Auto", selected: store.relationFilters.type == "auto", color: SmartHomeStyle.orange) {
                Task { await store.setRelationType("auto") }
            }
            FilterPill(label: "✓ Manuell", selected: store.relationFilters.type == "manual", color: SmartHomeStyle.purple) {
                Task { await store.setRelationType("manual") }
            }
            Spacer()
            Menu {
                ForEach(HARelationSort.allCases, id: \.self) { s in
                    Button(s.label) { store.relationSort = s }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down").font(.footnote.weight(.semibold))
                    .padding(8).background(Color(.secondarySystemBackground), in: Circle())
            }
            Button { showAdd = true } label: {
                Label("Neue", systemImage: "plus").font(.footnote.weight(.semibold))
            }
        }
        .padding(.horizontal, 14)
    }

    // MARK: - Gruppen

    @ViewBuilder private var groups: some View {
        let list = store.relationGroups
        if list.isEmpty {
            AreaEmptyState(emoji: "🔗", title: "Keine Gruppen gefunden",
                           hint: store.relationFilters.search.isEmpty
                                ? "Führe ha-voice-Sync aus, um Beziehungen zu entdecken."
                                : "Keine Treffer für deine Suche.")
                .frame(minHeight: 240)
        } else {
            ForEach(list) { g in relationCard(g) }
        }
    }

    private func relationCard(_ g: HARelationGroup) -> some View {
        let head = g.first
        return VStack(alignment: .leading, spacing: 0) {
            // Kopf
            HStack(spacing: 8) {
                Text(SmartHomeStyle.domainEmoji(head?.parentDomain))
                VStack(alignment: .leading, spacing: 2) {
                    Text(g.parentDisplay).font(.subheadline.weight(.bold)).lineLimit(1)
                    Text(g.parentId).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 6)
                HStack(spacing: 5) {
                    Circle().fill(SmartHomeStyle.stateColor(head?.parentState)).frame(width: 8, height: 8)
                    Text(head?.parentState ?? "unknown").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(
                LinearGradient(colors: [SmartHomeStyle.purple.opacity(0.12), SmartHomeStyle.indigo.opacity(0.12)],
                               startPoint: .leading, endPoint: .trailing)
            )

            // Mitglieder
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Mitglieder (\(g.rows.count))").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Pill(text: g.anyVerified ? "✓ Manuell" : "⚙ Auto",
                         color: g.anyVerified ? SmartHomeStyle.purple : SmartHomeStyle.orange, filled: false)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(g.rows) { row in memberChip(row) }
                    }
                }
                HStack {
                    Text(SmartHomeStyle.typeLabel(head?.type ?? "group_member"))
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(g.rows.count) Mitglied(er)").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(12)
        }
        .background(Color(.secondarySystemBackground).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(SmartHomeStyle.purple.opacity(0.2)))
        .padding(.horizontal, 14)
    }

    private func memberChip(_ row: HARelationship) -> some View {
        HStack(spacing: 4) {
            Text(row.childDisplay).font(.caption2)
            Button { deleteTarget = row } label: { Image(systemName: "xmark.circle.fill").font(.caption2) }
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(SmartHomeStyle.indigo.opacity(0.12), in: Capsule())
        .foregroundStyle(.primary)
        .contextMenu {
            Button {
                Task { await store.toggleVerified(row) }
            } label: {
                Label(row.manuallyVerified ? "Als Auto markieren" : "Als Manuell bestätigen",
                      systemImage: row.manuallyVerified ? "gearshape" : "checkmark.seal")
            }
            Button(role: .destructive) { deleteTarget = row } label: { Label("Löschen", systemImage: "trash") }
        }
    }
}

// MARK: - Neue Beziehung (Modal)

/// Modal zum Anlegen einer Beziehung. Parent/Child via durchsuchbarer Entity-Auswahl (alle Entities,
/// ungefiltert geladen), Typ als Menue. Server setzt auto_discovered=0, manually_verified=1.
struct SmartHomeAddRelationSheet: View {
    @EnvironmentObject private var store: SmartHomeStore
    @Environment(\.dismiss) private var dismiss

    @State private var all: [HAEntity] = []
    @State private var loading = true
    @State private var parent = ""
    @State private var child = ""
    @State private var type = "group_member"
    @State private var saving = false
    @State private var showValidation = false

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView("Lädt Entities …").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    form
                }
            }
            .navigationTitle("Neue Beziehung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Erstellen") { submit() }.disabled(saving)
                }
            }
            .alert("Bitte alle Felder ausfüllen", isPresented: $showValidation) {
                Button("OK", role: .cancel) {}
            }
        }
        .task {
            all = (try? await store.api.fetchAllEntities()) ?? []
            loading = false
        }
    }

    private var form: some View {
        Form {
            Section("Parent Entity (Gruppe)") {
                NavigationLink { SmartHomeEntityPicker(entities: all, selection: $parent) } label: {
                    pickerRow(title: display(parent), placeholder: "Parent wählen")
                }
            }
            Section("Child Entity (Mitglied)") {
                NavigationLink { SmartHomeEntityPicker(entities: all, selection: $child) } label: {
                    pickerRow(title: display(child), placeholder: "Child wählen")
                }
            }
            Section("Beziehungstyp") {
                Picker("Typ", selection: $type) {
                    ForEach(SmartHomeStyle.relationTypes, id: \.value) { t in Text(t.label).tag(t.value) }
                }
            }
        }
    }

    private func pickerRow(title: String?, placeholder: String) -> some View {
        HStack {
            Text(title ?? placeholder).foregroundStyle(title == nil ? .secondary : .primary)
            Spacer()
        }
    }

    private func display(_ id: String) -> String? {
        guard !id.isEmpty else { return nil }
        if let e = all.first(where: { $0.entityId == id }) { return "\(e.displayName) (\(id))" }
        return id
    }

    private func submit() {
        guard !parent.isEmpty, !child.isEmpty else { showValidation = true; return }
        Task {
            saving = true
            let ok = await store.addRelationship(parent: parent, child: child, type: type)
            saving = false
            if ok { dismiss() }
        }
    }
}

// MARK: - Durchsuchbare Entity-Auswahl

struct SmartHomeEntityPicker: View {
    let entities: [HAEntity]
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [HAEntity] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return entities }
        return entities.filter { $0.displayName.lowercased().contains(q) || $0.entityId.lowercased().contains(q) }
    }

    var body: some View {
        List(filtered) { e in
            Button {
                selection = e.entityId
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    Text(SmartHomeStyle.domainEmoji(e.domain))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.displayName).foregroundStyle(.primary)
                        Text(e.entityId).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if selection == e.entityId { Image(systemName: "checkmark").foregroundStyle(SmartHomeStyle.blue) }
                }
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Entity suchen")
        .navigationTitle("Entity wählen")
        .navigationBarTitleDisplayMode(.inline)
    }
}
