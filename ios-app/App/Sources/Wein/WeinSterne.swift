import SwiftUI
import UIKit

// Geteilte Anzeige-Bausteine des Weinbereichs: Sterne-Bewertung + Formatierung.
// Liegen bewusst zusammen, damit Liste und Detail exakt gleich aussehen.

// MARK: - Sterne

/// Sterne-Bewertung in zwei Modi:
/// - **anzeigend**: `WeinSterne(sterne: 4, kuerzel: "L")` — kompakt, optional mit Personenkuerzel
///   (L = Lars, E = Elita), damit in der Liste beide Bewertungen nebeneinander lesbar sind.
/// - **interaktiv**: `WeinSterne(auswahl: $sterne)` — 1 bis 5 antippbar, mit haptischer Rueckmeldung.
///
/// Ein Typ statt zweier, weil beide Modi dieselbe Optik teilen sollen. Der anzeigende Modus fasst
/// sich fuer VoiceOver zu EINEM Element zusammen; der interaktive laesst die fuenf Knoepfe stehen,
/// damit XCUITest sie einzeln antippen kann.
struct WeinSterne: View {
    private let sterne: Int
    private let auswahl: Binding<Int>?
    private let kuerzel: String?
    private let gross: Bool
    private let identifier: String?

    /// Nur anzeigen (Liste, Bewertung der anderen Person).
    init(sterne: Int, kuerzel: String? = nil, gross: Bool = false, identifier: String? = nil) {
        self.sterne = sterne
        self.auswahl = nil
        self.kuerzel = kuerzel
        self.gross = gross
        self.identifier = identifier
    }

    /// Antippbar (eigene Bewertung im Detail).
    init(auswahl: Binding<Int>, kuerzel: String? = nil, identifier: String = "wein-stern") {
        self.sterne = auswahl.wrappedValue
        self.auswahl = auswahl
        self.kuerzel = kuerzel
        self.gross = true
        self.identifier = identifier
    }

    private var wert: Int { auswahl?.wrappedValue ?? sterne }
    private var symbolFont: Font { gross ? .title3 : .caption2 }

    var body: some View {
        if let auswahl {
            interaktiv(auswahl)
        } else {
            anzeige
        }
    }

    // Fuenf Knoepfe: jeder einzeln antippbar und per Identifier auffindbar.
    private func interaktiv(_ auswahl: Binding<Int>) -> some View {
        HStack(spacing: 8) {
            personenKuerzel
            ForEach(1...5, id: \.self) { i in
                Button {
                    auswahl.wrappedValue = i
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    stern(i)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(i) + " von 5 Sternen")
                .accessibilityIdentifier((identifier ?? "wein-stern") + "-" + String(i))
            }
        }
    }

    // Reine Anzeige: ein Element fuer VoiceOver, keine Knoepfe (sonst wuerde XCUITest sie
    // faelschlich als bedienbar melden). Ein Identifier wird NUR gesetzt, wenn der Aufrufer einen
    // will — in einer Karte innerhalb eines NavigationLink wuerde er sonst die Zell-ID verdecken.
    @ViewBuilder private var anzeige: some View {
        let label = (kuerzel.map { $0 + ": " } ?? "") + String(wert) + " von 5 Sternen"
        if let identifier {
            sterneReihe.accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
                .accessibilityIdentifier(identifier)
        } else {
            sterneReihe.accessibilityElement(children: .ignore).accessibilityLabel(label)
        }
    }

    private var sterneReihe: some View {
        HStack(spacing: gross ? 4 : 2) {
            personenKuerzel
            ForEach(1...5, id: \.self) { i in stern(i) }
        }
    }

    @ViewBuilder private var personenKuerzel: some View {
        if let kuerzel, !kuerzel.isEmpty {
            Text(kuerzel)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(minWidth: 11)
        }
    }

    private func stern(_ i: Int) -> some View {
        Image(systemName: i <= wert ? "star.fill" : "star")
            .font(symbolFont)
            .foregroundStyle(i <= wert ? Color(hex: "F59E0B") : Color.secondary.opacity(0.4))
    }
}

// MARK: - Formatierung

/// Textaufbereitung des Weinbereichs (Preise, Datum, Prozente, Personen) an EINER Stelle.
/// Alle Zahl-zu-Text-Wandlungen laufen ueber `String(...)`, damit in `Text("…")` kein
/// Tausenderpunkt entsteht (aus 2019 wuerde sonst 2.019).
enum WeinText {
    /// Betrag als 12,90 € (de-DE).
    static func eur(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "EUR"
        f.locale = Locale(identifier: "de_DE")
        return f.string(from: NSNumber(value: v)) ?? String(format: "%.2f EUR", v)
    }

    /// Kommazahl mit deutschem Dezimalkomma (4.5 -> 4,5).
    static func zahl(_ v: Double, stellen: Int = 1) -> String {
        String(format: "%." + String(stellen) + "f", v).replacingOccurrences(of: ".", with: ",")
    }

    /// ISO-Datum oder SQLite-Zeitstempel -> 31.07.2026. Leerer String, wenn nichts da ist.
    static func datum(_ iso: String?) -> String {
        guard let iso, !iso.isEmpty else { return "" }
        let tag = String(iso.prefix(10))
        let teile = tag.split(separator: "-")
        guard teile.count == 3 else { return tag }
        return "\(teile[2]).\(teile[1]).\(teile[0])"
    }

    /// Rabatt gegenueber dem Referenzpreis als -23 % (kaufmaennisch gerundet).
    static func rabatt(_ prozent: Double) -> String {
        "-" + String(Int(prozent.rounded())) + " %"
    }

    /// Jahrgang ohne Tausenderpunkt; jahrgangslose Weine (viele Sekte) als o. J.
    static func jahrgang(_ j: Int?) -> String {
        guard let j else { return "o. J." }
        return String(j)
    }

    /// Alkoholgehalt als 13,5 % vol.
    static func alkohol(_ v: Double) -> String { zahl(v) + " % vol" }

    /// Flaschengroesse als 0,75 l (bzw. 375 ml unterhalb eines halben Liters).
    static func flasche(_ ml: Int) -> String {
        if ml < 500 { return String(ml) + " ml" }
        return zahl(Double(ml) / 1000.0, stellen: 2) + " l"
    }

    /// Trinkfenster als 2024 bis 2032 / ab 2024 / bis 2032.
    static func trinkfenster(_ von: Int?, _ bis: Int?) -> String {
        switch (von, bis) {
        case let (v?, b?): return String(v) + " bis " + String(b)
        case let (v?, nil): return "ab " + String(v)
        case let (nil, b?): return "bis " + String(b)
        default: return ""
        }
    }

    /// owner -> Anzeigename der Person.
    static func person(_ owner: String) -> String {
        switch owner {
        case "lars": return "Lars"
        case "elita": return "Elita"
        default: return owner
        }
    }

    /// owner -> Einbuchstaben-Kuerzel fuer die Listenansicht.
    static func kuerzel(_ owner: String) -> String {
        switch owner {
        case "lars": return "L"
        case "elita": return "E"
        default: return String(owner.prefix(1)).uppercased()
        }
    }

    /// Herkunft als Land · Region · Lage (nur gesetzte Teile).
    static func herkunft(land: String?, region: String?, lage: String?) -> String {
        [land, region, lage].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
