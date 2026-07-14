import SwiftUI

/// Geraete-Tab: Stats-Kacheln, Status/Domain/Raum/Sortier-Filter, Suche, Gruppen-Karten (domain=group),
/// Entities nach Raum (aufklappbar) mit Zustandspunkt, Alias-Chips, Aktivieren/Deaktivieren + Alias-Add.
struct SmartHomeEntitiesView: View {
    @EnvironmentObject private var store: SmartHomeStore

    @State private var collapsed: Set<String> = []
    @State private var aliasEditing: String?          // entity_id mit offenem Alias-Editor
    @State private var newAlias = ""
    @State private var detail: HAEntityRef?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                statsRow
                statusPills
                AreaSearchField(placeholder: "Suche …", text: $store.entityFilters.search)
                filterMenus
                if !store.groupEntities.isEmpty { groupsSection }
                entitiesByArea
                systemPromptNote
            }
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .refreshable { await store.loadAll() }
        .sheet(item: $detail) { ref in
            SmartHomeEntityDetail(entityId: ref.id).environmentObject(store)
        }
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack(spacing: 10) {
            AreaStatTile(value: "\(store.stats.totalEntities)", label: "Entities", color: SmartHomeStyle.blue)
            AreaStatTile(value: "\(store.stats.totalAreas)", label: "Räume", color: SmartHomeStyle.green)
            AreaStatTile(value: "\(store.stats.totalGroups)", label: "Gruppen", color: SmartHomeStyle.purple)
            AreaStatTile(value: "\(store.stats.topDomain?.count ?? 0)",
                         label: store.stats.topDomain?.domain ?? "N/A", color: SmartHomeStyle.orange)
        }
        .padding(.horizontal, 14)
    }

    // MARK: - Filter

    private var statusPills: some View {
        HStack(spacing: 8) {
            FilterPill(label: "Aktive", selected: store.entityFilters.disabled == "0", color: SmartHomeStyle.green) {
                Task { await store.setDisabled("0") }
            }
            FilterPill(label: "Deaktivierte", selected: store.entityFilters.disabled == "1", color: SmartHomeStyle.orange) {
                Task { await store.setDisabled("1") }
            }
            FilterPill(label: "Alle", selected: store.entityFilters.disabled == "all", color: Theme.accent) {
                Task { await store.setDisabled("all") }
            }
            Spacer()
        }
        .padding(.horizontal, 14)
    }

    private var filterMenus: some View {
        HStack(spacing: 10) {
            Menu {
                Button("Alle Domains") { Task { await store.setDomain(nil) } }
                ForEach(store.domainOptions, id: \.domain) { d in
                    Button("\(SmartHomeStyle.domainEmoji(d.domain)) \(d.domain) (\(d.count))") {
                        Task { await store.setDomain(d.domain) }
                    }
                }
            } label: {
                dropdownLabel(icon: "square.grid.2x2", text: store.entityFilters.domain ?? "Domain")
            }

            Menu {
                Button("Alle Räume") { store.setArea(nil) }
                ForEach(store.availableAreas, id: \.self) { a in Button(a) { store.setArea(a) } }
                if store.hasOhneRaum { Button("Ohne Raum") { store.setArea("") } }
            } label: {
                dropdownLabel(icon: "square.stack.3d.up", text: areaLabel)
            }

            Menu {
                Button("Name") { Task { await store.setSort("name") } }
                Button("Domain") { Task { await store.setSort("domain") } }
                Button("Häufig geschaltet") { Task { await store.setSort("usage") } }
            } label: {
                dropdownLabel(icon: "arrow.up.arrow.down", text: sortLabel)
            }

            Spacer()

            if store.entityFilters.isActive {
                Button { Task { await store.resetEntityFilters() } } label: {
                    Label("Reset", systemImage: "xmark.circle").font(.footnote.weight(.semibold))
                }
            }
        }
        .padding(.horizontal, 14)
    }

    private var areaLabel: String {
        guard let a = store.entityFilters.area else { return "Raum" }
        return a.isEmpty ? "Ohne Raum" : a
    }
    private var sortLabel: String {
        switch store.entityFilters.sort {
        case "domain": return "Domain"
        case "usage": return "Häufig"
        default: return "Name"
        }
    }

    private func dropdownLabel(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
            Text(text).lineLimit(1)
            Image(systemName: "chevron.up.chevron.down").font(.caption2)
        }
        .font(.footnote.weight(.medium))
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Color(.secondarySystemBackground), in: Capsule())
        .foregroundStyle(.primary)
    }

    // MARK: - Gruppen (domain=group)

    private var groupsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("📦 Gruppen").font(.headline).padding(.horizontal, 14)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(store.groupEntities) { g in groupCard(g) }
                }
                .padding(.horizontal, 14)
            }
        }
    }

    private func groupCard(_ g: HAEntity) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(g.displayName).font(.subheadline.weight(.bold)).lineLimit(1)
                Circle().fill(SmartHomeStyle.stateColor(g.state)).frame(width: 8, height: 8)
            }
            Text(g.entityId).font(.caption2).foregroundStyle(SmartHomeStyle.purple).lineLimit(1)
            Text(g.state == "on" ? "✓ Aktiv" : "○ Inaktiv")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(g.state == "on" ? SmartHomeStyle.green : .secondary)
        }
        .padding(12)
        .frame(width: 190, alignment: .leading)
        .background(
            LinearGradient(colors: [SmartHomeStyle.purple.opacity(0.12), SmartHomeStyle.blue.opacity(0.12)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(SmartHomeStyle.purple.opacity(0.3)))
    }

    // MARK: - Entities nach Raum

    @ViewBuilder private var entitiesByArea: some View {
        let sections = store.areaSections
        if sections.isEmpty {
            AreaEmptyState(emoji: "🏠", title: "Keine Geräte",
                           hint: "Andere Filter probieren oder ha-voice-Sync ausführen.")
                .frame(minHeight: 240)
        } else {
            ForEach(sections) { sec in areaCard(sec) }
        }
    }

    private func areaCard(_ sec: HAAreaSection) -> some View {
        let isCollapsed = collapsed.contains(sec.area)
        return VStack(spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    if isCollapsed { collapsed.remove(sec.area) } else { collapsed.insert(sec.area) }
                }
            } label: {
                HStack {
                    Text(sec.area).font(.subheadline.weight(.bold)).foregroundStyle(.primary)
                    Spacer()
                    Text("\(sec.entities.count) Geräte").font(.caption).foregroundStyle(.secondary)
                    Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12).padding(.vertical, 11)
                .background(
                    LinearGradient(colors: [SmartHomeStyle.blue.opacity(0.12), SmartHomeStyle.indigo.opacity(0.12)],
                                   startPoint: .leading, endPoint: .trailing)
                )
            }
            .buttonStyle(.plain)

            if !isCollapsed {
                VStack(spacing: 8) {
                    ForEach(sec.entities) { e in entityRow(e) }
                }
                .padding(10)
            }
        }
        .background(Color(.secondarySystemBackground).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(.separator).opacity(0.3)))
        .padding(.horizontal, 14)
    }

    // MARK: - Entity-Zeile

    private func entityRow(_ e: HAEntity) -> some View {
        let al = store.aliasList(for: e.entityId)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(SmartHomeStyle.domainEmoji(e.domain))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(e.displayName).font(.subheadline.weight(.semibold)).lineLimit(1)
                            .foregroundStyle(e.disabled ? .secondary : .primary)
                        if e.disabled { Text("(deaktiviert)").font(.caption2).foregroundStyle(.red) }
                        if let u = e.usageCount, u > 0 {
                            Pill(text: "\(u)x geschaltet", color: SmartHomeStyle.orange, filled: false)
                        }
                    }
                    Text(e.entityId).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 6)
                HStack(spacing: 5) {
                    Circle().fill(SmartHomeStyle.stateColor(e.state)).frame(width: 8, height: 8)
                    Text((e.state ?? "?").uppercased()).font(.caption2).foregroundStyle(.secondary)
                }
                Button { detail = HAEntityRef(id: e.entityId) } label: {
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if !al.isEmpty { aliasChips(al) }
            if aliasEditing == e.entityId { aliasEditor(e) }

            HStack(spacing: 12) {
                Button { Task { await store.toggleDisabled(e) } } label: {
                    Label(e.disabled ? "Aktivieren" : "Deaktivieren",
                          systemImage: e.disabled ? "checkmark.circle" : "minus.circle")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(e.disabled ? SmartHomeStyle.green : Color.red)

                Button {
                    withAnimation {
                        aliasEditing = (aliasEditing == e.entityId) ? nil : e.entityId
                        newAlias = ""
                    }
                } label: {
                    Label("Alias", systemImage: "plus").font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(SmartHomeStyle.blue)

                Spacer()
            }
        }
        .padding(10)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(e.disabled ? 0.6 : 1)
    }

    private func aliasChips(_ al: [HAAlias]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(al) { a in
                    HStack(spacing: 4) {
                        Text("🏷️ \(a.alias)").font(.caption2)
                        Button { Task { await store.deleteAlias(a) } } label: {
                            Image(systemName: "xmark.circle.fill").font(.caption2)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(SmartHomeStyle.blue.opacity(0.15), in: Capsule())
                    .foregroundStyle(SmartHomeStyle.blue)
                }
            }
        }
    }

    private func aliasEditor(_ e: HAEntity) -> some View {
        HStack(spacing: 8) {
            TextField("Neuer Alias …", text: $newAlias)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .onSubmit { submitAlias(e) }
            Button { submitAlias(e) } label: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(SmartHomeStyle.green)
            }
            .buttonStyle(.plain)
            .disabled(newAlias.trimmingCharacters(in: .whitespaces).isEmpty)
            Button { aliasEditing = nil; newAlias = "" } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func submitAlias(_ e: HAEntity) {
        let value = newAlias
        Task {
            if await store.addAlias(entityId: e.entityId, alias: value) {
                newAlias = ""
                aliasEditing = nil
            }
        }
    }

    // MARK: - System-Prompt (501, nicht migriert)

    private var systemPromptNote: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("🤖 System-Prompt").font(.subheadline.weight(.semibold))
                Text("Nicht verfügbar (nicht migriert)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color(.secondarySystemBackground).opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(0.7)
        .padding(.horizontal, 14)
    }
}
