import SwiftUI

// ElisBooks-Designidentität (warmes Amber/Braun) + Buch-Cover-Komponente.
enum BookTheme {
    static let amber600 = Color(hex: "#D97706")
    static let orange600 = Color(hex: "#EA580C")
    static let amber900 = Color(hex: "#78350F")
    static let amber700 = Color(hex: "#B45309")

    static var brandGradient: LinearGradient {
        LinearGradient(colors: [amber600, orange600], startPoint: .leading, endPoint: .trailing)
    }
    static var bgWash: LinearGradient {
        LinearGradient(colors: [Color(hex: "#FFFBEB"), Color(hex: "#FFEDD5")], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static func shelfColor(_ hex: String?) -> Color { Color(hex: hex?.isEmpty == false ? hex! : "#94A3B8") }
}

/// Buch-Cover (3:4). Externe URLs (Google Books / Open Library) via AsyncImage; sonst Fallback-Icon.
struct BookCover: View {
    let url: String?
    var wishlist = false
    var cornerRadius: CGFloat = 8

    var body: some View {
        Group {
            if let u = url, u.hasPrefix("http"), let link = URL(string: u) {
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
