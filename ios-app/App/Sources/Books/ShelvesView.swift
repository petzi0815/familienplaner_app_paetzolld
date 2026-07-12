import SwiftUI

/// Regale-Landing: Raster der Bücherregale, Anlegen/Bearbeiten/Löschen (mit Umzug).
struct ShelvesView: View {
    @EnvironmentObject private var store: BooksStore
    @State private var showCreate = false
    @State private var editShelf: Bookshelf?
    @State private var deleteShelf: Bookshelf?
    private let cols = [GridItem(.adaptive(minimum: 160), spacing: 12)]

    var body: some View {
        ScrollView {
            HStack {
                Text("Bücherregale").font(.title2.weight(.bold))
                Spacer()
                Button { showCreate = true } label: { Label("Neues Regal", systemImage: "plus") }
                    .buttonStyle(.borderedProminent).tint(BookTheme.amber700)
            }
            .padding(.horizontal).padding(.top, 8)

            if store.shelves.isEmpty {
                ContentUnavailableView("Keine Regale vorhanden", systemImage: "books.vertical",
                                       description: Text("Erstellen Sie Ihr erstes Bücherregal, um mit der Organisation zu beginnen."))
                    .padding(.top, 40)
            } else {
                LazyVGrid(columns: cols, spacing: 12) {
                    ForEach(store.shelves) { s in shelfCard(s) }
                }
                .padding()
            }
        }
        .sheet(isPresented: $showCreate) { ShelfEditSheet(shelf: nil) }
        .sheet(item: $editShelf) { ShelfEditSheet(shelf: $0) }
        .sheet(item: $deleteShelf) { ShelfDeleteSheet(shelf: $0) }
    }

    private func shelfCard(_ s: Bookshelf) -> some View {
        let count = store.bookCount(shelf: s.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(BookTheme.shelfColor(s.color)).frame(width: 14, height: 14)
                Text(s.name).font(.headline).lineLimit(1)
                Spacer()
                if store.shelves.count > 1 {
                    Menu {
                        Button { editShelf = s } label: { Label("Bearbeiten", systemImage: "pencil") }
                        Button(role: .destructive) { deleteShelf = s } label: { Label("Löschen", systemImage: "trash") }
                    } label: { Image(systemName: "ellipsis").foregroundStyle(.secondary).padding(4) }
                }
            }
            Text(s.description?.isEmpty == false ? s.description! : "Keine Beschreibung")
                .font(.caption).foregroundStyle(.secondary).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            Text("\(count) Bücher").font(.caption.weight(.semibold)).foregroundStyle(BookTheme.amber700)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(BookTheme.shelfColor(s.color).opacity(0.25)))
        .contentShape(Rectangle())
        .onTapGesture {
            store.activeShelf = s.id
            store.filters.bookshelf = s.id
            store.currentView = .books
        }
    }
}

/// Anlegen/Bearbeiten eines Regals (Name, Beschreibung, Farbe).
struct ShelfEditSheet: View {
    @EnvironmentObject private var store: BooksStore
    @Environment(\.dismiss) private var dismiss
    let shelf: Bookshelf?
    @State private var name = ""
    @State private var desc = ""
    @State private var color = "#3B82F6"

    var body: some View {
        NavigationStack {
            Form {
                Section("Name des Regals") {
                    TextField("z.B. Romane, Sachbücher …", text: $name)
                }
                Section("Beschreibung (optional)") {
                    TextField("Beschreibung", text: $desc, axis: .vertical).lineLimit(1...4)
                }
                Section("Farbe") {
                    HStack(spacing: 14) {
                        ForEach(SHELF_COLORS, id: \.self) { c in
                            Circle().fill(Color(hex: c)).frame(width: 30, height: 30)
                                .overlay(Circle().strokeBorder(.primary, lineWidth: color == c ? 3 : 0))
                                .onTapGesture { color = c }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(shelf == nil ? "Neues Regal" : "Regal bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        Task {
                            if let shelf { await store.updateShelf(shelf.id, name: name, description: desc, color: color) }
                            else { await store.createShelf(name: name, description: desc, color: color) }
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let shelf { name = shelf.name; desc = shelf.description ?? ""; color = shelf.color }
            }
        }
    }
}

/// Regal löschen — bei vorhandenen Büchern Zielregal für den Umzug wählen.
struct ShelfDeleteSheet: View {
    @EnvironmentObject private var store: BooksStore
    @Environment(\.dismiss) private var dismiss
    let shelf: Bookshelf
    @State private var target: String = ""

    private var count: Int { store.bookCount(shelf: shelf.id) }
    private var others: [Bookshelf] { store.shelves.filter { $0.id != shelf.id } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Regal \"\(shelf.name)\" löschen?").font(.headline)
                    if count > 0 {
                        Label("\(count) Bücher in diesem Regal müssen umziehen.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange).font(.subheadline)
                        Picker("Zielregal", selection: $target) {
                            Text("— wählen —").tag("")
                            ForEach(others) { s in Text(s.name).tag(s.id) }
                        }
                    } else {
                        Text("Dieses Regal ist leer.").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Regal löschen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Löschen", role: .destructive) {
                        Task { await store.deleteShelf(shelf.id, transferTo: target.isEmpty ? nil : target); dismiss() }
                    }
                    .disabled(count > 0 && target.isEmpty)
                }
            }
        }
    }
}
