import SwiftUI

extension FieldFormat {
    /// Formate, die die volle Breite brauchen (Label darüber statt daneben).
    var isBlock: Bool { self == .jsonList || self == .multiline || self == .keyValue }
}

/// Status-/Enum-Farbe nach Schlüsselwort.
func badgeColor(_ text: String) -> Color {
    let t = text.lowercased()
    if ["vergeben", "geschenkt", "aktiv", "erledigt", "zugeordnet", "verfügbar", "gekauft", "fertig", "vorhanden"].contains(where: t.contains) { return .green }
    if ["verworfen", "aussortiert", "verbraucht", "abgelaufen", "abgelehnt", "storniert", "gekündigt"].contains(where: t.contains) { return .red }
    if ["offen", "neu", "geplant", "bearbeitung", "wunsch", "ausstehend", "bald"].contains(where: t.contains) { return .orange }
    return .blue
}

/// Einfaches Flow-Layout für Chips (iOS 16+).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxW { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
        return CGSize(width: maxW == .infinity ? x : maxW, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
    }
}

struct BadgeView: View {
    let text: String
    var body: some View {
        Text(prettyColumn(text)).font(.caption.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(badgeColor(text).opacity(0.18), in: Capsule())
            .foregroundStyle(badgeColor(text))
    }
}

/// Rendert einen Feldwert gemäß seinem Format.
struct FieldValueView: View {
    let value: Any?
    let format: FieldFormat
    var accent: Color = .accentColor

    var body: some View {
        switch format {
        case .jsonList:
            let items = parseJSONList(fieldString(value))
            FlowLayout(spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, t in
                    Text(t).font(.caption.weight(.medium))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(accent.opacity(0.14), in: Capsule())
                        .foregroundStyle(accent)
                }
            }
        case .keyValue:
            let pairs = parseJSONObject(fieldString(value))
            if pairs.isEmpty {
                Text(fieldString(value)).multilineTextAlignment(.leading)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(pairs.enumerated()), id: \.offset) { _, kv in
                        HStack(alignment: .top, spacing: 8) {
                            Text(prettyColumn(kv.key)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                            Text(kv.value).font(.caption).multilineTextAlignment(.trailing)
                        }
                    }
                }
            }
        case .date: Text(DateText.pretty(fieldString(value)))
        case .datetime: Text(prettyDateTime(fieldString(value)))
        case .multiline: Text(fieldString(value)).multilineTextAlignment(.leading)
        case .bool: boolLabel(fieldString(value))
        case .badge: BadgeView(text: fieldString(value))
        case .url: urlLink(fieldString(value))
        case .time, .number, .price, .plain: Text(fieldString(value))
        case .hidden: EmptyView()
        }
    }

    private func boolLabel(_ s: String) -> some View {
        let on = ["1", "true", "ja", "yes"].contains(s.lowercased())
        return Label(on ? "Ja" : "Nein", systemImage: on ? "checkmark.circle.fill" : "xmark.circle")
            .foregroundStyle(on ? Color.green : .secondary)
            .labelStyle(.titleAndIcon).font(.subheadline)
    }

    @ViewBuilder private func urlLink(_ s: String) -> some View {
        if let u = URL(string: s) {
            Link(destination: u) { Label(u.host ?? "Link", systemImage: "link").font(.subheadline) }
        } else {
            Text(s)
        }
    }
}
