import SwiftUI

enum Theme {
    /// Adaptiver Akzent (Blau, im Dark Mode heller) — Muster 1:1 aus dem Referenzprojekt.
    static let accent = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.40, green: 0.65, blue: 0.98, alpha: 1)
            : UIColor(red: 0.20, green: 0.48, blue: 0.90, alpha: 1)
    })
}

/// Markenzeichen für den Login-Header — Haus-Symbol mit hartem Offset-Schatten.
struct BrandMark: View {
    var size: CGFloat = 76
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(Color.primary)
            Image(systemName: "house.fill")
                .font(.system(size: size * 0.46, weight: .black))
                .foregroundStyle(Color(.systemBackground))
        }
        .frame(width: size, height: size)
        .background(
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(Theme.accent)
                .offset(x: size * 0.06, y: size * 0.06)
        )
    }
}
