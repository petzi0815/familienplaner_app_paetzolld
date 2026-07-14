import SwiftUI

/// Kalenderansicht: Monatsnavigator + Montag-erst 7-Spalten-Raster mit Ereignis-Punkten,
/// darunter (bei getipptem Tag) die Tages-Detailliste + „Termin"-Schnellanlage.
struct TermineCalendarView: View {
    @EnvironmentObject private var store: TermineStore

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let weekdays = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                monthNav
                weekdayHeader
                grid
                if let sel = store.selectedDate { dayDetail(sel) }
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 28)
        }
        .refreshable { await store.reloadMonth() }
    }

    // ── ‹ Monat Jahr › ──
    private var monthNav: some View {
        HStack {
            Button { store.prevMonth() } label: { Image(systemName: "chevron.left").font(.headline) }
            Spacer()
            Text(TermineDates.monthTitle(year: store.calYear, month: store.calMonth))
                .font(.headline)
            Spacer()
            Button { store.nextMonth() } label: { Image(systemName: "chevron.right").font(.headline) }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.accent)
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: cols, spacing: 4) {
            ForEach(weekdays, id: \.self) { d in
                Text(d).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            }
        }
    }

    private var grid: some View {
        LazyVGrid(columns: cols, spacing: 4) {
            ForEach(0..<store.leadingOffset, id: \.self) { _ in
                Color.clear.frame(height: 46)
            }
            ForEach(1...store.daysInMonth, id: \.self) { day in
                dayCell(day)
            }
        }
    }

    private func dayCell(_ day: Int) -> some View {
        let iso = store.iso(day: day)
        let isToday = iso == TermineDates.todayISO()
        let isPast = (TermineDates.daysUntil(iso) ?? 0) < 0
        let selected = store.selectedDate == iso
        let dots = store.dotCount(iso)
        return Button { store.selectDay(iso) } label: {
            VStack(spacing: 3) {
                Text("\(day)")
                    .font(.subheadline.weight(isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? Color.white : (isPast ? Color.secondary : Color.primary))
                HStack(spacing: 2) {
                    ForEach(0..<dots, id: \.self) { _ in
                        Circle().fill(isToday ? Color.white : Theme.accent).frame(width: 4, height: 4)
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(cellBackground(isToday: isToday, selected: selected),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected && !isToday ? Theme.accent : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func cellBackground(isToday: Bool, selected: Bool) -> AnyShapeStyle {
        if isToday { return AnyShapeStyle(Color.blue) }
        if selected { return AnyShapeStyle(Theme.accent.opacity(0.18)) }
        return AnyShapeStyle(Color.clear)
    }

    // ── Tagesdetail ──
    private func dayDetail(_ iso: String) -> some View {
        let events = store.eventsOn(iso)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("📅 \(DateText.pretty(iso))").font(.subheadline.weight(.bold))
                Spacer()
                Button { store.formRef = TermineFormRef(termin: nil, initialDate: iso) } label: {
                    Label("Termin", systemImage: "plus.circle.fill").font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain).foregroundStyle(Theme.accent)
            }
            if events.isEmpty {
                Text("Keine Termine an diesem Tag")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 20)
            } else {
                ForEach(events) { TerminCard(termin: $0) }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
