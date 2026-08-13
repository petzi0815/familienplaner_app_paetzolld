import SwiftUI

// Reisen-Liste: Gliederung nach dem gepflegten Feld `status` (Geplant / Ideen / Vergangen) statt
// einem flachen Cover-Raster über alle Reisen. Kurz- und Wochenendtrips bekommen einen eigenen
// optischen Aufhänger, damit ein Wochenend-Vorschlag nicht aussieht wie eine gebuchte Fernreise.
//
// Bewusst NICHT nach Datum gruppiert: in den echten Daten liegen geplante Reisen datumsmäßig
// bereits in der Vergangenheit. Der vom Nutzer gepflegte Status hat Vorrang; ein zurückliegendes
// Datum wird nur als dezenter Hinweis an der Karte gezeigt.

// MARK: - Gliederung

/// Segmente der Reiseliste. Die Zuordnung läuft über `status` — dem einzigen durchgängig
/// gepflegten Feld.
enum ReiseGruppe: String, CaseIterable, Hashable {
    case geplant, ideen, vergangen

    /// Unbekannte oder leere Statuswerte landen bewusst bei „Geplant" — so verschwindet
    /// keine Reise aus der Liste, auch wenn im Backend ein neuer Status auftaucht.
    init(status: String) {
        switch status {
        case "vergangen", "abgeschlossen", "archiviert": self = .vergangen
        case "idee", "vorschlag", "recherche", "wunsch": self = .ideen
        default: self = .geplant
        }
    }

    var label: String {
        switch self {
        case .geplant: return "Geplant"
        case .ideen: return "Ideen"
        case .vergangen: return "Vergangen"
        }
    }
    var symbol: String {
        switch self {
        case .geplant: return "airplane.departure"
        case .ideen: return "lightbulb"
        case .vergangen: return "clock.arrow.circlepath"
        }
    }
    var leerEmoji: String {
        switch self {
        case .geplant: return "🧳"
        case .ideen: return "💡"
        case .vergangen: return "📸"
        }
    }
    var leerTitel: String {
        switch self {
        case .geplant: return "Keine geplanten Reisen"
        case .ideen: return "Keine Ideen und Vorschläge"
        case .vergangen: return "Noch keine vergangenen Reisen"
        }
    }
    var leerHinweis: String {
        switch self {
        case .geplant: return "Reisen mit Status geplant oder gebucht erscheinen hier."
        case .ideen: return "Hier sammeln sich Reisen mit Status Idee oder Vorschlag."
        case .vergangen: return "Abgeschlossene Reisen wandern hierher — nach Jahren sortiert."
        }
    }
}

/// Filterzeile unter der Suche — trennt Kurz-/Wochenendtrips von den längeren Reisen.
enum ReiseLaenge: String, CaseIterable, Hashable {
    case alle, kurz, lang
}

/// Ein Abschnitt der Liste (Vergangene sind nach Jahr gruppiert, sonst gibt es genau einen).
struct ReiseAbschnitt: Identifiable {
    let id: String
    let titel: String?
    let reisen: [ReiseInfo]
}

// MARK: - Typen, Texte, Farben

/// Reisetyp → Emoji, deutsches Label und Farbe. Unbekannte Typen bekommen neutrale Werte,
/// damit ein neuer Typ im Backend die Liste nicht bricht.
enum ReiseTyp {
    /// Typen, die IMMER als Kurz-/Wochenendtrip gelten — unabhängig von der Dauer.
    static let kurzTypen: Set<String> = ["wochenende", "kurztrip", "tagesausflug"]
    /// Eine Farbe für alle Kurztrips: das ist der wiedererkennbare Aufhänger in der Liste.
    /// Teal-700 statt Teal-600: auf der gefüllten Pille setzt `Color.onFill` weißen Text, und der
    /// braucht 4,5:1 — das hellere 0D9488 kam nur auf 3,7:1. Hue und Wiedererkennung bleiben.
    static let kurzFarbe = Color(hex: "0F766E")

