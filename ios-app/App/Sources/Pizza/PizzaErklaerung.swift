import SwiftUI

// In-App-Erklaerungen fuer die Eingabe-Optionen des Pizza-Planers.
//
// Ziel (Nutzerwunsch): jede Option laesst sich verstehen, ohne Fachjargon zu kennen. Deshalb EIN
// wiederverwendbarer Baustein (`PizzaInfoButton`) plus ein Katalog fertiger Erklaertexte
// (`PizzaErklaerung`), damit die Texte an genau einer Stelle gepflegt werden und ueberall konsistent
// erscheinen. Rein erklaerend - der Button aendert keine Einstellung.

/// Unaufdringliches "info.circle" neben einem Options-Label. Tippen oeffnet ein kompaktes Sheet
/// mit Titel + Erklaertext + "Verstanden". Sekundaerfarbig, damit es die eigentliche Bedienung
/// nicht ueberlagert.
struct PizzaInfoButton: View {
    let titel: String
    let text: String
    @State private var zeigt = false

    var body: some View {
        Button { zeigt = true } label: {
            Image(systemName: "info.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Erklärung: " + titel)
        .accessibilityIdentifier("pizza-info-" + titel)
        .sheet(isPresented: $zeigt) {
            PizzaErklaerungSheet(titel: titel, text: text)
        }
    }
}

/// Das Erklaer-Sheet selbst: Titel als Ueberschrift, scrollbarer Erklaertext, ein Abschluss-Button.
/// Mittlere Detent, damit es den Kontext dahinter nicht verdeckt; Dark-Mode erbt es von System-Farben.
private struct PizzaErklaerungSheet: View {
    let titel: String
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(20)
            }
            .navigationTitle(titel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Verstanden") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// Modifier fuer die bequeme Platzierung eines Info-Buttons rechts neben einem Control-Label:
/// `Text("Raumtemperatur").pizzaErklaerung(PizzaErklaerung.raumtemperatur)`.
extension View {
    func pizzaErklaerung(_ e: PizzaErklaerung.Eintrag) -> some View {
        HStack(spacing: 6) {
            self
            PizzaInfoButton(titel: e.titel, text: e.text)
        }
    }
}

/// Katalog der Erklaertexte. Ein Eintrag = Titel (Sheet-Ueberschrift) + laienverstaendlicher Text.
///
/// WICHTIG (Projektregel): in diesen String-Literalen KEINE deutschen Anfuehrungszeichen (U+201E /
/// U+201C) verwenden - ein einzelnes offenes Zeichen ohne paariges Schliessen bricht das Literal.
/// Umlaute und Halbgeviertstriche (–) sind erwuenscht und unkritisch.
enum PizzaErklaerung {
    struct Eintrag {
        let titel: String
        let text: String
    }

    static let mehltyp = Eintrag(
        titel: "Mehltyp",
        text: "Bestimmt die Wassermenge (Hydration) und wie lange der Teig gären darf, bevor der "
            + "Kleber nachlässt. Die Hefemenge ändert sich dadurch kaum – alle Weizen-Tipo-00 gären "
            + "ähnlich schnell. Starke Mehle (z. B. La Farina 14) vertragen lange, kalte Gare; "
            + "mildere sind für kürzere Gare gedacht.")

    static let hefetyp = Eintrag(
        titel: "Hefetyp",
        text: "Frisch- oder Trockenhefe. Von Trockenhefe brauchst du nur ein Drittel der "
            + "Frischhefe-Menge und löst sie vorher 5 Minuten im Wasser auf. Der Planer rechnet die "
            + "Menge passend um.")

    static let knetmethode = Eintrag(
        titel: "Knetmethode",
        text: "Die Maschine reibt mehr Wärme in den Teig (ca. +6 °C) als Handkneten (ca. +2 °C). "
            + "Deshalb schlägt der Planer je nach Methode eine andere Wassertemperatur vor, damit "
            + "der Teig am Ende rund 24 °C hat.")

    static let raumtemperatur = Eintrag(
        titel: "Raumtemperatur",
        text: "Der wichtigste Faktor für die Gärgeschwindigkeit. Faustregel: pro +7 °C gärt der Teig "
            + "etwa doppelt so schnell. Wärmer heißt schneller fertig, aber es braucht mehr Hefe und "
            + "es bleibt weniger Zeit für Aroma.")

    static let teiglingsgewicht = Eintrag(
        titel: "Teiglingsgewicht",
        text: "Nur die Größe der einzelnen Pizza – 275 g ergeben etwa 30–32 cm. Ändert die Mengen, "
            + "nicht die Zeiten.")

    static let hydration = Eintrag(
        titel: "Hydration",
        text: "Der Wasseranteil im Verhältnis zum Mehl. Mehr Wasser = luftigerer, offenerer Rand, "
            + "aber ein klebrigerer, schwerer zu formender Teig. Der Standardwert passt zum "
            + "gewählten Mehl.")

    static let nachtruhe = Eintrag(
        titel: "Nachtruhe",
        text: "In diesem Zeitfenster plant der Planer keine Handgriffe – du schläfst. Wenn die Gare "
            + "über die Nacht laufen muss, wandert der Teig stattdessen in den Kühlschrank (kalte Gare).")

    static let kuehlschranktemperatur = Eintrag(
        titel: "Kühlschranktemperatur",
        text: "Steuert die kalte Übernacht-Gare. Kälter = langsamer = mehr Zeit für Aroma bei "
            + "weniger Hefe. 4–5 °C ist die übliche Kühlschrank-Einstellung.")

    static let kWert = Eintrag(
        titel: "K-Wert",
        text: "Die Kalibrier-Konstante des Hefe-Modells. Sie bestimmt, wie viel Hefe der Planer für "
            + "eine gegebene Zeit und Temperatur ansetzt. HÖHER = mehr Hefe (schneller, sicherer, "
            + "aber weniger Aroma-Zeit), NIEDRIGER = weniger Hefe (langsamer, aromatischer, aber "
            + "Risiko, dass der Teig nicht genug aufgeht). Der Standard 4,5 ist auf bewährte Rezepte "
            + "geeicht – ändere ihn nur, wenn dein Teig regelmäßig zu stark (dann K senken) oder zu "
            + "wenig (dann K erhöhen) aufgeht.")

    static let wassertemperatur = Eintrag(
        titel: "Wassertemperatur",
        text: "Kein Eingabewert, sondern berechnet: die Temperatur, die das Wasser haben sollte, "
            + "damit der fertige Teig nach dem Kneten rund 24 °C hat.")
}
