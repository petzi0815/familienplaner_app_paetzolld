import AppIntents
import SwiftUI
import WidgetKit

/// Schnellaktionen — vier Deep-Links (`familienplaner://…`) direkt vom Home-Screen.
struct QuickActionsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuickActionsWidget", provider: QuickActionsProvider()) { _ in
            QuickActionsWidgetView()
                .containerBackground(for: .widget) { WTheme.grad.opacity(0.14) }
        }
        .configurationDisplayName("Schnellaktionen")
        .description("Foto aufnehmen, Termin oder Aufgabe anlegen, Heute öffnen.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct QuickActionsEntry: TimelineEntry {
    let date: Date
}

/// Statisches Widget — kein Netz, kein Zustand, daher genau ein Entry ohne Ablauf.
struct QuickActionsProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickActionsEntry { QuickActionsEntry(date: Date()) }

    func getSnapshot(in context: Context, completion: @escaping (QuickActionsEntry) -> Void) {
        completion(QuickActionsEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickActionsEntry>) -> Void) {
        completion(Timeline(entries: [QuickActionsEntry(date: Date())], policy: .never))
    }
}

/// Eine Kachel = Symbol + Beschriftung + Deep-Link-Host.
private struct QuickAction: Identifiable {
    let id: String
    /// Kurzform für das 2x2-Raster (systemSmall).
    let short: String
    /// Volle Beschriftung (systemMedium) — zugleich das Accessibility-Label.
    let title: String
    let systemImage: String
    let color: Color
    let host: String

    var url: URL? { URL(string: "familienplaner://" + host) }
}

private let quickActions: [QuickAction] = [
    QuickAction(id: "foto", short: "Foto", title: "Foto aufnehmen",
                systemImage: "camera.fill", color: WTheme.start, host: "foto"),
    QuickAction(id: "termin", short: "Termin", title: "Termin anlegen",
                systemImage: "calendar.badge.plus", color: WTheme.mid, host: "termin-neu"),
    QuickAction(id: "aufgabe", short: "Aufgabe", title: "Aufgabe anlegen",
                systemImage: "checklist", color: WTheme.running, host: "aufgabe-neu"),
    QuickAction(id: "heute", short: "Heute", title: "Heute öffnen",
                systemImage: "square.grid.2x2.fill", color: WTheme.soon, host: "heute"),
]

struct QuickActionsWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .systemMedium {
            medium
        } else {
            small
        }
    }

    /// 2x2-Raster. In `.systemSmall` ignoriert WidgetKit `Link` (dort zählt nur `widgetURL`),
    /// deshalb je Kachel ein `Button` mit `OpenURLIntent`; `widgetURL` bleibt als Rückfall auf „Heute“.
    private var small: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)],
                  spacing: 6) {
            ForEach(quickActions) { action in
                tapTarget(action, useLink: false) {
                    tile(action, label: action.short, size: 30)
                }
            }
        }
        .widgetURL(URL(string: "familienplaner://heute"))
    }

    /// Vier Kacheln nebeneinander mit voller Beschriftung.
    private var medium: some View {
        HStack(spacing: 8) {
            ForEach(quickActions) { action in
                tapTarget(action, useLink: true) {
                    tile(action, label: action.title, size: 36)
                }
            }
        }
    }

    @ViewBuilder
    private func tapTarget<C: View>(_ action: QuickAction, useLink: Bool,
                                    @ViewBuilder content: () -> C) -> some View {
        if let url = action.url {
            if useLink {
                Link(destination: url) { content() }
            } else {
                Button(intent: OpenURLIntent(url)) { content() }
                    .buttonStyle(.plain)
            }
        } else {
            content()
        }
    }

    private func tile(_ action: QuickAction, label: String, size: CGFloat) -> some View {
        VStack(spacing: 5) {
            Image(systemName: action.systemImage)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(
                    LinearGradient(colors: [action.color, action.color.opacity(0.72)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                )
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(action.title))
        .accessibilityAddTraits(.isButton)
    }
}
