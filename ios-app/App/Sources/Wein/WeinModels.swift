import SwiftUI

// Native Wein-Modelle. Backend = generische v1-Ressourcen `/api/v1/weine`, `/wein-bewertungen`,
// `/wein-preise` (Envelope `{data:[…],total}`) plus die Sonderrouten `/wein-scan`, `/wein-lookup`,
// `/wein-bewertung`, `/wein-preischeck`, `/wein-einstellungen`.
// Werte kommen snake_case, Booleans als 0/1, die JSON-Array-Spalten (rebsorten/aromen/
// auszeichnungen) als JSON-STRING. Decodierung durchgaengig tolerant ueber `Coerce`.

// MARK: - Weintyp (CHECK typ IN (...))

enum WeinTyp: String, CaseIterable, Identifiable {
    case rot, weiss, rose, sekt, champagner, schaumwein, dessert, port, sonstiges

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rot:         return "Rotwein"
        case .weiss:       return "Weißwein"
        case .rose:        return "Rosé"
        case .sekt:        return "Sekt"
        case .champagner:  return "Champagner"
        case .schaumwein:  return "Schaumwein"
        case .dessert:     return "Dessertwein"
        case .port:        return "Portwein"
        case .sonstiges:   return "Sonstiges"
        }
    }

    var emoji: String {
        switch self {
        case .rot:         return "🍷"
        case .weiss:       return "🥂"
        case .rose:        return "🌸"
        case .sekt:        return "🍾"
        case .champagner:  return "🍾"
        case .schaumwein:  return "🫧"
        case .dessert:     return "🍯"
        case .port:        return "🥃"
        case .sonstiges:   return "🍇"
        }
    }

    /// Badge-Farbe. Die Textfarbe leitet `Color.onFill` aus der Helligkeit ab — hier stehen deshalb
    /// nur Werte, die zusammen mit der daraus gewählten Schrift mindestens 4,5:1 erreichen (AA für
    /// Normaltext; `Pill` rendert mit .caption2 = 11 pt).
    /// Die vier hellsten Töne (Weißwein, Rosé, Champagner, Schaumwein) waren dafür zu hell und sind
    /// je eine Stufe abgedunkelt — vorher lagen sie bei 2,8:1 bis 3,5:1 und damit unter dem Minimum.
    var farbe: Color {
        switch self {
        case .rot:         return Color(hex: "B91C1C")   // 6,5:1 auf Weiß
        case .weiss:       return Color(hex: "7A6A0A")   // war CA8A04 (2,9:1) → 5,4:1
        case .rose:        return Color(hex: "BE185D")   // war EC4899 (3,5:1) → 6,0:1
        case .sekt:        return Color(hex: "F59E0B")   // hell → schwarze Schrift, 9,8:1
        case .champagner:  return Color(hex: "B45309")   // war D97706 (3,2:1) → 5,0:1
        case .schaumwein:  return Color(hex: "0369A1")   // war 0EA5E9 (2,8:1) → 5,9:1
        case .dessert:     return Color(hex: "A16207")   // 4,9:1 auf Weiß
        case .port:        return Color(hex: "7C2D12")   // 9,4:1 auf Weiß
        case .sonstiges:   return Color(hex: "6B7280")   // 4,8:1 auf Weiß
        }
    }
}

// MARK: - Tabs, Sortierung

/// .alle = alles · .keller = bestand > 0 · .top = Schnitt >= 4 · .offen = von mir noch nicht bewertet.
enum WeinTab: Hashable { case alle, keller, top, offen }

enum WeinSort: String, CaseIterable {
    case neueste, bewertung, name, jahrgang, preis

    var label: String {
        switch self {
        case .neueste:   return "Neueste"
        case .bewertung: return "Bewertung"
        case .name:      return "Name"
        case .jahrgang:  return "Jahrgang"
        case .preis:     return "Preis"
        }
    }
}

// MARK: - Wein

