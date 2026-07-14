import SwiftUI

// Native Modelle des E-Book-Bereichs (Domain-Key `ebooks`, Wunschliste + externe Suche/Downloads).
// Backend = Kompat-API `/api/buecher` (bare Arrays, snake_case). Dies ist die E-BOOK-Wunschliste
// (Tabelle `ebook_wishlist`) — NICHT der physische Bücher-Bereich `elisbooks`.
// Externe Netz-Features (search/download/retry/enrich) liefern serverseitig 501 und sind im
// nativen UI deaktiviert; List/Filter/Anlegen/Löschen funktionieren offline.

// MARK: - Wunschlisten-Eintrag

struct EbookItem: Identifiable, Equatable {
    let id: Int
    var title: String
    var author: String?
    var publisher: String?
    var year: String?           // TEXT (exakter Filter)
    var category: String?
    var descriptionText: String?
    var coverURL: String?       // externe HTTPS-URL (Google Books/Shelfmark)
    var isbn: String?
    var language: String?       // Kurzcode de/en/…
    var status: String          // gesucht | heruntergeladen
    var sourceID: String?
    var requestedBy: String?
    var requestedAt: String?
    var downloadedAt: String?
    var attempts: Int
    var lastAttempt: String?
    var notes: String?
    var reviews: String?
    var createdAt: String?
    var updatedAt: String?

    init(fields f: [String: Any]) {
        id = Coerce.int(f["id"]) ?? 0
        title = Coerce.str(f["title"]) ?? "Ohne Titel"
        author = Coerce.str(f["author"])
        publisher = Coerce.str(f["publisher"])
        year = Coerce.str(f["year"])
        category = Coerce.str(f["category"])
        descriptionText = Coerce.str(f["description"])
        coverURL = Coerce.str(f["cover_url"])
        isbn = Coerce.str(f["isbn"])
        language = Coerce.str(f["language"])
        status = Coerce.str(f["status"]) ?? "gesucht"
        sourceID = Coerce.str(f["source_id"])
        requestedBy = Coerce.str(f["requested_by"])
        requestedAt = Coerce.str(f["requested_at"])
        downloadedAt = Coerce.str(f["downloaded_at"])
        attempts = Coerce.int(f["attempts"]) ?? 0
        lastAttempt = Coerce.str(f["last_attempt"])
        notes = Coerce.str(f["notes"])
        reviews = Coerce.str(f["reviews"])
        createdAt = Coerce.str(f["created_at"])
        updatedAt = Coerce.str(f["updated_at"])
    }

    var isDownloaded: Bool { status == "heruntergeladen" }

    /// Cover-Pfad für `AuthImage` — externe URLs kommen unverändert zurück, sonst Media-Proxy.
    var coverPath: String? {
        guard let u = coverURL, !u.isEmpty else { return nil }
        return mediaURLPath(fromKey: u)
    }

    var hasDescription: Bool { (descriptionText?.isEmpty == false) }
}

// MARK: - Visuelle Konfiguration

enum EbookStyle {
    struct StatusInfo { let emoji: String; let label: String; let color: Color }

    static let rose = Color(hex: "E11D48")
    static let amber = Color(hex: "D97706")
    static let green = Color(hex: "16A34A")
    static let indigo = Color(hex: "6366F1")
    static let purple = Color(hex: "9333EA")

    static func statusInfo(_ s: String) -> StatusInfo {
        s == "heruntergeladen"
            ? StatusInfo(emoji: "✅", label: "Geladen", color: green)
            : StatusInfo(emoji: "🔍", label: "Gesucht", color: amber)
    }

    /// Alle wählbaren Status (feste Reihenfolge) — für das Bearbeiten-Formular.
    static let statusOrder = ["gesucht", "heruntergeladen"]

    /// Flaggen-Emoji per Substring (kleingeschrieben); leer wenn keine Sprache gesetzt ist.
    static func langFlag(_ lang: String?) -> String {
        guard let l = lang?.lowercased(), !l.isEmpty else { return "" }
        if l.contains("de") { return "🇩🇪" }
        if l.contains("en") { return "🇬🇧" }
        if l.contains("fr") { return "🇫🇷" }
        if l.contains("es") { return "🇪🇸" }
        if l.contains("it") { return "🇮🇹" }
        return "🌐"
    }

    /// Sprache als Flagge + Code (z.B. „🇩🇪 de"), leer wenn nicht gesetzt.
    static func langLabel(_ lang: String?) -> String? {
        guard let l = lang, !l.isEmpty else { return nil }
        let flag = langFlag(l)
        return flag.isEmpty ? l : "\(flag) \(l)"
    }
}

// MARK: - Filterzustand

struct EbookFilters: Equatable {
    var status: String? = nil     // gesucht | heruntergeladen (nil = alle)
    var year: String? = nil       // exakter Serverfilter
    var category: String? = nil   // LIKE-Serverfilter
    var search: String = ""       // title OR author (debounced)

    /// Für den „Reset"-Knopf sichtbar (Status zählt NICHT als aktiver Filter fürs Reset-✕).
    var isActive: Bool { status != nil || year != nil || category != nil || !search.isEmpty }
    /// Das ✕ setzt nur Jahr/Kategorie/Suche zurück (nicht den Status).
    var hasClearable: Bool { year != nil || category != nil || !search.isEmpty }
}

// MARK: - Tabs

enum EbookTab: Hashable { case wunschliste, suche }
