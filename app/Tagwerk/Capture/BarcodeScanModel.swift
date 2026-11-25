import Foundation
import Observation
import TagwerkCore

/// Whether the app may use the camera.
enum CameraAccessStatus: Equatable {
    case notDetermined
    case authorized
    /// Refused by the user or restricted by the system (parental controls, device management).
    case denied
}

/// The camera permission, behind a protocol so the scan flow runs in tests without a camera.
@MainActor
protocol CameraAccessProviding: AnyObject {
    var status: CameraAccessStatus { get }
    /// Asks the user (the system dialog) when the status is `notDetermined`; `true` when the camera may be used.
    func requestAccess() async -> Bool
}

/// The state of the barcode scan sheet.
///
/// A scanned or typed code is checked (`Barcode`), then looked up in "Meine Lebensmittel" first: a hit needs no connection and no
/// consent. Only an unknown code goes to Open Food Facts, and the consent is asked only then. `handleScanned(_:)` and
/// `submitManual()` are the only ways a lookup starts, and while one is running or has finished no further code is taken until
/// `rescan()`, because the scanner reports the same code many times per second.
@MainActor
@Observable
final class BarcodeScanModel {
    enum Phase: Equatable {
        /// The camera permission is being checked.
        case starting
        /// The camera reads codes.
        case scanning
        /// The digits are typed (no camera, or the user chose it).
        case manualEntry
        case cameraDenied
        /// A valid, unknown code that needs the consent before it is sent.
        case needsConsent(String)
        case lookingUp(String)
        /// Open Food Facts knows the product: the preview follows.
        case found(ProductCandidate)
        /// The code belongs to a food in "Meine Lebensmittel": the amount sheet follows.
        case ownFood(FoodValue)
        /// Open Food Facts does not know the code.
        case notFound(String)
        /// The consent was declined: the code is not in "Meine Lebensmittel" and was not sent.
        case notInOwnFoods(String)
        case failed(code: String, message: String)
    }

    private(set) var phase: Phase = .starting
    /// The digits typed in the manual entry.
    var manualText = ""
    /// Why the typed digits were refused; `nil` while there is nothing to say.
    private(set) var manualError: String?
    /// The device can read barcodes with the camera (`false` in the simulator and on devices without the scanner).
    let isScannerAvailable: Bool

    @ObservationIgnored private let lookup: any ProductLookingUp
    @ObservationIgnored private let foodByBarcode: (String) -> FoodValue?
    @ObservationIgnored private let hasConsent: () -> Bool
    @ObservationIgnored private let isOnline: () -> Bool
    @ObservationIgnored private let isSignedIn: () -> Bool
    @ObservationIgnored private let camera: any CameraAccessProviding

    init(lookup: any ProductLookingUp, foodByBarcode: @escaping (String) -> FoodValue?, hasConsent: @escaping () -> Bool,
         isOnline: @escaping () -> Bool, isSignedIn: @escaping () -> Bool, camera: any CameraAccessProviding, isScannerSupported: Bool) {
        self.lookup = lookup
        self.foodByBarcode = foodByBarcode
        self.hasConsent = hasConsent
        self.isOnline = isOnline
        self.isSignedIn = isSignedIn
        self.camera = camera
        isScannerAvailable = isScannerSupported
    }

    /// "Etikett fotografieren" needs the ChatGPT sign-in.
    var offersLabelPhoto: Bool { isSignedIn() }

    /// Whether a code is taken now (a scan or typed digits).
    private var acceptsCode: Bool { phase == .scanning || phase == .manualEntry }

    // MARK: Start and input mode

    /// Decides how the sheet starts: manual entry without a scanner, the permission dialog on the first use, the camera otherwise.
    func start() async {
        guard phase == .starting else { return }
        guard isScannerAvailable else {
            phase = .manualEntry
            return
        }
        switch camera.status {
        case .authorized:
            phase = .scanning
        case .denied:
            phase = .cameraDenied
        case .notDetermined:
            let granted = await camera.requestAccess()
            // The sheet may have moved on while the dialog was open; only the start phase is replaced.
            if phase == .starting { phase = granted ? .scanning : .cameraDenied }
        }
    }

    func showManualEntry() {
        guard phase == .scanning || phase == .cameraDenied else { return }
        manualError = nil
        phase = .manualEntry
    }

    /// Back to reading: the camera when there is one, otherwise the typed digits.
    func rescan() {
        manualText = ""
        manualError = nil
        phase = isScannerAvailable && camera.status == .authorized ? .scanning : .manualEntry
    }

    // MARK: Codes

    /// A code read by the camera. A misread (wrong check digit) is ignored: the camera simply goes on.
    func handleScanned(_ text: String) async {
        guard phase == .scanning else { return }
        guard let code = Barcode.normalized(text) else { return }
        await process(code)
    }

    /// The digits typed by the user; a code that is no barcode is refused with a hint.
    func submitManual() async {
        guard phase == .manualEntry else { return }
        guard let code = Barcode.normalized(manualText) else {
            manualError = ProductLookupError.invalidBarcode.message
            return
        }
        manualError = nil
        await process(code)
    }

    /// The consent was given for the code that waited for it.
    func consentGiven() async {
        guard case .needsConsent(let code) = phase else { return }
        await lookUpOnline(code)
    }

    func consentDeclined() {
        guard case .needsConsent(let code) = phase else { return }
        phase = .notInOwnFoods(code)
    }

    /// "Erneut versuchen" after a failure: the same code once more (its own foods are checked again, too).
    func retry() async {
        guard case .failed(let code, _) = phase else { return }
        await process(code)
    }

    // MARK: Lookup

    private func process(_ code: String) async {
        // The phase changes before the first suspension, so a second code that arrives meanwhile is ignored.
        if let food = foodByBarcode(code) {
            phase = .ownFood(food)
            return
        }
        guard hasConsent() else {
            phase = .needsConsent(code)
            return
        }
        await lookUpOnline(code)
    }

    private func lookUpOnline(_ code: String) async {
        guard isOnline() else {
            phase = .failed(code: code, message: ProductLookupError.offline.message)
            return
        }
        phase = .lookingUp(code)
        do {
            if let product = try await lookup.product(barcode: code) {
                phase = .found(product)
            } else {
                phase = .notFound(code)
            }
        } catch is CancellationError {
            phase = isScannerAvailable && camera.status == .authorized ? .scanning : .manualEntry
        } catch let error as ProductLookupError {
            phase = .failed(code: code, message: error.message)
        } catch {
            phase = .failed(code: code, message: ProductLookupError.failed.message)
        }
    }

    // MARK: Taking the code over

    /// The edit sheet for a new food that carries the barcode: the energy field starts empty, so nothing is saved by accident.
    static func foodSeed(barcode: String, withLabelPhoto: Bool) -> FoodEditSheet.Seed {
        var seed = FoodEditSheet.Seed(food: FoodValue(name: "", reference: .per100g, kcal: 0, barcode: barcode), energyUnknown: true)
        seed.startsWithLabelPhoto = withLabelPhoto
        return seed
    }
}