    static func emoji(_ typ: String) -> String {
        switch typ {
        case "urlaub": return "🏖️"
        case "staedtereise": return "🏙️"
        case "tauchen": return "🤿"
        case "segeln": return "⛵️"
        case "wellness": return "🧖"
        case "kreuzfahrt": return "🛳️"
        case "wochenende": return "🎒"
        case "kurztrip": return "🚗"
        case "tagesausflug": return "🌞"
        case "wandern": return "🥾"
        case "aktivitaet": return "🎯"
        default: return "✈️"
        }
    }

    static func label(_ typ: String) -> String {
        switch typ {
        case "urlaub": return "Urlaub"
        case "staedtereise": return "Städtereise"
        case "tauchen": return "Tauchen"
        case "segeln": return "Segeln"
        case "wellness": return "Wellness"
        case "kreuzfahrt": return "Kreuzfahrt"
        case "wochenende": return "Wochenende"
        case "kurztrip": return "Kurztrip"
        case "tagesausflug": return "Tagesausflug"
        case "wandern": return "Wandern"
        case "aktivitaet": return "Aktivität"
        case "": return "Reise"
        default: return prettyColumn(typ)
        }
    }

    /// Füllfarben der Typ-Pille. Die Töne sind so dunkel gewählt, dass der von `Color.onFill`
    /// gesetzte Text (weiß bzw. schwarz auf hellem Grund) überall mindestens 4,5:1 erreicht.
    /// Die hellen 500er-Töne lagen bei 2,8–3,7:1 und waren bei Sonnenlicht kaum lesbar; der
    /// Pillentext trägt die Typ-Information, ist also kein Schmuck. Kontraste im Kommentar.
    static func farbe(_ typ: String) -> Color {
        switch typ {
        case "urlaub": return Color(hex: "F59E0B")          // hell → onFill nimmt Schwarz, 8,1:1
        case "staedtereise": return Color(hex: "4F46E5")    // 6,3:1
        case "tauchen": return Color(hex: "0369A1")         // 5,9:1
        case "segeln": return Color(hex: "0E7490")          // 5,4:1
        case "wellness": return Color(hex: "BE185D")        // 6,0:1
        case "kreuzfahrt": return Color(hex: "2563EB")      // 5,2:1
        case "wandern": return Color(hex: "15803D")         // 5,0:1
        case "aktivitaet": return Color(hex: "C2410C")      // 5,2:1
        case "wochenende", "kurztrip", "tagesausflug": return ReiseTyp.kurzFarbe
        default: return Color(hex: "64748B")                // 4,8:1
        }
    }
}

/// Datums-, Dauer- und Status-Texte der Reiseliste. Alle Formatierer sind auf de_DE festgelegt
/// (wie `DateText`), damit die Schreibweise unabhängig von der Geräte-Region stimmt.
enum ReiseText {
    private static func formatter(_ muster: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = muster
        return f
    }
    private static let tagFmt = ReiseText.formatter("d.")
    private static let tagMonatFmt = ReiseText.formatter("d. MMMM")
    private static let vollFmt = ReiseText.formatter("d. MMMM yyyy")

    /// Zeitraum in deutscher Schreibweise:
    /// gleicher Monat „23.-28. Juni 2026", gleiches Jahr „28. Juni - 3. Juli 2026",
    /// sonst beide Daten voll. Ohne Enddatum nur das Startdatum, ohne Startdatum GAR KEINE
    /// Zeile (statt eines nichtssagenden Strichs) — viele Reisen haben kein Enddatum,
    /// zwei gar kein Datum.
    static func zeitraum(start: Date?, ende: Date?) -> String? {
        guard let start else { return nil }
        guard let ende, ende > start else { return vollFmt.string(from: start) }
        let cal = Calendar.current
        let gleichesJahr = cal.component(.year, from: start) == cal.component(.year, from: ende)
        let gleicherMonat = gleichesJahr && cal.component(.month, from: start) == cal.component(.month, from: ende)
        if gleicherMonat { return tagFmt.string(from: start) + "-" + vollFmt.string(from: ende) }
        if gleichesJahr { return tagMonatFmt.string(from: start) + " - " + vollFmt.string(from: ende) }
        return vollFmt.string(from: start) + " - " + vollFmt.string(from: ende)
    }

