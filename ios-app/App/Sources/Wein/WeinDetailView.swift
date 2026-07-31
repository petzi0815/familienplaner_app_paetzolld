import SwiftUI

/// Detailseite eines Weins: Stammdaten, Geschmacksprofil, Hintergrund, Keller, Preise —
/// und der Bewertungsblock, in dem die eigene Bewertung bearbeitbar und die der anderen
/// Person daneben lesbar ist.
///
/// Der angezeigte Datensatz wird ueber `store.weine` nachgeschlagen (`current`), damit
/// Bestandsaenderungen, Bewertungen und Preisergebnisse sofort sichtbar sind.
struct WeinDetailView: View {
    let wein: Wein

    @EnvironmentObject private var store: WeinStore
    @State private var sterne = 0
    @State private var kommentar = ""
    @State private var speichert = false
    @State private var pruefe = false
    @State private var vorbereitet = false

    private var current: Wein { store.weine.first { $0.id == wein.id } ?? wein }
    private var tint: Color { Palette.colors(for: "wein").first ?? Theme.accent }
    private var preise: [WeinPreis] { store.preise[current.id] ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                kopf
                bewertungsblock
                stammdaten
                geschmacksprofil
                aromen
                // Gruppiert, weil ein ViewBuilder-Block hoechstens zehn Kinder aufnimmt.
                Group {
                    hintergrund
                    auszeichnungen
                    trinkfenster
                    kellerBlock
                    preisBlock
                    notizen
                }
            }
            .padding(16)
        }
        .background(Palette.gradient(for: "wein").opacity(0.05).ignoresSafeArea())
        .navigationTitle(current.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await ersteLadung() }
        .areaToast($store.message, isError: store.messageIsError)
    }

    // ── Laden / Speichern ──

    private func ersteLadung() async {
        guard !vorbereitet else { return }
        vorbereitet = true
        if let b = store.meine(current) {
            sterne = b.sterne
            kommentar = b.kommentar
        }
        await store.loadPreise(current)
    }

    private func bewertungSpeichern() async {
        guard sterne >= 1 else { return }
        speichert = true
        await store.bewerten(current, sterne: sterne, kommentar: kommentar)
        speichert = false
    }

    private func preisPruefen() async {
        pruefe = true
        await store.preischeck(current)
        await store.loadPreise(current)
        pruefe = false
    }

    // ── Bausteine ──

    /// Abschnitts-Karte mit Ueberschrift — haelt die Detailseite optisch ruhig.
    private func block<Inhalt: View>(_ titel: String, @ViewBuilder _ inhalt: () -> Inhalt) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(titel).font(.caption.weight(.bold)).textCase(.uppercase).foregroundStyle(.secondary)
            inhalt()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // ── Kopf ──

    private var kopf: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let path = current.imagePath {
                AuthImage(path: path, contentMode: .fit)
                    .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 320)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            Text(current.titel).font(.title3.weight(.bold))
            FlowLayout(spacing: 6) {
                Pill(text: current.typ.emoji + " " + current.typ.label, color: current.typ.farbe)
                if current.geschmacksrichtung != "unbekannt" {
                    Pill(text: WeinGeschmack.label(current.geschmacksrichtung), color: tint, filled: false)
                }
                if current.bio { Pill(text: "Bio", systemImage: "leaf.fill", color: Color(hex: "16A34A")) }
                if current.vegan { Pill(text: "Vegan", systemImage: "carrot.fill", color: Color(hex: "65A30D")) }
                if current.bestand > 0 {
                    Pill(text: String(current.bestand) + " Flaschen", systemImage: "archivebox",
                         color: Color(hex: "475569"), filled: false)
                }
            }
            let ort = WeinText.herkunft(land: current.land, region: current.region, lage: current.lage)
            if !ort.isEmpty {
                Label(ort, systemImage: "mappin.and.ellipse").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    // ── Bewertungen ──

    private var bewertungsblock: some View {
        block("Bewertungen") {
            VStack(alignment: .leading, spacing: 12) {
                if let s = store.schnitt(current) {
                    HStack(spacing: 6) {
                        Text("Schnitt").font(.subheadline).foregroundStyle(.secondary)
                        Text(WeinText.zahl(s) + " von 5").font(.subheadline.weight(.semibold))
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Meine Bewertung").font(.subheadline.weight(.semibold))
                    WeinSterne(auswahl: $sterne, identifier: "wein-stern")
                    TextField("Kommentar (optional)", text: $kommentar, axis: .vertical)
                        .lineLimit(1...4)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("wein-kommentar")
                    if (store.owner ?? "").isEmpty {
                        Text("Ohne persönlichen Zugangsschlüssel lässt sich keine Bewertung zuordnen.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    Button {
                        Task { await bewertungSpeichern() }
                    } label: {
                        if speichert {
                            HStack(spacing: 8) { ProgressView(); Text("Speichert …") }
                        } else {
                            Text(store.meine(current) == nil ? "Bewertung speichern" : "Bewertung aktualisieren")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(tint)
                    .disabled(sterne < 1 || speichert)
                    .accessibilityIdentifier("wein-bewerten")
                }

                Divider()

                if let a = store.andere(current) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(WeinText.person(a.owner)).font(.subheadline.weight(.semibold))
                        WeinSterne(sterne: a.sterne, gross: true)
                        if !a.kommentar.isEmpty {
                            Text(a.kommentar).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Die andere Person hat diesen Wein noch nicht bewertet.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // ── Stammdaten ──

    private var stammdaten: some View {
        block("Stammdaten") {
            VStack(spacing: 0) {
                if !current.weingut.isEmpty { InfoRow(icon: "🏛️", label: "Weingut", value: current.weingut) }
                InfoRow(icon: "📅", label: "Jahrgang", value: WeinText.jahrgang(current.jahrgang))
                if !current.rebsorten.isEmpty {
                    InfoRow(icon: "🍇", label: "Rebsorten", value: current.rebsorten.joined(separator: ", "))
                }
                if let a = current.alkohol { InfoRow(icon: "🥃", label: "Alkohol", value: WeinText.alkohol(a)) }
                InfoRow(icon: "🍬", label: "Geschmack", value: WeinGeschmack.label(current.geschmacksrichtung))
                if let t = current.serviertemperatur, !t.isEmpty {
                    InfoRow(icon: "🌡️", label: "Serviertemperatur", value: t)
                }
                InfoRow(icon: "🍾", label: "Flasche", value: WeinText.flasche(current.flaschengroesseMl))
                if let e = current.ean, !e.isEmpty { InfoRow(icon: "🔖", label: "EAN", value: e) }
            }
        }
    }

    // ── Geschmacksprofil ──

    private var profilWerte: [WeinProfilEintrag] {
        var w: [WeinProfilEintrag] = []
        if let v = current.suesse { w.append(.init(id: "Süße", wert: v, farbe: Color(hex: "EC4899"))) }
        if let v = current.saeure { w.append(.init(id: "Säure", wert: v, farbe: Color(hex: "84CC16"))) }
        if let v = current.tannin { w.append(.init(id: "Tannin", wert: v, farbe: Color(hex: "92400E"))) }
        if let v = current.koerper { w.append(.init(id: "Körper", wert: v, farbe: Color(hex: "7C3AED"))) }
        return w
    }

    @ViewBuilder private var geschmacksprofil: some View {
        if !profilWerte.isEmpty {
            block("Geschmacksprofil") {
                VStack(spacing: 8) {
                    ForEach(profilWerte) { e in
                        WeinProfilBalken(label: e.id, wert: e.wert, farbe: e.farbe)
                    }
                }
            }
        }
    }

    @ViewBuilder private var aromen: some View {
        if !current.aromen.isEmpty {
            block("Aromen") {
                FlowLayout(spacing: 6) {
                    ForEach(current.aromen, id: \.self) { a in
                        Pill(text: a, color: tint, filled: false)
                    }
                }
            }
        }
    }

    @ViewBuilder private var hintergrund: some View {
        if let text = current.beschreibung, !text.isEmpty {
            block("Hintergrund") {
                Text(text).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        if let speise = current.speiseempfehlung, !speise.isEmpty {
            NoteBlock(icon: "🍽️", text: speise, tint: Color(hex: "F59E0B"))
        }
    }

    @ViewBuilder private var auszeichnungen: some View {
        if !current.auszeichnungen.isEmpty {
            block("Auszeichnungen") {
                FlowLayout(spacing: 6) {
                    ForEach(current.auszeichnungen, id: \.self) { a in
                        Pill(text: a, systemImage: "rosette", color: Color(hex: "F59E0B"))
                    }
                }
            }
        }
    }

    @ViewBuilder private var trinkfenster: some View {
        if current.trinkfensterVon != nil || current.trinkfensterBis != nil {
            block("Trinkfenster") {
                HStack(spacing: 8) {
                    Text(WeinText.trinkfenster(current.trinkfensterVon, current.trinkfensterBis))
                        .font(.subheadline.weight(.semibold))
                    if current.istTrinkreif {
                        Pill(text: "jetzt trinkreif", systemImage: "checkmark.seal.fill", color: Color(hex: "16A34A"))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // ── Keller ──

    private var kellerBlock: some View {
        block("Keller") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    Text("Flaschen").font(.subheadline).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button {
                        Task { await store.setBestand(current, max(0, current.bestand - 1)) }
                    } label: {
                        Image(systemName: "minus.circle.fill").font(.title2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(current.bestand > 0 ? tint : Color.secondary.opacity(0.4))
                    .disabled(current.bestand == 0)
                    .accessibilityLabel("Eine Flasche weniger")
                    .accessibilityIdentifier("wein-bestand-minus")

                    Text(String(current.bestand)).font(.title3.weight(.bold)).frame(minWidth: 32)

                    Button {
                        Task { await store.setBestand(current, current.bestand + 1) }
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.title2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(tint)
                    .accessibilityLabel("Eine Flasche mehr")
                    .accessibilityIdentifier("wein-bestand-plus")
                }
                if let ort = current.lagerort, !ort.isEmpty {
                    InfoRow(icon: "📦", label: "Lagerort", value: ort)
                }
            }
        }
    }

    // ── Preise ──

    private var preisBlock: some View {
        block("Preise") {
            VStack(alignment: .leading, spacing: 10) {
                if let ref = current.referenzpreis {
                    InfoRow(icon: "🏷️", label: "Referenzpreis", value: WeinText.eur(ref))
                }
                if let best = current.besterPreis {
                    InfoRow(icon: "💶", label: "Bester Preis", value: WeinText.eur(best),
                            valueColor: Color(hex: "16A34A"))
                    if let r = current.rabattProzent, r >= 5 {
                        HStack {
                            Pill(text: WeinText.rabatt(r) + " gegenüber Referenz", systemImage: "tag.fill",
                                 color: Color(hex: "16A34A"))
                            Spacer(minLength: 0)
                        }
                    }
                }
                haendlerZeile
                let geprueft = WeinText.datum(current.preisGeprueftAt)
                InfoRow(icon: "🕒", label: "Zuletzt geprüft", value: geprueft.isEmpty ? "noch nie" : geprueft)

                Toggle(isOn: Binding(get: { current.preisBeobachten },
                                     set: { neu in Task { await store.setBeobachten(current, neu) } })) {
                    Text("Preis beobachten").font(.subheadline)
                }
                .tint(tint)
                .accessibilityIdentifier("wein-beobachten")

                Button {
                    Task { await preisPruefen() }
                } label: {
                    if pruefe {
                        HStack(spacing: 8) { ProgressView(); Text("Sucht Angebote …") }
                    } else {
                        Label("Preis jetzt prüfen", systemImage: "magnifyingglass")
                    }
                }
                .buttonStyle(.bordered)
                .tint(tint)
                .disabled(pruefe)
                .accessibilityIdentifier("wein-preischeck")

                preisverlauf
            }
        }
    }

    @ViewBuilder private var haendlerZeile: some View {
        let haendler = current.besterPreisHaendler ?? ""
        if let link = current.besterPreisURL, let url = URL(string: link) {
            Link(destination: url) {
                Label(haendler.isEmpty ? "Zum Angebot" : haendler, systemImage: "arrow.up.right.square")
                    .font(.subheadline)
            }
            .accessibilityIdentifier("wein-preis-link")
        } else if !haendler.isEmpty {
            InfoRow(icon: "🏬", label: "Händler", value: haendler)
        }
    }

    @ViewBuilder private var preisverlauf: some View {
        if !preise.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Preisverlauf").font(.caption.weight(.bold)).foregroundStyle(.secondary).padding(.top, 4)
                ForEach(preise) { p in
                    HStack(spacing: 8) {
                        Text(WeinText.datum(p.gefundenAt)).font(.caption2).foregroundStyle(.secondary)
                            .frame(width: 74, alignment: .leading)
                        if let url = p.linkURL {
                            Link(p.haendler.isEmpty ? "Angebot" : p.haendler, destination: url)
                                .font(.caption).lineLimit(1)
                        } else {
                            Text(p.haendler.isEmpty ? "unbekannt" : p.haendler)
                                .font(.caption).lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        Text(WeinText.eur(p.preis)).font(.caption.weight(.semibold))
                    }
                }
            }
        }
    }

    @ViewBuilder private var notizen: some View {
        if let n = current.notizen, !n.isEmpty {
            NoteBlock(icon: "📝", text: n)
        }
    }
}

// MARK: - Geschmacksprofil-Balken

/// Ein Wert des Geschmacksprofils. Eigener Typ statt Tupel, weil `ForEach` einen Schluesselpfad
/// braucht und Tupel-Bestandteile keinen haben.
struct WeinProfilEintrag: Identifiable {
    /// Beschriftung (Süße/Säure/Tannin/Körper) — je Wein eindeutig, taugt daher als Id.
    let id: String
    let wert: Int
    let farbe: Color
}

/// Ein Profilwert (1 bis 5) als fuenf Segmente — ohne GeometryReader, damit es in jeder
/// Breite und in der Vorschau stabil bleibt.
struct WeinProfilBalken: View {
    let label: String
    let wert: Int
    let farbe: Color

    var body: some View {
        HStack(spacing: 10) {
            Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 62, alignment: .leading)
            HStack(spacing: 3) {
                ForEach(1...5, id: \.self) { i in
                    Capsule()
                        .fill(i <= wert ? farbe : Color.secondary.opacity(0.18))
                        .frame(height: 8)
                }
            }
            Text(String(max(0, min(5, wert))) + "/5").font(.caption2).foregroundStyle(.secondary)
                .frame(width: 26, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label + " " + String(wert) + " von 5")
    }
}
