import SwiftUI

/// Warteschlange der Hintergrund-Erkennung — das Segment "Queue (n)".
///
/// Hier stehen die Flaschen, die die Schnellerfassung eingereiht hat und die noch keinen Namen
/// tragen: sie sind bereits vollwertiger Bestand (die Zusage „nichts geht verloren"), nur eben noch
/// ohne Etikettendaten. Die Ansicht ist deshalb eine Arbeitsliste und keine Katalogliste — sie zeigt
/// je Zeile den Zustand im Klartext und die drei Auswege daraus: noch einmal erkennen lassen, von
/// Hand ausfuellen oder wegwerfen.
///
/// Bewusst `ScrollView` statt `List`: in einer Listenzeile mit MEHREREN Knoepfen ist nicht mehr
/// eindeutig, was ein Tipp meint (die Zeile faengt ihn ab) — hier ist jeder Knopf eine eigene
/// Aktion, es gibt keine Zeilenaktion und damit auch keine Wisch-Aktionen zu erhalten.
struct WeinQueueView: View {
    /// "Von Hand ausfuellen" — die Bereichswurzel oeffnet damit die Bearbeiten-Maske.
    /// Als Closure, weil das Sheet dort haengt: die Warteschlange kennt die Maske absichtlich nicht.
    var onBearbeiten: (Wein) -> Void = { _ in }

    @EnvironmentObject private var store: WeinStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var verwerfenZiel: Wein?

    private var tint: Color { Palette.colors(for: "wein").first ?? Theme.accent }

