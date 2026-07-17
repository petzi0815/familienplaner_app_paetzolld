import SwiftUI

/// Der Start-Korridor-Regler (Modell v3): ersetzt den alten Warm/Kalt-Umschalter.
///
/// Die Essenszeit ist fix; der Nutzer waehlt hier per Daumen den START. Der Regler zeigt den
/// Korridor [frueh, spaet] als waagerechte Spur: moegliche Bereiche in der Bereichsfarbe,
/// durch die Nachtruhe BLOCKIERTE Segmente grau/schraffiert. Beim Ziehen wird die Position auf
/// den naechsten FREIEN Start gesnappt (`onSelect`), sodass der Daumen nie in einer Sperrzone
/// stehen bleibt. Frueher Start = laengere (kalte) Gare = mehr Aroma; spaeter Start = kurze
/// warme Gare = schneller. Ob es gerade WARM oder KALT ist, ergibt sich aus dem Plan (Badge).
struct PizzaStartRegler: View {
    let korridor: PizzaKorridor
    let gewaehlterStart: Date
    /// Der aktive Plan (fuer das Warm/Kalt-Badge) — abgeleitet, nicht mehr waehlbar.
    let aktiverPlan: PizzaPlan?
    let tint: Color
    /// Wird beim Ziehen/Tippen mit dem Zieldatum gerufen; der Store snappt auf den naechsten freien Start.
    let onSelect: (Date) -> Void

    private let spurHoehe: CGFloat = 30
    private let daumen: CGFloat = 28

    /// Der tatsaechlich von den Segmenten abgedeckte Bereich. Die Segmente kacheln [lo, hi]
    /// lueckenlos, deshalb ist das der exakte Rahmen fuer die Pixel-Zuordnung (nicht frueh/spaet,
    /// deren rechter Rand um bis zu 14 min ueber den letzten Rasterpunkt hinausragen kann).
    private var lo: Date { korridor.segmente.first?.von ?? korridor.frueh }
    private var hi: Date { korridor.segmente.last?.bis ?? korridor.spaet }
    private var spanne: Double { max(1, hi.timeIntervalSince(lo)) }

