import SwiftUI

// Rezeptur-Tab des Pizza-Bereichs.
//
// Das Feature ist ein Experimentier-Logbuch, keine Favoritenliste: eine Rezeptur laedt man in den
// Planer, backt sie, und haelt danach fest, was beim naechsten Mal anders soll. Deshalb steht der
// Notiz-Log im Detail gleichberechtigt neben der Konfiguration und nicht in einer Nebenansicht.
//
// Speichern der AKTUELLEN Einstellungen bietet das Toolbar-Menue der PizzaRootView an — hier wird
// es bewusst nicht dupliziert; der Leerzustand fuehrt stattdessen in den Planer zurueck.

// MARK: - Liste

struct PizzaRezepteView: View {
    @EnvironmentObject private var store: PizzaStore
    @State private var loeschKandidat: PizzaRezept?

    private var uebrige: [PizzaRezept] { store.rezepte.filter { !$0.favorit } }

    var body: some View {
        Group {
            if !store.rezepte.isEmpty {
                liste
            } else if store.loading {
                ProgressView("Lädt Rezepturen …").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                leer
            }
        }
        // Die Notiz-Zähler der Zeilen brauchen die Notizen aller Rezepturen. Geladen wird nur, was
        // fehlt (`store.notizen` cacht) — nach dem ersten Durchlauf ist die Schleife ein No-Op, und
        // `id:` lässt sie nur neu laufen, wenn sich die Menge der Rezepturen ändert.
        .task(id: store.rezepte.map(\.id)) { await ladeFehlendeNotizen() }
        // `presenting:` reicht die Rezeptur in die Closures durch. Sie im Button aus `loeschKandidat`
        // zu lesen waere ein Fehler: beim Schliessen setzt der Dialog `isPresented` (und damit den
        // Kandidaten) zurueck — die Aktion haette dann womoeglich nichts mehr zu loeschen.
        .confirmationDialog("Rezeptur löschen?", isPresented: loeschDialog, titleVisibility: .visible,
                            presenting: loeschKandidat) { r in
            Button("Löschen", role: .destructive) { Task { await store.loescheRezept(r) } }
            Button("Abbrechen", role: .cancel) { }
        } message: { r in
            Text(r.name + " und alle Notizen dazu werden entfernt.")
        }
    }

    private var loeschDialog: Binding<Bool> {
        Binding(get: { loeschKandidat != nil }, set: { if !$0 { loeschKandidat = nil } })
    }

    private var leer: some View {
        // `List` rendert Leerzustände schlecht → eigener scrollbarer Zweig (Pull-to-Refresh bleibt).
        ScrollView {
            AreaEmptyState(emoji: "🍕",
                           title: "Noch keine Rezepturen",
                           hint: "Stelle im Planer deinen Teig ein und sichere ihn über das Menü oben rechts. Danach hältst du hier fest, wie er geworden ist.",
                           actionLabel: "Rezeptur anlegen",
                           action: { store.tab = .planer })
                .frame(minHeight: 300)
                .accessibilityIdentifier("pizza-rezepte-empty")
        }
        .refreshable { await store.loadRezepte() }
    }

    private var liste: some View {
        List {
            if store.favoriten.isEmpty {
                Section { zeilen(store.rezepte) }
            } else {
                Section { zeilen(store.favoriten) } header: { Text("★ Favoriten") }
                    .textCase(nil)
                if !uebrige.isEmpty {
                    Section { zeilen(uebrige) } header: { Text("Alle Rezepturen") }
                        .textCase(nil)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await store.loadRezepte() }
    }

    @ViewBuilder private func zeilen(_ items: [PizzaRezept]) -> some View {
        ForEach(items) { r in
            // Closure-basiert: wertbasierte NavigationLinks sind in bereits gepushten Views flaky.
            NavigationLink {
                PizzaRezeptDetailView(rezeptId: r.id).environmentObject(store)
            } label: {
                PizzaRezeptRow(rezept: r, notizAnzahl: store.notizen[r.id]?.count)
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14))
            .accessibilityIdentifier("pizza-rezept-row-\(String(r.id))")
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                // Kein Full-Swipe: Löschen nimmt die Notizen per CASCADE mit — das braucht eine Rückfrage.
                Button(role: .destructive) { loeschKandidat = r } label: {
                    Label("Löschen", systemImage: "trash")
                }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button { Task { await store.toggleFavorit(r) } } label: {
                    Label(r.favorit ? "Nicht mehr Favorit" : "Favorit",
                          systemImage: r.favorit ? "star.slash" : "star")
                }
                .tint(.yellow)
            }
        }
    }

