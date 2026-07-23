import SwiftUI

// Native Termine-Modelle (Familienkalender). Backend = Kompat-API `/api/termine`
// (bare Arrays, snake_case, Booleans als 0/1). Ein GET-Endpunkt multiplext via `?mode=`.

// MARK: - Termin

struct Termin: Identifiable, Equatable {
    let id: Int
    var title: String
    var beschreibung: String?
    var category: String
    var date: String            // yyyy-MM-dd
    var time: String?           // HH:MM (auf 5 Zeichen gekürzt)
    var endDate: String?
    var endTime: String?
    var location: String?
    var person: String?
    var recurring: String?
    var recurringInterval: String?
    var reminderDays: Int
    var reminderSent: Bool
    var cronJobId: String?
    var status: String          // offen | erledigt (GETEILT)
    var notes: String?
    var source: String?
    var createdAt: String?
    var updatedAt: String?
    var read: Bool              // PERSÖNLICH (nur bei Per-User-Key gesetzt)
    var notify: Bool            // PERSÖNLICH: Push-Opt-in (2 & 1 Tag vorher)
    var muted: Bool             // PERSÖNLICH: „nicht mehr erinnern" (Serverzustand, Migration 0018)

    init(fields f: [String: Any]) {
        id = Coerce.int(f["id"]) ?? 0
        title = Coerce.str(f["title"]) ?? ""
        beschreibung = Coerce.str(f["description"])
        category = Coerce.str(f["category"]) ?? "allgemein"
        date = Coerce.str(f["date"]).map { String($0.prefix(10)) } ?? ""
        time = Coerce.str(f["time"]).map { String($0.prefix(5)) }
        endDate = Coerce.str(f["end_date"]).map { String($0.prefix(10)) }
        endTime = Coerce.str(f["end_time"]).map { String($0.prefix(5)) }
        location = Coerce.str(f["location"])
        person = Coerce.str(f["person"])
        recurring = Coerce.str(f["recurring"])
        recurringInterval = Coerce.str(f["recurring_interval"])
        reminderDays = Coerce.int(f["reminder_days"]) ?? 2
        reminderSent = Coerce.bool(f["reminder_sent"])
        cronJobId = Coerce.str(f["cron_job_id"])
        status = Coerce.str(f["status"]) ?? "offen"
        notes = Coerce.str(f["notes"])
        source = Coerce.str(f["source"])
        createdAt = Coerce.str(f["created_at"])
        updatedAt = Coerce.str(f["updated_at"])
        read = Coerce.bool(f["read"])
        notify = Coerce.bool(f["notify"])
        muted = Coerce.bool(f["muted"])
    }

    var isDone: Bool { status == "erledigt" }
    /// Endet an einem anderen Tag (mehrtägig).
    var isMultiDay: Bool { (endDate?.isEmpty == false) && endDate != date }
}

// MARK: - Kategorie (aus `?mode=categories`: {id,label,emoji,color})

struct TerminCategory: Identifiable, Equatable {
    let id: String
    let label: String
    let emoji: String
    let color: String   // Token wie "blue"

    init(id: String, label: String, emoji: String, color: String) {
        self.id = id; self.label = label; self.emoji = emoji; self.color = color
    }

    init?(_ f: [String: Any]) {
        guard let i = Coerce.str(f["id"]) else { return nil }
        id = i
        label = Coerce.str(f["label"]) ?? i
        emoji = Coerce.str(f["emoji"]) ?? "📅"
        color = Coerce.str(f["color"]) ?? "blue"
    }
}

// MARK: - Person / Erinnerungs-Optionen (fest, clientseitig)

struct TerminPerson: Identifiable, Hashable {
    let id: String      // gespeicherter Wert ("Samu")
    let emoji: String
    let label: String
}

struct TerminReminderOption: Identifiable, Hashable {
    let id: Int         // Tage vorher
    let label: String
}

// MARK: - Ansicht-Umschaltung

enum TermineMode: Hashable { case liste, kalender }

// MARK: - Formular-Kontext für .sheet(item:) (nil = neu, sonst bearbeiten)

struct TermineFormRef: Identifiable {
    let id = UUID()
    let termin: Termin?
    let initialDate: String?
}

// MARK: - Visuelle Konfiguration (Farben, Emojis, Personen, Erinnerungen)

