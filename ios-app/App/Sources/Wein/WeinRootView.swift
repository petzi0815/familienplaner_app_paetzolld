import SwiftUI

/// Sheet-Ziele des Weinbereichs (`WeinErfassenView`, `WeinEinkaufsScanView`, `WeinEinstellungenView`).
/// Alle drei bringen ihren eigenen NavigationStack mit und schliessen sich selbst.
enum WeinSheet: Int, Identifiable {
    case erfassen, laden, einstellungen
    var id: Int { rawValue }
}

/// Wurzel des nativen Wein-Bereichs — Kopf mit Kennzahlen, Segmente Alle/Keller/Top/Offen,
/// Suche, Filterzeile und die Liste. Wird in den bestehenden NavigationStack des Bereiche-Tabs
/// gepusht — hier KEIN eigener Stack (sonst funktioniert der Detail-Push nicht).
struct WeinRootView: View {
    @StateObject private var store: WeinStore
    @EnvironmentObject private var app: AppState
    @State private var sheet: WeinSheet?
    /// Programmatisch gepushtes Detail (aus dem Einkaufs-Scan bzw. der Dubletten-Karte).
    /// Die Liste selbst pusht ueber einen eigenen NavigationLink.
    @State private var detailWein: Wein?
    /// Uebergabe vom Einkaufs-Scan an die Erfassung: gescannter Barcode und der dort bereits
    /// bezahlte KI-Vorschlag. Gilt fuer genau eine Erfassung (siehe `onDismiss` am Sheet).
    @State private var erfassenEan = ""
    @State private var erfassenVorschlag: WeinVorschlag?

    init(settings: Settings) { _store = StateObject(wrappedValue: WeinStore(settings: settings)) }

    private var tint: Color { Palette.colors(for: "wein").first ?? Theme.accent }

    // ── Kennzahlen ──

    private var flaschen: Int { store.weine.reduce(0) { $0 + max(0, $1.bestand) } }
    private var kellerAnzahl: Int { store.weine.filter { $0.bestand > 0 }.count }
    private var topAnzahl: Int { store.weine.filter { (store.schnitt($0) ?? 0) >= 4 }.count }
    private var offenAnzahl: Int { store.weine.filter { store.meine($0) == nil }.count }

    private var subtitle: String {
        if store.weine.isEmpty { return "Weinkeller & Bewertungen" }
        return String(store.weine.count) + " Weine · " + String(flaschen) + " Flaschen · "
            + String(offenAnzahl) + " offen"
    }

    private func zaehler(_ n: Int) -> String { n > 0 ? " (" + String(n) + ")" : "" }

    private var tabs: [(tab: WeinTab, label: String, systemImage: String?)] {
        [
            (.alle,   "Alle" + zaehler(store.weine.count), "square.grid.2x2"),
            (.keller, "Keller" + zaehler(kellerAnzahl), "archivebox"),
            (.top,    "Top" + zaehler(topAnzahl), "star.fill"),
            (.offen,  "Offen" + zaehler(offenAnzahl), "questionmark.circle"),
        ]
    }

    var body: some View {
        AreaScaffold(gradientKey: "wein", systemImage: "wineglass", title: "Wein", subtitle: subtitle,
                     toast: $store.message, toastIsError: store.messageIsError,
                     trailing: { menu },
                     controls: { controls },
                     content: { content })
            .task {
                store.owner = app.me?.owner
                consumeErfassenWunsch()
                if store.loading && store.weine.isEmpty { await store.loadAll() }
            }
            // Schnellaktion „Wein erfassen" / familienplaner://wein-neu. Steht die Ansicht schon,
            // kommt der Wunsch nicht mehr ueber .task an — deshalb zusaetzlich beobachten.
            .onChange(of: app.pendingWeinNew) { _, _ in consumeErfassenWunsch() }
            // /auth/me kommt asynchron — trifft die Person erst nach dem ersten Laden ein, muessen
            // die Bewertungen neu zugeordnet werden (meine/andere haengen am owner).
            .onChange(of: app.me?.owner) { _, neu in
                guard store.owner != neu else { return }
                store.owner = neu
                if !store.weine.isEmpty { Task { await store.reload() } }
            }
            .environmentObject(store)
            .navigationDestination(item: $detailWein) { w in
                WeinDetailView(wein: w).environmentObject(store)
            }
            .sheet(item: $sheet, onDismiss: {
                // Die Vorbelegung aus dem Laden gilt nur fuer die eine Erfassung, die ihr folgt —
                // sonst erbt sie der naechste Aufruf ueber das Menue.
                erfassenEan = ""
                erfassenVorschlag = nil
            }) { ziel in
                switch ziel {
                case .erfassen:
                    WeinErfassenView(startEan: erfassenEan,
                                     startVorschlag: erfassenVorschlag,
                                     onGespeichert: { _ in Task { await store.reload() } },
                                     onDubletteOeffnen: { id in oeffneDetail(id: id) })
                        .environmentObject(store)
                        // Jetzt steht die Erfassung wirklich → ein offener Wunsch ist eingeloest
                        // (siehe consumeErfassenWunsch).
                        .onAppear { app.pendingWeinNew = false }
                case .laden:
                    // Unbekannte Flasche: die Erfassung uebernimmt Barcode UND den schon
                    // recherchierten Vorschlag — die KI-Kette laeuft kein zweites Mal.
                    WeinEinkaufsScanView(onErfassen: { ean, v in wechsleZuErfassen(ean: ean, vorschlag: v) },
                                         onOeffnen: { w in oeffneDetail(w) })
                        .environmentObject(store)
                case .einstellungen:
                    // Braucht den Store (liest/schreibt ueber store.api) — ein Sheet bekommt die
                    // EnvironmentObjects des Aufrufers NICHT verlaesslich vererbt, deshalb wie bei
                    // den beiden Geschwistern oben explizit mitgeben.
                    WeinEinstellungenView().environmentObject(store)
                }
            }
    }