struct Wein: Identifiable, Hashable {
    let id: Int
    var name: String
    var weingut: String
    var jahrgang: Int?                  // nil = jahrgangslos (viele Sekte/Champagner)
    var typ: WeinTyp
    var rebsorten: [String]
    var land: String?
    var region: String?
    var lage: String?
    var alkohol: Double?                // Volumenprozent
    var geschmacksrichtung: String      // trocken … unbekannt (CHECK)
    var suesse: Int?                    // Geschmacksprofil je 1..5, nil = unbekannt
    var saeure: Int?
    var tannin: Int?
    var koerper: Int?
    var aromen: [String]
    var serviertemperatur: String?
    var trinkfensterVon: Int?
    var trinkfensterBis: Int?
    var bio: Bool
    var vegan: Bool
    var flaschengroesseMl: Int
    var ean: String?
    var beschreibung: String?
    var auszeichnungen: [String]
    var speiseempfehlung: String?
    var referenzpreis: Double?          // typischer Ladenpreis = Basis der Rabattrechnung
    var besterPreis: Double?
    var besterPreisHaendler: String?
    var besterPreisURL: String?
    var preisGeprueftAt: String?
    var gekauftPreis: Double?
    var gekauftBei: String?
    var preisBeobachten: Bool
    var bestand: Int                    // Flaschen im Keller
    var lagerort: String?
    var fotoKey: String?                // Etikettenfoto (media area "wein")
    var quelle: String                  // manuell | foto | ean | ki
    var notizen: String?

    init(fields f: [String: Any]) {
        id = Coerce.int(f["id"]) ?? 0
        name = Coerce.str(f["name"]) ?? ""
        weingut = Coerce.str(f["weingut"]) ?? ""
        jahrgang = Coerce.int(f["jahrgang"])
        typ = WeinTyp(rawValue: Coerce.str(f["typ"]) ?? "") ?? .sonstiges
        rebsorten = Coerce.stringArray(f["rebsorten"])
        land = Coerce.str(f["land"])
        region = Coerce.str(f["region"])
        lage = Coerce.str(f["lage"])
        alkohol = Coerce.double(f["alkohol"])
        geschmacksrichtung = Coerce.str(f["geschmacksrichtung"]) ?? "unbekannt"
        suesse = Coerce.int(f["suesse"])
        saeure = Coerce.int(f["saeure"])
        tannin = Coerce.int(f["tannin"])
        koerper = Coerce.int(f["koerper"])
        aromen = Coerce.stringArray(f["aromen"])
        serviertemperatur = Coerce.str(f["serviertemperatur"])
        trinkfensterVon = Coerce.int(f["trinkfenster_von"])
        trinkfensterBis = Coerce.int(f["trinkfenster_bis"])
        bio = Coerce.bool(f["bio"])
        vegan = Coerce.bool(f["vegan"])
        flaschengroesseMl = Coerce.int(f["flaschengroesse_ml"]) ?? 750
        ean = Coerce.str(f["ean"])
        beschreibung = Coerce.str(f["beschreibung"])
        auszeichnungen = Coerce.stringArray(f["auszeichnungen"])
        speiseempfehlung = Coerce.str(f["speiseempfehlung"])
        referenzpreis = Coerce.double(f["referenzpreis"])
        besterPreis = Coerce.double(f["bester_preis"])
        besterPreisHaendler = Coerce.str(f["bester_preis_haendler"])
        besterPreisURL = Coerce.str(f["bester_preis_url"])
        preisGeprueftAt = Coerce.str(f["preis_geprueft_at"])
        gekauftPreis = Coerce.double(f["gekauft_preis"])
        gekauftBei = Coerce.str(f["gekauft_bei"])
        preisBeobachten = Coerce.bool(f["preis_beobachten"])
        bestand = Coerce.int(f["bestand"]) ?? 0
        lagerort = Coerce.str(f["lagerort"])
        fotoKey = Coerce.str(f["foto_key"])
        quelle = Coerce.str(f["quelle"]) ?? "manuell"
        notizen = Coerce.str(f["notizen"])
    }

