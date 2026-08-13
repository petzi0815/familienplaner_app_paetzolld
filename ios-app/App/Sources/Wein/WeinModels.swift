import SwiftUI

// Native Wein-Modelle. Backend = generische v1-Ressourcen `/api/v1/weine`, `/wein-bewertungen`,
// `/wein-preise` (Envelope `{data:[…],total}`) plus die Sonderrouten `/wein-scan`, `/wein-lookup`,
// `/wein-bewertung`, `/wein-preischeck`, `/wein-einstellungen`.
// Werte kommen snake_case, Booleans als 0/1, die JSON-Array-Spalten (rebsorten/aromen/
// auszeichnungen/cocktails) als JSON-STRING. Decodierung durchgaengig tolerant ueber `Coerce`.
//
// WARUM der Typ weiterhin `Wein` heisst, obwohl er seit Migration 0022 AUCH Spirituosen traegt:
// Tabelle (`weine`), Routen (`/api/v1/wein-*`), Registry-Key und Bereichs-Key bleiben unveraendert.
// An ihnen haengt die bereits installierte App (Build 58), die nach dem Deploy weiterlaufen muss;
// ein Umbenennen waere eine grosse, riskante Aenderung ohne fachlichen Gewinn. Beide Getraenkearten
// liegen bewusst in EINER Tabelle — Bewertung je Person, Preis-Historie, Preis-Waechter, Keller,
// Einkaufs-Scan und Dublettenerkennung sind fuer Whisky und Barolo identisch. Unterschieden werden
// sie ausschliesslich ueber `Wein.art`; nur die ANZEIGE-Texte heissen „Wein & Spirituosen".

// MARK: - Getraenkeart (CHECK art IN ('wein','spirituose'))

/// Die eine Unterscheidung, an der alles haengt: Umschalter, Filter, Erfassungsmaske, Detailseite
/// und `Wein.patchFields`. Bestandszeilen ohne Wert sind Weine (Default der Migration).
enum GetraenkeArt: String, CaseIterable, Identifiable {
    case wein, spirituose

    var id: String { rawValue }

    /// Mehrzahl — Umschalter, Ueberschriften, Zaehler ("8 Spirituosen").
    var label: String {
        switch self {
        case .wein:       return "Wein"
        case .spirituose: return "Spirituosen"
        }
    }

    /// Einzahl — Meldungen und Menue-Eintraege ("Spirituose erfassen", "Wein gespeichert").
    var einzahl: String {
        switch self {
        case .wein:       return "Wein"
        case .spirituose: return "Spirituose"
        }
    }

    var emoji: String {
        switch self {
        case .wein:       return "🍷"
        case .spirituose: return "🥃"
        }
    }
}

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

// MARK: - Spirituosen-Kategorie (CHECK kategorie IN (...)), nur bei art == .spirituose

/// Reihenfolge = Reihenfolge des CHECK in Migration 0022; Filter-Pills und Picker zeigen sie genau
/// so. `sonstiges` steht bewusst am Ende (Auffangwert, keine eigene Warengruppe).
enum SpirituosenKategorie: String, CaseIterable, Identifiable {
    case whisky, gin, rum, wodka, tequila, mezcal, cognac, brandy
    case grappa, obstbrand, likoer, aperitif, wermut, absinth, sonstiges

    var id: String { rawValue }

    var label: String {
        switch self {
        case .whisky:    return "Whisky"
        case .gin:       return "Gin"
        case .rum:       return "Rum"
        case .wodka:     return "Wodka"
        case .tequila:   return "Tequila"
        case .mezcal:    return "Mezcal"
        case .cognac:    return "Cognac"
        case .brandy:    return "Brandy"
        case .grappa:    return "Grappa"
        case .obstbrand: return "Obstbrand"
        case .likoer:    return "Likör"
        case .aperitif:  return "Aperitif"
        case .wermut:    return "Wermut"
        case .absinth:   return "Absinth"
        case .sonstiges: return "Sonstiges"
        }
    }

    var emoji: String {
        switch self {
        case .whisky:    return "🥃"
        case .gin:       return "🍸"
        case .rum:       return "🏝️"
        case .wodka:     return "🧊"
        case .tequila:   return "🌵"
        case .mezcal:    return "🔥"
        case .cognac:    return "🛢️"
        case .brandy:    return "🍐"
        case .grappa:    return "🍇"
        case .obstbrand: return "🍒"
        case .likoer:    return "🍯"
        case .aperitif:  return "🍊"
        case .wermut:    return "🌿"
        case .absinth:   return "🧚"
        case .sonstiges: return "🍶"
        }
    }