    /// Dauer in Nächten. 0 Nächte = Tagestrip; ohne vollständiges Datum keine Angabe.
    static func dauer(_ naechte: Int?) -> String? {
        guard let n = naechte else { return nil }
        if n == 0 { return "Tagestrip" }
        return String(n) + (n == 1 ? " Nacht" : " Nächte")
    }

    /// Countdown bis zum Start — nur für künftige Reisen (sonst nil).
    static func countdown(_ tage: Int?) -> String? {
        guard let t = tage else { return nil }
        if t == 0 { return "heute" }
        if t == 1 { return "morgen" }
        return "in " + String(t) + " Tagen"
    }

    static func statusLabel(_ status: String) -> String {
        switch status {
        case "geplant": return "Geplant"
        case "gebucht": return "Gebucht"
        case "vorschlag": return "Vorschlag"
        case "idee": return "Idee"
        case "recherche": return "Recherche"
        case "wunsch": return "Wunsch"
        case "vergangen": return "Vergangen"
        case "": return "Ohne Status"
        default: return prettyColumn(status)
        }
    }

    static func statusFarbe(_ status: String) -> Color {
        switch status {
        case "geplant", "gebucht": return Color(hex: "16A34A")
        case "vorschlag": return Color(hex: "F59E0B")
        case "idee", "recherche", "wunsch": return Color(hex: "8B5CF6")
        default: return Color(hex: "64748B")
        }
    }
}

// MARK: - Aufbereiteter Datensatz

/// Ein Reisedatensatz in der für die Anzeige aufbereiteten Form. Fehlende Werte sind hier bereits
/// zu nil normalisiert — die Ansichten müssen sich nicht mehr um Leerstrings kümmern.
struct ReiseInfo: Identifiable {
    /// Rohdatensatz — die Detailansicht arbeitet weiterhin datengetrieben darauf.
    let record: GenericRecord
    let titel: String
    let ziel: String
    let land: String
    let region: String
    /// Rohwert aus `type`, kleingeschrieben.
    let typ: String
    /// Rohwert aus `status`, kleingeschrieben.
    let status: String
    let start: Date?
    let ende: Date?
    let coverPfad: String?

    var id: String { record.id }

    init(record: GenericRecord, imageSpec: ResourceImageSpec?) {
        let f = record.fields
        self.record = record
        self.titel = fieldString(f["title"])
        self.ziel = fieldString(f["destination"])
        self.land = fieldString(f["country"])
        self.region = fieldString(f["region"])
        self.typ = fieldString(f["type"]).lowercased()
        self.status = fieldString(f["status"]).lowercased()
        self.start = DateText.parse(date: fieldString(f["start_date"]))
        self.ende = DateText.parse(date: fieldString(f["end_date"]))
        self.coverPfad = recordImageURL(f, imageSpec)
    }

    var gruppe: ReiseGruppe { ReiseGruppe(status: status) }

    /// Nächte zwischen Start und Ende. nil, wenn ein Datum fehlt oder das Ende vor dem Start liegt.
    var naechte: Int? {
        guard let start, let ende else { return nil }
        let cal = Calendar.current
        let tage = cal.dateComponents([.day], from: cal.startOfDay(for: start), to: cal.startOfDay(for: ende)).day ?? 0
        return tage >= 0 ? tage : nil
    }

    /// Kurz-/Wochenendtrip: entweder sagt es der Typ, oder die Reise dauert höchstens 3 Nächte.
    var istKurztrip: Bool {
        if ReiseTyp.kurzTypen.contains(typ) { return true }
        if let n = naechte { return n <= 3 }
        return false
    }

    /// Aufhänger für Kurztrips: der gepflegte Typ, sonst aus der Dauer abgeleitet.
    var kurzLabel: String {
        ReiseTyp.kurzTypen.contains(typ) ? ReiseTyp.label(typ) : "Kurztrip"
    }

