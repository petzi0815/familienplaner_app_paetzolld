import SwiftUI

/// Native Abfuhrkalender-Ansicht: kommende Termine je Kategorie gruppiert, farbig und übersichtlich.
/// Ersetzt den generischen Ressourcen-Browser für den Bereich „abfuhrkalender".
struct AbfuhrCalendarView: View {
    @EnvironmentObject private var app: AppState
    @State private var groups: [AbfuhrGroup] = []
    @State private var loading = true
    @State private var syncing = false
    @State private var toast: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if loading && groups.isEmpty {
                    ProgressView("Lädt Abfuhrtermine …").padding(.top, 70)
                } else if groups.isEmpty {
                    emptyState
                } else {
                    heroGrid
                    ForEach(groups) { g in categoryCard(g) }
                    footer
                }
            }
            .padding()
        }
        .background(Palette.gradient(for: "abfuhrkalender").opacity(0.06).ignoresSafeArea())
        .navigationTitle("Abfuhrkalender")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await sync() } } label: {
                    if syncing { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                }
                .disabled(syncing)
                .accessibilityLabel("Von aha-region.de aktualisieren")
            }
        }
        .overlay(alignment: .bottom) { if let t = toast { toastView(t) } }
        .task { if groups.isEmpty { await load() } }
        .refreshable { await load() }
    }

    // MARK: - Hero: nächste Abfuhr je Kategorie
    private let heroCols = [GridItem(.adaptive(minimum: 158), spacing: 12)]
    private var heroGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("Nächste Abfuhr").foregroundStyle(.primary)
            } icon: {
                Image(systemName: "trash.circle.fill").foregroundStyle(Palette.colors(for: "abfuhrkalender").first!)
            }
            .font(.headline)
            LazyVGrid(columns: heroCols, spacing: 12) {
                ForEach(groups) { g in heroCard(g) }
            }
        }
    }

    private func heroCard(_ g: AbfuhrGroup) -> some View {
        let c = Color(hex: g.color)
        let fg = c.onFill
        let scrim = (c.isLightFill ? Color.white : Color.black).opacity(0.28)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 4) {
                Text(g.emoji).font(.title2)
                Spacer()
                if let n = g.next {
                    Text(countdown(n.daysUntil, compact: true))
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(scrim, in: Capsule())
                        .foregroundStyle(fg)
                }
            }
            Spacer(minLength: 2)
            Text(g.label).font(.subheadline.weight(.bold)).foregroundStyle(fg).lineLimit(1).minimumScaleFactor(0.8)
            if let n = g.next {
                Text(compactDate(n.datum)).font(.caption).foregroundStyle(fg.opacity(0.9))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .background(
            LinearGradient(colors: [c, c.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .shadow(color: c.opacity(0.4), radius: 9, y: 4)
    }

    // MARK: - Kategorie-Sektion (nach Kategorien gruppiert)
    private func categoryCard(_ g: AbfuhrGroup) -> some View {
        let c = Color(hex: g.color)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(c)
                    Text(g.emoji).font(.title3)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(g.label).font(.headline)
                    Text("\(g.termine.count) \(g.termine.count == 1 ? "Termin" : "Termine")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let n = g.next {
                    Text(countdown(n.daysUntil, compact: false))
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(c, in: Capsule())
                        .foregroundStyle(c.onFill)
                }
            }
            Divider()
            ForEach(Array(g.termine.enumerated()), id: \.element.id) { pair in
                terminRow(pair.element, first: pair.offset == 0, color: c)
                if pair.element.id != g.termine.last?.id { Divider().opacity(0.4) }
            }
        }
        .padding(16)
        .cardSurface()
    }

    private func terminRow(_ t: AbfuhrTerminDate, first: Bool, color c: Color) -> some View {
        HStack(spacing: 12) {
            dateChip(t.datum, color: c, highlight: first)
            VStack(alignment: .leading, spacing: 1) {
                Text(DateText.weekdayLong(t.datum)).font(.subheadline.weight(first ? .bold : .medium))
                Text(DateText.longNoWeekday(t.datum)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(countdown(t.daysUntil, compact: true))
                .font(.caption.weight(first ? .bold : .regular))
                .foregroundStyle(first ? Color.primary : Color.secondary)
        }
        .padding(.vertical, 3)
    }

    private func dateChip(_ datum: String, color c: Color, highlight: Bool) -> some View {
        VStack(spacing: 0) {
            Text(DateText.day(datum)).font(.system(size: 18, weight: .bold, design: .rounded))
            Text(DateText.monthShort(datum)).font(.system(size: 10, weight: .semibold)).textCase(.uppercase)
        }
        .frame(width: 46, height: 46)
        .foregroundStyle(highlight ? c.onFill : c)
        .background(highlight ? c : c.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Leer / Footer / Toast
    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "trash.slash").font(.system(size: 46)).foregroundStyle(.secondary)
            Text("Keine Abfuhrtermine").font(.headline)
            Text("Termine von aha-region.de holen oder eine ICS-Datei ins Backend laden.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button { Task { await sync() } } label: {
                Label(syncing ? "Lädt …" : "Von aha-region.de laden", systemImage: "arrow.down.circle")
            }
            .buttonStyle(GradientButtonStyle(gradientKey: "abfuhrkalender")).disabled(syncing)
        }
        .frame(maxWidth: .infinity).padding(.top, 50).padding(.horizontal, 8)
    }

    private var footer: some View {
        Text("Quelle: aha-region.de · nach unten ziehen zum Aktualisieren")
            .font(.caption2).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity).padding(.top, 4)
    }

    private func toastView(_ t: String) -> some View {
        Text(t).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.black.opacity(0.8), in: Capsule())
            .padding(.bottom, 24)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Helfer
    private func countdown(_ days: Int, compact: Bool) -> String {
        if days == 0 { return "heute" }
        if days == 1 { return "morgen" }
        return compact ? "in \(days) T." : "in \(days) Tagen"
    }

    private func compactDate(_ s: String) -> String {
        "\(DateText.weekdayShort(s)), \(DateText.day(s)). \(DateText.monthShort(s))"
    }

    // MARK: - Laden / Sync
    private func load() async {
        loading = true
        defer { loading = false }
        do { groups = try await app.api.abfuhrCalendar() }
        catch { showToast("Konnte Termine nicht laden") }
    }

    private func sync() async {
        guard !syncing else { return }
        syncing = true
        defer { syncing = false }
        do {
            let n = try await app.api.syncAbfuhr()
            groups = try await app.api.abfuhrCalendar()
            showToast("\(n) Termine aktualisiert")
        } catch {
            showToast("Sync fehlgeschlagen")
        }
    }

    private func showToast(_ s: String) {
        withAnimation { toast = s }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation { toast = nil }
        }
    }
}
