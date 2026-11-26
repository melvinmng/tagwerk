import AVFoundation
import SwiftUI
import TagwerkCore
import VisionKit

/// What opens the barcode scan sheet; an identity, so the sheet starts fresh for each tap.
struct BarcodeScanRequest: Identifiable {
    let id = UUID()
}

/// How the scan sheet ended; the food list acts on it once the sheet is gone (two sheets of one list never change at the same moment).
enum BarcodeScanOutcome {
    /// The code belongs to a food in "Meine Lebensmittel": its amount sheet opens.
    case ownFood(FoodValue)
    /// A new food with the barcode: the edit sheet opens.
    case newFood(FoodEditSheet.Seed)
    /// A product of Open Food Facts was saved as a food: the list redraws.
    case foodSaved
}

/// The camera permission of the system.
@MainActor
final class SystemCameraAccess: CameraAccessProviding {
    var status: CameraAccessStatus {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: .authorized
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    func requestAccess() async -> Bool { await AVCaptureDevice.requestAccess(for: .video) }
}

/// "Strichcode scannen": the camera (or typed digits) reads a code, "Meine Lebensmittel" is searched first, and only an unknown code is
/// looked up in Open Food Facts, after the consent. The camera image never leaves the device and is not stored; only the digits are sent.
struct BarcodeScannerSheet: View {
    let onOutcome: (BarcodeScanOutcome) -> Void

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var model: BarcodeScanModel?
    @FocusState private var manualFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    content(model)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Strichcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            }
        }
        .presentationDetents([.large])
        .task {
            environment.connectivity.start()
            if model == nil {
                model = BarcodeScanModel(
                    lookup: environment.productLookup,
                    foodByBarcode: { environment.foods.food(barcode: $0) },
                    hasConsent: { environment.settings.isFoodLookupEnabled },
                    isOnline: { environment.connectivity.isOnline },
                    isSignedIn: { environment.ai.isSignedIn },
                    camera: SystemCameraAccess(),
                    isScannerSupported: DataScannerViewController.isSupported)
            }
            await model?.start()
        }
        .onDisappear { environment.productLookup.clearMemory() }
    }

    // MARK: Phases

    @ViewBuilder
    private func content(_ model: BarcodeScanModel) -> some View {
        Group {
            switch model.phase {
            case .starting:
                ProgressView()
            case .scanning:
                scanningView(model)
            case .manualEntry:
                manualEntryView(model)
            case .cameraDenied:
                cameraDeniedView(model)
            case .needsConsent(let code):
                messageForm(code: code, message: Text("Dieser Strichcode ist nicht in „Meine Lebensmittel“. Bevor Tagwerk bei Open Food Facts nachfragt, brauchen wir deine Einwilligung."),
                            model: model, offersRetry: false, offersLabelPhoto: false)
            case .lookingUp:
                lookingUpView
            case .found:
                // The preview is pushed (see `navigationDestination` below); this is what lies behind it.
                lookingUpView
            case .ownFood:
                ProgressView()
            case .notFound(let code):
                messageForm(code: code, message: Text("Open Food Facts kennt diesen Strichcode nicht."), model: model, offersRetry: false,
                            offersLabelPhoto: model.offersLabelPhoto)
            case .notInOwnFoods(let code):
                messageForm(code: code, message: Text("Dieser Strichcode ist nicht in „Meine Lebensmittel“. Ohne Einwilligung fragt Tagwerk nicht bei Open Food Facts nach."),
                            model: model, offersRetry: false, offersLabelPhoto: false)
            case .failed(let code, let message):
                messageForm(code: code, message: Text(verbatim: message), model: model, offersRetry: true, offersLabelPhoto: false, isProblem: true)
            }
        }
        .navigationDestination(isPresented: foundBinding(model)) {
            if case .found(let candidate) = model.phase {
                ProductPreviewView(candidate: candidate, onFoodSaved: {
                    onOutcome(.foodSaved)
                    dismiss()
                })
            }
        }
        .sheet(isPresented: consentBinding(model)) {
            FoodLookupConsentSheet(startsSearch: true) {
                Task { await model.consentGiven() }
            } onDecline: {
                model.consentDeclined()
            }
        }
        .onChange(of: model.phase) { old, new in
            if case .ownFood(let food) = new {
                onOutcome(.ownFood(food))
                dismiss()
            }
            if old == .scanning, new != .scanning {
                AccessibilityNotification.Announcement(String(localized: "Strichcode erkannt")).post()
            }
        }
        .sensoryFeedback(trigger: model.phase) { old, new in old == .scanning && new != .scanning ? .success : nil }
    }

    private func foundBinding(_ model: BarcodeScanModel) -> Binding<Bool> {
        Binding(
            get: { if case .found = model.phase { true } else { false } },
            // The back button of the preview: read the next code.
            set: { isPresented in if !isPresented, case .found = model.phase { model.rescan() } })
    }

    private func consentBinding(_ model: BarcodeScanModel) -> Binding<Bool> {
        Binding(get: { if case .needsConsent = model.phase { true } else { false } }, set: { _ in })
    }

    // MARK: Camera

    private func scanningView(_ model: BarcodeScanModel) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                BarcodeCameraView(isActive: model.phase == .scanning) { code in
                    Task { await model.handleScanned(code) }
                }
                .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.9), lineWidth: 3).padding(36)
                        .accessibilityHidden(true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Kamera zum Lesen von Strichcodes")
                .accessibilityHint("Halte den Strichcode in den Rahmen, oder gib die Nummer von Hand ein.")
                Text("Halte den Strichcode in den Rahmen.").font(.subheadline).foregroundStyle(.secondaryText)
                    .multilineTextAlignment(.center)
                Button { model.showManualEntry() } label: {
                    Label("Nummer eingeben", systemImage: "keyboard").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier(AccessibilityID.FoodLookup.manualEntryButton)
                Text("Das Kamerabild bleibt auf dem Gerät. Gesendet wird höchstens die Nummer, und nur nach deiner Einwilligung.")
                    .font(.footnote).foregroundStyle(.secondaryText).multilineTextAlignment(.center)
            }
            .padding()
        }
    }

    private func cameraDeniedView(_ model: BarcodeScanModel) -> some View {
        Form {
            Section {
                Text("Die Kamera ist für Tagwerk ausgeschaltet.")
                Button("Einstellungen öffnen", systemImage: "gear") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                Button("Nummer eingeben", systemImage: "keyboard") { model.showManualEntry() }
                    .accessibilityIdentifier(AccessibilityID.FoodLookup.manualEntryButton)
            } footer: {
                Text("Du kannst die Nummer unter dem Strichcode auch von Hand eingeben.").foregroundStyle(.secondaryText)
            }
        }
    }

    // MARK: Manual entry

    private func manualEntryView(_ model: BarcodeScanModel) -> some View {
        @Bindable var model = model
        return Form {
            Section {
                TextField("Strichcode-Nummer", text: $model.manualText)
                    .keyboardType(.numberPad)
                    .focused($manualFocused)
                    .accessibilityIdentifier(AccessibilityID.FoodLookup.manualField)
                Button("Suchen") {
                    manualFocused = false
                    Task { await model.submitManual() }
                }
                .accessibilityIdentifier(AccessibilityID.FoodLookup.manualSubmit)
                if let error = model.manualError {
                    Text(error).font(.subheadline).foregroundStyle(.orangeText)
                }
            } footer: {
                Text("Gib die Nummer unter dem Strichcode ein.").foregroundStyle(.secondaryText)
            }
            if model.isScannerAvailable {
                Section {
                    Button("Kamera verwenden", systemImage: "barcode.viewfinder") { model.rescan() }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: Results

    private var lookingUpView: some View {
        Form {
            Section {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Suche bei Open Food Facts …").foregroundStyle(.secondaryText)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// The result of a code that led to no food: what happened, the code, and the ways on.
    private func messageForm(code: String, message: Text, model: BarcodeScanModel, offersRetry: Bool, offersLabelPhoto: Bool,
                             isProblem: Bool = false) -> some View {
        Form {
            Section {
                message.foregroundStyle(isProblem ? Color.orangeText : Color.primary)
                LabeledContent("Strichcode") { Text(verbatim: code).monospacedDigit() }
            }
            Section {
                if offersRetry {
                    Button("Erneut versuchen", systemImage: "arrow.clockwise") { Task { await model.retry() } }
                        .accessibilityIdentifier(AccessibilityID.FoodLookup.scanRetry)
                }
                if offersLabelPhoto {
                    Button("Etikett fotografieren", systemImage: "camera") { finish(.newFood(BarcodeScanModel.foodSeed(barcode: code, withLabelPhoto: true))) }
                }
                Button("Selbst anlegen", systemImage: "plus") { finish(.newFood(BarcodeScanModel.foodSeed(barcode: code, withLabelPhoto: false))) }
                    .accessibilityIdentifier(AccessibilityID.FoodLookup.scanCreateFood)
                Button("Erneut scannen", systemImage: "barcode.viewfinder") { model.rescan() }
                    .accessibilityIdentifier(AccessibilityID.FoodLookup.scanAgain)
            } footer: {
                Text("Beim Anlegen wird der Strichcode mit dem Lebensmittel gespeichert.").foregroundStyle(.secondaryText)
            }
        }
    }

    private func finish(_ outcome: BarcodeScanOutcome) {
        onOutcome(outcome)
        dismiss()
    }
}

// MARK: Camera view

/// The camera of the system scanner (`DataScannerViewController`). It reads EAN-13 and EAN-8 codes (a UPC-A code is reported as EAN-13
/// with a leading zero) and stops at the first one; the scan starts again only when `isActive` turns on.
struct BarcodeCameraView: UIViewControllerRepresentable {
    let isActive: Bool
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> BarcodeCameraController {
        BarcodeCameraController(onCode: onCode)
    }

    func updateUIViewController(_ controller: BarcodeCameraController, context: Context) {
        controller.onCode = onCode
        controller.setActive(isActive)
    }

    static func dismantleUIViewController(_ controller: BarcodeCameraController, coordinator: ()) {
        controller.setActive(false)
    }
}

@MainActor
final class BarcodeCameraController: UIViewController, DataScannerViewControllerDelegate {
    var onCode: (String) -> Void
    private let scanner = DataScannerViewController(
        recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8])], qualityLevel: .balanced,
        recognizesMultipleItems: false, isHighlightingEnabled: true)
    private var wantsScanning = false

    init(onCode: @escaping (String) -> Void) {
        self.onCode = onCode
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        scanner.delegate = self
        addChild(scanner)
        scanner.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scanner.view)
        NSLayoutConstraint.activate([
            scanner.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scanner.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scanner.view.topAnchor.constraint(equalTo: view.topAnchor),
            scanner.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        scanner.didMove(toParent: self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyScanState()
    }

    func setActive(_ active: Bool) {
        wantsScanning = active
        applyScanState()
    }

    /// The camera runs only while the view is on screen and the flow wants a code.
    private func applyScanState() {
        guard isViewLoaded, view.window != nil else { return }
        if wantsScanning, !scanner.isScanning {
            try? scanner.startScanning()
        } else if !wantsScanning, scanner.isScanning {
            scanner.stopScanning()
        }
    }

    func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
        guard wantsScanning else { return }
        for case .barcode(let barcode) in addedItems {
            guard let payload = barcode.payloadStringValue, Barcode.normalized(payload) != nil else { continue }
            // One code ends the scan: the camera stops here, the flow decides what comes next.
            wantsScanning = false
            dataScanner.stopScanning()
            onCode(payload)
            return
        }
    }
}