    /// Body fuer POST/PATCH: DB-Spaltennamen, Arrays als JSON-String, nil als NSNull (damit
    /// Felder im Formular auch geleert werden koennen).
    /// BEWUSST NICHT enthalten: bester_preis*, preis_geprueft_at (setzt der Preischeck-Job) und
    /// id/created_at/updated_at.
    var patchFields: [String: Any] {
        // Schrittweise aufgebaut (kein grosses Dictionary-Literal) — das haelt den Swift-Typechecker
        // schnell und die Zuordnung Spalte/Wert lesbar.
        var d: [String: Any] = [:]
        d["name"] = name
        d["weingut"] = weingut
        d["jahrgang"] = jahrgang ?? NSNull()
        d["typ"] = typ.rawValue
        d["rebsorten"] = WeinFormat.jsonArray(rebsorten)
        d["land"] = land ?? NSNull()
        d["region"] = region ?? NSNull()
        d["lage"] = lage ?? NSNull()
        d["alkohol"] = alkohol ?? NSNull()
        d["geschmacksrichtung"] = geschmacksrichtung
        d["suesse"] = suesse ?? NSNull()
        d["saeure"] = saeure ?? NSNull()
        d["tannin"] = tannin ?? NSNull()
        d["koerper"] = koerper ?? NSNull()
        d["aromen"] = WeinFormat.jsonArray(aromen)
        d["serviertemperatur"] = serviertemperatur ?? NSNull()
        d["trinkfenster_von"] = trinkfensterVon ?? NSNull()
        d["trinkfenster_bis"] = trinkfensterBis ?? NSNull()
        d["bio"] = bio ? 1 : 0
        d["vegan"] = vegan ? 1 : 0
        d["flaschengroesse_ml"] = flaschengroesseMl
        d["ean"] = ean ?? NSNull()
        d["beschreibung"] = beschreibung ?? NSNull()
        d["auszeichnungen"] = WeinFormat.jsonArray(auszeichnungen)
        d["speiseempfehlung"] = speiseempfehlung ?? NSNull()
        d["referenzpreis"] = referenzpreis ?? NSNull()
        d["gekauft_preis"] = gekauftPreis ?? NSNull()
        d["gekauft_bei"] = gekauftBei ?? NSNull()
        d["preis_beobachten"] = preisBeobachten ? 1 : 0
        d["bestand"] = bestand
        d["lagerort"] = lagerort ?? NSNull()
        d["foto_key"] = fotoKey ?? NSNull()
        d["quelle"] = quelle
        d["notizen"] = notizen ?? NSNull()
        return d
    }

    /// Anzeigename: "Weingut Name Jahrgang" (leere Teile entfallen).
    var titel: String {
        var teile: [String] = []
        if !weingut.isEmpty { teile.append(weingut) }
        if !name.isEmpty { teile.append(name) }
        if let j = jahrgang { teile.append(String(j)) }
        return teile.isEmpty ? "Wein" : teile.joined(separator: " ")
    }

    /// Ersparnis gegenueber dem Referenzpreis in Prozent. nil = kein Preisvorteil bzw. Daten fehlen.
    var rabattProzent: Double? {
        guard let ref = referenzpreis, ref > 0, let best = besterPreis, best < ref else { return nil }
        return (ref - best) / ref * 100
    }

    /// Liegt das aktuelle Jahr im Trinkfenster? Ohne Fenster-Angabe false (unbekannt).
    var istTrinkreif: Bool {
        let jahr = Calendar.current.component(.year, from: Date())
        switch (trinkfensterVon, trinkfensterBis) {
        case let (von?, bis?): return jahr >= von && jahr <= bis
        case let (von?, nil):  return jahr >= von
        case let (nil, bis?):  return jahr <= bis
        default: return false
        }
    }