    /// Badge-Farbe, gleiche Regel wie `WeinTyp.farbe`: `Color.onFill` waehlt die Schrift anhand der
    /// Helligkeit, hier stehen deshalb nur Toene, die zusammen mit dieser Schrift mindestens 4,5:1
    /// erreichen (AA für Normaltext; `Pill` rendert mit .caption2 = 11 pt).
    /// Alle fünfzehn liegen unter der Hell-Schwelle → durchgehend weiße Schrift; der knappste Wert
    /// ist Sonstiges mit 4,8:1. Nicht ändern, ohne den Kontrast nachzurechnen.
    var farbe: Color {
        switch self {
        case .whisky:    return Color(hex: "92400E")   // 7,1:1
        case .gin:       return Color(hex: "0F766E")   // 5,5:1
        case .rum:       return Color(hex: "9A3412")   // 7,3:1
        case .wodka:     return Color(hex: "334155")   // 10,4:1
        case .tequila:   return Color(hex: "4D7C0F")   // 5,0:1
        case .mezcal:    return Color(hex: "3F6212")   // 7,1:1
        case .cognac:    return Color(hex: "B45309")   // 5,0:1
        case .brandy:    return Color(hex: "A16207")   // 4,9:1
        case .grappa:    return Color(hex: "15803D")   // 5,0:1
        case .obstbrand: return Color(hex: "BE185D")   // 6,0:1
        case .likoer:    return Color(hex: "7E22CE")   // 7,0:1
        case .aperitif:  return Color(hex: "C2410C")   // 5,2:1
        case .wermut:    return Color(hex: "9F1239")   // 8,0:1
        case .absinth:   return Color(hex: "166534")   // 7,1:1
        case .sonstiges: return Color(hex: "6B7280")   // 4,8:1 — knappster Wert der Reihe
        }
    }
}

// MARK: - Standort (CHECK standort IN ('zuhause','buero'))

/// WO die Flasche steht — Gebaeude, nicht Regal. `lagerort` beantwortet weiterhin „welches Regal"
/// (Bar, Keller Regal 2), `standort` beantwortet „welches Haus"; beides gilt nebeneinander
/// („im Buero, dort im Schrank links"). Als Freitext in `lagerort` waere daraus weder ein
/// verlaessliches Abzeichen noch ein Filter noch eine eigene Keller-Gruppe zu machen, und ein
/// Tippfehler (Buero/Büro) wuerde die Flasche unauffindbar machen — genau das soll das Feature
/// verhindern.
/// Die SPALTE gilt fuer beide Getraenkearten (kostet nichts, haelt den Weg offen), die
/// BEDIENELEMENTE zeigen nur die Spirituosen: geparkt wird in der Praxis dort, weil zu Hause der
/// Platz fehlt. Bestandszeilen ohne Wert stehen zu Hause (Default der Migration 0023).
enum WeinStandort: String, CaseIterable, Identifiable {
    case zuhause, buero

    var id: String { rawValue }

    /// Ausgeschrieben — Detailzeile, Menue-Eintraege, Auswahl im Erfassen-Formular.
    var label: String {
        switch self {
        case .zuhause: return "Zu Hause"
        case .buero:   return "Im Büro"
        }
    }

    /// Kurzform fuer enge Stellen (Abzeichen auf Karte und Kellerzeile, Filter-Pille).
    var kurz: String {
        switch self {
        case .zuhause: return "Zuhause"
        case .buero:   return "Büro"
        }
    }

    var emoji: String {
        switch self {
        case .zuhause: return "🏠"
        case .buero:   return "🏢"
        }
    }

    /// SF Symbol fuer Knoepfe und Menues.
    var symbol: String {
        switch self {
        case .zuhause: return "house"
        case .buero:   return "building.2"
        }
    }
}

// MARK: - Zustand der Hintergrund-Erkennung (CHECK ki_status IN ('offen','laeuft','fertig','fehler'))

