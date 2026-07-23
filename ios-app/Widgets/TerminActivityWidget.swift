import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Live Activity für den laufenden/nächsten Termin des Tages —
/// Sperrbildschirm-Banner + Dynamic Island, inkl. Quittieren ohne App-Start.
///
/// Der Inhalt kommt per APNs (`server/push/apns.ts::sendLiveActivity`), siehe
/// `Shared/TerminActivityAttributes.swift` für den harten Feld-Vertrag.
struct TerminActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TerminActivityAttributes.self) { context in
            // ── Sperrbildschirm / Banner ──
            TerminActivityLockScreenView(context: context)
                .activityBackgroundTint(WTheme.mid.opacity(0.16))
                .activitySystemActionForegroundColor(WTheme.mid)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(TerminActivityStyle.emoji(context.state))
                        .font(.title2)
                        .padding(.leading, 2)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TerminActivityCountdown(state: context.state)
                        .font(.callout.weight(.semibold).monospacedDigit())
                        .foregroundStyle(TerminActivityStyle.tint(context.state))
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.title)
                            .font(.headline)
                            .lineLimit(1)
                        if let sub = TerminActivityStyle.subline(context.state) {
                            Text(sub)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 8) {
                        Text(TerminActivityStyle.timeLine(context.state))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if context.state.isAcked(by: SharedStore.owner) {
                            TerminActivityAckedLabel(state: context.state)
                        } else {
                            TerminActivityAckButton(terminId: context.attributes.terminId,
                                                    action: .gelesen,
                                                    prominent: false)
                        }
                    }
                }
            } compactLeading: {
                Text(TerminActivityStyle.emoji(context.state))
            } compactTrailing: {
                TerminActivityCountdown(state: context.state)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(TerminActivityStyle.tint(context.state))
                    .frame(maxWidth: 54)
            } minimal: {
                Text(TerminActivityStyle.emoji(context.state))
            }
            .keylineTint(TerminActivityStyle.tint(context.state))
            .widgetURL(TerminActivityStyle.deepLink(context.attributes.terminId))
        }
    }
}

// ── Sperrbildschirm-Ansicht ──────────────────────────────────────────────────

struct TerminActivityLockScreenView: View {
    let context: ActivityViewContext<TerminActivityAttributes>

    private var state: TerminActivityAttributes.ContentState { context.state }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Text(TerminActivityStyle.emoji(state))
                    .font(.title2)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(state.title)
                            .font(.headline)
                            .lineLimit(1)
                        if state.isRunning { WRunningBadge() }
                    }
                    if let sub = TerminActivityStyle.subline(state) {
                        Text(sub)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(TerminActivityStyle.timeLine(state))
                        .font(.headline.monospacedDigit())
                    TerminActivityCountdown(state: state)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(TerminActivityStyle.tint(state))
                }
            }

            if state.isAcked(by: SharedStore.owner) {
                TerminActivityAckedLabel(state: state)
            } else {
                HStack(spacing: 8) {
                    TerminActivityAckButton(terminId: context.attributes.terminId,
                                            action: .gelesen,
                                            prominent: true)
                    TerminActivityAckButton(terminId: context.attributes.terminId,
                                            action: .erledigt,
                                            prominent: false)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .widgetURL(TerminActivityStyle.deepLink(context.attributes.terminId))
    }
}

// ── Bausteine ────────────────────────────────────────────────────────────────

/// Quittieren-Button (interaktiv seit iOS 17). Gerendert wird er hier in der Extension,
/// ausgeführt wird `TerminAckIntent.perform()` als `LiveActivityIntent` aber im **App-Prozess** —
/// nur dort darf ActivityKit die laufende Activity aktualisieren (siehe `Shared/WidgetIntents.swift`).
struct TerminActivityAckButton: View {
    let terminId: Int
    let action: TerminAckAction
    let prominent: Bool

