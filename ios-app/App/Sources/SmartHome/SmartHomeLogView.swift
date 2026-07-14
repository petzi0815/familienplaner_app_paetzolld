import SwiftUI
import Charts

/// Command-Log-Tab: Kennzahlen (Total/Erfolgsrate/Durchschnitt), Antwortzeiten-Balkendiagramm
/// (letzte 20) und die Command-Historie als Zeilenliste (Zeit/Input/Entity/Action/Dauer/Status).
struct SmartHomeLogView: View {
    @EnvironmentObject private var store: SmartHomeStore

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if store.logs.isEmpty {
                    AreaEmptyState(emoji: "📋", title: "Noch keine Commands ausgeführt",
                                   hint: "Sprachbefehle erscheinen hier, sobald ha-voice sie protokolliert.")
                        .frame(minHeight: 300)
                } else {
                    statsRow
                    chart
                    logList
                }
            }
            .padding(.top, 6)
            .padding(.bottom, 28)
        }
        .refreshable { await store.reloadLog() }
    }

    // MARK: - Stats

    private var statsRow: some View {
        let s = store.logStats
        return HStack(spacing: 10) {
            AreaStatTile(value: "\(s.total)", label: "Commands", color: SmartHomeStyle.blue)
            AreaStatTile(value: "\(s.successRate)%", label: "Erfolgsrate", color: SmartHomeStyle.green)
            AreaStatTile(value: "\(s.avg)ms", label: "Durchschnitt", color: SmartHomeStyle.orange)
        }
        .padding(.horizontal, 14)
    }

    // MARK: - Balkendiagramm (letzte 20, aelteste -> neueste)

    @ViewBuilder private var chart: some View {
        let data = store.logChartData
        if !data.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Antwortzeiten (letzte 20)").font(.headline).padding(.horizontal, 14)
                Chart(Array(data.enumerated()), id: \.offset) { pair in
                    BarMark(
                        x: .value("Index", pair.offset),
                        y: .value("Dauer", pair.element.durationMs ?? 0)
                    )
                    .foregroundStyle(pair.element.success ? SmartHomeStyle.blue : Color.red)
                }
                .chartYScale(domain: 0...store.logChartMax)
                .chartXAxis(.hidden)
                .frame(height: 140)
                .padding(.horizontal, 14)
                HStack {
                    Text("Älteste").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text("Neueste").font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
            }
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground).opacity(0.5), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 14)
        }
    }

    // MARK: - Log-Liste

    private var logList: some View {
        VStack(spacing: 8) {
            ForEach(store.logs) { log in logRow(log) }
        }
        .padding(.horizontal, 14)
    }

    private func logRow(_ log: HACommandLog) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(HALogFormat.time(log.timestamp)).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: log.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(log.success ? SmartHomeStyle.green : Color.red)
            }
            if let input = log.inputText, !input.isEmpty {
                Text(input).font(.subheadline).lineLimit(2)
            }
            HStack(spacing: 6) {
                Text(log.entityDisplay).font(.caption.weight(.semibold)).lineLimit(1)
                if let score = log.matchScore {
                    Text("Score: \(String(format: "%.3f", score))").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
            }
            HStack(spacing: 6) {
                if let a = log.action, !a.isEmpty {
                    Pill(text: a.uppercased(), color: SmartHomeStyle.blue, filled: false)
                }
                if let ms = log.durationMs {
                    Pill(text: "\(ms)ms", color: SmartHomeStyle.durationColor(ms), filled: false)
                }
                Spacer()
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Log-Zeitstempel ("yyyy-MM-dd HH:mm:ss" UTC) -> "dd.MM, HH:mm:ss" in lokaler Zeit.
enum HALogFormat {
    private static let inFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
    private static let outFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM, HH:mm:ss"
        f.locale = Locale(identifier: "de_DE")
        return f
    }()
    static func time(_ s: String?) -> String {
        guard let s else { return "—" }
        guard let d = inFmt.date(from: String(s.prefix(19))) else { return s }
        return outFmt.string(from: d)
    }
}
