import Foundation

/// Anbindung des Wein-Bereichs an die generischen v1-Ressourcen (`weine`, `wein-bewertungen`,
/// `wein-preise`) und die Sonderrouten (`wein-scan`, `wein-lookup`, `wein-bewertung`,
/// `wein-preischeck`, `wein-einstellungen`).
/// Alle Routen tragen BEIDE Getraenkearten (Wein und Spirituose) — Tabelle, Pfade und Namen bleiben
/// deshalb unveraendert, unterschieden wird ueber die Spalte `art` (siehe Kopf von WeinModels.swift).
/// WICHTIG: v1-Listen liefern einen ENVELOPE `{data:[…],total}` (kein bares Array);
/// Einzel-GET/POST/PATCH liefern die Zeile als bares Objekt.
/// CompatClient stellt `/api` voran → alle Pfade beginnen hier mit `/v1/…`.
@MainActor
final class WeinAPI {
    private let c: CompatClient
    init(settings: Settings) { c = CompatClient(settings: settings) }

    // MARK: - Lesen

    /// Alle Weine (bis 500). Sortierung passiert clientseitig im Store.
    func fetchWeine() async throws -> [Wein] {
        let obj = try await c.getObject("/v1/weine", query: [
            URLQueryItem(name: "limit", value: "500"),
            URLQueryItem(name: "sort", value: "id:desc"),
        ])
        return ((obj["data"] as? [[String: Any]]) ?? []).map(Wein.init(fields:))
    }

    /// Einzelner Wein (bares Objekt, KEIN Envelope) — nach Mutationen zum Nachziehen.
    func fetchWein(_ id: Int) async throws -> Wein {
        Wein(fields: try await c.getObject("/v1/weine/\(id)"))
    }

    /// Alle Bewertungen (maximal 2 je Wein) — der Store gruppiert sie nach `wein_id`.
    func fetchBewertungen() async throws -> [WeinBewertung] {
        let obj = try await c.getObject("/v1/wein-bewertungen", query: [
            URLQueryItem(name: "limit", value: "500"),
            URLQueryItem(name: "sort", value: "id:asc"),
        ])
        return ((obj["data"] as? [[String: Any]]) ?? []).map(WeinBewertung.init(fields:))
    }

    /// Preis-Historie eines Weins (neueste zuerst).
    func fetchPreise(weinId: Int) async throws -> [WeinPreis] {
        let obj = try await c.getObject("/v1/wein-preise", query: [
            URLQueryItem(name: "wein_id", value: String(weinId)),
            URLQueryItem(name: "limit", value: "100"),
            URLQueryItem(name: "sort", value: "gefunden_at:desc"),
        ])
        return ((obj["data"] as? [[String: Any]]) ?? []).map(WeinPreis.init(fields:))
    }

    // MARK: - Schreiben (Agent-Rolle)

    @discardableResult
    func create(_ fields: [String: Any]) async throws -> Wein {
        Wein(fields: try await c.send("/v1/weine", method: "POST", body: fields))
    }

    @discardableResult
    func update(_ id: Int, _ fields: [String: Any]) async throws -> Wein {
        Wein(fields: try await c.send("/v1/weine/\(id)", method: "PATCH", body: fields))
    }

    func delete(_ id: Int) async throws {
        _ = try await c.send("/v1/weine/\(id)", method: "DELETE")
    }

    /// Bewerten (UPSERT auf wein_id+owner). `owner` ist nur ein Fallback — primaer nimmt der
    /// Server die Person aus dem API-Key. Antwort: die gespeicherte Bewertung + neuer Schnitt.
    func bewerten(weinId: Int, sterne: Int, kommentar: String, owner: String?) async throws -> (bewertung: WeinBewertung, schnitt: Double?) {
        var body: [String: Any] = ["wein_id": weinId, "sterne": sterne, "kommentar": kommentar]
        if let owner, !owner.isEmpty { body["owner"] = owner }
        let r = try await c.send("/v1/wein-bewertung", method: "POST", body: body)
        let b = WeinBewertung(fields: (r["bewertung"] as? [String: Any]) ?? [:])
        return (b, Coerce.double(r["schnitt"]))
    }

    /// Etikettenfoto hochladen → storage_key (fuer `foto_key`). nil, wenn der Server keinen liefert.
    func uploadFoto(jpeg: Data) async throws -> String? {
        let payload: [String: Any] = [
            "area": "wein", "filename": "etikett.jpg", "mime": "image/jpeg",
            "data_base64": jpeg.base64EncodedString(),
        ]
        return try await c.send("/v1/media/upload", method: "POST", body: payload)["storage_key"] as? String
    }

    // MARK: - Sonderrouten (langlaufend)