    private var hatSperren: Bool { korridor.segmente.contains { !$0.moeglich } }
    private var istKalt: Bool { aktiverPlan?.variante == .kalt }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            kopf
            spur
            legende
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .accessibilityIdentifier("pizza-start-regler")
    }

    // MARK: - Kopf (gewaehlte Startzeit gross + Warm/Kalt-Badge)

    private var kopf: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Teig ansetzen").font(.footnote.weight(.bold)).textCase(.uppercase)
                    .foregroundStyle(tint)
                Text(PizzaCalculator.uhrzeit(gewaehlterStart))
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
                if !Calendar.current.isDateInToday(gewaehlterStart) {
                    Text(PizzaCalculator.datumUndUhrzeit(gewaehlterStart))
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if aktiverPlan != nil {
                Pill(text: istKalt ? "Kalt · über Nacht" : "Warm · am selben Tag",
                     systemImage: istKalt ? "snowflake" : "hare.fill", color: tint)
            }
        }
    }

    // MARK: - Spur (Korridor + Sperrzonen + Daumen)

    private var spur: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    // Segmente: moeglich = Bereichsfarbe, blockiert = grau/schraffiert.
                    HStack(spacing: 0) {
                        ForEach(korridor.segmente) { seg in
                            segmentBalken(seg)
                                .frame(width: max(0, breite(seg, gesamt: w)))
                        }
                    }
                    .frame(height: spurHoehe)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08)))

                    // Daumen am gewaehlten Start.
                    Circle()
                        .fill(tint)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
                        .frame(width: daumen, height: daumen)
                        .shadow(color: tint.opacity(0.45), radius: 4, y: 2)
                        .offset(x: daumenX(w))
                }
                .frame(height: spurHoehe)
                .contentShape(Rectangle())
                // minimumDistance > 0: SwiftUI kann so eine ueberwiegend VERTIKALE Bewegung an den
                // umschliessenden ScrollView geben (Scrollen) und nur horizontales Ziehen an den Regler.
                // Bei minimumDistance 0 gewinnt der Regler schon beim Touch-Down → Seite unscrollbar +
                // Daumen springt zum Finger. Tippen-zum-Positionieren liefert die SpatialTapGesture.
                .gesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { wert in onSelect(datum(fuerX: wert.location.x, breite: w)) }
                )
                .simultaneousGesture(
                    SpatialTapGesture()
                        .onEnded { wert in onSelect(datum(fuerX: wert.location.x, breite: w)) }
                )
                .accessibilityElement()
                .accessibilityLabel("Startzeit-Regler")
                .accessibilityValue(PizzaCalculator.uhrzeit(gewaehlterStart))
                .accessibilityAdjustableAction { richtung in
                    let schritt: TimeInterval = 15 * 60
                    switch richtung {
                    case .increment: onSelect(gewaehlterStart.addingTimeInterval(schritt))
                    case .decrement: onSelect(gewaehlterStart.addingTimeInterval(-schritt))
                    @unknown default: break
                    }
                }
            }
            .frame(height: spurHoehe)

            // Rand-Beschriftung: fruehester (mehr Aroma) … spaetester (schneller) Start.
            HStack {
                Text(PizzaCalculator.uhrzeit(lo)).font(.caption2).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(PizzaCalculator.uhrzeit(hi)).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    /// Ein Segment als farbiger Balken. Blockiert = grau mit diagonaler Schraffur, damit die
    /// Sperrzonen auch ohne Farbe (Kontrast/Dark Mode) eindeutig „nicht moeglich" signalisieren.
    @ViewBuilder private func segmentBalken(_ seg: PizzaKorridorSegment) -> some View {
        if seg.moeglich {
            Rectangle().fill(tint.opacity(0.38))
        } else {
            Rectangle().fill(Color(.systemGray4))
                .overlay(Schraffur().stroke(Color(.systemGray).opacity(0.7), lineWidth: 1.1))
        }
    }

    // MARK: - Legende

    private var legende: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.left").font(.caption2.weight(.bold)).foregroundStyle(tint)
                Text("früh = mehr Aroma").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text("spät = schneller").font(.caption).foregroundStyle(.secondary)
                Image(systemName: "arrow.right").font(.caption2.weight(.bold)).foregroundStyle(tint)
            }
            if hatSperren {
                HStack(spacing: 7) {
                    Rectangle().fill(Color(.systemGray4))
                        .overlay(Schraffur().stroke(Color(.systemGray).opacity(0.7), lineWidth: 1))
                        .frame(width: 22, height: 12)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    Text("nicht möglich (Nachtruhe)").font(.caption2).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - Pixel <-> Zeit

    private func breite(_ seg: PizzaKorridorSegment, gesamt w: CGFloat) -> CGFloat {
        CGFloat(seg.bis.timeIntervalSince(seg.von) / spanne) * w
    }

    /// x-Position des Daumen-fuehrenden Rands, sodass sein Mittelpunkt auf dem Start sitzt,
    /// aber innerhalb der Spur bleibt.
    private func daumenX(_ w: CGFloat) -> CGFloat {
        let anteil = CGFloat(gewaehlterStart.timeIntervalSince(lo) / spanne)
        let mitte = anteil * w
        return min(max(0, mitte - daumen / 2), max(0, w - daumen))
    }

    private func datum(fuerX x: CGFloat, breite w: CGFloat) -> Date {
        let anteil = min(max(0, x / max(1, w)), 1)
        return lo.addingTimeInterval(Double(anteil) * spanne)
    }
}

/// Diagonale Schraffur (fuellt den Rahmen mit 45°-Linien) fuer die blockierten Segmente.
private struct Schraffur: Shape {
    var abstand: CGFloat = 6
    func path(in rect: CGRect) -> Path {
        var p = Path()
        var x = -rect.height
        while x < rect.width {
            p.move(to: CGPoint(x: x, y: rect.height))
            p.addLine(to: CGPoint(x: x + rect.height, y: 0))
            x += abstand
        }
        return p
    }
}