enum TermineStyle {
    /// Farbtoken → Hex (der Tailwind-500-Akzent/Punkt). Unbekannt → blau.
    static let colorTokens: [String: String] = [
        "blue": "3B82F6", "red": "EF4444", "rose": "F43F5E", "purple": "A855F7",
        "indigo": "6366F1", "cyan": "06B6D4", "amber": "F59E0B", "orange": "F97316",
        "gray": "6B7280", "green": "22C55E", "pink": "EC4899", "violet": "8B5CF6",
        "slate": "64748B",
    ]
    static func color(_ token: String) -> Color { Color(hex: colorTokens[token] ?? "3B82F6") }

    /// Die 13 kanonischen Kategorien — Fallback + Emoji/Farb-Lookup, wenn die API nichts liefert.
    /// (id-Tippfehler `schliesszzeit` [doppel-z] MUSS für Datenkompatibilität erhalten bleiben.)
    static let defaultCategories: [TerminCategory] = [
        .init(id: "allgemein", label: "Allgemein", emoji: "📅", color: "blue"),
        .init(id: "arzt_samu", label: "Arzt Samu", emoji: "👶🏥", color: "red"),
        .init(id: "arzt_familie", label: "Arzt Familie", emoji: "🏥", color: "rose"),
        .init(id: "impfung", label: "Impfung", emoji: "💉", color: "purple"),
        .init(id: "u_untersuchung", label: "U-Untersuchung", emoji: "📋", color: "indigo"),
        .init(id: "zahnarzt", label: "Zahnarzt", emoji: "🦷", color: "cyan"),
        .init(id: "schliesszzeit", label: "Schließzeit Kita", emoji: "🏫", color: "amber"),
        .init(id: "tierarzt", label: "Tierarzt", emoji: "🐱", color: "orange"),
        .init(id: "wartung", label: "Wartung/Haushalt", emoji: "🔧", color: "gray"),
        .init(id: "garten", label: "Garten", emoji: "🌱", color: "green"),
        .init(id: "geburtstag", label: "Geburtstag", emoji: "🎂", color: "pink"),
        .init(id: "friseur", label: "Friseur", emoji: "💇", color: "violet"),
        .init(id: "auto", label: "Auto/TÜV", emoji: "🚗", color: "slate"),
    ]

    static let persons: [TerminPerson] = [
        .init(id: "Samu", emoji: "👶", label: "Samu"),
        .init(id: "Lars", emoji: "👨", label: "Lars"),
        .init(id: "Elita", emoji: "👩", label: "Elita"),
        .init(id: "Gypsi", emoji: "🐱", label: "Gypsi"),
        .init(id: "Familie", emoji: "👨‍👩‍👦", label: "Familie"),
    ]
    static func personEmoji(_ p: String) -> String { persons.first { $0.id == p }?.emoji ?? "👤" }

    static let reminderOptions: [TerminReminderOption] = [
        .init(id: 0, label: "Keine"),
        .init(id: 1, label: "1 Tag vorher"),
        .init(id: 2, label: "2 Tage vorher"),
        .init(id: 3, label: "3 Tage vorher"),
        .init(id: 7, label: "1 Woche vorher"),
        .init(id: 14, label: "2 Wochen vorher"),
    ]
}

// MARK: - Datums-Arithmetik (datumsbasiert, tz-sicher)

enum TermineDates {
    private static let cal = Calendar.current
    private static let isoFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .current; return f
    }()
    private static let monthTitleFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "de_DE"); f.dateFormat = "LLLL yyyy"; return f
    }()

    static func today() -> Date { cal.startOfDay(for: Date()) }

    static func parse(_ s: String) -> Date? {
        guard !s.isEmpty, let d = isoFmt.date(from: String(s.prefix(10))) else { return nil }
        return cal.startOfDay(for: d)
    }

    static func iso(_ d: Date) -> String { isoFmt.string(from: d) }
    static func todayISO() -> String { iso(today()) }

    /// Tage von heute bis `date` (negativ = vergangen, nil = unparsbar).
    static func daysUntil(_ s: String) -> Int? {
        guard let d = parse(s) else { return nil }
        return cal.dateComponents([.day], from: today(), to: d).day
    }

    static func monthTitle(year: Int, month: Int) -> String {
        var c = DateComponents(); c.year = year; c.month = month; c.day = 1
        guard let d = cal.date(from: c) else { return "\(month)/\(year)" }
        return monthTitleFmt.string(from: d)
    }
}
