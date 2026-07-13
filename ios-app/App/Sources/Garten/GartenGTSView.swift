import SwiftUI
import Charts

/// GTS-Detail (Grünlandtemperatursumme) als Sheet: aktueller Wert, Fortschrittsbalken mit
/// 150/200-Markern + 14-Tage-Forecast, zwei Forecast-Kacheln, Verlaufs-Chart (Swift Charts),
/// Meilensteine (plant_tips) und frostempfindliche Pflanzen.
struct GartenGTSSheet: View {
    let gts: GTSResult
    @Environment(\.dismiss) private var dismiss

    private static let parser: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    private struct ChartPoint: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
    }

    private var historyPoints: [ChartPoint] {
        gts.history.compactMap { d in
            Self.parser.date(from: d.date).map { ChartPoint(date: $0, value: d.cumulative) }
        }
    }
    private var forecastPoints: [ChartPoint] {
        var pts = gts.forecast.compactMap { d in
            Self.parser.date(from: d.date).map { ChartPoint(date: $0, value: d.cumulative) }
        }
        if let last = historyPoints.last { pts.insert(ChartPoint(date: last.date, value: last.value), at: 0) }
        return pts
    }
    private var maxY: Double {
        max(200, gts.projected14d, (gts.history + gts.forecast).map { $0.cumulative }.max() ?? 0)
    }
    private var barScale: Double { max(200, gts.projected14d) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    titleRow
                    progressBar
                    forecastTiles
                    chartSection
                    meilensteine
                    frostPlants
                }
                .padding()
            }
            .navigationTitle("Grünlandtemperatursumme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } } }
        }
    }

    private var titleRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("🌡️ Grünlandtemperatursumme").font(.headline)
                Text("Burgwedel · \(gts.date)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(Int(gts.current.rounded()))°C").font(.title.weight(.heavy))
                Text("von 200°C").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    // ── Fortschrittsbalken ──
    private var progressBar: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5))
                    if gts.projected14d > gts.current {
                        Capsule().fill(GartenStyle.gts150.opacity(0.35))
                            .frame(width: w * CGFloat(min(1, gts.projected14d / barScale)))
                    }
                    Capsule().fill(GartenStyle.gtsColor(gts.current))
                        .frame(width: w * CGFloat(min(1, gts.current / barScale)))
                    Rectangle().fill(GartenStyle.gts150).frame(width: 2, height: 12)
                        .offset(x: w * CGFloat(min(1, 150 / barScale)) - 1)
                    Rectangle().fill(GartenStyle.gts200).frame(width: 2, height: 12)
                        .offset(x: w * CGFloat(min(1, 200 / barScale)) - 2)
                }
            }
            .frame(height: 12)
            HStack {
                Text("0").font(.system(size: 9)).foregroundStyle(.secondary)
                Spacer()
                Text("150 Düngung").font(.system(size: 9)).foregroundStyle(Color(hex: "D97706"))
                Spacer()
                Text("200 Wachstum").font(.system(size: 9)).foregroundStyle(Color(hex: "16A34A"))
            }
        }
    }

    // ── Forecast-Kacheln ──
    private var forecastTiles: some View {
        HStack(spacing: 10) {
            forecastTile(title: "🧪 150°C Düngung", tint: Color(hex: "B45309"), bg: Color(hex: "F59E0B").opacity(0.12),
                         value: thresholdText(reached: gts.threshold150Reached, forecast: gts.forecastReach150, remaining: gts.remaining150))
            forecastTile(title: "🌿 200°C Wachstum", tint: Color(hex: "15803D"), bg: Color(hex: "22C55E").opacity(0.12),
                         value: thresholdText(reached: gts.threshold200Reached, forecast: gts.forecastReach200, remaining: gts.remaining200))
        }
    }

    private func forecastTile(title: String, tint: Color, bg: Color, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(tint)
            Text(value).font(.subheadline.weight(.bold)).foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(bg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func thresholdText(reached: Bool, forecast: String?, remaining: Double) -> String {
        if reached { return "✅ Erreicht!" }
        if let f = forecast { return "~\(Self.formatDate(f))" }
        return "Noch \(GartenStyle.trimDouble(remaining))°C"
    }

    // ── Chart ──
    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("📈 Verlauf & Forecast").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Chart {
                ForEach(historyPoints) { p in
                    LineMark(x: .value("Datum", p.date), y: .value("GTS", p.value), series: .value("Serie", "hist"))
                        .foregroundStyle(GartenStyle.gtsHistory)
                }
                ForEach(forecastPoints) { p in
                    LineMark(x: .value("Datum", p.date), y: .value("GTS", p.value), series: .value("Serie", "fc"))
                        .foregroundStyle(GartenStyle.gts150)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                }
                RuleMark(y: .value("150", 150))
                    .foregroundStyle(GartenStyle.gts150.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                RuleMark(y: .value("200", 200))
                    .foregroundStyle(GartenStyle.gts200.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            .chartYScale(domain: 0...maxY)
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 170)
            HStack(spacing: 14) {
                legendItem(GartenStyle.gtsHistory, "Historisch")
                legendItem(GartenStyle.gts150, "Forecast")
            }
        }
    }

    private func legendItem(_ c: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Capsule().fill(c).frame(width: 14, height: 3)
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    // ── Meilensteine ──
    private var meilensteine: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("🌱 Garten-Meilensteine").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(gts.plantTips) { tip in
                HStack(spacing: 8) {
                    Text(tip.emoji)
                    Text("\(tip.gts)°C").font(.system(size: 11, weight: .bold).monospaced())
                        .foregroundStyle(tip.reached ? Color(hex: "16A34A") : Color.secondary)
                        .frame(minWidth: 40, alignment: .leading)
                    Text(tip.label + (tip.reached ? " ✅" : ""))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(tip.reached ? Color(hex: "166534") : .primary)
                    Spacer(minLength: 4)
                    if !tip.reached, let f = tip.forecastDate {
                        Text("~\(Self.formatDate(f))").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color(hex: "D97706"))
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(tip.reached ? Color(hex: "22C55E").opacity(0.12) : Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    // ── Frostpflanzen ──
    @ViewBuilder private var frostPlants: some View {
        if !gts.frostPlants.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("🥶 Frostempfindliche Pflanzen").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(gts.frostPlants) { p in
                    HStack(alignment: .top, spacing: 8) {
                        Text(frostIcon(p.status))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name).font(.subheadline.weight(.semibold)).foregroundStyle(frostText(p.status))
                            Text(p.hinweis).font(.caption).foregroundStyle(frostText(p.status).opacity(0.85))
                        }
                        Spacer(minLength: 4)
                        Text("min \(GartenStyle.trimDouble(p.minTemp))°C")
                            .font(.system(size: 10).monospaced()).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(frostBg(p.status), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    private func frostIcon(_ s: String) -> String {
        switch s { case "draussen_ok": return "☀️"; case "reinholen": return "🚨"; default: return "🏠" }
    }
    private func frostText(_ s: String) -> Color {
        switch s { case "draussen_ok": return Color(hex: "166534"); case "reinholen": return Color(hex: "991B1B"); default: return Color(hex: "1E40AF") }
    }
    private func frostBg(_ s: String) -> Color {
        switch s {
        case "draussen_ok": return Color(hex: "22C55E").opacity(0.12)
        case "reinholen": return Color(hex: "EF4444").opacity(0.12)
        default: return Color(hex: "3B82F6").opacity(0.12)
        }
    }

    /// "2026-07-12" → "12.7."
    private static func formatDate(_ iso: String) -> String {
        let parts = iso.split(separator: "-")
        guard parts.count >= 3, let m = Int(parts[1]), let d = Int(parts[2]) else { return iso }
        return "\(d).\(m)."
    }
}
