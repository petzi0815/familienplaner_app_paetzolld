import SwiftUI

/// Neues-Futter-Formular (Bottom-Sheet). Nur die 4 PWA-Felder Marke/Sorte/Geschmack/Notizen;
/// Status defaultet serverseitig auf `mag_er`. Eigener NavigationStack ist als Sheet erlaubt.
struct GypsiAddSheet: View {
    @EnvironmentObject private var store: GypsiStore
    @Environment(\.dismiss) private var dismiss

    @State private var marke = ""
    @State private var sorte = ""
    @State private var geschmack = ""
    @State private var notizen = ""
    @State private var saving = false

    private var canSave: Bool {
        !marke.trimmingCharacters(in: .whitespaces).isEmpty
            && !sorte.trimmingCharacters(in: .whitespaces).isEmpty
            && !saving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Pflichtangaben") {
                    LabeledContent("Marke") { TextField("z.B. Animonda, MjAMjAM", text: $marke) }
                    LabeledContent("Sorte") { TextField("z.B. Carny Adult Rind & Huhn", text: $sorte) }
                }
                Section("Optional") {
                    LabeledContent("Geschmack") { TextField("z.B. Rind, Huhn, Fisch", text: $geschmack) }
                    TextField("Notizen (optional) …", text: $notizen, axis: .vertical).lineLimit(2...4)
                }
            }
            .navigationTitle("🐱 Neues Futter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hinzufügen") { Task { await submit() } }.disabled(!canSave)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func submit() async {
        saving = true
        let ok = await store.add(
            marke: marke.trimmingCharacters(in: .whitespaces),
            sorte: sorte.trimmingCharacters(in: .whitespaces),
            geschmack: geschmack.trimmingCharacters(in: .whitespaces),
            notizen: notizen.trimmingCharacters(in: .whitespaces))
        saving = false
        if ok { dismiss() }
    }
}