    /// Auth-faehiger Media-Pfad des Etikettenfotos (fuer `AuthImage`).
    var imagePath: String? {
        guard let k = fotoKey, !k.isEmpty else { return nil }
        return mediaURLPath(fromKey: k)
    }
}

// MARK: - Bewertung (genau eine je Wein und Person)

struct WeinBewertung: Identifiable, Hashable {
    let id: Int
    var weinId: Int
    var owner: String          // lars | elita
    var sterne: Int            // 1..5
    var kommentar: String

    init(fields f: [String: Any]) {
        weinId = Coerce.int(f["wein_id"]) ?? 0
        owner = Coerce.str(f["owner"]) ?? ""
        sterne = Coerce.int(f["sterne"]) ?? 0
        kommentar = Coerce.str(f["kommentar"]) ?? ""
        // /wein-lookup liefert Bewertungen OHNE id → stabile Ersatz-ID je Person, damit ForEach
        // nicht zwei Eintraege mit id 0 sieht.
        if let realId = Coerce.int(f["id"]), realId > 0 { id = realId }
        else { id = owner == "elita" ? -2 : -1 }
    }

    /// Anzeigename der Person.
    var personName: String {
        switch owner {
        case "lars": return "Lars"
        case "elita": return "Elita"
        default: return owner.isEmpty ? "Unbekannt" : owner
        }
    }
}

// MARK: - Preis-Historie

struct WeinPreis: Identifiable, Hashable {
    let id: Int
    var weinId: Int
    var preis: Double
    var haendler: String
    var url: String?
    var gefundenAt: String

    init(fields f: [String: Any]) {
        id = Coerce.int(f["id"]) ?? 0
        weinId = Coerce.int(f["wein_id"]) ?? 0
        preis = Coerce.double(f["preis"]) ?? 0
        haendler = Coerce.str(f["haendler"]) ?? ""
        url = Coerce.str(f["url"])
        gefundenAt = Coerce.str(f["gefunden_at"]) ?? ""
    }

    var linkURL: URL? {
        guard let u = url, !u.isEmpty else { return nil }
        return URL(string: u.hasPrefix("http") ? u : "https://\(u)")
    }
}

/// Einzelner Preisfund aus `/wein-scan` bzw. `/wein-preischeck` (noch nicht gespeichert).
struct WeinPreisTreffer: Hashable {
    var preis: Double
    var haendler: String
    var url: String?
}

extension WeinPreisTreffer {
    init(fields f: [String: Any]) {
        preis = Coerce.double(f["preis"]) ?? 0
        haendler = Coerce.str(f["haendler"]) ?? ""
        url = Coerce.str(f["url"])
    }

    var linkURL: URL? {
        guard let u = url, !u.isEmpty else { return nil }
        return URL(string: u.hasPrefix("http") ? u : "https://\(u)")
    }
}

// MARK: - Erfassungs-Vorschlag (POST /wein-scan)

/// Vorhandener Wein, den der Scan als Dublette erkannt hat (inkl. bereits abgegebener Bewertungen).
struct WeinDublette {
    var id: Int
    var titel: String
    var bewertungen: [WeinBewertung]
}

extension WeinDublette {
    init?(object o: [String: Any]?) {
        guard let o, let i = Coerce.int(o["id"]), i > 0 else { return nil }
        id = i
        titel = Coerce.str(o["titel"]) ?? "Wein"
        bewertungen = ((o["bewertungen"] as? [[String: Any]]) ?? []).map(WeinBewertung.init(fields:))
    }
}

/// Antwort des Scans: fertige Feldwerte (DB-Spaltennamen) + Recherche-Beiwerk. Speichert nichts.
struct WeinVorschlag {
    var felder: [String: Any]
    var preise: [WeinPreisTreffer]
    var quellen: [String]
    var confidence: String        // hoch | mittel | niedrig | unbekannt
    var hinweise: [String]
    var dublette: WeinDublette?
}

