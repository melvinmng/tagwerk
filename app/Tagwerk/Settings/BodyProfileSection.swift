import HealthBridge
import SwiftUI
import TagwerkCore

/// The section "Körper" of Einstellungen › Erfassen (decision 4A, #317): height, birth year and the sex of the formula, each
/// editable at any time. An edited value wins over Health; a line below each value says where it comes from and where it goes.
/// Tagwerk writes the height to Health. Date of birth and sex cannot be written by apps (iOS offers them read-only), so they stay
/// a local override that only the Health app can change in Health itself. The values feed the cross-check of the goal planning;
/// nothing is sent anywhere from here.
struct BodyProfileSection: View {
    let store: BodyProfileStore
    /// Whether Health takes the height; drives the line below the height. `nil` before the first query.
    let heightWriteAccess: HealthWriteAccess?
    @Environment(\.openURL) private var openURL

    var body: some View {
        let profile = store.profile
        let health = store.healthValues
        Section {
            heightRow(profile.height, health: health.heightCm.map { Int($0) })
            birthYearRow(profile.birthYear, health: health.birthYear)
            sexRow(profile.sex, health: health.sex)
            Button("Aus Health lesen") { Task { await store.readFromHealth() } }
                .accessibilityIdentifier(AccessibilityID.BodyProfile.readButton)
                // Once when the section appears; a modifier on the `Section` itself would run once per row.
                .task { await store.refresh() }
            Button("Geburtsdatum und Geschlecht in Health ändern") {
                if let url = URL(string: "x-apple-health://") { openURL(url) }
            }
            .accessibilityIdentifier(AccessibilityID.BodyProfile.openHealthButton)
        } header: {
            Text("Körper")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if store.lastRead == .nothingDelivered {
                    Text("Health hat nichts geliefert. Entweder fehlt die Angabe in Health oder das Lesen ist nicht erlaubt; iOS teilt Tagwerk das nicht mit. Trage die Werte hier ein oder erlaube das Lesen in Health › Teilen › Apps › Tagwerk.")
                        .accessibilityIdentifier(AccessibilityID.BodyProfile.nothingDelivered)
                }
                Text("Größe, Alter und Geschlecht rechnen nur auf diesem iPhone: Tagwerk prüft damit Zielvorschläge. Gespeichert werden die Größe in ganzen Zentimetern, das Geburtsjahr und das Geschlecht der Formel, nie das Geburtsdatum. Die Größe schreibt Tagwerk nach Health. Geburtsdatum und Geschlecht kann nur die Health-App ändern, iOS erlaubt Apps das nicht: trägst du hier etwas anderes ein, rechnet Tagwerk damit und Health bleibt unverändert. Leere das Feld, damit wieder der Wert aus Health gilt.")
            }
        }
    }

    // MARK: Rows

    private func heightRow(_ field: BodyValue<Int>, health: Int?) -> some View {
        LabeledContent {
            HStack(spacing: 4) {
                TextField("fehlt", value: Binding(get: { store.profile.height.value },
                                                  set: { value in Task { await store.updateHeight(value) } }),
                          format: .number.grouping(.never))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(maxWidth: 80)
                    .accessibilityIdentifier(AccessibilityID.BodyProfile.heightField)
                Text("cm").foregroundStyle(.secondaryText)
            }
        } label: {
            label("Größe", note: Self.heightNote(source: field.source, value: field.value, health: health,
                                                  writeAccess: heightWriteAccess))
        }
    }

    private func birthYearRow(_ field: BodyValue<Int>, health: Int?) -> some View {
        LabeledContent {
            TextField("fehlt", value: Binding(get: { store.profile.birthYear.value }, set: { store.setTypedBirthYear($0) }),
                      format: .number.grouping(.never))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(maxWidth: 100)
                .accessibilityIdentifier(AccessibilityID.BodyProfile.birthYearField)
        } label: {
            label("Geburtsjahr", note: Self.note(source: field.source, value: field.value.map(String.init),
                                                  health: health.map(String.init)))
        }
    }

    private func sexRow(_ field: BodyValue<FormulaSex>, health: FormulaSex?) -> some View {
        LabeledContent {
            Picker("Geschlecht für die Formel", selection: Binding(get: { store.profile.sex.value }, set: { store.setTypedSex($0) })) {
                Text("nicht gewählt").tag(FormulaSex?.none)
                ForEach(FormulaSex.allCases, id: \.self) { sex in Text(Self.sexName(sex)).tag(FormulaSex?.some(sex)) }
            }
            .labelsHidden()
            .accessibilityIdentifier(AccessibilityID.BodyProfile.sexPicker)
        } label: {
            label("Geschlecht für die Formel", note: Self.note(source: field.source, value: field.value.map(Self.sexName),
                                                                health: health.map(Self.sexName)))
        }
    }

    private func label(_ title: LocalizedStringKey, note: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(note).font(.caption).foregroundStyle(.secondaryText)
        }
    }

    // MARK: Texts

    /// The line below a value: "aus Health", "eingetragen", "eingetragen · Health sagt 1994" or "fehlt".
    static func note(source: BodyValueSource, value: String?, health: String?) -> String {
        switch source {
        case .health: String(localized: "aus Health")
        case .typed:
            if let health, health != value { String(localized: "eingetragen · Health sagt \(health)") } else { String(localized: "eingetragen") }
        case .missing: String(localized: "fehlt")
        }
    }

    /// The same for the height, which Tagwerk writes to Health when Health allows it.
    static func heightNote(source: BodyValueSource, value: Int?, health: Int?, writeAccess: HealthWriteAccess?) -> String {
        guard source == .typed else { return note(source: source, value: value.map(String.init), health: health.map(String.init)) }
        switch writeAccess {
        case .allowed: return String(localized: "eingetragen · wird nach Health geschrieben")
        default: return String(localized: "eingetragen · nicht nach Health geschrieben")
        }
    }

    static func sexName(_ sex: FormulaSex) -> String {
        switch sex {
        case .female: String(localized: "weiblich")
        case .male: String(localized: "männlich")
        }
    }
}