/// Die Schnellerfassung legt die Flasche SOFORT an und laesst die KI danach im Hintergrund laufen —
/// `ki_status` ist der Fortschritt dieses Laufs. Bestand, von Hand angelegte Flaschen und die alte
/// App gelten als 'fertig' (Default der Migration 0024); nur die drei uebrigen Werte bedeuten Arbeit.
enum WeinKiStatus: String, CaseIterable, Identifiable {
    case offen, laeuft, fertig, fehler

    var id: String { rawValue }

    /// Klartext fuer Abzeichen und Warteschlangen-Zeile. 'offen' und 'laeuft' lesen sich BEWUSST
    /// gleich: fuer den Nutzer ist "eingereiht" und "gerade dran" derselbe Zustand ("es passiert
    /// etwas, warte kurz"), und ein Unterschied waere nur eine Erklaerung, die niemand braucht.
    /// 'fertig' hat trotzdem einen Text — er erscheint nirgends als Abzeichen, aber eine leere
    /// Beschriftung waere eine Falle fuer jede spaetere Aufrufstelle.
    var label: String {
        switch self {
        case .offen, .laeuft: return "Wird erkannt …"
        case .fertig:         return "Erkannt"
        case .fehler:         return "Erkennung fehlgeschlagen"
        }
    }

    /// Badge-Farbe, gleiche Regel wie `WeinTyp.farbe`: `Color.onFill` waehlt die Schrift anhand der
    /// Helligkeit, hier stehen deshalb nur Toene, die damit mindestens 4,5:1 erreichen.
    /// Laufende Erkennung ist NEUTRAL (kein Warnton) — sie ist der Normalfall der Schnellerfassung
    /// und kein Problem, das Aufmerksamkeit verlangt.
    var farbe: Color {
        switch self {
        case .offen, .laeuft: return Color(hex: "6B7280")   // 4,8:1 — neutral, kein Alarm
        case .fertig:         return Color(hex: "15803D")   // 5,0:1
        case .fehler:         return Color(hex: "B91C1C")   // 6,5:1
        }
    }

    /// SF Symbol fuer Abzeichen und Warteschlangen-Zeile.
    var symbol: String {
        switch self {
        case .offen, .laeuft: return "sparkles"
        case .fertig:         return "checkmark.circle"
        case .fehler:         return "exclamationmark.triangle"
        }
    }
}

// MARK: - Tabs, Sortierung

/// .alle = alles · .keller = bestand > 0 · .top = Schnitt >= 4 · .offen = von mir noch nicht bewertet ·
/// .queue = Flaschen, deren Hintergrund-Erkennung noch laeuft oder fehlgeschlagen ist.
/// Das Queue-Segment erscheint nur, solange es dort etwas zu tun gibt (siehe WeinRootView) — im
/// Alltag bleibt die Segmentleiste dadurch unveraendert.
enum WeinTab: Hashable { case alle, keller, top, offen, queue }

enum WeinSort: String, CaseIterable {
    case neueste, bewertung, name, jahrgang, preis

    /// Beschriftung fuer Wein — unveraendert, damit bestehende Aufrufstellen weiter passen.
    var label: String { label(for: .wein) }

    /// Art-abhaengige Beschriftung: Spirituosen haben keinen Jahrgang, sondern eine Altersangabe —
    /// derselbe Sortierfall heisst dort „Alter". Der ROHWERT bleibt `jahrgang`, damit eine einmal
    /// gewaehlte Sortierung den Umschalter zwischen den Arten ueberlebt.
    func label(for art: GetraenkeArt) -> String {
        switch self {
        case .neueste:   return "Neueste"
        case .bewertung: return "Bewertung"
        case .name:      return "Name"
        case .jahrgang:  return art == .spirituose ? "Alter" : "Jahrgang"
        case .preis:     return "Preis"
        }
    }
}

// MARK: - Wein

