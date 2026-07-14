import SwiftUI

/// Einzelne Futter-Karte: Thumbnail + Marke/Sorte + Status/Geschmack/Datum + Notiz,
/// darunter Umschalt- und Löschknopf. Dislike-Karten sind leicht abgedunkelt (wie PWA).
struct GypsiFutterCard: View {
    let f: GypsiFutter
    let busy: Bool
    var onToggle: () -> Void
    var onDelete: () -> Void

    var body: some View {
        let info = GypsiStyle.info(f.status)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                thumb
                VStack(alignment: .leading, spacing: 5) {
                    if !f.marke.isEmpty {
                        Text(f.marke.uppercased())
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(GypsiStyle.amber)
                            .lineLimit(1)
                    }
                    Text(f.sorte.isEmpty ? "Unbenannt" : f.sorte)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Pill(text: info.badge, color: info.badgeColor, filled: false)
                        if let g = f.geschmack, !g.isEmpty {
                            Pill(text: "🥩 \(g)", color: GypsiStyle.amber, filled: false)
                        }
                    }
                    if let d = GypsiDate.short(f.erfasstAm) {
                        Text(d).font(.caption2).foregroundStyle(.secondary)
                    }
                    if let n = f.notizen, !n.isEmpty {
                        Text(n).font(.caption).italic().foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            actionRow(info)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(info.borderColor.opacity(0.4), lineWidth: 1))
        .opacity(f.liked ? 1 : 0.85)
    }

    private var thumb: some View {
        Group {
            if let path = f.imagePath {
                AuthImage(path: path, contentMode: .fill)
            } else {
                LinearGradient(colors: [Color(hex: "FBBF24"), Color(hex: "FB923C")],
                               startPoint: .top, endPoint: .bottom)
                    .overlay(Text("🐱").font(.system(size: 34)))
            }
        }
        .frame(width: 80, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func actionRow(_ info: GypsiStyle.StatusInfo) -> some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                HStack(spacing: 6) {
                    if busy { ProgressView().controlSize(.small).tint(info.toggleColor.onFill) }
                    Text(info.toggleLabel)
                }
                .font(.footnote.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(info.toggleColor, in: Capsule())
                .foregroundStyle(info.toggleColor.onFill)
            }
            .buttonStyle(.plain)
            .disabled(busy)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .font(.footnote.weight(.semibold))
                    .padding(.vertical, 9).padding(.horizontal, 15)
                    .background(Color(.tertiarySystemBackground), in: Capsule())
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .disabled(busy)
        }
    }
}
