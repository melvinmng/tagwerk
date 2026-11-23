import SwiftUI
import TagwerkCore

/// What the consent sheet of the online search holds: the contact address the user types. It starts empty (or with the address the
/// user typed earlier); the app never suggests an address and takes none from the device or an account.
@MainActor
@Observable
final class FoodLookupConsentModel {
    var contact: String

    init(settings: AppSettings) {
        contact = settings.foodLookupContact ?? ""
    }

    /// The agreement is possible only with a valid address.
    var canAgree: Bool { ProductSearchRules.validContact(contact) != nil }

    /// Something is typed that is not an address (shown as a hint; an empty field is no error).
    var showsInvalidHint: Bool { !contact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !canAgree }

    func agree(settings: AppSettings) { settings.agreeToFoodLookup(contact: contact) }
}

/// The consent for the online search in Open Food Facts (decision LM1d, LM2b; built like `ShoppingSortConsentSheet`).
///
/// "Einverstanden" is possible only with a contact address, because the operator asks every client to name one in each request.
struct FoodLookupConsentSheet: View {
    /// `true` when the sheet comes from the tap on "Online suchen": the button then says that a search follows.
    var startsSearch = false
    let onAgree: () -> Void
    let onDecline: () -> Void

    @Environment(AppEnvironment.self) private var environment
    @State private var model: FoodLookupConsentModel?
    @FocusState private var contactFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Für die Online-Suche sendet Tagwerk dein Suchwort an Open Food Facts, eine offene Lebensmitteldatenbank von Freiwilligen (openfoodfacts.org), ohne Konto.")
                    point("paperplane", "**Gesendet wird:** das Suchwort (später auch ein Strichcode), technisch unvermeidbar deine IP-Adresse, der Name der App mit ihrer Version und die Kontaktadresse, die du unten einträgst.")
                    point("eye.slash", "**Nicht gesendet werden:** Mengen, Mahlzeiten, Ziele, Gewicht, Daten aus Health und ein Konto.")
                    point("hand.tap", "**Nur auf dein Tippen:** Gesucht wird erst, wenn du „Online suchen“ tippst, nie beim Tippen im Suchfeld.")
                    point("exclamationmark.circle", "**Wer sucht, verrät, was er isst oder kaufen will.** Open Food Facts speichert IP-Adressen und Protokolle bis zu 3 Jahre. Die Daten stammen von Freiwilligen und können fehlen oder falsch sein.")

                    if let model {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Kontaktadresse für Open Food Facts").font(.subheadline).fontWeight(.semibold)
                            TextField("E-Mail-Adresse", text: Bindable(model).contact)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.emailAddress)
                                .textContentType(nil)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($contactFocused)
                                .accessibilityIdentifier(AccessibilityID.FoodLookup.contactField)
                            if model.showsInvalidHint {
                                Text("Das ist keine gültige E-Mail-Adresse.").font(.footnote).foregroundStyle(.orangeText)
                            }
                            Text("Open Food Facts verlangt, dass jede App in jeder Anfrage eine Kontaktadresse nennt, damit der Betreiber sich bei Problemen melden kann. Er sieht diese Adresse bei jeder Anfrage. Tagwerk trägt selbst keine Adresse ein und übernimmt keine aus dem Gerät oder aus einem Konto; du kannst eine eigene Adresse für diesen Zweck wählen.")
                                .font(.footnote).foregroundStyle(.secondaryText)
                        }
                        VStack(spacing: 10) {
                            Button {
                                model.agree(settings: environment.settings)
                                onAgree()
                            } label: {
                                Text(startsSearch ? "Einverstanden und suchen" : "Einverstanden").fontWeight(.semibold).frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(!model.canAgree)
                            .accessibilityIdentifier(AccessibilityID.FoodLookup.agreeButton)
                            Button("Nicht jetzt", action: onDecline)
                        }
                        .padding(.top, 4)
                    }
                    Text("Du kannst das in den Einstellungen unter „Erfassen“ widerrufen.")
                        .font(.footnote).foregroundStyle(.secondaryText)
                        .frame(maxWidth: .infinity)
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Online-Suche in Open Food Facts")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if model == nil { model = FoodLookupConsentModel(settings: environment.settings) }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled()
    }

    private func point(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(.tint).frame(width: 24)
            Text(text)
        }
    }
}

/// The contact address in the settings: shown while the online search is on. It takes over what is typed when the field is left or
/// submitted. A valid address replaces the stored one, an empty field removes it and switches the search off, anything else keeps the
/// stored address and says so.
struct FoodLookupContactField: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var text = ""
    @State private var showsInvalid = false
    @State private var loaded = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Kontaktadresse", text: $text)
                .keyboardType(.emailAddress)
                .textContentType(nil)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused)
                .submitLabel(.done)
                .onSubmit(commit)
                .accessibilityIdentifier(AccessibilityID.FoodLookup.contactField)
            if showsInvalid {
                Text("Das ist keine gültige E-Mail-Adresse. Die bisherige Adresse bleibt.").font(.footnote).foregroundStyle(.orangeText)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            text = environment.settings.foodLookupContact ?? ""
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { commit() }
        }
    }

    private func commit() {
        switch environment.settings.commitFoodLookupContact(text) {
        case .accepted(let address):
            text = address
            showsInvalid = false
        case .cleared:
            showsInvalid = false
        case .invalid:
            showsInvalid = true
            text = environment.settings.foodLookupContact ?? ""
        }
    }
}