    /// Takt-Schluessel des Nachladens. Er wechselt, sobald die App in den Hintergrund geht ODER die
    /// Warteschlange leer wird — `.task(id:)` bricht den laufenden Takt dann ab und startet ihn erst
    /// wieder, wenn beides zutrifft. Verschwindet die Ansicht ganz, beendet SwiftUI den Task ohnehin.
    /// Genau so entsteht die Zusage aus der Spezifikation: kein Dauerpolling bei leerer Queue und
    /// keines, wenn niemand hinschaut.
    private var taktSchluessel: String {
        String(store.queueGesamt > 0) + "-" + String(scenePhase == .active)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if store.queueEintraege.isEmpty {
                    leerZustand.frame(maxWidth: .infinity).frame(minHeight: 280)
                } else {
                    kopf
                    ForEach(store.queueEintraege) { w in zeile(w) }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .refreshable { await store.reload() }
        .task(id: taktSchluessel) { await nachladeSchleife() }
        .confirmationDialog(verwerfenTitel,
                            isPresented: Binding(get: { verwerfenZiel != nil },
                                                 set: { if !$0 { verwerfenZiel = nil } }),
                            titleVisibility: .visible) {
            Button("Verwerfen", role: .destructive) {
                if let z = verwerfenZiel { Task { await store.verwerfen(z) } }
                verwerfenZiel = nil
            }
            Button("Abbrechen", role: .cancel) { verwerfenZiel = nil }
        } message: {
            Text("Der Eintrag wird mitsamt dem Foto aus dem Bestand entfernt.")
        }
    }

    /// Faellt auf die gerade gewaehlte Art zurueck, weil der Dialog-Rumpf auch dann noch ausgewertet
    /// wird, wenn `verwerfenZiel` bereits nil ist (dasselbe Muster wie in `WeinListView`).
    private var verwerfenTitel: String {
        (verwerfenZiel?.art ?? store.art).einzahl + " verwerfen?"
    }

    // ── Kopfzeile: Stand + Sammellauf ──

    private var kopf: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(standMeldung).font(.footnote).foregroundStyle(.secondary)
            Button {
                Task { await store.anreicherungStarten() }
            } label: {
                HStack(spacing: 6) {
                    if store.anreicherungLaeuft {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(store.anreicherungLaeuft ? "Wird verarbeitet …" : "Alle jetzt verarbeiten")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.borderedProminent)
            .tint(tint)
            // Waehrend eines Laufs gesperrt: ein zweiter Anstoss brauchte gar nicht anzukommen (der
            // Server laesst nur einen Sammellauf zu) und saehe fuer den Nutzer wie ein Fehler aus.
            .disabled(store.anreicherungLaeuft)
            .accessibilityIdentifier("wein-queue-alle")
        }
        .padding(.bottom, 2)
    }

    /// Stand der Warteschlange in einem Satz. 'offen' und 'laeuft' stehen bewusst zusammen — fuer
    /// den Nutzer ist beides derselbe Zustand ("es passiert etwas"). Jede Zahl geht ueber
    /// `String(...)` (sonst macht die Interpolation aus 1024 ein "1.024"), und jede Form muss auch
    /// bei genau einer Flasche stimmen.
    private var standMeldung: String {
        var teile: [String] = []
        let wartend = store.queueOffen + store.queueLaeuft
        if wartend > 0 {
            teile.append(wartend == 1 ? "1 Flasche wird erkannt"
                                      : String(wartend) + " Flaschen werden erkannt")
        }
        if store.queueFehler > 0 {
            teile.append(store.queueFehler == 1 ? "1 Erkennung fehlgeschlagen"
                                                : String(store.queueFehler) + " Erkennungen fehlgeschlagen")
        }
        // Kann die Ansicht im Alltag nicht erreichen (ohne Eintraege steht hier der Leerzustand),
        // ist aber die einzige Beschriftung, die auch bei 0 stimmt.
        if teile.isEmpty { return "Nichts in der Warteschlange" }
        return teile.joined(separator: " · ")
    }

    // ── Leerzustand ──

    private var leerZustand: some View {
        // Das Segment erscheint nur, solange n > 0 — dieser Zustand ist deshalb der kurze Moment,
        // in dem die letzte Flasche gerade fertig geworden ist und die Leiste noch nachzieht.
        AreaEmptyState(
            emoji: "✅",
            title: "Nichts in der Warteschlange",
            hint: "Alle erfassten Flaschen sind erkannt."
        )
    }

    // ── Zeile ──

    private func zeile(_ w: Wein) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                etikett(w)
                VStack(alignment: .leading, spacing: 5) {
                    // `Wein.titel` liefert fuer diese Zeilen "Wird erkannt …" statt eines leeren
                    // Feldes oder eines geratenen "Wein".
                    Text(w.titel).font(.subheadline.weight(.semibold)).lineLimit(2)
                    Pill(text: w.kiStatus.label, systemImage: w.kiStatus.symbol,
                         color: w.kiStatus.farbe, filled: false)
                    if let grund = fehlerText(w) {
                        Text(grund).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    }
                    if w.kiStatus == .fehler && w.kiVersuche >= 3 {
                        // Ab drei Anlaeufen laeuft nichts mehr von allein (ein dauerhaft unlesbares
                        // Etikett wuerde sonst jede Nacht Geld verbrennen) — das muss dastehen,
                        // sonst wartet der Nutzer auf etwas, das nicht mehr kommt.
                        Text("Läuft nicht mehr von allein — hier erneut auslösen.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(quellenText(w)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            knoepfe(w)
        }
        .padding(10)
        .background(Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Etikettenfoto in derselben Groesse wie in der Listenkarte. Vorschau (160 px) statt Original:
    /// gerendert werden 54x72 pt, das Original (bis 2000 px) waere hier reine Ladezeit.
    private func etikett(_ w: Wein) -> some View {
        Group {
            if let path = w.imagePath {
                AuthImage(path: path, contentMode: .fill, thumb: 160)
            } else {
                // Ohne Foto (Barcode-Serie) bleibt das Glas der Art — die Kategorie kennt hier
                // noch niemand.
                Palette.gradient(for: "wein").opacity(0.20)
                    .overlay(Text(w.art.emoji).font(.title2))
            }
        }
        .frame(width: 54, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// Fehlergrund im Klartext. Ohne Meldung vom Server steht hier ein vollstaendiger Satz statt
    /// "Fehler: " mit nichts dahinter.
    private func fehlerText(_ w: Wein) -> String? {
        guard w.kiStatus == .fehler else { return nil }
        let grund = (w.kiFehler ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if grund.isEmpty { return "Fehler: Grund unbekannt" }
        return "Fehler: " + grund
    }

    /// Woher die Zeile kommt — die einzige Angabe, an der zwei namenlose Eintraege auseinanderzuhalten
    /// sind. Der Barcode steht vor dem Foto: er ist die genauere Auskunft.
    private func quellenText(_ w: Wein) -> String {
        if let ean = w.ean, !ean.isEmpty { return "Barcode " + ean }
        if w.imagePath != nil { return "Etikettenfoto" }
        return "Ohne Foto und Barcode"
    }

    // ── Die drei Auswege je Zeile ──

    private func knoepfe(_ w: Wein) -> some View {
        HStack(spacing: 8) {
            queueKnopf(titel: "Erneut versuchen", symbol: "arrow.clockwise",
                       identifier: "wein-queue-retry", rolle: nil) {
                // Mit `id` ignoriert der Server die Versuchsgrenze — genau dafuer ist der Knopf da.
                Task { await store.anreicherungStarten(id: w.id) }
            }
            // Gleiche Sperre wie oben: waehrend eines Laufs waere der Anstoss wirkungslos.
            .disabled(store.anreicherungLaeuft)

            queueKnopf(titel: "Von Hand ausfüllen", symbol: "square.and.pencil",
                       identifier: "wein-queue-edit", rolle: nil) {
                onBearbeiten(w)
            }

            queueKnopf(titel: "Verwerfen", symbol: "trash",
                       identifier: "wein-queue-drop", rolle: .destructive) {
                // Erst fragen: geloescht wird die ganze Zeile, und ein Fehlauslöser der Kamera ist
                // nicht vom versehentlichen Tipp zu unterscheiden.
                verwerfenZiel = w
            }
        }
    }

    /// Ein Knopf der Zeile. Drei nebeneinander sind auf einem iPhone eng — deshalb kleine Schrift,
    /// eine Zeile und Verkleinerung als letzter Ausweg, aber volle Beschriftung: "Erneut" oder ein
    /// blosses Symbol saehe man an, ohne es zu verstehen. Die Hoehe haelt die Trefferflaeche ueber
    /// den 44 pt (36 pt Inhalt + Rand des `.bordered`-Stils).
    private func queueKnopf(titel: String, symbol: String, identifier: String,
                            rolle: ButtonRole?, aktion: @escaping () -> Void) -> some View {
        Button(role: rolle, action: aktion) {
            Label(titel, systemImage: symbol)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier(identifier)
    }

    // ── Nachladen im Takt ──

    /// Zaehlerstand alle zehn Sekunden beim Server holen; die volle Liste zieht `queueNachladen()`
    /// nur nach, wenn sich wirklich etwas bewegt hat.
    /// Erst schlafen, dann zaehlen: die Liste ist beim Erscheinen der Ansicht gerade frisch geladen.
    private func nachladeSchleife() async {
        guard scenePhase == .active, store.queueGesamt > 0 else { return }
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            if Task.isCancelled { return }
            // Leert sich die Warteschlange, endet der Takt hier — der Schluesselwechsel raeumt den
            // Task zwar ohnehin ab, aber erst beim naechsten Zeichnen.
            guard store.queueGesamt > 0 else { return }
            await store.queueNachladen()
        }
    }
}
