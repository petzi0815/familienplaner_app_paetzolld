import Foundation

/// Baut aus einem fertigen Plan den Text zum Teilen (Zutatenblock + Zeitplan, Format der Spec).
///
/// Der Teilen-Dialog selbst ist der bereits vorhandene `ShareSheet` (UIActivityViewController,
/// definiert in Ebooks/CalibreBookDetail.swift) — hier entsteht bewusst KEIN zweiter.
/// Alle Zahlen/Zeiten kommen aus den Formatierern des Rechenkerns, damit geteilter Text und
/// angezeigter Plan garantiert dieselben Werte zeigen.
enum PizzaShare {

    /// Ein Plan als Klartext (WhatsApp/Notizen/Mail).
    static func text(plan p: PizzaPlan, calendar: Calendar = .current) -> String {
        let c = p.config
        let z = p.zutaten
        var zeilen: [String] = []

        zeilen.append("🍕 Pizza-Plan für \(String(c.anzahlPizzen)) × \(PizzaCalculator.gramm(c.teiglingsgewichtG)) g")
        zeilen.append("\(c.mehltyp.label) · \(c.hefetyp.label) · \(c.knetmethode.label) · \(PizzaCalculator.grad(c.raumtempC)) °C")
        zeilen.append("")

        zeilen.append("ZUTATEN")
        zeilen.append(feld("Mehl (\(c.mehltyp.label))", PizzaCalculator.gramm(z.mehlG) + " g"))
        zeilen.append(feld("Wasser (\(PizzaCalculator.grad(z.wasserTempC)) °C)", PizzaCalculator.gramm(z.wasserMl) + " ml"))
        zeilen.append(feld("Salz", PizzaCalculator.gramm(z.salzG) + " g"))
        zeilen.append(feld(c.hefetyp.label, PizzaCalculator.hefeGramm(z.hefeG) + " g"))
        zeilen.append(feld("Semola (zum Ausbreiten)", PizzaCalculator.gramm(z.semolaG) + " g"))
        zeilen.append(feld("Hydration", PizzaCalculator.grad(c.hydration * 100) + " %"))
        zeilen.append("")

        zeilen.append("ZEITPLAN (Essen \(PizzaCalculator.uhrzeit(p.essenszeit, calendar: calendar)) Uhr)")
        for s in p.schritte {
            let zeit = PizzaCalculator.uhrzeit(s.zeit, calendar: calendar)
            if let d = s.detail, !d.isEmpty { zeilen.append("\(zeit)  \(s.titel) — \(d)") }
            else { zeilen.append("\(zeit)  \(s.titel)") }
        }
        zeilen.append("")

        zeilen.append("Gesamt \(PizzaCalculator.dauer(p.gesamtdauerMinuten)) · Gare \(PizzaCalculator.dauer(p.nettoMinuten)) "
            + "(Stock \(PizzaCalculator.dauer(p.stockMinuten)) / Stück \(PizzaCalculator.dauer(p.stueckMinuten)))")
        zeilen.append("Start: \(PizzaCalculator.datumUndUhrzeit(p.startzeit, calendar: calendar))")

        // Hinweise gehoeren mit in den geteilten Text — wer nur den Zettel liest, soll die
        // Einschraenkungen des Plans trotzdem kennen.
        let hinweise = p.hinweise.map(\.text)
        if !hinweise.isEmpty {
            zeilen.append("")
            zeilen.append("HINWEISE")
            for h in hinweise { zeilen.append("• " + h) }
        }
        return zeilen.joined(separator: "\n")
    }

    /// Label + Wert, damit die Zutatenliste eine Spalte bildet (monospaced-freundlich).
    private static func feld(_ label: String, _ wert: String) -> String {
        let breite = 26
        let fehlt = max(0, breite - label.count)
        return label + String(repeating: " ", count: fehlt) + wert
    }
}

/// Text-Element fuer den Teilen-Dialog (`.sheet(item:)` braucht Identifiable).
struct PizzaShareItem: Identifiable {
    let id = UUID()
    let text: String
}