extension WeinVorschlag {
    /// Vertraegt BEIDE Antwortformen: `/wein-scan` liefert das Beiwerk (preise/quellen/confidence/
    /// hinweise) auf oberster Ebene, `/wein-lookup` je nach Backend-Stand gar nicht. Was fehlt,
    /// wird zur leeren Liste bzw. faellt auf die Werte zurueck, die IM Vorschlag stehen — nie auf
    /// einen erfundenen Zustand (siehe `confidence`).
    init(object o: [String: Any]) {
        felder = (o["vorschlag"] as? [String: Any]) ?? [:]
        quellen = Coerce.stringArray(o["quellen"])
        hinweise = Coerce.stringArray(o["hinweise"])
        dublette = WeinDublette(object: o["dublette"] as? [String: Any])

        // Fehlt die Angebotsliste, steht der guenstigste Fund immer noch als `bester_preis*` im
        // Vorschlag selbst — daraus wird ein einzelner Treffer, statt gar keinen Preis zu zeigen.
        let obenPreise = ((o["preise"] as? [[String: Any]]) ?? []).map(WeinPreisTreffer.init(fields:))
        if !obenPreise.isEmpty {
            preise = obenPreise
        } else if let p = Coerce.double(felder["bester_preis"]), p > 0 {
            preise = [WeinPreisTreffer(preis: p,
                                       haendler: Coerce.str(felder["bester_preis_haendler"]) ?? "",
                                       url: Coerce.str(felder["bester_preis_url"]))]
        } else {
            preise = []
        }

        // Fehlt die Confidence oben, hat das Backend sie als `ki_confidence` in den Vorschlag
        // geschrieben. Ist sie nirgends zu finden, ist sie UNBEKANNT — nicht "niedrig": ein
        // Default-Wert wuerde jeden Vorschlag faelschlich als unsicher brandmarken.
        confidence = Coerce.str(o["confidence"])
            ?? Coerce.str(felder["ki_confidence"])
            ?? "unbekannt"
    }

    /// Vorschlag als Wein-Objekt (fuer Vorschau/Formular-Vorbelegung).
    var alsWein: Wein { Wein(fields: felder) }

    var confidenceLabel: String {
        switch confidence {
        case "hoch":    return "Sicher erkannt"
        case "mittel":  return "Wahrscheinlich richtig"
        case "niedrig": return "Unsicher, bitte prüfen"
        default:        return "Ungeprüft"
        }
    }

    var confidenceFarbe: Color {
        switch confidence {
        case "hoch":    return Color(hex: "22C55E")
        case "mittel":  return Color(hex: "F59E0B")
        case "niedrig": return Color(hex: "EF4444")
        default:        return Color(hex: "6B7280")   // unbekannt = neutral, kein Alarmrot
        }
    }
}

// MARK: - Einkaufs-Scan (GET /wein-lookup)

struct WeinLookup {
    var known: Bool
    var wein: Wein?
    var bewertungen: [WeinBewertung]
    var schnitt: Double?
    var vorschlag: WeinVorschlag?
}

extension WeinLookup {
    init(object o: [String: Any]) {
        known = Coerce.bool(o["known"])
        wein = (o["wein"] as? [String: Any]).map(Wein.init(fields:))
        bewertungen = ((o["bewertungen"] as? [[String: Any]]) ?? []).map(WeinBewertung.init(fields:))
        schnitt = Coerce.double(o["schnitt"])
        // Der Vorschlag steckt unter "vorschlag". Das Beiwerk (preise/quellen/confidence/hinweise)
        // liegt — wenn die Route es liefert — auf oberster Ebene → das ganze Objekt weiterreichen.
        // `WeinVorschlag.init(object:)` kommt auch ohne das Beiwerk zurecht.
        let felder = (o["vorschlag"] as? [String: Any]) ?? [:]
        vorschlag = felder.isEmpty ? nil : WeinVorschlag(object: o)
    }
}