    private func ladeFehlendeNotizen() async {
        for r in store.rezepte where store.notizen[r.id] == nil {
            if Task.isCancelled { return }
            await store.loadNotizen(r.id)
        }
    }
}

// MARK: - Zeile

private struct PizzaRezeptRow: View {
    let rezept: PizzaRezept
    /// nil = Notizen noch nicht geladen (dann bleibt der Zähler weg, statt 0 zu behaupten).
    let notizAnzahl: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                if rezept.favorit {
                    Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
                }
                Text(rezept.name).font(.subheadline.weight(.semibold)).lineLimit(1)
            }
            Text(PizzaRezeptText.kurzfassung(rezept.config))
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            if let n = rezept.notiz, !n.isEmpty {
                Text(n).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
            HStack(spacing: 8) {
                if let a = notizAnzahl, a > 0 {
                    Pill(text: PizzaRezeptText.notizen(a), systemImage: "text.bubble",
                         color: PizzaRezeptStil.tint, filled: false)
                }
                let d = PizzaText.datum(rezept.updatedAt)
                if !d.isEmpty { Text(d).font(.caption2).foregroundStyle(.tertiary) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Detail

private struct PizzaRezeptDetailView: View {
    let rezeptId: Int
    @EnvironmentObject private var store: PizzaStore
    @Environment(\.dismiss) private var dismiss

    @State private var bearbeiten: PizzaRezept?
    @State private var confirmLoeschen = false
    @State private var confirmUeberschreiben = false

    @State private var notizText = ""
    @State private var bewertung: Int?
    @State private var gebackenAm = Date()
    @State private var speichertNotiz = false

    /// Immer frisch aus dem Store lesen: nach Umbenennen/Überschreiben lädt der Store neu, und
    /// eine mitgereichte Kopie wäre dann veraltet.
    private var rezept: PizzaRezept? { store.rezepte.first { $0.id == rezeptId } }
    private var notizen: [PizzaNotiz] { store.notizen[rezeptId] ?? [] }

    var body: some View {
        Group {
            if let r = rezept {
                inhalt(r)
            } else {
                AreaEmptyState(emoji: "🍕", title: "Rezeptur nicht mehr vorhanden")
            }
        }
        .navigationTitle(rezept?.name ?? "Rezeptur")
        .navigationBarTitleDisplayMode(.inline)
        .background(Palette.gradient(for: "pizza").opacity(0.05).ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { menu }
        }
        .task { await store.loadNotizen(rezeptId) }
        .sheet(item: $bearbeiten) { r in PizzaRezeptFormSheet(rezept: r).environmentObject(store) }
        // Eigener Toast: der des AreaScaffold liegt unter dieser gepushten View und wäre unsichtbar.
        .areaToast($store.message, isError: store.messageIsError)
        .confirmationDialog(rezept.map { $0.name + " löschen?" } ?? "Rezeptur löschen?",
                            isPresented: $confirmLoeschen, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                if let r = rezept { Task { await store.loescheRezept(r); dismiss() } }
            }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text("Die Rezeptur und alle Notizen dazu werden entfernt.")
        }
        .confirmationDialog("Rezeptur überschreiben?", isPresented: $confirmUeberschreiben,
                            titleVisibility: .visible) {
            Button("Überschreiben", role: .destructive) {
                if let r = rezept { Task { await store.aktualisiereRezept(r) } }
            }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text("Die gespeicherten Einstellungen werden durch die aktuellen Planer-Einstellungen ersetzt. Die Notizen bleiben erhalten.")
        }
    }

    private var menu: some View {
        Menu {
            Button { bearbeiten = rezept } label: {
                Label("Umbenennen & Notiz", systemImage: "pencil")
            }
            Button { if let r = rezept { Task { await store.toggleFavorit(r) } } } label: {
                let fav = rezept?.favorit ?? false
                Label(fav ? "Favorit lösen" : "Als Favorit merken", systemImage: fav ? "star.slash" : "star")
            }
            // Der Weg zum Variieren: laden → im Planer schrauben → hier festschreiben.
            Button { confirmUeberschreiben = true } label: {
                Label("Mit Planer-Einstellungen überschreiben", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(rezept.map { $0.config == store.config } ?? true)
            Divider()
            Button(role: .destructive) { confirmLoeschen = true } label: {
                Label("Löschen", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityIdentifier("pizza-rezept-menu")
        .accessibilityLabel("Rezeptur-Aktionen")
    }

    @ViewBuilder private func inhalt(_ r: PizzaRezept) -> some View {
        List {
            Section {
                Button { laden(r) } label: {
                    Label("In den Planer laden", systemImage: "arrow.down.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GradientButtonStyle(gradientKey: "pizza"))
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .accessibilityIdentifier("pizza-rezept-laden")
            }

            Section { konfiguration(r.config) } header: { Text("Konfiguration") }
                .textCase(nil)

            Section { rezeptNotiz(r) } header: { Text("Notiz zur Rezeptur") } footer: {
                Text("Beschreibt die Rezeptur selbst. Wie ein einzelner Backversuch war, gehört in die Notizen darunter.")
            }
            .textCase(nil)

            Section { neueNotiz } header: { Text("Neue Notiz") }
                .textCase(nil)

            Section { notizListe } header: { Text(PizzaRezeptText.notizenHeader(notizen.count)) }
                .textCase(nil)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder private func konfiguration(_ c: PizzaConfig) -> some View {
        InfoRow(icon: "🍕", label: "Menge", value: PizzaRezeptText.menge(c))
        InfoRow(icon: "🌾", label: "Mehl", value: c.mehltyp.label)
        InfoRow(icon: "💧", label: "Hydration", value: PizzaRezeptText.hydration(c) + " %")
        InfoRow(icon: "🫧", label: "Hefe", value: c.hefetyp.label)
        InfoRow(icon: "🌡️", label: "Raumtemperatur", value: PizzaCalculator.grad(c.raumtempC) + " °C")
        if c.mehltempOverride != nil {
            InfoRow(icon: "🧊", label: "Mehltemperatur", value: PizzaCalculator.grad(c.mehltempC) + " °C")
        }
        InfoRow(icon: "🥣", label: "Kneten", value: c.mehltyp.knetzeitText(c.knetmethode))
        InfoRow(icon: "🌙", label: "Nachtruhe", value: PizzaRezeptText.nachtruhe(c))
        if c.kFaktor != PizzaKonstanten.kDefault {
            InfoRow(icon: "⚙️", label: "K-Faktor", value: PizzaCalculator.grad(c.kFaktor))
        }
    }

    @ViewBuilder private func rezeptNotiz(_ r: PizzaRezept) -> some View {
        if let n = r.notiz, !n.isEmpty {
            Button { bearbeiten = r } label: {
                NoteBlock(icon: "📝", text: n, tint: PizzaRezeptStil.tint)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("pizza-rezept-notiz-bearbeiten")
        } else {
            Button { bearbeiten = r } label: {
                Label("Notiz zur Rezeptur hinzufügen", systemImage: "square.and.pencil")
            }
            .accessibilityIdentifier("pizza-rezept-notiz-bearbeiten")
        }
    }

    @ViewBuilder private var neueNotiz: some View {
        TextField("Wie ist der Teig geworden? Was beim nächsten Mal ändern?",
                  text: $notizText, axis: .vertical)
            .lineLimit(2...6)
            .accessibilityIdentifier("pizza-notiz-text")
        HStack {
            Text("Bewertung").foregroundStyle(.secondary)
            Spacer(minLength: 8)
            PizzaSternePicker(bewertung: $bewertung)
        }
        DatePicker("Gebacken am", selection: $gebackenAm, displayedComponents: .date)
        Button { Task { await sichereNotiz() } } label: {
            Label(speichertNotiz ? "Sichert …" : "Notiz sichern", systemImage: "plus.circle.fill")
        }
        .disabled(notizText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || speichertNotiz)
        .accessibilityIdentifier("pizza-notiz-speichern")
    }

    @ViewBuilder private var notizListe: some View {
        if notizen.isEmpty {
            Text("Noch nichts festgehalten. Nach dem Backen ist die beste Zeit dafür.")
                .font(.footnote).foregroundStyle(.secondary)
        } else {
            ForEach(notizen) { n in
                PizzaNotizRow(notiz: n)
                    .accessibilityIdentifier("pizza-notiz-row-\(String(n.id))")
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { Task { await store.loescheNotiz(n) } } label: {
                            Label("Löschen", systemImage: "trash")
                        }
                    }
            }
        }
    }

    private func laden(_ r: PizzaRezept) {
        store.ladeRezept(r)   // setzt config + tab = .planer und toastet selbst
        dismiss()             // sonst bliebe das Detail über dem Planer stehen
    }

    private func sichereNotiz() async {
        speichertNotiz = true
        defer { speichertNotiz = false }
        if await store.addNotiz(rezeptId: rezeptId, text: notizText,
                                bewertung: bewertung, gebackenAm: gebackenAm) {
            notizText = ""
            bewertung = nil
        }
    }
}

// MARK: - Notiz-Zeile + Sterne

private struct PizzaNotizRow: View {
    let notiz: PizzaNotiz

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                if let b = notiz.bewertung { PizzaSterne(bewertung: b) }
                Spacer(minLength: 0)
                let d = PizzaText.datum(notiz.gebackenAm ?? notiz.createdAt)
                if !d.isEmpty { Text(d).font(.caption2).foregroundStyle(.secondary) }
            }
            Text(notiz.text).font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 3)
    }
}

private struct PizzaSterne: View {
    let bewertung: Int
    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: i <= bewertung ? "star.fill" : "star")
                    .font(.caption2)
                    .foregroundStyle(i <= bewertung ? Color.yellow : Color.secondary.opacity(0.4))
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Bewertung " + String(bewertung) + " von 5")
    }
}

/// Sterne zum Antippen. Nochmal auf denselben Stern = Bewertung wieder weg (sie ist optional).
private struct PizzaSternePicker: View {
    @Binding var bewertung: Int?
    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { i in
                Button {
                    bewertung = (bewertung == i) ? nil : i
                } label: {
                    Image(systemName: (bewertung ?? 0) >= i ? "star.fill" : "star")
                        .foregroundStyle((bewertung ?? 0) >= i ? Color.yellow : Color.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(i) + " von 5 Sternen")
                .accessibilityIdentifier("pizza-notiz-stern-\(String(i))")
            }
        }
    }
}

// MARK: - Umbenennen / Notiz bearbeiten

/// Name + Notiz einer gespeicherten Rezeptur.
///
/// Bewusst NICHT über `store.aktualisiereRezept(_:name:notiz:)`: das schreibt die AKTUELLE
/// Planer-Konfiguration in die Rezeptur — beim reinen Umbenennen würde es also die gespeicherten
/// Einstellungen still überschreiben. Ein PATCH nur auf name/notiz lässt den Rest der Zeile in
/// Ruhe (generisches CRUD nimmt Teilfelder). Das Überschreiben mit den Planer-Werten ist im
/// Detail-Menü eine eigene, bestätigte Aktion.
private struct PizzaRezeptFormSheet: View {
    let rezept: PizzaRezept
    @EnvironmentObject private var store: PizzaStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var notiz = ""
    @State private var speichert = false

    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("Name", text: $name).accessibilityIdentifier("pizza-rezept-name") }
                Section {
                    TextField("Woran willst du dich erinnern?", text: $notiz, axis: .vertical)
                        .lineLimit(3...8)
                        .accessibilityIdentifier("pizza-rezept-notiz")
                } header: {
                    Text("Notiz zur Rezeptur")
                } footer: {
                    Text("Ein Satz zur Rezeptur selbst — etwa wofür du sie nimmst oder was sie von den anderen unterscheidet.")
                }
                .textCase(nil)
            }
            .navigationTitle("Rezeptur bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { Task { await sichere() } }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || speichert)
                        .accessibilityIdentifier("pizza-rezept-sichern")
                }
            }
            .onAppear {
                name = rezept.name
                notiz = rezept.notiz ?? ""
            }
        }
    }

    private func sichere() async {
        speichert = true
        defer { speichert = false }
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = notiz.trimmingCharacters(in: .whitespacesAndNewlines)
        let notizWert: String? = t.isEmpty ? nil : t
        var b: [String: Any] = ["name": n]
        // NSNull statt Weglassen: eine geleerte Notiz muss auch serverseitig verschwinden.
        b["notiz"] = notizWert.map { $0 as Any } ?? NSNull()
        do {
            try await store.api.updateRezept(rezept.id, b)
            await store.loadRezepte()
            store.notify("Rezeptur gesichert")
            dismiss()
        } catch {
            store.notify(store.errText(error), error: true)
        }
    }
}