    var body: some View {
        Button(intent: TerminAckIntent(terminId: terminId, action: action)) {
            Label(action.buttonTitle, systemImage: action.systemImage)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: prominent ? CGFloat.infinity : nil)
                .background(prominent ? WTheme.mid.opacity(0.22) : Color.secondary.opacity(0.14),
                            in: Capsule())
                .foregroundStyle(prominent ? WTheme.mid : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

/// Bestätigung statt Button, sobald quittiert wurde.
struct TerminActivityAckedLabel: View {
    let state: TerminActivityAttributes.ContentState

    var body: some View {
        Label(TerminActivityStyle.ackedText(state), systemImage: "checkmark.circle.fill")
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(WTheme.running)
    }
}

/// Live-Countdown bis zum Start bzw. Restzeit bis zum Ende. `Text(timerInterval:)` läuft
/// im System-Renderer weiter — kein Timeline-Reload und kein Push nötig.
struct TerminActivityCountdown: View {
    let state: TerminActivityAttributes.ContentState

    var body: some View {
        switch TerminActivityStyle.phase(state) {
        case .countdown(let range), .running(let range):
            Text(timerInterval: range, countsDown: true)
                .multilineTextAlignment(.trailing)
        case .text(let s):
            Text(s)
        }
    }
}

// ── Darstellungs-Logik (an einem Ort, damit Sperrbildschirm und Insel identisch sind) ──

enum TerminActivityStyle {
    enum Phase {
        /// Zählt bis zum Terminbeginn herunter.
        case countdown(ClosedRange<Date>)
        /// Läuft — zählt bis zum Terminende herunter.
        case running(ClosedRange<Date>)
        /// Statischer Text (ganztägig, vorbei, kein Ende bekannt).
        case text(String)
    }

    static func emoji(_ s: TerminActivityAttributes.ContentState) -> String {
        s.emoji.isEmpty ? "📅" : s.emoji
    }

    static func tint(_ s: TerminActivityAttributes.ContentState) -> Color {
        if s.isAckedByAnyone { return WTheme.running }
        if s.isRunning { return WTheme.running }
        if s.status == "vorbei" { return .secondary }
        let minutes = s.startAt.timeIntervalSinceNow / 60
        return minutes <= 60 ? WTheme.soon : WTheme.mid
    }

    /// Zeile unter dem Titel: Ort bevorzugt, sonst Person/Kategorie.
    static func subline(_ s: TerminActivityAttributes.ContentState) -> String? {
        let loc = s.location?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sub = s.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let loc, !loc.isEmpty, let sub, !sub.isEmpty { return "\(sub) · \(loc)" }
        if let loc, !loc.isEmpty { return loc }
        if let sub, !sub.isEmpty { return sub }
        return nil
    }

    /// Uhrzeit-Zeile: „15:45" bzw. „15:45–17:00", ganztägig ohne Uhrzeit.
    static func timeLine(_ s: TerminActivityAttributes.ContentState) -> String {
        if s.allDay { return "Ganztägig" }
        guard let end = s.endAt else { return WDate.time(s.startAt) }
        return "\(WDate.time(s.startAt))–\(WDate.time(end))"
    }

    static func phase(_ s: TerminActivityAttributes.ContentState) -> Phase {
        let now = Date()
        if s.status == "vorbei" { return .text("vorbei") }
        if s.startAt > now { return .countdown(now...s.startAt) }
        if s.allDay { return .text("heute") }
        if let end = s.endAt, end > now { return .running(now...end) }
        return .text("läuft")
    }

    /// „Von Lars quittiert" / „Quittiert".
    static func ackedText(_ s: TerminActivityAttributes.ContentState) -> String {
        let names = s.ackedBy
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .filter { !$0.isEmpty }
        guard !names.isEmpty else { return "Quittiert" }
        return "Quittiert von \(names.joined(separator: ", "))"
    }

    /// Deep-Link auf den Termin in der App (`familienplaner://termin/<id>`).
    static func deepLink(_ terminId: Int) -> URL? {
        URL(string: "familienplaner://termin/\(terminId)")
    }
}