// MARK: - Preischeck-Ergebnis (POST /wein-preischeck)

// ACHTUNG, andere Konvention als der Rest der Datei: diese Sonderroute serialisiert ihr
// TypeScript-Interface direkt, die Schluessel sind also camelCase (`weinId`, `rabattProzent`) und
// NICHT snake_case. Beide Schreibweisen werden gelesen, damit ein spaeterer Umbau nicht still bricht.

/// Ergebnis der Preisrecherche fuer EINEN Wein. Die Route liefert davon eine Liste — je geprueftem
/// Wein einen Eintrag; die eigentlichen Angebote liegen eine Ebene tiefer in `treffer`/`bester`.
struct WeinPreisErgebnis {
    var weinId: Int
    var titel: String
    var treffer: [WeinPreisTreffer]
    /// Guenstigstes Angebot, bereits serverseitig ermittelt (fehlt, wenn nichts gefunden wurde).
    var bester: WeinPreisTreffer?
    var referenzpreis: Double?
    var rabattProzent: Double?
    /// Klartext-Grund, wenn nichts Verwertbares herauskam (fehlender API-Key, Anbieter nicht
    /// erreichbar, Angebote nicht auswertbar …).
    var fehler: String?
}

extension WeinPreisErgebnis {
    init(object o: [String: Any]) {
        weinId = Coerce.int(o["weinId"]) ?? Coerce.int(o["wein_id"]) ?? 0
        titel = Coerce.str(o["titel"]) ?? ""
        treffer = ((o["treffer"] as? [[String: Any]]) ?? []).map(WeinPreisTreffer.init(fields:))
        bester = (o["bester"] as? [String: Any]).map(WeinPreisTreffer.init(fields:))
        referenzpreis = Coerce.double(o["referenzpreis"])
        rabattProzent = Coerce.double(o["rabattProzent"]) ?? Coerce.double(o["rabatt_prozent"])
        fehler = Coerce.str(o["fehler"])
    }

    /// Guenstigstes echtes Angebot dieses Weins. `bester` kommt vom Server, die Trefferliste ist
    /// die Absicherung, falls die Route ihn einmal weglaesst.
    var guenstigstes: WeinPreisTreffer? {
        var kandidaten = treffer
        if let b = bester { kandidaten.append(b) }
        return kandidaten.filter { $0.preis > 0 }.min { $0.preis < $1.preis }
    }
}

struct WeinPreischeckErgebnis {
    var geprueft: Int
    /// Ein Eintrag JE GEPRUEFTEM WEIN (Feld `treffer` der Route).
    var ergebnisse: [WeinPreisErgebnis]
    /// Teilmenge davon, die die eingestellte Rabattschwelle erreicht.
    var rabatte: [WeinPreisErgebnis]
    /// Klartext-Grund fuer den Nutzer, wenn nichts gefunden wurde — sonst bleibt ein fehlender
    /// PERPLEXITY_API_KEY von einem echten Nulltreffer ununterscheidbar.
    var fehler: String?
}

extension WeinPreischeckErgebnis {
    init(object o: [String: Any]) {
        geprueft = Coerce.int(o["geprueft"]) ?? 0
        ergebnisse = ((o["treffer"] as? [[String: Any]]) ?? []).map(WeinPreisErgebnis.init(object:))
        rabatte = ((o["rabatte"] as? [[String: Any]]) ?? []).map(WeinPreisErgebnis.init(object:))
        // Erster Klartext-Grund aus den Einzelergebnissen, ersatzweise der Hinweis der Route
        // (z. B. "Kein Wein geprueft — es ist gerade keiner faellig").
        fehler = ergebnisse.compactMap { $0.fehler }.first ?? Coerce.stringArray(o["hinweise"]).first
    }

