import SwiftUI

// Keller-Sicht: was steht wirklich im Haus. Bewusst KEINE zweite Katalogliste (das ist
// `WeinListView`), sondern eine Bestandsansicht — nach Lagerort gruppiert, Flaschen direkt in der
// Zeile hoch- und runterzaehlbar, damit das Nachtragen nach dem Oeffnen einer Flasche zwei
// Sekunden dauert und nicht den Umweg ueber die Detailseite braucht.
//
// Darueber die Summenzeile und zwei Hinweisabschnitte, die den Bestand zum Sprechen bringen:
//   "Jetzt trinkreif"  — trinkfenster_bis endet in den naechsten 2 Jahren (oder ist schon vorbei),
//   "Letzte Flasche"   — bestand == 1, also beim naechsten Einkauf mitdenken.
//
// Die Zeile ist absichtlich KEIN NavigationLink: ein Link mit zwei Knoepfen darin ist in einer
// `List` unzuverlaessig, und hier zaehlt das Zaehlen. Der Weg ins Detail bleibt der Alle-Tab.

/// Eine Lagerort-Gruppe. `id` ist der Lagerort — je Gruppe eindeutig.
private struct WeinKellerGruppe: Identifiable {
    var id: String { lagerort }
    let lagerort: String
    let weine: [Wein]
    var flaschen: Int { weine.reduce(0) { $0 + $1.bestand } }
}

struct WeinKellerView: View {
    @EnvironmentObject private var store: WeinStore

    /// Ohne Lagerort erfasste Flaschen landen gesammelt am Ende.
    private static let ohneLagerort = "Ohne Lagerort"

    private var imKeller: [Wein] { store.weine.filter { $0.bestand > 0 } }

    private var gruppen: [WeinKellerGruppe] {
        let gruppiert = Dictionary(grouping: imKeller) { w -> String in
            let l = (w.lagerort ?? "").trimmingCharacters(in: .whitespaces)
            return l.isEmpty ? Self.ohneLagerort : l
        }
        return gruppiert
            .map { WeinKellerGruppe(lagerort: $0.key, weine: $0.value.sorted { $0.titel < $1.titel }) }
            .sorted { a, b in
                // Der Sammel-Eimer steht immer hinten, sonst alphabetisch.
                if a.lagerort == Self.ohneLagerort { return false }
                if b.lagerort == Self.ohneLagerort { return true }
                return a.lagerort.localizedCaseInsensitiveCompare(b.lagerort) == .orderedAscending
            }
    }

    private var flaschenGesamt: Int { imKeller.reduce(0) { $0 + $1.bestand } }

    /// Geschaetzter Kellerwert ueber den Referenzpreis. Weine ohne Referenzpreis fehlen darin —
    /// deshalb steht die Einschraenkung als Fusszeile unter der Summe.
    private var wertGesamt: Double {
        imKeller.reduce(0) { summe, w in summe + (w.referenzpreis ?? 0) * Double(w.bestand) }
    }
    private var ohnePreis: Int { imKeller.filter { $0.referenzpreis == nil }.count }

    /// Trinkfenster endet in den naechsten 2 Jahren (oder ist bereits abgelaufen).
    private var trinkreif: [Wein] {
        let jahr = Calendar.current.component(.year, from: Date())
        return imKeller
            .filter { w in
                guard let bis = w.trinkfensterBis else { return false }
                return bis <= jahr + 2
            }
            .sorted { ($0.trinkfensterBis ?? 0) < ($1.trinkfensterBis ?? 0) }
    }

    private var letzteFlasche: [Wein] {
        imKeller.filter { $0.bestand == 1 }.sorted { $0.titel < $1.titel }
    }

    var body: some View {
        Group {
            if imKeller.isEmpty {
                // `List` rendert Leerzustaende schlecht → eigener scrollbarer Zweig (Pull-to-Refresh bleibt).
                ScrollView {
                    AreaEmptyState(emoji: "🍷",
                                   title: "Keller ist leer",
                                   hint: "Trage bei einem Wein den Bestand ein, dann taucht er hier auf.")
                        .frame(maxWidth: .infinity).frame(minHeight: 300)
                        .accessibilityIdentifier("wein-keller-empty")
                }
                .refreshable { await store.reload() }
            } else {
                liste
            }
        }
    }