// MARK: - Textbausteine

private enum PizzaRezeptStil {
    /// Erste Farbe des Bereichsverlaufs — Pills/Notizblöcke bleiben so am Bereich.
    static var tint: Color { Palette.colors(for: "pizza").first ?? Theme.accent }
}

private enum PizzaRezeptText {
    /// "6 × 275 g · Tipo 00 · 62,5 % · 22 °C"
    static func kurzfassung(_ c: PizzaConfig) -> String {
        [menge(c), c.mehltyp.label, hydration(c) + " %", PizzaCalculator.grad(c.raumtempC) + " °C"]
            .joined(separator: " · ")
    }

    static func menge(_ c: PizzaConfig) -> String {
        String(c.anzahlPizzen) + " × " + PizzaCalculator.gramm(c.teiglingsgewichtG) + " g"
    }

    /// `grad(_:)` ist der 0–1-Nachkommastellen-Formatter des Rechenkerns (62,5 statt 62,50) — der
    /// Name kommt von seinem ersten Einsatzort, das Format passt für die Hydration exakt.
    static func hydration(_ c: PizzaConfig) -> String { PizzaCalculator.grad(c.hydration * 100) }

    static func nachtruhe(_ c: PizzaConfig) -> String {
        c.nachtruheAktiv ? c.schlafVonHHmm + " – " + c.schlafBisHHmm : "keine"
    }

    static func notizen(_ n: Int) -> String { String(n) + (n == 1 ? " Notiz" : " Notizen") }

    /// "Notizen" bzw. "Notizen (3)" — als fertiger String, damit im ViewBuilder kein Text/LocalizedStringKey
    /// aus einem Ternaer abgeleitet werden muss.
    static func notizenHeader(_ n: Int) -> String { n == 0 ? "Notizen" : "Notizen (" + String(n) + ")" }
}