    /// Guenstigster gefundener Preis ueber alle geprueften Weine (fuer die Rueckmeldung im Toast).
    var bester: WeinPreisTreffer? {
        ergebnisse.compactMap { $0.guenstigstes }.min { $0.preis < $1.preis }
    }
}

// MARK: - Einstellungen des Preis-Wächters (GET|PUT /wein-einstellungen)

struct WeinEinstellungen: Hashable {
    var intervallTage: Int = 7      // 1..90
    var rabattProzent: Int = 20     // 5..80
    var pushAktiv: Bool = true

    init() {}

    init(object o: [String: Any]) {
        intervallTage = Coerce.int(o["intervall_tage"]) ?? 7
        rabattProzent = Coerce.int(o["rabatt_prozent"]) ?? 20
        pushAktiv = Coerce.bool(o["push_aktiv"])
    }

    var body: [String: Any] {
        ["intervall_tage": intervallTage, "rabatt_prozent": rabattProzent, "push_aktiv": pushAktiv]
    }
}

// MARK: - Formatierung (an EINER Stelle, damit Karte/Detail/Formular gleich aussehen)

enum WeinFormat {
    private static let preisFmt: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "de_DE")
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    private static let parseFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

    private static let displayFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yyyy"
        f.locale = Locale(identifier: "de_DE")
        f.timeZone = .current
        return f
    }()

    /// "12,90 €" — nil, wenn kein Preis bekannt ist.
    static func preis(_ v: Double?) -> String? {
        guard let v else { return nil }
        let s = preisFmt.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v)
        return "\(s) €"
    }

    /// "20 %" (kaufmaennisch gerundet) — nil, wenn nichts zu zeigen ist.
    static func prozent(_ v: Double?) -> String? {
        guard let v else { return nil }
        return "\(String(Int(v.rounded()))) %"
    }

    /// "4,3" fuer Sterne-Schnitte — nil ohne Bewertung.
    static func schnitt(_ v: Double?) -> String? {
        guard let v else { return nil }
        return String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",")
    }

    /// "yyyy-MM-dd" oder ISO-Zeitstempel → "dd.MM.yyyy".
    static func datum(_ iso: String?) -> String? {
        guard let iso, iso.count >= 10, let d = parseFmt.date(from: String(iso.prefix(10))) else { return nil }
        return displayFmt.string(from: d)
    }

    /// Alkohol "13,5 % vol" — nil ohne Angabe.
    static func alkohol(_ v: Double?) -> String? {
        guard let v, v > 0 else { return nil }
        return String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",") + " % vol"
    }

    /// Flaschengroesse "0,75 l" bzw. "1,5 l".
    static func flasche(_ ml: Int) -> String {
        let liter = Double(ml) / 1000
        return String(format: "%.2f", liter).replacingOccurrences(of: ".", with: ",") + " l"
    }

    /// [String] → JSON-String fuer die JSON-Array-Spalten (leer = "[]").
    static func jsonArray(_ items: [String]) -> String {
        let clean = items.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !clean.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: clean),
              let s = String(data: data, encoding: .utf8) else { return "[]" }
        return s
    }

    /// Kommaliste ("Merlot, Cabernet") in Einzelwerte zerlegen (Formular-Eingabe).
    static func splitListe(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - Geschmacksrichtungen (CHECK geschmacksrichtung IN (...))

enum WeinGeschmack {
    /// Feste Reihenfolge fuer den Picker im Formular (identisch zum CHECK der Migration).
    static let alle = [
        "trocken", "halbtrocken", "feinherb", "lieblich", "suess",
        "brut nature", "extra brut", "brut", "extra dry", "sec", "demi-sec", "unbekannt",
    ]

    static func label(_ key: String) -> String {
        switch key {
        case "suess": return "Süß"
        case "unbekannt": return "Unbekannt"
        default: return key.prefix(1).uppercased() + String(key.dropFirst())
        }
    }
}
