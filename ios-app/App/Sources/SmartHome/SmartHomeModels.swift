import SwiftUI

// Native Smart-Home-Modelle. Backend = Kompat-API `/api/smarthome/*` (Home-Assistant-Spiegel).
// WICHTIG: Diese Endpunkte liefern GEWRAPPTE Objekte (`{entities:[…]}`, `{aliases:[…]}`, …),
// nicht die bare-`data`-Arrays der v1-API. snake_case, Booleans als 0/1. `attributes` ist eine
// JSON-OBJEKT-Spalte (Coerce.jsonObject) und wird im Detail als Key/Value gerendert.

// MARK: - Entity (ha_entities)

struct HAEntity: Identifiable {
    let id: String            // = entity_id (unique); Fallback auf DB-id
    let dbId: Int
    let entityId: String
    let domain: String
    let friendlyName: String?
    let areaId: String?
    let areaName: String?
    let deviceId: String?
    let deviceName: String?
    let state: String?
    let attributes: [String: Any]   // JSON-Objekt (Key/Value)
    let lastSynced: String?
    let discoveredAt: String?
    let disabled: Bool
    let usageCount: Int?            // nur bei sort=usage vorhanden

    init(fields f: [String: Any]) {
        let dbid = Coerce.int(f["id"]) ?? 0
        let eid = Coerce.str(f["entity_id"]) ?? ""
        dbId = dbid
        entityId = eid
        id = eid.isEmpty ? "e\(dbid)" : eid
        domain = Coerce.str(f["domain"]) ?? "unknown"
        friendlyName = Coerce.str(f["friendly_name"])
        areaId = Coerce.str(f["area_id"])
        areaName = Coerce.str(f["area_name"])
        deviceId = Coerce.str(f["device_id"])
        deviceName = Coerce.str(f["device_name"])
        state = Coerce.str(f["state"])
        attributes = Coerce.jsonObject(f["attributes"])
        lastSynced = Coerce.str(f["last_synced"])
        discoveredAt = Coerce.str(f["discovered_at"])
        disabled = Coerce.bool(f["disabled"])
        usageCount = Coerce.int(f["usage_count"])
    }

    var displayName: String { friendlyName ?? entityId }
    var isGroup: Bool { domain == "group" }
}

// MARK: - Relationship (ha_relationships, mit Parent/Child-Joins)

struct HARelationship: Identifiable {
    let id: Int
    let parentEntityId: String
    let childEntityId: String
    let type: String
    let autoDiscovered: Bool
    let manuallyVerified: Bool
    let parentName: String?
    let parentState: String?
    let parentDomain: String?
    let childName: String?

    init(fields f: [String: Any]) {
        id = Coerce.int(f["id"]) ?? 0
        parentEntityId = Coerce.str(f["parent_entity_id"]) ?? ""
        childEntityId = Coerce.str(f["child_entity_id"]) ?? ""
        type = Coerce.str(f["type"]) ?? "group_member"
        autoDiscovered = Coerce.bool(f["auto_discovered"])
        manuallyVerified = Coerce.bool(f["manually_verified"])
        parentName = Coerce.str(f["parent_name"])
        parentState = Coerce.str(f["parent_state"])
        parentDomain = Coerce.str(f["parent_domain"])
        childName = Coerce.str(f["child_name"])
    }

    var childDisplay: String { childName ?? childEntityId }
}

// MARK: - Alias (ha_aliases)

struct HAAlias: Identifiable {
    let id: Int
    let entityId: String
    let alias: String

    init(fields f: [String: Any]) {
        id = Coerce.int(f["id"]) ?? 0
        entityId = Coerce.str(f["entity_id"]) ?? ""
        alias = Coerce.str(f["alias"]) ?? ""
    }
}

// MARK: - Command-Log (ha_command_log, mit friendly_name-Join)

struct HACommandLog: Identifiable {
    let id: Int
    let timestamp: String?
    let inputText: String?
    let matchedEntityId: String?
    let matchScore: Double?
    let action: String?
    let durationMs: Int?
    let success: Bool
    let friendlyName: String?

    init(fields f: [String: Any]) {
        id = Coerce.int(f["id"]) ?? 0
        timestamp = Coerce.str(f["timestamp"])
        inputText = Coerce.str(f["input_text"])
        matchedEntityId = Coerce.str(f["matched_entity_id"])
        matchScore = Coerce.double(f["match_score"])
        action = Coerce.str(f["action"])
        durationMs = Coerce.int(f["duration_ms"])
        success = Coerce.bool(f["success"])
        friendlyName = Coerce.str(f["friendly_name"])
    }

