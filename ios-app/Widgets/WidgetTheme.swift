import SwiftUI
import WidgetKit

/// Gemeinsame Optik + Formatierung aller Widgets (bewusst eigenständig — die Widget-Extension
/// zieht das App-Theme NICHT mit). Einziger Ort für Farben/Datums-Helfer im Widget-Target.
enum WTheme {
    static let start = Color(red: 0.00, green: 0.48, blue: 0.90)
    static let mid = Color(red: 0.35, green: 0.34, blue: 0.84)
    static let end = Color(red: 0.20, green: 0.78, blue: 0.35)
    static let grad = LinearGradient(colors: [start, mid, end], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let running = Color(red: 0.20, green: 0.72, blue: 0.35)
    static let soon = Color(red: 0.96, green: 0.62, blue: 0.04)

    /// Hex („#3B82F6" / „3B82F6") → Color. Unbekannt/leer → `mid`.
    static func color(hex: String?) -> Color {
        guard var s = hex?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return mid }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return mid }
        return Color(red: Double((v >> 16) & 0xFF) / 255.0,
                     green: Double((v >> 8) & 0xFF) / 255.0,
                     blue: Double(v & 0xFF) / 255.0)
    }
}

/// Datums-/Zeit-Formatierung im Widget (deutsch, ohne Abhängigkeit zur App).
enum WDate {
    private static let de = Locale(identifier: "de_DE")

    private static let hhmm: DateFormatter = {
        let f = DateFormatter(); f.locale = de; f.dateFormat = "HH:mm"; return f
    }()
    private static let weekdayShort: DateFormatter = {
        let f = DateFormatter(); f.locale = de; f.dateFormat = "EE"; return f
    }()
    private static let dayMonth: DateFormatter = {
        let f = DateFormatter(); f.locale = de; f.dateFormat = "d. MMM"; return f
    }()

    static func time(_ d: Date) -> String { hhmm.string(from: d) }

    /// Kurzes Datum ohne Wochentag („30. Jul") — für Zeitspannen wie „noch bis 30. Jul".
    static func shortDate(_ d: Date) -> String { dayMonth.string(from: d) }

    /// Wochentag-Kürzel („Fr") — vor Uhrzeiten von Terminen an anderen Tagen.
    /// (Heißt bewusst nicht `weekdayShort`: Swift erlaubt Property und Methode gleichen Namens nicht.)
    static func weekday(_ d: Date) -> String { weekdayShort.string(from: d) }

    /// Tagesüberschrift: „Heute" / „Morgen" / „Mi, 29. Jul".
    static func dayHeader(_ d: Date, now: Date = Date()) -> String {
        let cal = Calendar.current
        if cal.isDate(d, inSameDayAs: now) { return "Heute" }
        if let t = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(d, inSameDayAs: t) { return "Morgen" }
        return "\(weekdayShort.string(from: d)), \(dayMonth.string(from: d))"
    }

    /// Kompakte Restzeit ohne Live-Timer: „in 12 Min", „in 3 Std", „in 2 Tagen", „jetzt".
    static func relative(to target: Date, now: Date = Date()) -> String {
        let s = target.timeIntervalSince(now)
        if s <= 0 { return "jetzt" }
        let min = Int(s / 60)
        if min < 1 { return "gleich" }
        if min < 60 { return "in \(min) Min" }
        let h = min / 60
        if h < 24 { return "in \(h) Std" }
        let d = h / 24
        return d == 1 ? "morgen" : "in \(d) Tagen"
    }

    /// „Stand 14:20" für den Offline-Fallback aus dem Cache.
    static func stamp(_ d: Date) -> String { "Stand \(hhmm.string(from: d))" }
}

/// Kleines farbiges Kategorie-Pünktchen.
struct WDot: View {
    let color: Color
    var size: CGFloat = 7
    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
    }
}

/// Badge „Läuft" für den gerade laufenden Termin.
struct WRunningBadge: View {
    var body: some View {
        Text("Läuft")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(WTheme.running.opacity(0.20), in: Capsule())
            .foregroundStyle(WTheme.running)
    }
}