struct Wein: Identifiable, Hashable {
    let id: Int
    var art: GetraenkeArt               // wein | spirituose — bestimmt Maske, Filter und Anzeige
    var name: String
    var weingut: String                 // bei Spirituosen die Destillerie bzw. Marke
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
    // Nur Spirituosen (bei Weinen durchgaengig nil bzw. leer) — `patchFields` schickt sie
    // entsprechend auch nur bei art == .spirituose mit.
    var kategorie: SpirituosenKategorie? // nil = keine der 15 Kategorien erkannt
    var stil: String?                   // Unterart, z.B. "Single Malt Islay", "London Dry"
    var alterJahre: Int?                // Altersangabe; nil = ohne (NAS-Abfuellung)
    var fass: String?                   // Reifung/Finish, z.B. "Ex-Bourbon, Oloroso-Finish"
    var abgefuelltJahr: Int?            // Abfuelljahr (Single Cask/Batch), NICHT der Jahrgang
    var trinkempfehlung: String?        // "pur", "on the rocks", "Gin Tonic mit …"
    var cocktails: [String]
    // Fuer beide Arten gueltig — auch eine Weinflasche wird geoeffnet; gepflegt wird es in der
    // Praxis vor allem an der Bar.
    var angebrochenAt: String?          // ISO-Datum des Oeffnens; nil = ungeoeffnet
    var fuellstandProzent: Int?         // 0..100; nil = nie erfasst (NICHT 0 raten)
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
    var lagerort: String?               // Regal/Fach — WO GENAU, unabhaengig vom Gebaeude
    var standort: WeinStandort          // Gebaeude: zu Hause oder im Buero geparkt
    var fotoKey: String?                // Etikettenfoto (media area "wein")
    var quelle: String                  // manuell | foto | ean | ki
    var notizen: String?
    // Hintergrund-Erkennung (Migration 0024). Diese Spalten gehoeren ALLEIN dem Server — die App
    // liest sie, schreibt sie aber nie (siehe `patchFields`).
    var kiStatus: WeinKiStatus          // offen | laeuft | fertig | fehler
    var kiFehler: String?               // Klartext des letzten Fehlschlags
    var kiVersuche: Int                 // Zahl der Anlaeufe (ab 3 nur noch von Hand)
    var dubletteVon: Int?               // vermuteter vorhandener Eintrag; NIE automatisch zusammengefuehrt

    init(fields f: [String: Any]) {
        id = Coerce.int(f["id"]) ?? 0
        // Unbekannte/fehlende Art = Wein: genau das steht als Default in der Migration, und die
        // Bestandszeilen sind ausnahmslos Weine.
        art = GetraenkeArt(rawValue: Coerce.str(f["art"]) ?? "") ?? .wein
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
        // Spirituosen-Spalten: unbekannte Kategorie bleibt nil (kein Rueckfall auf "sonstiges" —
        // das waere eine Behauptung, die der Datensatz nicht hergibt).
        kategorie = SpirituosenKategorie(rawValue: Coerce.str(f["kategorie"]) ?? "")
        stil = Coerce.str(f["stil"])
        alterJahre = Coerce.int(f["alter_jahre"])
        fass = Coerce.str(f["fass"])
        abgefuelltJahr = Coerce.int(f["abgefuellt_jahr"])
        trinkempfehlung = Coerce.str(f["trinkempfehlung"])
        cocktails = Coerce.stringArray(f["cocktails"])
        angebrochenAt = Coerce.str(f["angebrochen_at"])
        fuellstandProzent = Coerce.int(f["fuellstand_prozent"])
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
        // Fehlender/unbekannter Wert = zu Hause. Genau das steht als Default in der Migration, und
        // die installierte App (Build 58) schickt das Feld gar nicht mit — sie darf ihre Flaschen
        // dadurch nicht als geparkt angezeigt bekommen.
        standort = WeinStandort(rawValue: Coerce.str(f["standort"]) ?? "") ?? .zuhause
        fotoKey = Coerce.str(f["foto_key"])
        quelle = Coerce.str(f["quelle"]) ?? "manuell"
        notizen = Coerce.str(f["notizen"])
        // FEHLENDES Feld = fertig, nicht offen. Antworten ohne `ki_status` kommen von einem Backend
        // vor Migration 0024 bzw. aus Teilobjekten (Lookup-Vorschlag, Fixtures) — wuerde daraus
        // 'offen', zeigte die App schlagartig den GANZEN Bestand als "wird erkannt" und die
        // Warteschlange waere unbrauchbar. Derselbe Default steht in der Migration.
        kiStatus = WeinKiStatus(rawValue: Coerce.str(f["ki_status"]) ?? "") ?? .fertig
        kiFehler = Coerce.str(f["ki_fehler"])
        kiVersuche = Coerce.int(f["ki_versuche"]) ?? 0
        // 0 gilt als "keine Dublette": das generische CRUD liefert NULL, aber ein 0-Wert waere als
        // Fremdschluessel ohnehin sinnlos und wuerde sonst zu einem Verweis ins Leere.
        dubletteVon = Coerce.int(f["dublette_von"]).flatMap { $0 > 0 ? $0 : nil }
    }