    /// Die vier KI-Routen unten rechnen serverseitig minutenlang (Vision → Websuche → Normalisierung;
    /// `maxDuration` 120 bzw. 300 beim Preischeck) und senden bis zum fertigen JSON kein Byte. Sie
    /// laufen deshalb ueber den Langsam-Pfad des CompatClient (`slow: true`, Budget 310 s) — alle
    /// uebrigen Aufrufe dieser Datei bleiben bewusst beim schnellen 25-s-Budget.
    /// Laeuft auch das grosse Budget ab, ist `URLError.timedOut` kein `APIError` und die Views zeigen
    /// nur ihren generischen Fallback. Darum hier in eine verstaendliche Meldung uebersetzen.
    private func langlaufend<T>(_ was: String, _ arbeit: () async throws -> T) async throws -> T {
        do {
            return try await arbeit()
        } catch let e as URLError where e.code == .timedOut {
            throw APIError(status: 0, message: "\(was) dauert gerade länger als erwartet und wurde abgebrochen. Bitte in ein paar Minuten noch einmal versuchen.")
        }
    }

    /// Schritt 1 der Erfassung: Etikettenfoto / EAN / Freitext → Vorschlag samt Preisen.
    /// Speichert NICHTS. Wirft APIError 501, wenn `OPENAI_API_KEY` fehlt.
    ///
    /// `art` ist nur ein HINWEIS an die Erkennungskette (welche Maske der Nutzer gerade offen hat).
    /// Widerspricht das Etikett dem Hinweis, gewinnt die Erkennung und das Backend legt einen
    /// Klartext-Hinweis in `hinweise` — im Laden schaltet niemand erst den Umschalter um.
    /// Der Parameter steht bewusst HINTEN mit Default (wie `slow:` im CompatClient), damit
    /// bestehende Aufrufstellen unveraendert uebersetzen; `.wein` entspricht dem Default, den das
    /// Backend ohne Hinweis ohnehin annimmt.
    func scan(image: Data? = nil, ean: String? = nil, text: String? = nil,
              art: GetraenkeArt = .wein) async throws -> WeinVorschlag {
        var body: [String: Any] = [:]
        if let image { body["image"] = "data:image/jpeg;base64," + image.base64EncodedString() }
        if let ean, !ean.isEmpty { body["ean"] = ean }
        if let text, !text.isEmpty { body["text"] = text }
        body["art"] = art.rawValue
        let o = try await langlaufend("Die Erkennung des Etiketts") {
            try await c.send("/v1/wein-scan", method: "POST", body: body, slow: true)
        }
        return WeinVorschlag(object: o)
    }

    /// Einkaufs-Scan im Laden: kennen wir die Flasche schon und wie fanden wir sie?
    /// Bei unbekannter EAN startet der Server dieselbe Anreicherungs-Kette wie `scan` → langlaufend.
    /// `art` ist derselbe unverbindliche Hinweis wie bei `scan` (hier als Query-Parameter); die
    /// EAN-Suche selbst schraenkt der Server bewusst NICHT auf eine Art ein — ein Barcode ist eindeutig.
    func lookup(ean: String? = nil, name: String? = nil,
                art: GetraenkeArt = .wein) async throws -> WeinLookup {
        var q: [URLQueryItem] = []
        if let ean, !ean.isEmpty { q.append(URLQueryItem(name: "ean", value: ean)) }
        if let name, !name.isEmpty { q.append(URLQueryItem(name: "name", value: name)) }
        q.append(URLQueryItem(name: "art", value: art.rawValue))
        let o = try await langlaufend("Das Nachschlagen der Flasche") {
            try await c.getObject("/v1/wein-lookup", query: q, slow: true)
        }
        return WeinLookup(object: o)
    }

    /// Preise einer Flasche jetzt pruefen (Perplexity-Recherche im Backend, Wein wie Spirituose).
    @discardableResult
    func preischeck(weinId: Int) async throws -> WeinPreischeckErgebnis {
        let o = try await langlaufend("Die Preisrecherche") {
            try await c.send("/v1/wein-preischeck", method: "POST", body: ["wein_id": weinId], slow: true)
        }
        return WeinPreischeckErgebnis(object: o)
    }

    /// Alle beobachteten Flaschen pruefen (der Nacht-Job macht dasselbe automatisch).
    @discardableResult
    func preischeckAlle() async throws -> WeinPreischeckErgebnis {
        let o = try await langlaufend("Die Preisrecherche für alle Flaschen") {
            try await c.send("/v1/wein-preischeck", method: "POST", body: ["alle": true], slow: true)
        }
        return WeinPreischeckErgebnis(object: o)
    }

    // MARK: - Einstellungen des Preis-Waechters

    func einstellungen() async throws -> WeinEinstellungen {
        WeinEinstellungen(object: try await c.getObject("/v1/wein-einstellungen"))
    }

    @discardableResult
    func saveEinstellungen(_ e: WeinEinstellungen) async throws -> WeinEinstellungen {
        WeinEinstellungen(object: try await c.send("/v1/wein-einstellungen", method: "PUT", body: e.body))
    }
}
