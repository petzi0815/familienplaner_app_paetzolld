import SwiftUI

// Wiederverwendbare, bereichsübergreifende UI-Bausteine für die nativen Lebensbereich-Module
// (Samu, Garten, Geschenkplaner). Halten Look & Verhalten konsistent zum ElisBooks-Modul.

/// Kopfzeile eines Bereichs: Verlaufs-Icon + Titel + optionale Unterzeile, optional Trailing-Slot.
struct AreaHeader<Trailing: View>: View {
    let gradientKey: String
    let systemImage: String
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    init(gradientKey: String, systemImage: String, title: String, subtitle: String? = nil,
         @ViewBuilder trailing: @escaping () -> Trailing) {
        self.gradientKey = gradientKey
        self.systemImage = systemImage
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 12) {
            GradientIcon(systemName: systemImage, gradientKey: gradientKey, size: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.title3.weight(.heavy))
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 6)
    }
}
extension AreaHeader where Trailing == EmptyView {
    init(gradientKey: String, systemImage: String, title: String, subtitle: String? = nil) {
        self.init(gradientKey: gradientKey, systemImage: systemImage, title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Horizontale Segment-Navigation (scrollbar). Ausgewähltes Segment = Bereichsverlauf.
struct SegmentBar<Tab: Hashable>: View {
    let tabs: [(tab: Tab, label: String, systemImage: String?)]
    @Binding var selection: Tab
    var gradientKey: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tabs, id: \.tab) { t in
                    let sel = selection == t.tab
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { selection = t.tab }
                    } label: {
                        Label {
                            Text(t.label)
                        } icon: {
                            if let s = t.systemImage { Image(systemName: s) }
                        }
                        .labelStyle(.titleAndIcon)
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 13).padding(.vertical, 8)
                        .background(sel ? AnyShapeStyle(Palette.gradient(for: gradientKey)) : AnyShapeStyle(Color(.secondarySystemBackground)),
                                    in: Capsule())
                        .foregroundStyle(sel ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
    }
}

/// Rundes Suchfeld mit Löschknopf (wie ElisBooks-Bibliothek).
struct AreaSearchField: View {
    let placeholder: String
    @Binding var text: String
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 14).padding(.vertical, 6)
    }
}

/// Umschalt-Pille für Filterleisten (aktiv = gefüllte Farbe, luminanz-sicherer Text).
struct FilterPill: View {
    let label: String
    var systemImage: String? = nil
    let selected: Bool
    var color: Color = Theme.accent
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let s = systemImage { Image(systemName: s) }
                Text(label)
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(selected ? AnyShapeStyle(color) : AnyShapeStyle(Color(.secondarySystemBackground)), in: Capsule())
            .foregroundStyle(selected ? color.onFill : .primary)
        }
        .buttonStyle(.plain)
    }
}

/// Farbige Kapsel (Badge/Chip) mit garantiert lesbarem Text.
struct Pill: View {
    let text: String
    var systemImage: String? = nil
    var color: Color = Theme.accent
    var filled: Bool = true
    var body: some View {
        HStack(spacing: 4) {
            if let s = systemImage { Image(systemName: s) }
            Text(text)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(filled ? AnyShapeStyle(color) : AnyShapeStyle(color.opacity(0.15)), in: Capsule())
        .foregroundStyle(filled ? color.onFill : color)
    }
}

/// Info-Zeile in Detailansichten: Emoji/Icon + Label + Wert.
struct InfoRow: View {
    let icon: String
    let label: String
    let value: String
    var valueColor: Color = .primary
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(icon).frame(width: 22)
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).foregroundStyle(valueColor).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.vertical, 3)
    }
}

/// Kennzahl-Kachel (Zahl groß + Label). Für Stats-Leisten.
/// (Name bewusst `AreaStatTile` — `StatTile` ist in HeuteView.swift bereits belegt.)
struct AreaStatTile: View {
    let value: String
    let label: String
    var color: Color = Theme.accent
    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.title2.weight(.bold)).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Notiz-/Textblock (farbig hinterlegt) für Detailansichten.
struct NoteBlock: View {
    let icon: String
    let text: String
    var tint: Color = .yellow
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(icon)
            Text(text).font(.subheadline).foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Kurzlebiger Toast am unteren Rand (Erfolg/Fehler).
struct AreaToast: View {
    let message: String
    let isError: Bool
    var body: some View {
        Label(message, systemImage: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
            .font(.subheadline.weight(.medium)).foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(isError ? Color.red : Color.green, in: Capsule())
            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
            .padding(.bottom, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// Leerzustand mit Emoji-Titel + Hinweis (statt SF-Symbol) — passt zum verspielten Bereichs-Look.
struct AreaEmptyState: View {
    let emoji: String
    let title: String
    var hint: String? = nil
    var body: some View {
        VStack(spacing: 8) {
            Text(emoji).font(.system(size: 44))
            Text(title).font(.headline)
            if let hint { Text(hint).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