    /// Body fuer POST/PATCH: DB-Spaltennamen, Arrays als JSON-String, nil als NSNull (damit
    /// Felder im Formular auch geleert werden koennen).
    /// BEWUSST NICHT enthalten: bester_preis*, preis_geprueft_at (setzt der Preischeck-Job),
    /// ki_status/ki_versuche/ki_fehler/ki_queued_at/dublette_von (setzt allein die Anreicherung) und
    /// id/created_at/updated_at.
    /// Der Warteschlangen-Zustand darf NICHT mitgeschickt werden: waehrend der Nutzer eine Flasche
    /// von Hand ausfuellt, kann der Hintergrundlauf sie gerade auf 'laeuft' bzw. 'fertig' gesetzt
    /// haben — ein PATCH mit dem alten Wert wuerde die Zeile zurueck in die Warteschlange werfen
    /// und die Erkennung ein zweites Mal bezahlen lassen. Wer neu erkennen lassen will, nimmt
    /// `POST /wein-anreicherung` mit `id`.
    /// ART-ABHAENGIG: die Spalten der jeweils ANDEREN Getraenkeart werden gar nicht geschickt —
    /// weder mit Wert noch als NSNull. Wuerden sie als NSNull mitgehen, wuerde jedes Speichern nach
    /// einem Umschalten die Angaben der Gegenart in der Zeile loeschen (ein falsch als Wein
    /// erkannter Whisky verloere beim Korrigieren seine Kategorie). Dieselbe Trennung nimmt das
    /// Backend beim Erfassen vor (`sanitizeFelder` in server/wein/enrich.ts).
    var patchFields: [String: Any] {
        // Schrittweise aufgebaut (kein grosses Dictionary-Literal) — das haelt den Swift-Typechecker
        // schnell und die Zuordnung Spalte/Wert lesbar.
        var d: [String: Any] = [:]
        d["art"] = art.rawValue
        d["name"] = name
        d["weingut"] = weingut
        d["jahrgang"] = jahrgang ?? NSNull()
        d["typ"] = typ.rawValue
        d["land"] = land ?? NSNull()
        d["region"] = region ?? NSNull()
        d["alkohol"] = alkohol ?? NSNull()
        d["aromen"] = WeinFormat.jsonArray(aromen)
        d["serviertemperatur"] = serviertemperatur ?? NSNull()
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
        // Standort geht bei BEIDEN Arten mit: die Spalte ist NOT NULL und gilt fuer beide; nur die
        // Bedienelemente sind auf Spirituosen beschraenkt. Bei Weinen ist der Wert schlicht immer
        // `zuhause` — ein Weglassen wuerde bei einem spaeter freigeschalteten Umschalter still
        // Aenderungen verschlucken.
        d["standort"] = standort.rawValue
        d["foto_key"] = fotoKey ?? NSNull()
        d["quelle"] = quelle
        d["notizen"] = notizen ?? NSNull()
        // Angebrochen/Fuellstand gelten fuer beide Arten und gehen deshalb immer mit.
        d["angebrochen_at"] = angebrochenAt ?? NSNull()
        d["fuellstand_prozent"] = fuellstandProzent ?? NSNull()

        switch art {
        case .wein:
            d["rebsorten"] = WeinFormat.jsonArray(rebsorten)
            d["lage"] = lage ?? NSNull()
            d["geschmacksrichtung"] = geschmacksrichtung
            d["suesse"] = suesse ?? NSNull()
            d["saeure"] = saeure ?? NSNull()
            d["tannin"] = tannin ?? NSNull()
            d["koerper"] = koerper ?? NSNull()
            d["trinkfenster_von"] = trinkfensterVon ?? NSNull()
            d["trinkfenster_bis"] = trinkfensterBis ?? NSNull()
        case .spirituose:
            d["kategorie"] = kategorie?.rawValue ?? NSNull()
            d["stil"] = stil ?? NSNull()
            d["alter_jahre"] = alterJahre ?? NSNull()
            d["fass"] = fass ?? NSNull()
            d["abgefuellt_jahr"] = abgefuelltJahr ?? NSNull()
            d["trinkempfehlung"] = trinkempfehlung ?? NSNull()
            d["cocktails"] = WeinFormat.jsonArray(cocktails)
        }
        return d
    }