    /// Offenen Wunsch „Wein erfassen" einloesen (Schnellaktion vom App-Icon bzw. Deep-Link).
    /// Verbraucht wird er erst, wenn die Erfassung wirklich auf dem Schirm steht (`onAppear` am
    /// Sheet-Inhalt) — bleibt die Praesentation aus, weil noch ein Sheet eines ANDEREN Tabs oben
    /// liegt, bleibt der Wunsch offen und der naechste `.task`/`.onChange`-Durchlauf versucht es
    /// erneut. Vorbelegung (EAN/Vorschlag) gibt es hier keine: freie Erfassung wie ueber das
    /// Kopf-Menue.
    private func consumeErfassenWunsch() {
        guard app.pendingWeinNew else { return }
        // Die Erfassung steht schon (oder ist bereits angefordert) → Wunsch erfuellt.
        if sheet == WeinSheet.erfassen { app.pendingWeinNew = false; return }
        // Liegt ein anderes Sheet oben (Laden-Scan/Einstellungen), gilt dieselbe Regel wie unten:
        // erst schliessen, kurz warten, dann oeffnen — ein direkter Zielwechsel haengt.
        if sheet == nil { sheet = .erfassen } else { wechsleZuErfassen(ean: "", vorschlag: nil) }
    }

    /// Vom Einkaufs-Scan in die Erfassung: erst schliessen, dann neu oeffnen. Ein direkter
    /// Wechsel des Sheet-Ziels bei offenem Sheet laesst die Animation haengen.
    private func wechsleZuErfassen(ean: String, vorschlag: WeinVorschlag?) {
        sheet = nil
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            // Erst NACH dem Schliessen setzen — das `onDismiss` des Laden-Sheets raeumt die
            // Uebergabe sonst gleich wieder weg.
            erfassenEan = ean
            erfassenVorschlag = vorschlag
            sheet = .erfassen
        }
    }

    /// Sheet schliessen und danach das Detail pushen. Beides im selben Lauf verschluckt UIKit
    /// gelegentlich die Navigation, deshalb die kurze Pause.
    ///
    /// Aus dem Einkaufs-Scan liegt der vollstaendige Datensatz bereits vor (die Lookup-Route
    /// liefert die ganze Zeile) — er wird direkt angezeigt, auch wenn der lokale Bestand ihn noch
    /// nicht kennt. `WeinDetailView` loest live gegen den Store auf, ein spaeter eintreffender
    /// Reload zieht die Ansicht ohne Zutun nach.
    private func oeffneDetail(_ wein: Wein) {
        sheet = nil
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            let vorhanden = store.weine.first { $0.id == wein.id }
            detailWein = vorhanden ?? wein
            if vorhanden == nil { await store.reload() }
        }
    }

    /// Nur die ID bekannt (Dubletten-Karte aus der Erfassung): nachladen und — falls der Wein
    /// danach immer noch fehlt (Netzfehler, Liste gedeckelt) — das sagen. Ohne die Meldung
    /// schliesst sich das Sheet und es passiert sichtbar gar nichts.
    private func oeffneDetail(id: Int) {
        sheet = nil
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            if store.weine.first(where: { $0.id == id }) == nil { await store.reload() }
            if let w = store.weine.first(where: { $0.id == id }) { detailWein = w }
            else { store.notify("Wein konnte nicht geladen werden. Prüfe die Verbindung.", error: true) }
        }
    }

    // ── Kopf-Menue ──

    /// Menue statt drei Knoepfen: der Kopf soll auch bei langer Kennzahlenzeile schmal bleiben.
    private var menu: some View {
        Menu {
            Button { sheet = .erfassen } label: { Label("Wein erfassen", systemImage: "camera.viewfinder") }
            Button { sheet = .laden } label: { Label("Im Laden scannen", systemImage: "barcode.viewfinder") }
            Divider()
            Button { sheet = .einstellungen } label: { Label("Einstellungen", systemImage: "gearshape") }
        } label: {
            Image(systemName: "ellipsis.circle.fill").font(.title2).foregroundStyle(tint)
        }
        .accessibilityIdentifier("wein-menu")
        .accessibilityLabel("Wein-Aktionen")
    }

    // ── Steuerleiste: Segmente + Suche + Filter ──

    private var controls: some View {
        VStack(spacing: 6) {
            SegmentBar(tabs: tabs, selection: $store.tab, gradientKey: "wein")
            AreaSearchField(placeholder: "Wein, Weingut, Rebsorte …", text: $store.suche)
            typFilter
            dropdowns
        }
        .padding(.bottom, 4)
    }

    private var typFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterPill(label: "Alle Farben", selected: store.filterTyp.isEmpty, color: tint) {
                    store.filterTyp = []
                }
                .accessibilityIdentifier("wein-filter-alle")
                ForEach(WeinTyp.allCases) { t in
                    FilterPill(label: t.emoji + " " + t.label, selected: store.filterTyp.contains(t), color: t.farbe) {
                        if store.filterTyp.contains(t) { store.filterTyp.remove(t) } else { store.filterTyp.insert(t) }
                    }
                    .accessibilityIdentifier("wein-filter-" + t.rawValue)
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private var dropdowns: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Menu {
                    Button("Alle Rebsorten") { store.filterRebsorte = nil }
                    ForEach(store.alleRebsorten, id: \.self) { r in
                        Button(r) { store.filterRebsorte = r }
                    }
                } label: {
                    dropdownLabel(icon: "leaf", text: store.filterRebsorte ?? "Rebsorte",
                                  aktiv: store.filterRebsorte != nil)
                }
                .accessibilityIdentifier("wein-menu-rebsorte")

                Menu {
                    Button("Alle Laender") { store.filterLand = nil }
                    ForEach(store.alleLaender, id: \.self) { l in
                        Button(l) { store.filterLand = l }
                    }
                } label: {
                    dropdownLabel(icon: "globe.europe.africa", text: store.filterLand ?? "Land",
                                  aktiv: store.filterLand != nil)
                }
                .accessibilityIdentifier("wein-menu-land")

                Menu {
                    Button("Alle Bewertungen") { store.filterMinSterne = nil }
                    ForEach([3, 4, 5], id: \.self) { n in
                        Button("ab " + String(n) + " Sternen") { store.filterMinSterne = n }
                    }
                } label: {
                    dropdownLabel(icon: "star",
                                  text: store.filterMinSterne.map { "ab " + String($0) } ?? "Sterne",
                                  aktiv: store.filterMinSterne != nil)
                }
                .accessibilityIdentifier("wein-menu-sterne")

                Menu {
                    ForEach(WeinSort.allCases, id: \.rawValue) { s in
                        Button(s.label) { store.sort = s }
                    }
                } label: {
                    dropdownLabel(icon: "arrow.up.arrow.down", text: store.sort.label, aktiv: store.sort != .neueste)
                }
                .accessibilityIdentifier("wein-menu-sortierung")

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
        }
    }

    private func dropdownLabel(icon: String, text: String, aktiv: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
            Text(text).lineLimit(1)
            Image(systemName: "chevron.up.chevron.down").font(.caption2)
        }
        .font(.footnote.weight(.medium))
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(aktiv ? AnyShapeStyle(tint.opacity(0.18)) : AnyShapeStyle(Color(.secondarySystemBackground)),
                    in: Capsule())
        .foregroundStyle(aktiv ? tint : Color.primary)
    }

    /// Keller = Bestandssicht nach Lagerort (`WeinKellerView`), alle uebrigen Segmente = Katalogliste.
    @ViewBuilder private var content: some View {
        if store.loading && store.weine.isEmpty {
            ProgressView("Lädt …").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.tab == .keller {
            WeinKellerView()
        } else {
            WeinListView(onErfassen: { sheet = .erfassen })
        }
    }
}