    /// Sortier-/Gruppierschlüssel — das Enddatum rettet Reisen, bei denen nur dieses gepflegt ist.
    var sortDatum: Date? { start ?? ende }

    /// Jahr für die Gruppierung der vergangenen Reisen; nil ohne jedes Datum.
    var jahr: Int? {
        guard let d = sortDatum else { return nil }
        return Calendar.current.component(.year, from: d)
    }

    /// Tage bis zum Start (0 = heute). nil, wenn kein Startdatum oder der Start zurückliegt.
    var tageBisStart: Int? {
        guard let start else { return nil }
        let cal = Calendar.current
        let d = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: start)).day ?? 0
        return d >= 0 ? d : nil
    }

    /// Dezenter Hinweis „Datum liegt zurück": nur bei Reisen, die NICHT als vergangen geführt
    /// werden. Wir korrigieren den Status des Nutzers nicht, wir machen nur darauf aufmerksam.
    var datumHinweis: Bool {
        guard gruppe != .vergangen, let d = ende ?? start else { return false }
        let cal = Calendar.current
        return cal.startOfDay(for: d) < cal.startOfDay(for: Date())
    }

    var ortText: String { [ziel, land].filter { !$0.isEmpty }.joined(separator: ", ") }
    var zeitraum: String? { ReiseText.zeitraum(start: start, ende: ende) }
    var dauer: String? { ReiseText.dauer(naechte) }
    var typEmoji: String { ReiseTyp.emoji(typ) }
    var typLabel: String { ReiseTyp.label(typ) }
    /// Pillen-Text des Typs — Kurztrips zeigen ihren eigenen Aufhänger.
    var typPille: String { typEmoji + " " + (istKurztrip ? kurzLabel : typLabel) }
    var typFarbe: Color { istKurztrip ? ReiseTyp.kurzFarbe : ReiseTyp.farbe(typ) }
    /// Durchsuchbarer Text: Titel, Ziel, Land, Region.
    var sucheText: String { [titel, ziel, land, region].joined(separator: " ").lowercased() }
}

// MARK: - Liste

/// Reisen-Bereich: Segmente nach Status, Suche, Kurztrip-Filter und die Kartenliste.
/// Vergangene Reisen sind zusätzlich nach Jahr gruppiert (absteigend).
struct ReiseListView: View {
    @EnvironmentObject private var app: AppState
    @State private var reisen: [ReiseInfo] = []
    @State private var gruppe: ReiseGruppe = .geplant
    @State private var suche = ""
    @State private var laenge: ReiseLaenge = .alle
    @State private var loading = true
    /// Nur beim allerersten Laden darf das Segment automatisch springen (siehe `load()`).
    @State private var ersteLadung = true
    @State private var toast: String?
    @State private var toastIsError = false
    /// Bleibt stehen, bis das Laden gelingt. Der Toast blendet sich nach 2,5 s aus — danach wäre
    /// ein Übertragungsfehler nicht mehr vom leeren Bestand zu unterscheiden.
    @State private var ladeFehler: String?

    private var res: ResourceInfo? { app.resources.first { $0.key == "reisen" } }
    private var tint: Color { Palette.colors(for: "reisen").first ?? Theme.accent }

    // ── Kennzahlen / Segmente ──

    private func anzahl(_ g: ReiseGruppe) -> Int { reisen.filter { $0.gruppe == g }.count }
    /// Zähler nur zeigen, wenn es etwas zu zählen gibt (hält die Leiste ruhig und die
    /// Segment-Identifier im leeren Zustand stabil).
    private func zaehler(_ n: Int) -> String { n > 0 ? " (" + String(n) + ")" : "" }

    /// Ein Segment mit Zähler. Eigene Funktion mit ausgeschriebenem Rückgabetyp, damit die
    /// Umwandlung `String` → `String?` beim Symbol nicht in einer generischen `map`-Inferenz hängt.
    private func tab(_ g: ReiseGruppe) -> (tab: ReiseGruppe, label: String, systemImage: String?) {
        (tab: g, label: g.label + zaehler(anzahl(g)), systemImage: g.symbol)
    }