    private var liste: some View {
        List {
            Section { summe }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            if !trinkreif.isEmpty {
                Section {
                    ForEach(trinkreif) { zeile($0, hinweis: trinkfensterHinweis($0), praefix: "wein-keller-reif") }
                } header: {
                    kopf("⏳ Jetzt trinkreif", trinkreif.count)
                        .accessibilityIdentifier("wein-keller-trinkreif")
                } footer: {
                    Text("Das Trinkfenster endet in den nächsten zwei Jahren.")
                }
                .textCase(nil)
            }

            if !letzteFlasche.isEmpty {
                Section {
                    ForEach(letzteFlasche) { zeile($0, hinweis: "Letzte Flasche", praefix: "wein-keller-rest") }
                } header: {
                    kopf("🔔 Letzte Flasche", letzteFlasche.count)
                        .accessibilityIdentifier("wein-keller-letzte")
                } footer: {
                    Text("Beim nächsten Einkauf mitdenken.")
                }
                .textCase(nil)
            }

            ForEach(gruppen) { g in
                Section {
                    ForEach(g.weine) { zeile($0, hinweis: nil) }
                } header: {
                    kopf("📦 " + g.lagerort, g.flaschen, einheit: "Flaschen")
                }
                .textCase(nil)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await store.reload() }
        // KEIN Container-Identifier auf der List: er wuerde auf saemtliche Zeilen, Kopfzeilen und
        // Zaehl-Knoepfe durchschlagen. Anker sind die Kopfzeilen und die Zeilen-Titel.
    }

    // MARK: - Summenzeile

    private var summe: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                AreaStatTile(value: String(flaschenGesamt), label: "Flaschen", color: Color(hex: "7C3AED"))
                AreaStatTile(value: String(imKeller.count), label: "Weine", color: Color(hex: "DB2777"))
                // Ohne Nachkommastellen — die Kachel ist schmal. `WeinText.zahl` haelt den
                // Tausenderpunkt aus dem Text heraus.
                AreaStatTile(value: WeinText.zahl(wertGesamt, stellen: 0) + " €",
                             label: "Wert (ca.)", color: Color(hex: "EA580C"))
            }
            if ohnePreis > 0 {
                Text("Für " + String(ohnePreis) + (ohnePreis == 1 ? " Wein" : " Weine")
                     + " ist kein Referenzpreis hinterlegt — der fehlt im Wert.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .accessibilityIdentifier("wein-keller-summe")
    }

    private func kopf(_ titel: String, _ anzahl: Int, einheit: String? = nil) -> some View {
        let zusatz = einheit.map { " (" + String(anzahl) + " " + $0 + ")" } ?? (" (" + String(anzahl) + ")")
        return Text(titel + zusatz)
            .font(.caption.weight(.bold)).textCase(.uppercase).foregroundStyle(.secondary)
    }

    // MARK: - Zeile mit Flaschen-Zaehler

    /// `praefix` haelt die Kennungen eindeutig: derselbe Wein steht oft in mehreren Abschnitten
    /// (trinkreif UND letzte Flasche UND seinem Lagerort), und eine reine Wein-ID gaebe es dann
    /// mehrfach — `app.buttons["wein-keller-minus-5"]` waere im XCUITest mehrdeutig. Die
    /// Lagerort-Gruppe behaelt per Vorgabewert die kanonische Kennung.
    private func zeile(_ w: Wein, hinweis: String?, praefix: String = "wein-keller") -> some View {
        HStack(spacing: 12) {
            Text(w.typ.emoji).font(.title3).frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                // Die Zeilen-Kennung sitzt am Titel, NICHT am HStack: ein Container-Identifier
                // propagiert in SwiftUI auf alle Kind-Elemente und ueberschreibt deren eigene IDs
                // (siehe AlarmoTile) — die Zaehl-Knoepfe hiessen dann alle "wein-keller-zeile-N".
                Text(w.titel).font(.subheadline.weight(.semibold)).lineLimit(2)
                    .accessibilityIdentifier(praefix + "-zeile-" + String(w.id))
                HStack(spacing: 6) {
                    Pill(text: w.typ.label, color: w.typ.farbe)
                    if let h = hinweis {
                        Pill(text: h, systemImage: "clock", color: Color(hex: "EA580C"), filled: false)
                    }
                    if let p = w.referenzpreis {
                        Text(WeinText.eur(p)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 8)

            zaehler(w, praefix: praefix)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 14))
    }

    /// Flaschen +/- direkt in der Zeile. `.borderless` ist Pflicht: sonst wuerde die `List` die
    /// ganze Zeile als EINEN Knopf behandeln und beide Symbole loesten dasselbe aus.
    private func zaehler(_ w: Wein, praefix: String) -> some View {
        HStack(spacing: 10) {
            Button {
                Task { await store.setBestand(w, max(0, w.bestand - 1)) }
            } label: {
                Image(systemName: "minus.circle.fill").font(.title3)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color(hex: "DC2626"))
            .accessibilityLabel("Eine Flasche weniger")
            .accessibilityIdentifier(praefix + "-minus-" + String(w.id))

            Text(String(w.bestand))
                .font(.headline.monospacedDigit())
                .frame(minWidth: 26)
                .accessibilityIdentifier(praefix + "-bestand-" + String(w.id))

            Button {
                Task { await store.setBestand(w, w.bestand + 1) }
            } label: {
                Image(systemName: "plus.circle.fill").font(.title3)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color(hex: "16A34A"))
            .accessibilityLabel("Eine Flasche mehr")
            .accessibilityIdentifier(praefix + "-plus-" + String(w.id))
        }
    }

    /// Klartext zum Trinkfenster — je nachdem, ob es laeuft, dieses Jahr endet oder vorbei ist.
    private func trinkfensterHinweis(_ w: Wein) -> String {
        guard let bis = w.trinkfensterBis else { return "Trinkreif" }
        let jahr = Calendar.current.component(.year, from: Date())
        if bis < jahr { return "seit " + String(bis) + " über dem Fenster" }
        if bis == jahr { return "nur noch " + String(bis) }
        return "bis " + String(bis)
    }
}
