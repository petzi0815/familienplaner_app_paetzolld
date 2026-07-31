import SwiftUI
import UIKit

// Einstellungen des Preis-Waechters: GET/PUT /api/v1/wein-einstellungen.
//
// Die drei Werte liegen SERVERSEITIG (app_settings), nicht in @AppStorage: der naechtliche Job
// muss sie kennen, und sie gelten fuer die ganze Familie statt je Geraet. Deshalb wird geladen,
// bearbeitet und bewusst per Knopf gesichert — bei Auto-Save wuerde jeder Regler-Zwischenschritt
// eine PUT-Runde ausloesen.
//
// Der Toast liegt LOKAL an dieser Ansicht: als Sheet ueber der Bereichswurzel waere deren
// AreaScaffold-Toast verdeckt und damit unsichtbar.

struct WeinEinstellungenView: View {
    @EnvironmentObject private var store: WeinStore
    @Environment(\.dismiss) private var dismiss

    // Startwerte = Server-Defaults (7 Tage / 20 % / Push an), damit vor dem Laden nichts springt.
    @State private var intervall: Double = 7
    @State private var rabatt: Double = 20
    @State private var pushAktiv = true
    /// Zuletzt geladener/gesicherter Stand — daran haengt der Sichern-Knopf.
    @State private var gesichert = WeinEinstellungen()

    @State private var laedt = true
    @State private var speichert = false
    @State private var ladefehler: String?
    @State private var message: String?
    @State private var messageIsError = false

    private var tint: Color { Palette.colors(for: "wein").first ?? Theme.accent }

    private var aktuell: WeinEinstellungen {
        var e = WeinEinstellungen()
        e.intervallTage = Int(intervall.rounded())
        e.rabattProzent = Int(rabatt.rounded())
        e.pushAktiv = pushAktiv
        return e
    }
    private var geaendert: Bool { aktuell != gesichert }

    /// Klartext darunter — was der Server mit den Werten tatsaechlich macht.
    private var klartext: String {
        let tage = aktuell.intervallTage
        let basis = "Der Server prüft beobachtete Weine höchstens alle " + String(tage)
            + (tage == 1 ? " Tag" : " Tage")
            + " und merkt sich ein Angebot, wenn es mindestens " + String(aktuell.rabattProzent)
            + " Prozent unter dem Referenzpreis liegt."
        return basis + (pushAktiv
            ? " Bei einem solchen Angebot bekommt die Familie eine Mitteilung aufs Handy."
            : " Mitteilungen sind aus — Angebote stehen dann nur beim Wein in der App.")
    }

    var body: some View {
        NavigationStack {
            Form {
                if let f = ladefehler {
                    Section {
                        Label(f, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline).foregroundStyle(.orange)
                            .accessibilityIdentifier("wein-einstellungen-fehler")
                        Button("Erneut laden") { Task { await laden() } }
                            .accessibilityIdentifier("wein-einstellungen-neuladen")
                    }
                }

                Section {
                    regler(titel: "Alle",
                           wert: String(aktuell.intervallTage) + (aktuell.intervallTage == 1 ? " Tag" : " Tage"),
                           bindung: $intervall, bereich: 1...90,
                           hinweis: "Wie oft derselbe Wein höchstens neu recherchiert wird.",
                           identifier: "wein-einstellungen-intervall")
                } header: {
                    Text("Prüf-Abstand")
                }

                Section {
                    regler(titel: "Mindestens",
                           wert: String(aktuell.rabattProzent) + " %",
                           bindung: $rabatt, bereich: 5...80,
                           hinweis: "Ab dieser Ersparnis gegenüber dem Referenzpreis gilt ein Fund als Angebot.",
                           identifier: "wein-einstellungen-rabatt")
                } header: {
                    Text("Rabattschwelle")
                }

                Section {
                    Toggle("Push bei Angeboten", isOn: $pushAktiv)
                        .tint(tint)
                        .accessibilityIdentifier("wein-einstellungen-push")
                } header: {
                    Text("Mitteilungen")
                } footer: {
                    Text(klartext).accessibilityIdentifier("wein-einstellungen-klartext")
                }

                Section {
                    Button {
                        Task { await sichern() }
                    } label: {
                        HStack {
                            if speichert { ProgressView().padding(.trailing, 4) }
                            Text("Sichern")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(tint)
                    .disabled(laedt || speichert || !geaendert)
                    .accessibilityIdentifier("wein-einstellungen-sichern")
                }
            }
            .disabled(laedt)
            .overlay { if laedt { ProgressView("Lädt Einstellungen …") } }
            .navigationTitle("Preisbeobachtung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }
                        .accessibilityIdentifier("wein-einstellungen-schliessen")
                }
            }
            .task { await laden() }
            .areaToast($message, isError: messageIsError)
        }
    }

    /// Ein Regler + Wertanzeige + Klartext darunter (beide Einstellungen sehen gleich aus).
    private func regler(titel: String, wert: String, bindung: Binding<Double>,
                        bereich: ClosedRange<Double>, hinweis: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(titel).font(.subheadline)
                Spacer(minLength: 8)
                Text(wert).font(.subheadline.weight(.semibold)).monospacedDigit()
            }
            Slider(value: bindung, in: bereich, step: 1)
                .tint(tint)
                .accessibilityIdentifier(identifier)
            Text(hinweis).font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Laden / Sichern

    @MainActor
    private func laden() async {
        laedt = true
        ladefehler = nil
        defer { laedt = false }
        do {
            uebernehmen(try await store.api.einstellungen())
        } catch {
            ladefehler = (error as? APIError)?.errorDescription
                ?? "Die Einstellungen konnten nicht geladen werden."
        }
    }

    @MainActor
    private func sichern() async {
        speichert = true
        defer { speichert = false }
        do {
            // Der Server clampt und normalisiert — sein Ergebnis gewinnt ueber die Regler.
            uebernehmen(try await store.api.saveEinstellungen(aktuell))
            ladefehler = nil
            melden("Einstellungen gesichert")
        } catch {
            melden((error as? APIError)?.errorDescription ?? "Speichern fehlgeschlagen", fehler: true)
        }
    }

    /// Serverantwort auf die Regler legen. Der normalisierte Stand wird EXPLIZIT gebaut und nicht
    /// ueber `aktuell` zurueckgelesen — frisch geschriebene @State-Werte gelten im selben Aufruf
    /// noch nicht zuverlaessig, der Sichern-Knopf bliebe sonst faelschlich aktiv.
    private func uebernehmen(_ e: WeinEinstellungen) {
        var norm = WeinEinstellungen()
        norm.intervallTage = min(90, max(1, e.intervallTage))
        norm.rabattProzent = min(80, max(5, e.rabattProzent))
        norm.pushAktiv = e.pushAktiv
        intervall = Double(norm.intervallTage)
        rabatt = Double(norm.rabattProzent)
        pushAktiv = norm.pushAktiv
        gesichert = norm
    }

    /// Toast + Haptik — dieselbe Rueckmeldung wie in den Bereichs-Stores, nur lokal am Sheet.
    private func melden(_ text: String, fehler: Bool = false) {
        message = text
        messageIsError = fehler
        if fehler { UINotificationFeedbackGenerator().notificationOccurred(.error) }
        else { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    }
}
