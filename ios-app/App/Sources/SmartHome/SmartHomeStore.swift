import SwiftUI

/// Zentraler Zustand des Smart-Home-Bereichs (Entities, Aliase, Beziehungen, Command-Log, Stats,
/// Filter). Alle clientseitig abgeleiteten Felder (Gruppen/Regular-Split, Raum-Gruppierung,
/// Beziehungs-Gruppierung, Log-Kennzahlen) werden hier berechnet — das Backend liefert sie nicht.
@MainActor
final class SmartHomeStore: ObservableObject {
    let api: SmartHomeAPI

    @Published var tab: SmartHomeTab = .geraete

    // Entities-Tab
    @Published var entities: [HAEntity] = []
    @Published var aliases: [HAAlias] = []
    @Published var stats = HAStats()
    @Published var entityFilters = HAEntityFilters()

    // Beziehungen-Tab
    @Published var relationships: [HARelationship] = []
    @Published var relationFilters = HARelationFilters()
    @Published var relationSort: HARelationSort = .name

    // Command-Log-Tab
    @Published var logs: [HACommandLog] = []

    @Published var loading = true
    @Published var loaded = false
    @Published var message: String?
    @Published var messageIsError = false

    init(settings: Settings) { api = SmartHomeAPI(settings: settings) }

    // MARK: - Laden

    func loadAll() async {
        loading = true
        async let e = api.fetchEntities(entityFilters)
        async let s = api.fetchStats()
        async let a = api.fetchAliases()
        async let r = api.fetchRelationships(relationFilters)
        async let l = api.fetchLog()
        entities = (try? await e) ?? []
        stats = (try? await s) ?? HAStats()
        aliases = (try? await a) ?? []
        relationships = (try? await r) ?? []
        logs = (try? await l) ?? []
        loading = false
        loaded = true
    }

    func reloadEntities() async { if let e = try? await api.fetchEntities(entityFilters) { entities = e } }
    func reloadStats() async { if let s = try? await api.fetchStats() { stats = s } }
    func reloadAliases() async { if let a = try? await api.fetchAliases() { aliases = a } }
    func reloadRelationships() async { if let r = try? await api.fetchRelationships(relationFilters) { relationships = r } }
    func reloadLog() async { if let l = try? await api.fetchLog() { logs = l } }

    // MARK: - Filter-Setter

    func setDisabled(_ v: String) async {
        guard entityFilters.disabled != v else { return }
        entityFilters.disabled = v
        await reloadEntities()
    }
    func setDomain(_ d: String?) async {
        guard entityFilters.domain != d else { return }
        entityFilters.domain = d
        await reloadEntities()
    }
    func setSort(_ s: String) async {
        guard entityFilters.sort != s else { return }
        entityFilters.sort = s
        await reloadEntities()
    }
    func setArea(_ a: String?) { entityFilters.area = a }   // rein clientseitig
    func resetEntityFilters() async {
        entityFilters = HAEntityFilters()
        await reloadEntities()
    }

    func setRelationType(_ t: String) async {
        guard relationFilters.type != t else { return }
        relationFilters.type = t
        await reloadRelationships()
    }

    // MARK: - Abgeleitet: Entities

    var regularEntities: [HAEntity] { entities.filter { !$0.isGroup } }
    var groupEntities: [HAEntity] { entities.filter { $0.isGroup } }

    /// Benannte Raeume (fuer das Raum-Dropdown).
    var availableAreas: [String] {
        Array(Set(regularEntities.compactMap { $0.areaName }.filter { !$0.isEmpty }))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    var hasOhneRaum: Bool { regularEntities.contains { ($0.areaName ?? "").isEmpty } }

    var domainOptions: [(domain: String, count: Int)] { stats.byDomain }

    func aliasList(for entityId: String) -> [HAAlias] { aliases.filter { $0.entityId == entityId } }

    /// Nach Raum gruppierte, gefilterte Entities (Suche filtert ganze Karten wie in der PWA).
    var areaSections: [HAAreaSection] {
        var list = regularEntities
        if let a = entityFilters.area {
            if a.isEmpty { list = list.filter { ($0.areaName ?? "").isEmpty } }
            else { list = list.filter { $0.areaName == a } }
        }
        var map: [String: [HAEntity]] = [:]
        for e in list {
            let key = (e.areaName?.isEmpty == false) ? e.areaName! : "Ohne Raum"
            map[key, default: []].append(e)
        }
        var sections = map.map { HAAreaSection(area: $0.key, entities: $0.value) }
        let q = entityFilters.search.lowercased().trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            sections = sections.filter { sec in
                sec.area.lowercased().contains(q) || sec.entities.contains { $0.displayName.lowercased().contains(q) }
            }
        }
        return sections.sorted { $0.area.localizedStandardCompare($1.area) == .orderedAscending }
    }