    private var tabs: [(tab: ReiseGruppe, label: String, systemImage: String?)] {
        [tab(.geplant), tab(.ideen), tab(.vergangen)]
    }

    private var subtitle: String {
        if reisen.isEmpty { return "Urlaube, Kurztrips und Ideen" }
        let kurz = reisen.filter { $0.istKurztrip }.count
        return String(reisen.count) + " Reisen · " + String(anzahl(.geplant)) + " geplant · "
            + String(kurz) + " kurz"
    }

    var body: some View {
        AreaScaffold(gradientKey: "reisen", systemImage: "airplane.departure", title: "Reisen",
                     subtitle: subtitle, toast: $toast, toastIsError: toastIsError,
                     controls: { controls },
                     content: { content })
            .task { if loading { await load() } }
    }

    // ── Steuerleiste ──

    private var controls: some View {
        VStack(spacing: 6) {
            SegmentBar(tabs: tabs, selection: $gruppe, gradientKey: "reisen")
            AreaSearchField(placeholder: "Titel, Ziel, Land …", text: $suche)
            laengenFilter
        }
    }

    /// Kernwunsch: Wochenendtrips und geplante Reisen dürfen nicht verschwimmen.
    private var laengenFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterPill(label: "Alle", selected: laenge == .alle, color: tint) { laenge = .alle }
                    .accessibilityIdentifier("reise-filter-alle")
                FilterPill(label: "Kurz & Wochenende", systemImage: "bolt.fill",
                           selected: laenge == .kurz, color: ReiseTyp.kurzFarbe) { laenge = .kurz }
                    .accessibilityIdentifier("reise-filter-kurz")
                FilterPill(label: "Längere Reisen", systemImage: "airplane",
                           selected: laenge == .lang, color: tint) { laenge = .lang }
                    .accessibilityIdentifier("reise-filter-lang")
            }
            .padding(.horizontal, 14).padding(.bottom, 4)
        }
    }

    // ── Filter / Abschnitte ──

    private var gefiltert: [ReiseInfo] {
        let q = suche.trimmingCharacters(in: .whitespaces).lowercased()
        return reisen.filter { r in
            guard r.gruppe == gruppe else { return false }
            switch laenge {
            case .alle: break
            case .kurz: if !r.istKurztrip { return false }
            case .lang: if r.istKurztrip { return false }
            }
            return q.isEmpty || r.sucheText.contains(q)
        }
    }

    /// Geplant/Ideen: eine Liste, das Nächste zuerst. Vergangen: nach Jahr absteigend gruppiert —
    /// Reisen ohne jedes Datum bekommen einen eigenen Abschnitt ganz am Ende.
    private var abschnitte: [ReiseAbschnitt] {
        let items = gefiltert
        if items.isEmpty { return [] }
        if gruppe != .vergangen {
            let sortiert = items.sorted { a, b in
                switch (a.sortDatum, b.sortDatum) {
                case let (x?, y?): return x == y ? a.titel < b.titel : x < y
                case (nil, _?): return false      // ohne Datum ans Ende
                case (_?, nil): return true
                default: return a.titel < b.titel
                }
            }
            return [ReiseAbschnitt(id: gruppe.rawValue, titel: nil, reisen: sortiert)]
        }
        var jahre: [Int: [ReiseInfo]] = [:]
        var ohneDatum: [ReiseInfo] = []
        for r in items {
            if let j = r.jahr { jahre[j, default: []].append(r) } else { ohneDatum.append(r) }
        }
        var out = jahre.keys.sorted(by: >).map { j -> ReiseAbschnitt in
            let inhalt = (jahre[j] ?? []).sorted { ($0.sortDatum ?? Date.distantPast) > ($1.sortDatum ?? Date.distantPast) }
            return ReiseAbschnitt(id: "jahr-" + String(j), titel: String(j), reisen: inhalt)
        }
        if !ohneDatum.isEmpty {
            out.append(ReiseAbschnitt(id: "ohne-datum", titel: "Ohne Datum",
                                      reisen: ohneDatum.sorted { $0.titel < $1.titel }))
        }
        return out
    }

    // ── Inhalt ──

    @ViewBuilder private var content: some View {
        if loading && reisen.isEmpty {
            ProgressView("Lädt …").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let ladeFehler, reisen.isEmpty {
            // Vor dem Leerzustand: ein Ladefehler darf nicht wie „keine Reisen vorhanden" aussehen.
            // Nur bei leerer Liste — schlägt ein Aktualisieren fehl, bleiben die alten Daten
            // stehen und der Toast ist das richtige (nicht verdrängende) Signal.
            ScrollView {
                ContentUnavailableView {
                    Label("Keine Verbindung", systemImage: "wifi.slash")
                } description: {
                    Text(ladeFehler)
                } actions: {
                    Button("Erneut laden") { Task { await load() } }
                        .buttonStyle(.glassProminent)
                        .accessibilityIdentifier("reise-retry")
                }
                .frame(maxWidth: .infinity).frame(minHeight: 300)
            }
            .refreshable { await load() }
        } else if abschnitte.isEmpty {
            ScrollView { leerZustand.frame(maxWidth: .infinity).frame(minHeight: 300) }
                .refreshable { await load() }
        } else {
            List {
                ForEach(abschnitte) { a in
                    if let t = a.titel {
                        Section {
                            ForEach(a.reisen) { r in zeile(r) }
                        } header: {
                            Text(t).font(.footnote.weight(.bold)).foregroundStyle(.secondary)
                        }
                        .textCase(nil)     // sonst macht List daraus Großbuchstaben
                    } else {
                        Section { ForEach(a.reisen) { r in zeile(r) } }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable { await load() }
        }
    }

    private func zeile(_ r: ReiseInfo) -> some View {
        // Closure-basierter NavigationLink: wertbasierte Links sind in gepushten Views flaky.
        NavigationLink {
            ReiseDetailView(record: r.record)
        } label: {
            ReiseKachel(reise: r, zeigeStatus: gruppe != .vergangen)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("reise-" + r.id)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 14))
    }

    private var leerZustand: some View {
        let eingeschraenkt = !suche.trimmingCharacters(in: .whitespaces).isEmpty || laenge != .alle
        return AreaEmptyState(
            emoji: eingeschraenkt ? "🔍" : gruppe.leerEmoji,
            title: eingeschraenkt ? "Keine Treffer" : gruppe.leerTitel,
            hint: eingeschraenkt ? "Andere Filter oder Suchbegriffe probieren." : gruppe.leerHinweis
        )
        .accessibilityIdentifier("reise-empty")
    }

    // ── Laden ──

    private func load() async {
        loading = true
        await app.loadCapabilities()
        guard let r = res else {
            // `loadCapabilities()` schluckt seinen Fehler (try?) — ohne Meldung endete der
            // Kaltstart ohne Netz stumm im Leerzustand.
            reisen = []
            ladeFehler = "Reisen konnten nicht geladen werden."
            loading = false
            return
        }
        do {
            let rows = try await app.api.listRecords("reisen", primaryKey: r.primaryKey, limit: 300)
            reisen = rows.map { ReiseInfo(record: $0, imageSpec: r.image) }
            ladeFehler = nil
            // Sinnvoller Einstieg: ist „Geplant" leer, öffnet sich die erste Gruppe mit Inhalt.
            // Nur beim ersten Laden — beim Aktualisieren bleibt die Wahl des Nutzers stehen.
            if ersteLadung {
                ersteLadung = false
                if anzahl(gruppe) == 0, let erste = ReiseGruppe.allCases.first(where: { anzahl($0) > 0 }) {
                    gruppe = erste
                }
            }
        } catch {
            toastIsError = true
            toast = "Reisen konnten nicht geladen werden."
            ladeFehler = (error as? APIError)?.errorDescription ?? "Reisen konnten nicht geladen werden."
        }
        loading = false
    }
}

// MARK: - Karte

/// Listenkarte einer Reise: Cover (oder Verlaufs-Platzhalter mit Typ-Emoji), Titel, Ziel + Land,
/// Zeitraum + Dauer, Typ-/Status-Pille und Countdown.
///
/// Kurz- und Wochenendtrips bekommen ein kompakteres Layout, eine eigene Pille und einen
/// eigenen Farbstreifen — sie sollen sich auf den ersten Blick von einer längeren Reise
/// unterscheiden.
struct ReiseKachel: View {
    let reise: ReiseInfo
    /// Im Segment „Vergangen" ist der Status redundant (alle sind vergangen) → dort aus.
    var zeigeStatus: Bool = true

    private var kompakt: Bool { reise.istKurztrip }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            cover
            VStack(alignment: .leading, spacing: 4) {
                Text(reise.titel)
                    .font(kompakt ? Font.subheadline.weight(.semibold) : Font.headline)
                    .lineLimit(2)
                if !reise.ortText.isEmpty {
                    Text("📍 " + reise.ortText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                if let z = reise.zeitraum {
                    // Jahresübergreifende Zeiträume („28. Dezember 2026 - 3. Januar 2027 · 6 Nächte")
                    // sind breiter als die Karte. Lieber leicht kleiner setzen als das Enddatum
                    // abschneiden — bei einem Datum kostet die Ellipse die Aussage.
                    Text(reise.dauer.map { z + " · " + $0 } ?? z)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                pillen
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .padding(.leading, 4)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .leading) {
            // Farbstreifen: Kurztrip vs. längere Reise ist damit schon beim Überfliegen sichtbar.
            Rectangle().fill(reise.typFarbe).frame(width: 5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
    }

    /// Viele Reisen haben kein Cover — dann tritt der Bereichsverlauf mit dem Typ-Emoji an.
    private var cover: some View {
        Group {
            if let pfad = reise.coverPfad {
                // Karten-Cover bis 96x74 pt — mittlere Stufe; das Reise-Detail zeigt das Original.
                AuthImage(path: pfad, contentMode: .fill, thumb: 320)
            } else {
                Palette.gradient(for: "reisen").opacity(0.85)
                    .overlay(Text(reise.typEmoji).font(kompakt ? .title3 : .title))
            }
        }
        .frame(width: kompakt ? 62 : 96, height: kompakt ? 62 : 74)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var pillen: some View {
        // FlowLayout statt HStack: Typ + Status + Countdown/Datumshinweis brauchen zusammen mehr
        // Breite, als in der Karte übrig ist (neben dem Cover bleiben je nach Layout nur rund
        // 200–240 pt). In einer HStack würde SwiftUI den Fehlbetrag auf die Pillen verteilen —
        // „Datum liegt zurück" bräche innerhalb der Kapsel um, „Geplant" bekäme drei Punkte.
        // Das Flow-Layout lässt jeder Pille ihre Breite und schiebt die überzählige in die
        // zweite Zeile; das trägt auch bei größerer Dynamic Type und auf schmalen Geräten.
        FlowLayout(spacing: 6) {
            Pill(text: reise.typPille, color: reise.typFarbe)
            if zeigeStatus && !reise.status.isEmpty {
                Pill(text: ReiseText.statusLabel(reise.status),
                     color: ReiseText.statusFarbe(reise.status), filled: false)
            }
            if let c = ReiseText.countdown(reise.tageBisStart) {
                Pill(text: c, systemImage: "hourglass", color: Palette.colors(for: "reisen").first ?? Theme.accent)
            } else if reise.datumHinweis {
                // Hilfreich, nicht bevormundend: der Status des Nutzers bleibt, wie er ist.
                Pill(text: "Datum liegt zurück", systemImage: "clock.badge.exclamationmark",
                     color: Color(hex: "94A3B8"), filled: false)
            }
        }
        .padding(.top, 1)
    }
}
