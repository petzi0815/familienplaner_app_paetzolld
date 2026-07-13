import Foundation

/// Tolerante Wertkonvertierung für dynamische JSON-Felder (`[String: Any]` aus JSONSerialization).
/// Die Kompat-API liefert Zahlen mal als Int, mal als Double, Booleans als 0/1-Int, Arrays teils
/// als JSON-String. Diese Helfer kapseln das an EINER Stelle (statt in jedem Modell zu duplizieren).
enum Coerce {
    static func int(_ v: Any?) -> Int? {
        switch v {
        case let i as Int: return i
        case let d as Double: return Int(d)
        case let n as NSNumber: return n.intValue
        case let s as String: return Int(s) ?? Double(s).map(Int.init)
        default: return nil
        }
    }

    static func double(_ v: Any?) -> Double? {
        switch v {
        case let d as Double: return d
        case let i as Int: return Double(i)
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s.replacingOccurrences(of: ",", with: "."))
        default: return nil
        }
    }

    static func bool(_ v: Any?) -> Bool {
        if let b = v as? Bool { return b }
        if let i = int(v) { return i != 0 }
        if let s = v as? String { return ["1", "true", "ja", "yes"].contains(s.lowercased()) }
        return false
    }

    /// Nicht-leerer String, sonst nil (leere Strings gelten als „nicht gesetzt").
    static func str(_ v: Any?) -> String? {
        if let s = v as? String { return s.isEmpty ? nil : s }
        if v is NSNull || v == nil { return nil }
        return String(describing: v!)
    }

    /// JSON-Array-Spalte tolerant lesen: echtes Array ODER JSON-String `["a","b"]` ODER Einzelwert.
    static func stringArray(_ v: Any?) -> [String] {
        if let arr = v as? [String] { return arr }
        if let arr = v as? [Any] { return arr.compactMap { $0 as? String } }
        if let s = v as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty || t == "[]" { return [] }
            if let data = t.data(using: .utf8), let arr = try? JSONSerialization.jsonObject(with: data) as? [Any] {
                return arr.compactMap { $0 as? String }
            }
            return [t]
        }
        return []
    }

    /// JSON-Objekt-Spalte (`metadata`) tolerant lesen.
    static func jsonObject(_ v: Any?) -> [String: Any] {
        if let o = v as? [String: Any] { return o }
        if let s = v as? String, let data = s.data(using: .utf8),
           let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { return o }
        return [:]
    }
}

/// Erste Bild-URL aus einer `bild_pfade`-JSON-Spalte → auth-fähiger Media-Pfad bzw. externe URL.
/// Storage-Keys sind bereits `<bereich>/<datei>` (das alte `images/`-Prefix wird defensiv entfernt).
func mediaURLPath(fromBildPfade raw: Any?) -> String? {
    guard let key = Coerce.stringArray(raw).first, !key.isEmpty else { return nil }
    return mediaURLPath(fromKey: key)
}

/// Alle Bild-URLs (mehrere Fotos) aus `bild_pfade`.
func mediaURLPaths(fromBildPfade raw: Any?) -> [String] {
    Coerce.stringArray(raw).compactMap { mediaURLPath(fromKey: $0) }
}

/// Einzelnen Storage-Key/externe URL → Pfad für `AuthImage`/`loadMedia`.
func mediaURLPath(fromKey key: String) -> String? {
    let k = key.trimmingCharacters(in: .whitespaces)
    if k.isEmpty { return nil }
    if k.hasPrefix("http") { return k }
    let clean = k.hasPrefix("images/") ? String(k.dropFirst("images/".count)) : k
    return "/api/v1/media/\(clean)"
}