    // MARK: - Abgeleitet: Beziehungen

    var relationGroups: [HARelationGroup] {
        let q = relationFilters.search.lowercased().trimmingCharacters(in: .whitespaces)
        var filtered = relationships
        if !q.isEmpty {
            filtered = filtered.filter {
                ($0.parentName ?? "").lowercased().contains(q) || $0.parentEntityId.lowercased().contains(q)
                    || ($0.childName ?? "").lowercased().contains(q) || $0.childEntityId.lowercased().contains(q)
            }
        }
        var map: [String: [HARelationship]] = [:]
        for r in filtered { map[r.parentEntityId, default: []].append(r) }
        var groups = map.map { HARelationGroup(parentId: $0.key, rows: $0.value) }
        switch relationSort {
        case .name: groups.sort { $0.parentDisplay.localizedStandardCompare($1.parentDisplay) == .orderedAscending }
        case .members: groups.sort { $0.rows.count > $1.rows.count }
        }
        return groups
    }

    var relationStats: (groups: Int, total: Int, auto: Int, manual: Int) {
        let groups = Set(relationships.map { $0.parentEntityId }).count
        let auto = relationships.filter { $0.autoDiscovered && !$0.manuallyVerified }.count
        let manual = relationships.filter { $0.manuallyVerified }.count
        return (groups, relationships.count, auto, manual)
    }

    // MARK: - Abgeleitet: Log

    var logStats: (total: Int, successRate: Int, avg: Int) {
        let total = logs.count
        guard total > 0 else { return (0, 0, 0) }
        let succ = logs.filter { $0.success }.count
        let durs = logs.compactMap { $0.durationMs }
        let avg = durs.isEmpty ? 0 : durs.reduce(0, +) / durs.count
        return (total, Int((Double(succ) / Double(total) * 100).rounded()), avg)
    }

    /// Aelteste..neueste der letzten 20 (fuer das Balkendiagramm).
    var logChartData: [HACommandLog] { Array(logs.prefix(20).reversed()) }
    var logChartMax: Int { max(1000, logChartData.compactMap { $0.durationMs }.max() ?? 0) }

    // MARK: - Mutationen (brauchen Agent-Key)

    func toggleDisabled(_ e: HAEntity) async {
        do {
            _ = try await api.toggleDisabled(e.entityId)
            await reloadEntities()
            await reloadStats()
        } catch { notify(errText(error), error: true) }
    }

    func addAlias(entityId: String, alias: String) async -> Bool {
        let a = alias.trimmingCharacters(in: .whitespaces)
        guard !a.isEmpty else { return false }
        // UNIQUE(entity_id, alias) waere sonst ein opaker 500 -> vorab abfangen.
        if aliasList(for: entityId).contains(where: { $0.alias.caseInsensitiveCompare(a) == .orderedSame }) {
            notify("Alias existiert bereits", error: true)
            return false
        }
        do {
            try await api.addAlias(entityId: entityId, alias: a)
            await reloadAliases()
            return true
        } catch { notify(errText(error), error: true); return false }
    }

    func deleteAlias(_ alias: HAAlias) async {
        do { try await api.deleteAlias(entityId: alias.entityId, alias: alias.alias); await reloadAliases() }
        catch { notify(errText(error), error: true) }
    }

    func addRelationship(parent: String, child: String, type: String) async -> Bool {
        do {
            try await api.addRelationship(parent: parent, child: child, type: type)
            await reloadRelationships()
            notify("Beziehung erstellt")
            return true
        } catch { notify(errText(error), error: true); return false }
    }

    func deleteRelationship(_ id: Int) async {
        do { try await api.deleteRelationship(id); await reloadRelationships() }
        catch { notify(errText(error), error: true) }
    }

    func toggleVerified(_ r: HARelationship) async {
        do { try await api.setVerified(r.id, !r.manuallyVerified); await reloadRelationships() }
        catch { notify(errText(error), error: true) }
    }

    // MARK: - Helfer

    func notify(_ text: String, error: Bool = false) { message = text; messageIsError = error }
    private func errText(_ e: Error) -> String { (e as? APIError)?.errorDescription ?? "Fehler" }
}

enum SmartHomeTab: Hashable { case geraete, beziehungen, log }
