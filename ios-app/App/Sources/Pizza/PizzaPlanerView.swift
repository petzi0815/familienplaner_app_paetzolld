import SwiftUI

/// Hauptbildschirm des Pizza-Planers: oben rein, wann gegessen wird - direkt darunter die
/// Variantenwahl (schnell/warm oder ueber Nacht/kalt) und der Plan.
///
/// Die View rechnet NICHT selbst und ruft auch `rechne()` nicht auf: jede Eingabe bindet direkt
/// an `store.config` bzw. `store.essenszeit`, deren `didSet` den Rechenkern anwirft. Hier wird
/// ausschliesslich `store.planung`/`store.aktiverPlan` angezeigt - eine zweite Rechenschleife
/// gaebe es nur die Chance, mit der ersten auseinanderzulaufen.
struct PizzaPlanerView: View {
    @EnvironmentObject var store: PizzaStore

    /// Sheet zur Mehlauswahl (zeigt alle Sorten mit Charakter + Protein/W-Wert).
    @State private var zeigtMehlAuswahl = false

    private var tint: Color { Palette.colors(for: "pizza").first ?? Theme.accent }

    /// Textfarbe auf dem Bereichsverlauf. Weiss auf einem hellen Verlauf (Amber/Lime) waere
    /// unlesbar - deshalb entscheidet die Luminanz der Verlaufsfarben, nicht der Geschmack.
    private var onGradient: Color {
        let farben = Palette.colors(for: "pizza")
        let helle = farben.filter(\.isLightFill).count
        return helle * 2 > farben.count ? Color.black.opacity(0.85) : .white
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                essenszeitKarte
                variantenBereich
                if let p = store.aktiverPlan {
                    startKarte(p)
                    PizzaZutatenKarte(plan: p, tint: tint)
                    PizzaZeitplanKarte(plan: p, tint: tint)
                    hinweiseKarte(p)
                } else if let frueh = store.planung?.fruehestesMoeglichesEssen {
                    kurzfristigKarte(frueh)
                }
                eingabenKarte
                erweitertKarte
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
    }

    // MARK: - 1. Essenszeit

