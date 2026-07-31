import SwiftUI

// Einkaufs-Scan im Laden — das Killer-Feature des Weinbereichs: Flasche aus dem Regal nehmen,
// Barcode anvisieren, in EINER Sekunde sehen, ob die Familie den Wein schon kennt und mochte.
//
// Zwei Ergebniszustaende, beide gross und ohne Lesen erfassbar:
//   (a) bekannt   — Ampel + Titel + beide Bewertungen mit Kommentar + Familienschnitt
//   (b) unbekannt — "Kennt ihr noch nicht" + Vorschlagsdaten des Backends + Erfassen-Knopf
//
// WICHTIG (Kamera): der gemeinsame `BarcodeScannerView` liefert je Instanz genau EINEN Code.
// Waehrend ein Ergebnis auf dem Schirm steht, wird er deshalb komplett aus der Hierarchie
// genommen — die Kamera stoppt (`dismantleUIViewController`), es gibt kein Dauerfeuer, und beim
// Weiterscannen baut `scanRunde` eine frische Instanz mit neuem Coordinator auf. Zusaetzlich
// entprellt `darfVerarbeiten` denselben Code fuer 3 Sekunden.

/// Kauf-Signal: eine Farbe, ein Wort, ein Symbol.
private struct WeinEinkaufsAmpel {
    let farbe: Color
    let titel: String
    let symbol: String

    static func fuer(_ schnitt: Double?) -> WeinEinkaufsAmpel {
        guard let s = schnitt else {
            return WeinEinkaufsAmpel(farbe: Color(hex: "3B82F6"), titel: "Noch nicht bewertet",
                                     symbol: "questionmark.circle.fill")
        }
        if s >= 4 {
            return WeinEinkaufsAmpel(farbe: Color(hex: "16A34A"), titel: "Zugreifen",
                                     symbol: "checkmark.circle.fill")
        }
        if s >= 3 {
            return WeinEinkaufsAmpel(farbe: Color(hex: "F59E0B"), titel: "Geht so",
                                     symbol: "hand.raised.fill")
        }
        return WeinEinkaufsAmpel(farbe: Color(hex: "DC2626"), titel: "Lieber stehen lassen",
                                 symbol: "xmark.circle.fill")
    }
}

struct WeinEinkaufsScanView: View {
    /// Unbekannter Wein: der Aufrufer oeffnet seinen Erfassungsfluss mit dieser EAN und dem
    /// bereits recherchierten Vorschlag — damit laeuft die kostenpflichtige KI-Kette KEIN
    /// zweites Mal und der Barcode landet wirklich im Datensatz.
    /// Leerer String = ohne Barcode gesucht (Namenssuche); `nil` = das Backend hatte keinen
    /// Vorschlag (kein Schluessel, keine Daten) — dann erfasst der Nutzer wie bisher.
    /// Die Ansicht schliesst sich bewusst NICHT selbst; die Praesentation bleibt beim Aufrufer.
    var onErfassen: (String, WeinVorschlag?) -> Void = { _, _ in }
    /// Bekannter Wein: der Aufrufer oeffnet die Detailansicht.
    var onOeffnen: (Wein) -> Void = { _ in }

    @EnvironmentObject private var store: WeinStore
    @Environment(\.dismiss) private var dismiss

    @State private var treffer: Treffer?
    @State private var laeuft = false
    @State private var fehler: String?
    @State private var eingabe = ""
    /// Zaehlt die Scan-Runden hoch — erzwingt eine frische Scanner-Instanz.
    @State private var scanRunde = 0
    /// 3-Sekunden-Entprellung je Code (sonst feuert dieselbe Flasche mehrfach).
    @State private var letzteScans: [String: Date] = [:]

    /// Ergebnis EINES Scans: die Antwort plus das, womit gesucht wurde.
    private struct Treffer: Identifiable {
        let id = UUID()
        /// Barcode — leer, wenn ueber den Namen gesucht wurde.
        var ean: String
        var begriff: String
        var lookup: WeinLookup
    }

    private var tint: Color { Palette.colors(for: "wein").first ?? Theme.accent }