    /// Anzeigename: Wein "Weingut Name Jahrgang", Spirituose "Destillerie Name · 16 Jahre"
    /// (leere Teile entfallen). Spirituosen tragen keinen Jahrgang — was zwei Abfuellungen
    /// derselben Destillerie unterscheidet, ist die Altersangabe.
    /// Solange die Hintergrund-Erkennung laeuft und weder Name noch Weingut da sind, steht hier
    /// "Wird erkannt …": im Serienmodus entstehen in einer Minute ein Dutzend solcher Zeilen, und
    /// eine Liste aus lauter Eintraegen namens "Wein" waere das Erste, was der Nutzer sieht — sie
    /// saehe nach einem Fehler aus, obwohl alles nach Plan laeuft.
    var titel: String {
        if name.isEmpty, weingut.isEmpty, kiStatus != .fertig { return "Wird erkannt …" }
        var teile: [String] = []
        if !weingut.isEmpty { teile.append(weingut) }
        if !name.isEmpty { teile.append(name) }
        if art == .wein, let j = jahrgang { teile.append(String(j)) }
        var text = teile.isEmpty ? art.einzahl : teile.joined(separator: " ")
        if art == .spirituose, let alter = WeinFormat.alterText(alterJahre) { text += " · " + alter }
        return text
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

    /// Ist die Flasche geoeffnet? Allein `angebrochen_at` entscheidet das — ein Fuellstand von
    /// 100 % steht auch an einer ungeoeffneten Flasche.
    var istAngebrochen: Bool {
        guard let a = angebrochenAt else { return false }
        return !a.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Wartet die Flasche noch auf die Hintergrund-Erkennung (oder ist sie daran gescheitert)?
    /// Solche Zeilen sind trotzdem vollwertiger Bestand — sie werden in Kennzahlen und Zaehlern
    /// normal mitgezaehlt und tragen nur zusaetzlich ein Abzeichen.
    var istUnfertig: Bool { kiStatus != .fertig }

    /// Hat die Erkennung einen vorhandenen Eintrag als wahrscheinliche Dublette markiert?
    /// Zusammengefuehrt wird NIE automatisch — zwei Flaschen desselben Weins sind der Normalfall,
    /// und ein falsch verschmolzener Eintrag waere nicht mehr zu trennen.
    var istDublette: Bool { dubletteVon != nil }

    /// Steht die Flasche im Buero? Sie bleibt dabei voll im Bestand (Keller, Suche, Bewertung,
    /// Preisbeobachtung) — sie traegt nur zusaetzlich ein Abzeichen, damit zu Hause niemand danach
    /// sucht.
    var istImBuero: Bool { standort == .buero }

    /// Fuellstand als Beschriftung der naechstliegenden Stufe (100/75/50/25/10/0).
    /// OHNE erfassten Wert nil — "leer" waere geraten und wuerde jede ungeoeffnete Flasche als
    /// ausgetrunken anzeigen.
    var fuellstandLabel: String? {
        guard let p = fuellstandProzent else { return nil }
        // Reihenfolge von voll nach leer: bei Gleichstand (z.B. 5 % — 10 und 0 sind gleich weit weg)
        // gewinnt dadurch die vollere Stufe. Eine Flasche mit Rest ist "Neige", nicht "leer".
        let stufen: [(wert: Int, text: String)] = [
            (wert: 100, text: "voll"), (wert: 75, text: "¾ voll"), (wert: 50, text: "halb"),
            (wert: 25, text: "¼"), (wert: 10, text: "Neige"), (wert: 0, text: "leer"),
        ]
        return stufen.min { abs($0.wert - p) < abs($1.wert - p) }?.text
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

    /// Altersangabe "16 Jahre" — nil ohne Angabe. Abfuellungen ohne Alter ("NAS") sind bei
    /// Spirituosen voellig normal und duerfen NICHT als "0 Jahre" erscheinen.
    static func alterText(_ jahre: Int?) -> String? {
        guard let jahre, jahre > 0 else { return nil }
        return jahre == 1 ? "1 Jahr" : "\(String(jahre)) Jahre"
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
