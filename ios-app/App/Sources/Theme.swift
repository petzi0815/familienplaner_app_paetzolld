import SwiftUI

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgb)
        self.init(.sRGB,
                  red: Double((rgb >> 16) & 0xFF) / 255,
                  green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255,
                  opacity: 1)
    }
}

enum Theme {
    /// Adaptiver App-Akzent (Blau, im Dark Mode heller).
    static let accent = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.40, green: 0.65, blue: 0.98, alpha: 1)
            : UIColor(red: 0.20, green: 0.48, blue: 0.90, alpha: 1)
    })
}

/// Frohe Farbverläufe je Lebensbereich — 1:1 zur Web-App.
enum Palette {
    static let gradients: [String: [String]] = [
        "samu": ["FF9F0A", "FF6B6B", "AF52DE"],
        "gypsi": ["FF8C00", "FF6600", "FF4500"],
        "smarthome": ["007AFF", "5856D6", "AF52DE"],
        "garten": ["34C759", "30D158", "00C7BE"],
        "vertraege": ["5856D6", "AF52DE", "FF2D55"],
        "buecher": ["FF2D55", "FF6B6B", "FF9500"],
        "ebooks": ["FF2D55", "FF6B6B", "FF9500"],
        "wunschliste": ["AF52DE", "FF2D55", "FF9500"],
        "termine": ["007AFF", "5856D6", "34C759"],
        "reisen": ["FF9500", "FF6B6B", "5856D6"],
        "geschenkplaner": ["F59E0B", "EF4444", "8B5CF6"],
        "vorratskammer": ["F97316", "FB923C", "FBBF24"],
        "reiniger": ["0EA5E9", "14B8A6", "84CC16"],
        "elisbooks": ["92400E", "B45309", "D97706"],
        "foto": ["5AC8FA", "007AFF", "5856D6"],
    ]

    static func colors(for key: String?) -> [Color] {
        (gradients[key ?? ""] ?? ["5AC8FA", "007AFF", "5856D6"]).map { Color(hex: $0) }
    }

    static func gradient(for key: String?) -> LinearGradient {
        LinearGradient(colors: colors(for: key), startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Bunte Bereichs-Kachel/Chip (ausgewählt = Verlauf, sonst dezent).
struct BereichChip: View {
    let bereich: Lebensbereich
    let selected: Bool
    var body: some View {
        HStack(spacing: 6) {
            if let e = bereich.emoji, !e.isEmpty { Text(e) }
            Text(bereich.titel).fontWeight(.semibold)
        }
        .font(.subheadline)
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(
            selected ? AnyShapeStyle(Palette.gradient(for: bereich.key))
                     : AnyShapeStyle(Color(.secondarySystemBackground)),
            in: Capsule()
        )
        .foregroundStyle(selected ? Color.white : Color.primary)
        .overlay(Capsule().strokeBorder(selected ? Color.white.opacity(0.35) : Color.clear, lineWidth: 1))
        .shadow(color: selected ? Palette.colors(for: bereich.key).first!.opacity(0.45) : .clear, radius: 8, y: 4)
        .animation(.snappy(duration: 0.2), value: selected)
    }
}

/// Großer Verlaufs-Button (primäre Aktion).
struct GradientButtonStyle: ButtonStyle {
    var gradientKey: String? = "foto"
    var enabled: Bool = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                enabled ? AnyShapeStyle(Palette.gradient(for: gradientKey))
                        : AnyShapeStyle(Color.gray.opacity(0.4)),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .foregroundStyle(.white)
            .shadow(color: enabled ? Palette.colors(for: gradientKey).first!.opacity(0.4) : .clear, radius: 12, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// Markenzeichen für den Login-Header — Haus mit hartem Offset-Schatten.
struct BrandMark: View {
    var size: CGFloat = 84
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(Palette.gradient(for: "foto"))
            Image(systemName: "house.fill")
                .font(.system(size: size * 0.44, weight: .black))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: Color(hex: "007AFF").opacity(0.45), radius: 16, y: 8)
    }
}