    var body: some View {
        NavigationStack {
            Group {
                if let t = treffer { ergebnis(t) } else { scanner }
            }
            .background(Palette.gradient(for: "wein").opacity(0.05).ignoresSafeArea())
            .navigationTitle("Wein im Laden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }
                        .accessibilityIdentifier("wein-einkauf-schliessen")
                }
            }
        }
    }

    // MARK: - Zustand 1: Kamera laeuft

    private var scanner: some View {
        VStack(spacing: 14) {
            if laeuft {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Wird nachgeschlagen …").font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("wein-einkauf-laeuft")
            } else if BarcodeScannerView.isSupported {
                BarcodeScannerView { code in gescannt(code) }
                    .id(scanRunde)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .frame(maxHeight: .infinity)
                    .overlay(alignment: .bottom) {
                        Text("Barcode der Flasche anvisieren")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding()
                    }
                    .padding(.horizontal, 14)
                    .accessibilityIdentifier("wein-einkauf-scanner")
            } else {
                ContentUnavailableView("Scanner nicht verfügbar", systemImage: "barcode.viewfinder",
                                       description: Text("Gib den Barcode oder den Weinnamen unten ein."))
                    .frame(maxHeight: .infinity)
            }

            if let f = fehler {
                Label(f, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline).foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.orange.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 14)
                    .accessibilityIdentifier("wein-einkauf-fehler")
            }

            HStack {
                TextField("Barcode oder Weinname", text: $eingabe)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { starteSuche(eingabe) }
                    .accessibilityIdentifier("wein-einkauf-eingabe")
                Button("Suchen") { starteSuche(eingabe) }
                    .buttonStyle(.borderedProminent).tint(tint)
                    .disabled(eingabe.trimmingCharacters(in: .whitespaces).count < 3 || laeuft)
                    .accessibilityIdentifier("wein-einkauf-suchen")
            }
            .padding(.horizontal, 14)
        }
        .padding(.vertical, 12)
    }

    // MARK: - Zustand 2: Ergebnis (Kamera ist aus)

    private func ergebnis(_ t: Treffer) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 14) {
                    if let w = t.lookup.wein, t.lookup.known {
                        bekannt(t, w)
                    } else {
                        unbekannt(t)
                    }
                }
                .padding(14)
            }
            aktionen(t)
        }
        // KEIN Container-Identifier hier: er wuerde die IDs der Aktionsknoepfe (oeffnen/erfassen/
        // weiter) und der Ergebnisbloecke ueberschreiben (siehe AlarmoTile). Der Ergebniszustand
        // ist ueber "wein-einkauf-ampel" bzw. "wein-einkauf-unbekannt" eindeutig erkennbar.
    }

    // ── (a) bekannt ──

    private func bekannt(_ t: Treffer, _ w: Wein) -> some View {
        let schnitt = t.lookup.schnitt
        let ampel = WeinEinkaufsAmpel.fuer(schnitt)
        return VStack(spacing: 14) {
            VStack(spacing: 6) {
                Image(systemName: ampel.symbol).font(.system(size: 46, weight: .semibold))
                Text(ampel.titel).font(.title2.weight(.heavy))
                if let s = schnitt {
                    Text("Familienschnitt " + WeinText.zahl(s) + " von 5")
                        .font(.subheadline.weight(.semibold))
                } else {
                    Text("Ihr habt den Wein, aber noch keine Note vergeben.").font(.subheadline)
                }
            }
            .foregroundStyle(ampel.farbe.onFill)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .background(ampel.farbe, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .accessibilityIdentifier("wein-einkauf-ampel")

            VStack(alignment: .leading, spacing: 8) {
                Text(w.typ.emoji + " " + w.titel).font(.title3.weight(.bold))
                let ort = WeinText.herkunft(land: w.land, region: w.region, lage: nil)
                if !ort.isEmpty { Text(ort).font(.subheadline).foregroundStyle(.secondary) }
                HStack(spacing: 6) {
                    Pill(text: w.typ.label, color: w.typ.farbe)
                    if w.bestand > 0 {
                        Pill(text: String(w.bestand) + " Fl. im Keller", systemImage: "archivebox",
                             color: Color(hex: "475569"), filled: false)
                    }
                    if let p = w.referenzpreis {
                        Text("ca. " + WeinText.eur(p)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityIdentifier("wein-einkauf-titel")

            if t.lookup.bewertungen.isEmpty {
                NoteBlock(icon: "⭐️", text: "Noch keine Bewertung — probiert ihn und haltet fest, wie er war.")
            } else {
                VStack(spacing: 10) {
                    ForEach(t.lookup.bewertungen) { stimme($0) }
                }
            }
        }
    }

    private func stimme(_ b: WeinBewertung) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(WeinText.person(b.owner)).font(.subheadline.weight(.bold))
                Spacer(minLength: 8)
                WeinSterne(sterne: b.sterne, gross: true)
            }
            if !b.kommentar.isEmpty {
                Text(b.kommentar).font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityIdentifier("wein-einkauf-stimme-" + b.owner)
    }

    // ── (b) unbekannt ──

    private func unbekannt(_ t: Treffer) -> some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                Image(systemName: "sparkle.magnifyingglass").font(.system(size: 46, weight: .semibold))
                Text("Kennt ihr noch nicht").font(.title2.weight(.heavy))
                Text(t.begriff).font(.footnote.monospaced()).opacity(0.9)
            }
            .foregroundStyle(Color(hex: "4F46E5").onFill)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .background(Color(hex: "4F46E5"), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .accessibilityIdentifier("wein-einkauf-unbekannt")

            if let v = t.lookup.vorschlag {
                vorschlag(v)
            } else {
                NoteBlock(icon: "📷",
                          text: "Zu diesem Barcode gibt es keine Daten. Beim Erfassen kannst du das Etikett fotografieren — den Rest ergänzt die KI.")
            }
        }
    }

    private func vorschlag(_ v: WeinVorschlag) -> some View {
        let w = v.alsWein
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Das haben wir gefunden").font(.caption.weight(.bold))
                    .textCase(.uppercase).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Pill(text: v.confidenceLabel, color: v.confidenceFarbe)
            }
            Text(w.typ.emoji + " " + w.titel).font(.title3.weight(.bold))

            ForEach(zeilen(w), id: \.self) { z in
                Text(z).font(.subheadline).foregroundStyle(.secondary)
            }

            if let best = v.preise.filter({ $0.preis > 0 }).min(by: { $0.preis < $1.preis }) {
                Divider().padding(.vertical, 2)
                HStack(spacing: 6) {
                    Image(systemName: "tag.fill").foregroundStyle(Color(hex: "16A34A"))
                    Text(WeinText.eur(best.preis)).font(.subheadline.weight(.semibold))
                    if !best.haendler.isEmpty {
                        Text("bei " + best.haendler).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            ForEach(v.hinweise, id: \.self) { h in
                Label(h, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityIdentifier("wein-einkauf-vorschlag")
    }

    /// Die wenigen Zeilen, die im Laden wirklich zaehlen — was fehlt, faellt weg.
    private func zeilen(_ w: Wein) -> [String] {
        var out: [String] = []
        var art: [String] = [w.typ.label]
        if w.geschmacksrichtung != "unbekannt" && !w.geschmacksrichtung.isEmpty {
            art.append(w.geschmacksrichtung)
        }
        if let a = w.alkohol, a > 0 { art.append(WeinText.alkohol(a)) }
        out.append(art.joined(separator: " · "))

        let ort = WeinText.herkunft(land: w.land, region: w.region, lage: w.lage)
        if !ort.isEmpty { out.append(ort) }
        if !w.rebsorten.isEmpty { out.append(w.rebsorten.joined(separator: ", ")) }
        if let p = w.referenzpreis { out.append("Referenzpreis ca. " + WeinText.eur(p)) }
        return out
    }

    // ── Aktionsleiste: zwei grosse Knoepfe, beide mit dem Daumen erreichbar ──

    private func aktionen(_ t: Treffer) -> some View {
        VStack(spacing: 10) {
            if let w = t.lookup.wein, t.lookup.known {
                Button { onOeffnen(w) } label: { Label("Öffnen", systemImage: "wineglass") }
                    .buttonStyle(GradientButtonStyle(gradientKey: "wein"))
                    .accessibilityIdentifier("wein-einkauf-oeffnen")
            } else {
                Button { onErfassen(t.ean, t.lookup.vorschlag) } label: {
                    Label("Jetzt erfassen", systemImage: "plus.circle.fill")
                }
                .buttonStyle(GradientButtonStyle(gradientKey: "wein"))
                .accessibilityIdentifier("wein-einkauf-erfassen")
            }
            Button { weiterScannen() } label: {
                Label("Weiter scannen", systemImage: "barcode.viewfinder").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("wein-einkauf-weiter")
        }
        .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 14)
        .background(.regularMaterial)
    }

    // MARK: - Ablauf

    private func gescannt(_ code: String) {
        let ean = code.trimmingCharacters(in: .whitespaces)
        guard darfVerarbeiten(ean) else { return }
        starteSuche(ean)
    }

    private func starteSuche(_ roh: String) {
        let begriff = roh.trimmingCharacters(in: .whitespaces)
        guard !begriff.isEmpty, !laeuft else { return }
        eingabe = ""
        Task { await suche(begriff) }
    }

    private func weiterScannen() {
        treffer = nil
        fehler = nil
        scanRunde += 1
    }

    /// Derselbe Code wird 3 Sekunden lang nicht erneut verarbeitet.
    private func darfVerarbeiten(_ code: String) -> Bool {
        guard !code.isEmpty else { return false }
        let jetzt = Date()
        if let l = letzteScans[code], jetzt.timeIntervalSince(l) < 3 { return false }
        letzteScans[code] = jetzt
        return true
    }

    /// Reine Ziffern = Barcode, sonst Weinname — die Route kann beides (`?ean=` / `?name=`).
    private func istBarcode(_ s: String) -> Bool {
        s.count >= 6 && s.allSatisfy { $0.isNumber }
    }

    @MainActor
    private func suche(_ begriff: String) async {
        laeuft = true
        fehler = nil
        defer { laeuft = false }
        let alsEan = istBarcode(begriff)
        do {
            let lookup = try await store.api.lookup(ean: alsEan ? begriff : nil,
                                                    name: alsEan ? nil : begriff)
            treffer = Treffer(ean: alsEan ? begriff : "", begriff: begriff, lookup: lookup)
        } catch {
            fehler = (error as? APIError)?.errorDescription
                ?? "Der Wein konnte nicht nachgeschlagen werden."
        }
    }
}
