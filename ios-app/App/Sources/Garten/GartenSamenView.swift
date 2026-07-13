import SwiftUI

/// Samen-Tab: Suche + Status-/Eigenschafts-Pills + Hersteller/Bio/Typ-Dropdowns, Inline-Add,
/// vertikale Liste mit Foto-Thumbnail + Aktiv-Schalter, reiches Detail-Sheet.
struct GartenSamenView: View {
    @EnvironmentObject private var store: GartenStore
    @State private var detail: GartenSamen?
    @State private var showAdd = false
    private let green = Color(hex: "34C759")

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                AreaSearchField(placeholder: "Samen suchen …", text: $store.samenFilter.search)
                filterPills
                dropdowns
                addSection
                list
            }
            .padding(.bottom, 24)
        }
        .refreshable { await store.reloadSamen() }
        .task(id: store.samenFilter) {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if !Task.isCancelled { await store.reloadSamen() }
        }
        .sheet(item: $detail) { s in
            GartenSamenDetailSheet(samen: s).environmentObject(store)
        }
    }

    private var filterPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterPill(label: "✅ Aktiv", selected: store.samenFilter.aktiv == 1, color: green) {
                    store.samenFilter.aktiv = (store.samenFilter.aktiv == 1) ? -1 : 1
                }
                FilterPill(label: "⏸️ Inaktiv", selected: store.samenFilter.aktiv == 0, color: Color(hex: "EA580C")) {
                    store.samenFilter.aktiv = (store.samenFilter.aktiv == 0) ? -1 : 0
                }
                FilterPill(label: "🌱 Samenfest", selected: store.samenFilter.samenfest == 1, color: green) {
                    store.samenFilter.samenfest = (store.samenFilter.samenfest == 1) ? -1 : 1
                }
                FilterPill(label: "✅ Keimfähig", selected: store.samenFilter.keimfaehig == "ok", color: green) {
                    store.samenFilter.keimfaehig = (store.samenFilter.keimfaehig == "ok") ? "" : "ok"
                }
                FilterPill(label: "⚠️ Abgelaufen", selected: store.samenFilter.keimfaehig == "abgelaufen", color: Color(hex: "D97706")) {
                    store.samenFilter.keimfaehig = (store.samenFilter.keimfaehig == "abgelaufen") ? "" : "abgelaufen"
                }
            }
            .padding(.horizontal, 14)
        }
    }

    private var dropdowns: some View {
        HStack(spacing: 10) {
            Menu {
                Button("Alle Hersteller") { store.samenFilter.hersteller = "" }
                ForEach(store.herstellerOptions, id: \.self) { h in
                    Button(h) { store.samenFilter.hersteller = h }
                }
            } label: {
                dropdownLabel(icon: "building.2", text: store.samenFilter.hersteller.isEmpty ? "Hersteller" : store.samenFilter.hersteller)
            }

            Menu {
                Button("Alle Bio") { store.samenFilter.bio = "" }
                Button("Bio") { store.samenFilter.bio = "Bio" }
                Button("Demeter") { store.samenFilter.bio = "Demeter" }
            } label: {
                dropdownLabel(icon: "leaf", text: store.samenFilter.bio.isEmpty ? "Bio" : store.samenFilter.bio)
            }

            Menu {
                Button("Alle Typen") { store.samenFilter.typ = "" }
                ForEach(store.samenTypOptions, id: \.self) { t in
                    Button(t) { store.samenFilter.typ = t }
                }
            } label: {
                dropdownLabel(icon: "tag", text: store.samenFilter.typ.isEmpty ? "Typ" : store.samenFilter.typ)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
    }

    private func dropdownLabel(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
            Text(text).lineLimit(1)
            Image(systemName: "chevron.up.chevron.down").font(.caption2)
        }
        .font(.footnote.weight(.medium))
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Color(.secondarySystemBackground), in: Capsule())
        .foregroundStyle(.primary)
    }

    @ViewBuilder private var addSection: some View {
        if showAdd {
            GartenNameAddForm(title: "🌱 Neuen Samen hinzufügen", accent: green, placeholder: "Name eingeben …",
                              onCancel: { showAdd = false }) { name in
                let ok = await store.addSamen(name: name)
                if ok { showAdd = false }
                return ok
            }
            .padding(.horizontal, 14)
        } else {
            Button { withAnimation { showAdd = true } } label: {
                Label("Neuen Samen hinzufügen", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(green, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(green.onFill)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
        }
    }

    @ViewBuilder private var list: some View {
        if store.samen.isEmpty {
            AreaEmptyState(emoji: "🔍", title: "Keine Samen gefunden!", hint: "Versuch andere Filter 🎯")
                .frame(minHeight: 220)
        } else {
            VStack(spacing: 10) {
                ForEach(store.samen) { s in
                    GartenSamenCard(samen: s,
                                    onOpen: { detail = s },
                                    onToggle: { Task { await store.toggleSamenAktiv(s) } })
                }
            }
            .padding(.horizontal, 14)
        }
    }
}

// MARK: - Karte

struct GartenSamenCard: View {
    let samen: GartenSamen
    var onOpen: () -> Void
    var onToggle: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                thumb
                body_
            }
            .contentShape(Rectangle())
            .onTapGesture { onOpen() }

            toggle
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var thumb: some View {
        Group {
            if let path = samen.firstImagePath {
                AuthImage(path: path, contentMode: .fill)
            } else {
                LinearGradient(colors: [Color(hex: "D1FAE5"), Color(hex: "DCFCE7")], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(Text(samen.emoji).font(.system(size: 30)).opacity(0.6))
            }
        }
        .frame(width: 80, height: 80)
        .clipped()
    }

    private var body_: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("#\(samen.nummer)").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color(.tertiarySystemFill), in: Capsule())
                if let art = samen.art, !art.isEmpty {
                    Pill(text: "\(samen.emoji) \(art)", color: Color(hex: "10B981"), filled: false)
                }
                Pill(text: samen.aktiv ? "Aktiv" : "Inaktiv", color: samen.aktiv ? Color(hex: "16A34A") : Color(hex: "EA580C"), filled: false)
            }
            Text(samen.name).font(.subheadline.weight(.bold)).lineLimit(1)
            let pflanz = GartenStyle.monthRange(samen.pflanzVon, samen.pflanzBis)
            let ernte = GartenStyle.monthRange(samen.ernteVon, samen.ernteBis)
            if !pflanz.isEmpty || !ernte.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(pflanz.enumerated()), id: \.offset) { _, m in
                        Text("🌱 \(m)").font(.system(size: 10, weight: .bold)).foregroundStyle(Color(hex: "059669"))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color(hex: "10B981").opacity(0.12), in: Capsule())
                    }
                    ForEach(Array(ernte.enumerated()), id: \.offset) { _, m in
                        Text("🌾 \(m)").font(.system(size: 10, weight: .bold)).foregroundStyle(Color(hex: "C2410C"))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color(hex: "F97316").opacity(0.12), in: Capsule())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
    }

    private var toggle: some View {
        Button(action: onToggle) {
            (samen.aktiv ? Color(hex: "22C55E") : Color.gray.opacity(0.4))
                .frame(width: 44)
                .overlay(Circle().fill(samen.aktiv ? Color.white : Color.gray).frame(width: 18, height: 18))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Wiederverwendbares Name-Only Add-Formular

struct GartenNameAddForm: View {
    let title: String
    var accent: Color
    var placeholder: String
    var onCancel: () -> Void
    var onSubmit: (String) async -> Bool

    @State private var name = ""
    @State private var saving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            HStack {
                TextField(placeholder, text: $name)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .onSubmit { submit() }
                Button(action: { submit() }) {
                    Image(systemName: "checkmark").fontWeight(.bold)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(accent, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(accent.onFill)
                }
                .buttonStyle(.plain)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func submit() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !saving else { return }
        Task {
            saving = true
            _ = await onSubmit(trimmed)
            saving = false
            name = ""
        }
    }
}
