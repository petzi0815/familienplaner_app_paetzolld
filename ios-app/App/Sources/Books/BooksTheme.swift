import SwiftUI

extension Color {
    /// Farbe, die sich an Hell/Dunkel anpasst (hex je Modus).
    static func adaptiveHex(light: String, dark: String) -> Color {
        Color(uiColor: UIColor { trait in
            UIColor(Color(hex: trait.userInterfaceStyle == .dark ? dark : light))
        })
    }
}

// ElisBooks-Designidentität (warmes Amber/Braun) — **dark-mode-tauglich** (adaptive Farben).
enum BookTheme {
    static let amber600 = Color(hex: "#D97706")       // mittleres Amber, auf beiden Modi lesbar (Verlaufsbutton)
    static let orange600 = Color(hex: "#EA580C")
    // Markentext/Akzente: dunkelbraun in Hell, helles Amber in Dunkel.
    static let amber900 = Color.adaptiveHex(light: "#78350F", dark: "#FCD34D")
    static let amber700 = Color.adaptiveHex(light: "#B45309", dark: "#FBBF24")

    static var brandGradient: LinearGradient {
        LinearGradient(colors: [amber600, orange600], startPoint: .leading, endPoint: .trailing)
    }
    /// Hintergrund: warmes Cremeverlauf in Hell, dunkelbraun/fast-schwarz in Dunkel.
    static var bgWash: LinearGradient {
        LinearGradient(
            colors: [Color.adaptiveHex(light: "#FFFBEB", dark: "#1A1512"),
                     Color.adaptiveHex(light: "#FFEDD5", dark: "#241C17")],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static func shelfColor(_ hex: String?) -> Color { Color(hex: hex?.isEmpty == false ? hex! : "#94A3B8") }
}

/// Buch-Cover (3:4). Externe URLs via AsyncImage (http→https, da ATS http blockt);
/// fehlt das Cover, wird als Fallback das Open-Library-Cover per ISBN versucht, sonst Icon.
struct BookCover: View {
    let url: String?
    var isbn: String? = nil
    var wishlist = false
    var cornerRadius: CGFloat = 8

    private var effectiveURL: URL? {
        if let u = url, u.hasPrefix("http") {
            return URL(string: u.replacingOccurrences(of: "http://", with: "https://"))
        }
        if let i = isbn {
            let clean = i.filter { $0.isNumber || $0 == "X" }
            if clean.count >= 10 { return URL(string: "https://covers.openlibrary.org/b/isbn/\(clean)-M.jpg?default=false") }
        }
        return nil
    }

    var body: some View {
        Group {
            if let link = effectiveURL {
                AsyncImage(url: link) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    case .empty: ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    default: fallback
                    }
                }
            } else {
                fallback
            }
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var fallback: some View {
        ZStack {
            if wishlist {
                LinearGradient(colors: [Color(hex: "#FBCFE8"), Color(hex: "#DDD6FE")], startPoint: .top, endPoint: .bottom)
                Image(systemName: "heart.fill").font(.title).foregroundStyle(.white.opacity(0.9))
            } else {
                LinearGradient(colors: [Color(hex: "#DBEAFE"), Color(hex: "#EDE9FE")], startPoint: .top, endPoint: .bottom)
                Image(systemName: "book.closed.fill").font(.title).foregroundStyle(.white.opacity(0.9))
            }
        }
    }
}

/// Amber→Orange-Verlaufsbutton (Login/Primäraktionen).
struct ElisButtonStyle: ButtonStyle {
    var enabled = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline).foregroundStyle(.white)
            .frame(maxWidth: .infinity).padding(.vertical, 13)
            .background(enabled ? AnyShapeStyle(BookTheme.brandGradient) : AnyShapeStyle(Color.gray.opacity(0.4)),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct ReadBadge: View {
    let read: Bool
    var body: some View {
        Text(read ? "Gelesen" : "Ungelesen")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(read ? Color.green.opacity(0.18) : Color.secondary.opacity(0.15), in: Capsule())
            .foregroundStyle(read ? Color.green : .secondary)
    }
}

struct ShelfDot: View {
    let color: String?
    let name: String?
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(BookTheme.shelfColor(color)).frame(width: 8, height: 8)
            if let name, !name.isEmpty { Text(name).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
        }
    }
}

/// Kategorie-Chips (Flow).
struct CategoryPills: View {
    let categories: [String]
    var limit = 6
    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(categories.prefix(limit).enumerated()), id: \.offset) { _, c in
                Text(c).font(.caption2.weight(.medium))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(BookTheme.amber700.opacity(0.14), in: Capsule())
                    .foregroundStyle(BookTheme.amber900)
            }
        }
    }
}