    private var essenszeitKarte: some View {
        PizzaAbschnitt(titel: "Essenszeit", icon: "fork.knife", tint: tint) {
            VStack(alignment: .leading, spacing: 6) {
                DatePicker("Wann willst du essen?", selection: $store.essenszeit,
                           displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact)
                    .font(.headline)
                    .accessibilityIdentifier("pizza-essenszeit")
                Text("Alles andere rechnet der Planer von hier rückwärts.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 2. Variantenwahl (direkt unter der Essenszeit)

    /// Sind beide Varianten moeglich, waehlt der Nutzer; ist nur eine moeglich, erklaert ein
    /// dezenter Hinweis, welche das ist und warum die andere fuer diese Uhrzeit ausfaellt.
    @ViewBuilder private var variantenBereich: some View {
        if let p = store.planung {
            if p.warm != nil && p.kalt != nil {
                variantenUmschalter
            } else if p.warm != nil {
                variantenHinweis("Für diese Uhrzeit passt nur der Schnell-Plan am selben Tag – eine Übernacht-Gare würde nicht mehr rechtzeitig an einem Abend beginnen.",
                                 icon: "hare.fill")
            } else if p.kalt != nil {
                variantenHinweis("Für diese Uhrzeit ist nur die Übernacht-Gare im Kühlschrank möglich – ein Schnell-Plan am selben Tag ginge sich nicht ohne nächtliche Handgriffe aus.",
                                 icon: "snowflake")
            }
        }
    }

    /// Umschalter zwischen beiden Varianten. Jede Pille traegt ihre eigene ID
    /// (`pizza-variante-warm` / `pizza-variante-kalt`) — der Container bleibt bewusst ID-los,
    /// damit die Kinder fuer XCUITest einzeln auffindbar bleiben.
    private var variantenUmschalter: some View {
        PizzaAbschnitt(titel: "Variante", icon: "arrow.triangle.branch", tint: tint) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ForEach(PizzaVariante.allCases, id: \.self) { v in
                        FilterPill(label: v.label, systemImage: v == .kalt ? "snowflake" : "hare.fill",
                                   selected: store.variante == v, color: tint) {
                            store.waehleVariante(v)
                        }
                        .accessibilityIdentifier("pizza-variante-\(v.rawValue)")
                    }
                    Spacer(minLength: 0)
                }
                Text(store.variante.kurzErklaerung)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func variantenHinweis(_ text: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint).padding(.top, 1)
            Text(text).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .accessibilityIdentifier("pizza-variante-hinweis")
    }

    // MARK: - 3. Startzeit (die Antwort auf die eigentliche Frage)

    /// Deshalb die groesste Zahl auf dem Schirm. Bei der kalten Variante steht direkt darunter
    /// prominent die Kuehlschrank-Info (wann rein, wann raus, wie lange, bei welcher Temperatur).
    private func startKarte(_ p: PizzaPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Teig ansetzen um").font(.subheadline.weight(.semibold)).opacity(0.9)
                Text(PizzaCalculator.uhrzeit(p.startzeit))
                    .font(.system(size: 56, weight: .heavy, design: .rounded))
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .accessibilityIdentifier("pizza-startzeit")
                    .accessibilityLabel("Teig ansetzen um " + PizzaCalculator.uhrzeit(p.startzeit))
                if let tag = anderesDatum(p.startzeit) {
                    Text(tag).font(.caption.weight(.bold)).opacity(0.9)
                }
            }
            if let info = kuehlschrankText(p) {
                Label(info, systemImage: "refrigerator.fill")
                    .font(.subheadline.weight(.semibold)).opacity(0.95)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("pizza-kuehlschrank")
            }
            HStack(alignment: .top, spacing: 10) {
                PizzaHeroWert(titel: "Gesamtdauer", wert: PizzaCalculator.dauer(p.gesamtdauerMinuten))
                PizzaHeroWert(titel: p.variante == .kalt ? "Reife" : "Gare (netto)",
                              wert: PizzaCalculator.dauer(p.nettoMinuten))
                PizzaHeroWert(titel: "Essen", wert: PizzaCalculator.uhrzeit(p.essenszeit))
            }
            if let grund = verschobenText(p) {
                Label(grund, systemImage: "moon.stars.fill")
                    .font(.caption).opacity(0.95)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(onGradient)
        .background(Palette.gradient(for: "pizza"), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: tint.opacity(0.35), radius: 12, y: 6)
    }

    /// Kühlschrank-Zeile fuer die kalte Variante: "Kühlschrank: heute 23:00 → morgen 09:50,
    /// ~11 h bei 5 °C". Nil bei der warmen Variante.
    private func kuehlschrankText(_ p: PizzaPlan) -> String? {
        guard p.variante == .kalt,
              let rein = p.schritte.first(where: { $0.art == .kuehlschrank }),
              let raus = p.schritte.first(where: { $0.art == .anwaermen }) else { return nil }
        let von = PizzaCalculator.datumUndUhrzeit(rein.zeit)
        let bis = PizzaCalculator.datumUndUhrzeit(raus.zeit)
        return "Kühlschrank: \(von) → \(bis), \(PizzaCalculator.dauer(p.fridgeMinuten)) bei "
            + "\(PizzaCalculator.grad(p.config.fridgeTempC)) °C"
    }

    // MARK: - Kurzfristig (< 4,5 h Vorlauf — der einzige physische Grenzfall)

    /// Kein Fehler, keine Absage: der Teig braucht Vorlauf. Ein Knopf legt die Essenszeit auf den
    /// fruehestmoeglichen Zeitpunkt, ab dem wieder mindestens eine Variante existiert.
    private func kurzfristigKarte(_ frueh: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("So kurzfristig wird der Teig nicht reif", systemImage: "clock.badge.exclamationmark")
                .font(.headline).foregroundStyle(tint)
                .accessibilityIdentifier("pizza-kurzfristig")
            Text("Ein Pizzateig braucht etwas Vorlauf. Frühestens \(PizzaCalculator.datumUndUhrzeit(frueh)) Uhr ist er soweit.")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Button { store.essenszeit = frueh } label: {
                Label("Frühestmögliche Zeit übernehmen", systemImage: "clock.arrow.circlepath")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .background(tint, in: Capsule())
                    .foregroundStyle(tint.onFill)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("pizza-kurzfristig-button")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(tint.opacity(0.4)))
    }

    /// Nur zeigen, wenn der Start nicht heute ist - sonst ist das Datum bloss Rauschen.
    private func anderesDatum(_ d: Date) -> String? {
        Calendar.current.isDateInToday(d) ? nil : PizzaCalculator.datumUndUhrzeit(d)
    }

    /// Das WARUM zur Abweichung vom 6-h-Standard. Der Hinweis wird hier gezeigt und darum
    /// unten in der Hinweis-Karte ausgeblendet.
    /// Gesucht wird der FALL, nicht ein nachgebauter Wert: der Grund der Verschiebung steckt
    /// im Hinweis und ist hier nicht bekannt - ein Gleichheitsvergleich ginge daran vorbei.
    private func verschobenText(_ p: PizzaPlan) -> String? {
        for h in p.hinweise {
            if case .planVerschoben = h { return h.text }
        }
        return nil
    }

    // MARK: - 5. Hinweise

    @ViewBuilder private func hinweiseKarte(_ p: PizzaPlan) -> some View {
        // Beide Hinweise stehen bereits dort, wo sie hingehoeren (Startzeit-Karte bzw. Zutaten).
        let rest = p.hinweise.filter { h in
            switch h {
            case .planVerschoben, .wasserTempGeclampt: return false
            default: return true
            }
        }
        if !rest.isEmpty || p.config.mehltyp.knetHinweis != nil {
            PizzaAbschnitt(titel: "Hinweise", icon: "lightbulb.fill", tint: tint) {
                VStack(spacing: 8) {
                    ForEach(rest) { h in
                        NoteBlock(icon: h.istFehler ? "⚠️" : "💡", text: h.text,
                                  tint: h.istFehler ? .red : .yellow)
                    }
                    if let k = p.config.mehltyp.knetHinweis {
                        NoteBlock(icon: "🌾", text: k, tint: .brown)
                    }
                }
            }
        }
    }

    // MARK: - 6. Eingaben

    private var eingabenKarte: some View {
        PizzaAbschnitt(titel: "Eingaben", icon: "slider.horizontal.3", tint: tint, identifier: "pizza-eingaben") {
            VStack(alignment: .leading, spacing: 16) {
                Stepper(value: $store.config.anzahlPizzen,
                        in: PizzaKonstanten.anzahlMin...PizzaKonstanten.anzahlMax) {
                    reihe("Anzahl Pizzen", String(store.config.anzahlPizzen))
                }
                .accessibilityIdentifier("pizza-anzahl")

                VStack(alignment: .leading, spacing: 4) {
                    reihe("Teiglingsgewicht", PizzaCalculator.gramm(store.config.teiglingsgewichtG) + " g",
                          info: PizzaErklaerung.teiglingsgewicht)
                    Slider(value: $store.config.teiglingsgewichtG,
                           in: PizzaKonstanten.gewichtMin...PizzaKonstanten.gewichtMax, step: 5)
                        .tint(tint)
                        .accessibilityIdentifier("pizza-gewicht")
                    Text("275 g ≈ 30–32 cm Durchmesser").font(.caption).foregroundStyle(.secondary)
                }

                mehlBlock
                wahl("Hefe", Hefetyp.allCases, label: { $0.label }, aktiv: store.config.hefetyp,
                     info: PizzaErklaerung.hefetyp) {
                    store.config.hefetyp = $0
                }
                wahl("Kneten", Knetmethode.allCases, label: { $0.label }, aktiv: store.config.knetmethode,
                     info: PizzaErklaerung.knetmethode) {
                    store.config.knetmethode = $0
                }

                VStack(alignment: .leading, spacing: 4) {
                    reihe("Raumtemperatur", PizzaCalculator.grad(store.config.raumtempC) + " °C",
                          info: PizzaErklaerung.raumtemperatur)
                    Slider(value: $store.config.raumtempC,
                           in: PizzaKonstanten.raumtempMin...PizzaKonstanten.raumtempMax, step: 0.5)
                        .tint(tint)
                        .accessibilityIdentifier("pizza-raumtemp")
                    Text("Wärmer heißt weniger Hefe und kürzere Gare, kälter das Gegenteil.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                nachtruheBlock
            }
        }
    }

    /// Mehlauswahl: kompakte Zeile (Label + Protein/W + Info) über einer antippbaren Auswahl-Fläche,
    /// die das Sortiment-Sheet öffnet; darunter der Charakter-Satz der aktuell gewählten Sorte.
    private var mehlBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Mehl").font(.subheadline)
                PizzaInfoButton(titel: PizzaErklaerung.mehltyp.titel, text: PizzaErklaerung.mehltyp.text)
                Spacer(minLength: 8)
                Text(store.config.mehltyp.proteinInfo)
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            Button { zeigtMehlAuswahl = true } label: {
                HStack(spacing: 8) {
                    Text(store.config.mehltyp.label).font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .accessibilityIdentifier("pizza-mehl")
            Text(store.config.mehltyp.charakter)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .sheet(isPresented: $zeigtMehlAuswahl) {
            MehlAuswahlSheet(auswahl: $store.config.mehltyp)
        }
    }

    private var nachtruheBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nachtruhe").font(.subheadline.weight(.semibold))
                .pizzaErklaerung(PizzaErklaerung.nachtruhe)
            HStack(spacing: 8) {
                Text("von").font(.subheadline).foregroundStyle(.secondary)
                DatePicker("Nachtruhe Beginn", selection: schlafBinding(\.schlafVon),
                           displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .accessibilityIdentifier("pizza-schlaf-von")
                Text("bis").font(.subheadline).foregroundStyle(.secondary)
                DatePicker("Nachtruhe Ende", selection: schlafBinding(\.schlafBis),
                           displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .accessibilityIdentifier("pizza-schlaf-bis")
                Spacer(minLength: 0)
            }
            Text("In dieser Zeit plant der Planer keinen Handgriff ein – nachts wird nichts erledigt. Die Gare läuft trotzdem weiter: bei Bedarf über Nacht im Kühlschrank. Nur Kneten, Portionieren, Ofen und Backen bleiben in der Wachzeit.")
                .font(.caption).foregroundStyle(.secondary)
            if !store.config.nachtruheAktiv {
                Text("Beide Zeiten gleich = keine Nachtruhe. Handgriffe dürfen dann zu jeder Uhrzeit liegen.")
                    .font(.caption.weight(.semibold)).foregroundStyle(.orange)
            }
        }
    }

    // MARK: - 7. Erweitert

    private var erweitertKarte: some View {
        DisclosureGroup(isExpanded: $store.showAdvanced) {
            VStack(alignment: .leading, spacing: 16) {
                mehltempBlock
                hydrationBlock
                fridgeTempBlock
                kFaktorBlock
            }
            .padding(.top, 12)
        } label: {
            Label("Erweitert", systemImage: "gearshape.2.fill")
                .font(.footnote.weight(.bold)).textCase(.uppercase)
                .foregroundStyle(tint)
        }
        .tint(tint)
        .accessibilityIdentifier("pizza-erweitert")
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var mehltempBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(get: { store.config.mehltempOverride != nil },
                                 set: { store.config.mehltempOverride = $0 ? store.config.raumtempC : nil })) {
                Text("Mehltemperatur weicht ab").font(.subheadline)
            }
            .tint(tint)
            if store.config.mehltempOverride != nil {
                reihe("Mehltemperatur", PizzaCalculator.grad(store.config.mehltempC) + " °C")
                Slider(value: Binding(get: { store.config.mehltempC },
                                      set: { store.config.mehltempOverride = $0 }),
                       in: PizzaKonstanten.mehltempMin...PizzaKonstanten.mehltempMax, step: 0.5)
                    .tint(tint)
            }
            Text("Ohne Abweichung rechnet der Planer mit Mehl auf Raumtemperatur. Kaltes Mehl hebt die nötige Wassertemperatur an.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var hydrationBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Hydration").font(.subheadline)
                PizzaInfoButton(titel: PizzaErklaerung.hydration.titel, text: PizzaErklaerung.hydration.text)
                Spacer(minLength: 8)
                if store.config.hydrationOverride != nil {
                    Button("Standard") { store.config.hydrationOverride = nil }
                        .font(.caption.weight(.semibold)).buttonStyle(.borderless)
                }
                Text(PizzaCalculator.prozent(store.config.hydration * 100) + " %")
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
            }
            Slider(value: Binding(get: { store.config.hydration },
                                  set: { store.config.hydrationOverride = $0 }),
                   in: PizzaKonstanten.hydrationMin...PizzaKonstanten.hydrationMax, step: 0.005)
                .tint(tint)
                .accessibilityIdentifier("pizza-hydration")
            Text("Standard für " + store.config.mehltyp.label + ": "
                 + PizzaCalculator.prozent(store.config.mehltyp.hydrationDefault * 100)
                 + " %. Mehr Wasser heißt luftiger, aber klebriger.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var fridgeTempBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            reihe("Kühlschranktemperatur", PizzaCalculator.grad(store.config.fridgeTempC) + " °C",
                  info: PizzaErklaerung.kuehlschranktemperatur)
            // Praxisbereich 4–7 °C (die weiteren [2,10] aus `normalisiert()` sind nur die Clamp-Grenzen).
            Slider(value: $store.config.fridgeTempC, in: 4...7, step: 0.5)
                .tint(tint)
                .accessibilityIdentifier("pizza-fridge-temp")
            Text("Nur für die Übernacht-Gare: kälter heißt langsamere Reife und noch weniger Hefe, wärmer das Gegenteil. Übliche Kühlschränke stehen auf 4–5 °C.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var kFaktorBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("K-Wert").font(.subheadline)
                PizzaInfoButton(titel: PizzaErklaerung.kWert.titel, text: PizzaErklaerung.kWert.text)
                Spacer(minLength: 8)
                if abs(store.config.kFaktor - PizzaKonstanten.kDefault) > 0.001 {
                    Button("Standard") { store.config.kFaktor = PizzaKonstanten.kDefault }
                        .font(.caption.weight(.semibold)).buttonStyle(.borderless)
                }
                // grad() ist der gemeinsame 0-1-Nachkommastellen-Formatter (de_DE) - hier fuer
                // den K-Faktor statt fuer eine Temperatur. Selbst zu interpolieren waere die
                // Tausenderpunkt-Falle, deshalb bleibt die Formatierung im Rechenkern.
                Text(PizzaCalculator.grad(store.config.kFaktor))
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
            }
            Slider(value: $store.config.kFaktor, in: 3.0...6.0, step: 0.1)
                .tint(tint)
                .accessibilityIdentifier("pizza-kfaktor")
            Text("Kalibrierung des Hefemodells. Wird der Teig regelmäßig zu hefig, K verkleinern – bleibt er träge, K vergrößern.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Kleinteile

    private func reihe(_ titel: String, _ wert: String,
                       info: PizzaErklaerung.Eintrag? = nil) -> some View {
        HStack {
            Text(titel).font(.subheadline)
            if let info { PizzaInfoButton(titel: info.titel, text: info.text) }
            Spacer(minLength: 8)
            Text(wert).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
    }

    private func wahl<T: Hashable>(_ titel: String, _ werte: [T], label: @escaping (T) -> String,
                                   aktiv: T, info: PizzaErklaerung.Eintrag? = nil,
                                   waehle: @escaping (T) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(titel).font(.subheadline)
                if let info { PizzaInfoButton(titel: info.titel, text: info.text) }
            }
            HStack(spacing: 8) {
                ForEach(werte, id: \.self) { w in
                    FilterPill(label: label(w), selected: w == aktiv, color: tint) { waehle(w) }
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// Bindet eine Nachtruhe-Spalte (Minuten seit Mitternacht) an einen DatePicker.
    /// Der Kalendertag ist egal - gelesen und geschrieben werden nur Stunde und Minute.
    private func schlafBinding(_ pfad: WritableKeyPath<PizzaConfig, Int>) -> Binding<Date> {
        Binding(get: { PizzaPlanerView.tagesZeit(store.config[keyPath: pfad]) },
                set: { store.config[keyPath: pfad] = PizzaPlanerView.tagesMinute($0) })
    }

    /// Minute des Tages -> Date von heute. Bewusst ueber DateComponents und nicht ueber
    /// startOfDay + Minuten: an Zeitumstellungstagen hat ein Tag keine 1440 Minuten.
    private static func tagesZeit(_ minute: Int) -> Date {
        let cal = Calendar.current
        let m = PizzaConfig.normalisierteTagesminute(minute)
        var c = cal.dateComponents([.year, .month, .day], from: Date())
        c.hour = m / 60
        c.minute = m % 60
        return cal.date(from: c) ?? Date()
    }

    private static func tagesMinute(_ d: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}

// MARK: - Mehlauswahl-Sheet

/// Zeigt alle Mehlsorten (Reihenfolge = CaseIterable) mit Label, Protein/W-Wert und einem
/// Charakter-Satz zur Auswahl. Antippen setzt die Sorte und schließt das Sheet.
private struct MehlAuswahlSheet: View {
    @Binding var auswahl: Mehltyp
    @Environment(\.dismiss) private var dismiss

    private var tint: Color { Palette.colors(for: "pizza").first ?? Theme.accent }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Mehltyp.allCases, id: \.self) { m in
                        Button {
                            auswahl = m
                            dismiss()
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 8) {
                                        Text(m.label).font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Text(m.proteinInfo).font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(m.charakter).font(.caption).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                                if m == auswahl {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(tint)
                                }
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 3)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("pizza-mehl-option-" + m.rawValue)
                    }
                } footer: {
                    Text("Alle Weizen-Tipo-00 gären ähnlich schnell (gleiche Hefemenge) – sie "
                         + "unterscheiden sich in Wasseraufnahme und wie lange der Teig gut bleibt.")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Mehl wählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - 3. Zutaten

private struct PizzaZutatenKarte: View {
    let plan: PizzaPlan
    let tint: Color

    private var z: PizzaZutaten { plan.zutaten }

    /// Was in den Teig geht - in der Reihenfolge, in der es in die Schuessel wandert.
    private var teig: some View {
        VStack(alignment: .leading, spacing: 0) {
            InfoRow(icon: "🌾", label: "Mehl (" + plan.config.mehltyp.label + ")",
                    value: PizzaCalculator.gramm(z.mehlG) + " g")
            InfoRow(icon: "💧", label: "Wasser", value: PizzaCalculator.gramm(z.wasserMl) + " ml")
            // Die Wassertemperatur ist ein Ausgabewert des Modells, kein Beiwerk: nur mit ihr
            // landet der fertige Teig auf der Zielteigtemperatur von 24 °C.
            HStack(spacing: 8) {
                InfoRow(icon: "🌡️", label: "Wassertemperatur",
                        value: PizzaCalculator.grad(z.wasserTempC) + " °C", valueColor: tint)
                PizzaInfoButton(titel: PizzaErklaerung.wassertemperatur.titel,
                                text: PizzaErklaerung.wassertemperatur.text)
            }
            InfoRow(icon: "🧂", label: "Salz", value: PizzaCalculator.gramm(z.salzG) + " g")
            InfoRow(icon: "🫧", label: plan.config.hefetyp.label,
                    value: PizzaCalculator.hefeGramm(z.hefeG) + " g")
            Text("Hefe entspricht " + PizzaCalculator.prozent(z.hefePct) + " % Frischhefe vom Mehl.")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }

    private var semola: some View {
        VStack(alignment: .leading, spacing: 0) {
            InfoRow(icon: "✨", label: "Semola zum Ausbreiten",
                    value: PizzaCalculator.gramm(z.semolaG) + " g")
            Text("Semola gehört nicht in den Teig – nur zum Ausbreiten und Einschießen.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    var body: some View {
        PizzaAbschnitt(titel: "Zutaten", icon: "scalemass.fill", tint: tint, identifier: "pizza-zutaten") {
            VStack(alignment: .leading, spacing: 0) {
                teig
                Divider().padding(.vertical, 8)
                semola
                if z.wasserTempGeclampt {
                    NoteBlock(icon: "⚠️", text: PizzaHinweis.wasserTempGeclampt(z.wasserTempC).text, tint: .red)
                        .padding(.top, 10)
                }
            }
        }
    }
}

// MARK: - 4. Zeitplan

private struct PizzaZeitplanKarte: View {
    @EnvironmentObject var store: PizzaStore
    let plan: PizzaPlan
    let tint: Color

    var body: some View {
        PizzaAbschnitt(titel: "Zeitplan", icon: "list.bullet.clipboard.fill", tint: tint, identifier: "pizza-zeitplan") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(plan.schritte.enumerated()), id: \.element.id) { i, s in
                    if tageswechsel(vor: i) {
                        // Echter Datums-Header (Wochentag + Datum) statt eines generischen
                        // Mitternachts-Trenners: bei der kalten Variante kann die Kuehlschrankgare
                        // ueber MEHRERE Tage laufen, dann ist "23:00 -> 15:50" ohne Tag missverstaendlich.
                        Label(PizzaCalculator.wochentagDatum(s.zeit), systemImage: "moon.stars.fill")
                            .font(.caption2.weight(.bold)).foregroundStyle(.indigo)
                            .padding(.top, 8).padding(.bottom, 4)
                    }
                    PizzaSchrittZeile(schritt: s, tint: tint, ueberNacht: ueberNacht(ab: i))
                }
            }
            erinnerungen.padding(.top, 10)
        }
    }

    private var erinnerungen: some View {
        HStack(spacing: 10) {
            Button { Task { await store.planeErinnerungen() } } label: {
                Label("Erinnerungen setzen", systemImage: "bell.badge.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(tint, in: Capsule())
                    .foregroundStyle(tint.onFill)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("pizza-erinnerungen")

            Button { Task { await store.loescheErinnerungen() } } label: {
                Image(systemName: "bell.slash.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.vertical, 10).padding(.horizontal, 16)
                    .background(Color(.secondarySystemBackground), in: Capsule())
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("pizza-erinnerungen-weg")
            .accessibilityLabel("Erinnerungen entfernen")
        }
    }

    private func tageswechsel(vor i: Int) -> Bool {
        guard i > 0 else { return false }
        return !Calendar.current.isDate(plan.schritte[i - 1].zeit, inSameDayAs: plan.schritte[i].zeit)
    }

    /// Nur passive Bloecke koennen in die Nacht laufen - Handgriffe haelt der Solver in der
    /// Wachzeit. Der Block reicht bis zum naechsten Schritt.
    private func ueberNacht(ab i: Int) -> Bool {
        let s = plan.schritte[i]
        guard !s.istAktion, i + 1 < plan.schritte.count else { return false }
        return laeuftUeberNacht(von: s.zeit, bis: plan.schritte[i + 1].zeit)
    }

    private func laeuftUeberNacht(von a: Date, bis b: Date) -> Bool {
        let c = plan.config
        let cal = Calendar.current
        guard c.nachtruheAktiv, b > a else { return false }
        if PizzaCalculator.istSchlafend(a, config: c, calendar: cal) { return true }
        if PizzaCalculator.istSchlafend(b, config: c, calendar: cal) { return true }
        // Der Block kann die Nachtruhe auch komplett umschliessen: dann schlaeft keiner der
        // beiden Endpunkte, aber ein Nachtruhe-Beginn liegt dazwischen.
        let tagesbeginn = cal.startOfDay(for: a)
        for tag in 0...2 {
            let versatz = tag * PizzaKonstanten.minutenProTag + c.schlafVon
            guard let start = cal.date(byAdding: .minute, value: versatz, to: tagesbeginn) else { continue }
            if start > a && start < b { return true }
        }
        return false
    }
}

private struct PizzaSchrittZeile: View {
    let schritt: PizzaSchritt
    let tint: Color
    let ueberNacht: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(PizzaCalculator.uhrzeit(schritt.zeit))
                .font(.subheadline.weight(.bold)).monospacedDigit()
                .frame(width: 46, alignment: .leading)
                .padding(.top, 5)
            Image(systemName: schritt.icon)
                .font(.system(size: 13, weight: .bold))
                .frame(width: 28, height: 28)
                .background(schritt.istAktion ? AnyShapeStyle(tint) : AnyShapeStyle(Color(.tertiarySystemFill)),
                            in: Circle())
                .foregroundStyle(schritt.istAktion ? tint.onFill : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(schritt.titel)
                    .font(.subheadline.weight(schritt.istAktion ? .semibold : .regular))
                if let d = schritt.detail {
                    Text(d).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if ueberNacht {
                    Label("läuft über Nacht", systemImage: "moon.zzz.fill")
                        .font(.caption2.weight(.semibold)).foregroundStyle(.indigo)
                }
            }
            .padding(.top, 4)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        // Handgriffe sind, was Lars tun muss - die Gare laeuft von allein und tritt zurueck.
        .opacity(schritt.istAktion ? 1 : 0.7)
    }
}

// MARK: - Bausteine

/// Karte mit Abschnittsueberschrift. Der Identifier macht die Karte als Container fuer
/// XCUITest auffindbar (die Kinder bleiben einzeln erreichbar).
private struct PizzaAbschnitt<Inhalt: View>: View {
    let titel: String
    let icon: String
    let tint: Color
    var identifier: String?
    @ViewBuilder let inhalt: () -> Inhalt

    init(titel: String, icon: String, tint: Color, identifier: String? = nil,
         @ViewBuilder inhalt: @escaping () -> Inhalt) {
        self.titel = titel
        self.icon = icon
        self.tint = tint
        self.identifier = identifier
        self.inhalt = inhalt
    }

    private var karte: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(titel, systemImage: icon)
                .font(.footnote.weight(.bold)).textCase(.uppercase)
                .foregroundStyle(tint)
            inhalt()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    @ViewBuilder var body: some View {
        if let identifier {
            karte.accessibilityElement(children: .contain).accessibilityIdentifier(identifier)
        } else {
            karte
        }
    }
}

/// Kennzahl auf dem Verlaufs-Hero. Erbt die Textfarbe der Karte (luminanz-sicher gewaehlt),
/// deshalb hier keine eigene Farbe.
private struct PizzaHeroWert: View {
    let titel: String
    let wert: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(titel).font(.caption2).opacity(0.8)
            Text(wert).font(.subheadline.weight(.bold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