    var entityDisplay: String { friendlyName ?? matchedEntityId ?? "—" }
}

// MARK: - Stats (flaches Objekt aus /smarthome/stats)

struct HAStats {
    var totalEntities = 0
    var totalRelationships = 0
    var totalAreas = 0
    var totalGroups = 0
    var byDomain: [(domain: String, count: Int)] = []

    init() {}
    init(object o: [String: Any]) {
        totalEntities = Coerce.int(o["totalEntities"]) ?? 0
        totalRelationships = Coerce.int(o["totalRelationships"]) ?? 0
        totalAreas = Coerce.int(o["totalAreas"]) ?? 0
        totalGroups = Coerce.int(o["totalGroups"]) ?? 0
        if let arr = o["byDomain"] as? [[String: Any]] {
            byDomain = arr.map { (Coerce.str($0["domain"]) ?? "", Coerce.int($0["count"]) ?? 0) }
        }
    }
    var topDomain: (domain: String, count: Int)? { byDomain.first }
}

// MARK: - Filter

struct HAEntityFilters: Equatable {
    var domain: String? = nil     // ?domain= (Serverfilter)
    var area: String? = nil       // nil = alle, "" = Ohne Raum, sonst Raumname (CLIENTSEITIG)
    var disabled: String = "0"    // 0 = aktiv (default), 1 = deaktiviert, all
    var sort: String = "name"     // name | domain | usage
    var search: String = ""       // CLIENTSEITIG (Raumname ODER friendly_name)

    var isActive: Bool { domain != nil || area != nil || disabled != "0" || sort != "name" || !search.isEmpty }
}

struct HARelationFilters: Equatable {
    var type: String = "all"      // all | auto | manual (Serverfilter)
    var search: String = ""       // CLIENTSEITIG
}

enum HARelationSort: String, CaseIterable {
    case name, members
    var label: String { self == .name ? "Name" : "Anzahl Mitglieder" }
}

// MARK: - Abgeleitete Gruppierungen

struct HAAreaSection: Identifiable {
    var id: String { area }
    let area: String
    let entities: [HAEntity]
}

struct HARelationGroup: Identifiable {
    var id: String { parentId }
    let parentId: String
    let rows: [HARelationship]
    var first: HARelationship? { rows.first }
    var parentDisplay: String { first?.parentName ?? parentId }
    var anyVerified: Bool { rows.contains { $0.manuallyVerified } }
}

/// Identifiable-Wrapper fuer `.sheet(item:)` (Detail per entity_id, immer frisch aus dem Store gelesen).
struct HAEntityRef: Identifiable { let id: String }

// MARK: - Visuelle Konfiguration (Farben/Emoji/Latenz)

enum SmartHomeStyle {
    static let blue = Color(hex: "007AFF")
    static let green = Color(hex: "34C759")
    static let purple = Color(hex: "AF52DE")
    static let orange = Color(hex: "FF9F0A")
    static let indigo = Color(hex: "5856D6")
    static let gray = Color(hex: "8E8E93")

    /// Zustandspunkt-Farbe: on grün, off grau, unavailable rot, sonst blau, kein Zustand grau.
    static func stateColor(_ state: String?) -> Color {
        guard let state else { return gray }
        switch state {
        case "on": return green
        case "off": return gray
        case "unavailable": return Color(hex: "FF3B30")
        default: return blue
        }
    }

    static func domainEmoji(_ domain: String?) -> String {
        guard let domain else { return "🏠" }
        switch domain {
        case "light": return "💡"
        case "switch": return "🔌"
        case "sensor": return "📊"
        case "climate": return "🌡️"
        case "cover": return "🪟"
        case "lock": return "🔒"
        case "media_player": return "📺"
        case "group": return "📦"
        default: return "⚙️"
        }
    }

    /// Latenz-Farbe: <500ms grün, <2000ms gelb, sonst rot.
    static func durationColor(_ ms: Int?) -> Color {
        guard let ms else { return gray }
        if ms < 500 { return green }
        if ms < 2000 { return orange }
        return Color(hex: "FF3B30")
    }

    static let relationTypes: [(value: String, label: String)] = [
        ("group_member", "Group Member"),
        ("switch_controls_light", "Switch steuert Light"),
        ("device_sibling", "Device Sibling"),
        ("custom", "Custom"),
    ]
    static func typeLabel(_ t: String) -> String { relationTypes.first { $0.value == t }?.label ?? t }
}
