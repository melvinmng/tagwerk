import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

/// A lookup that records its calls and answers from a script; the consent and the connection are the model's concern here.
@MainActor
private final class FakeProductLookup: ProductLookingUp {
    private(set) var barcodes: [String] = []
    private(set) var cleared = 0
    var answer: ProductCandidate?
    var error: Error?

    func search(_ query: String, page: Int) async throws -> ProductPage { ProductPage(candidates: [], page: page, total: 0, hasMore: false) }

    func product(barcode: String) async throws -> ProductCandidate? {
        barcodes.append(barcode)
        if let error { throw error }
        return answer
    }

    func clearMemory() { cleared += 1 }
}

@MainActor
private final class FakeCamera: CameraAccessProviding {
    var status: CameraAccessStatus
    var grantsAccess: Bool
    private(set) var requests = 0

    init(status: CameraAccessStatus, grantsAccess: Bool = true) {
        self.status = status
        self.grantsAccess = grantsAccess
    }

    func requestAccess() async -> Bool {
        requests += 1
        status = grantsAccess ? .authorized : .denied
        return grantsAccess
    }
}

@MainActor
struct BarcodeScanModelTests {
    static let knownCode = "4008400404127"
    static let ownCode = "96385074"

    private let lookup = FakeProductLookup()
    private let ownFood = FoodValue(name: "Eigener Skyr", reference: .per100g, kcal: 62, barcode: BarcodeScanModelTests.ownCode)

    /// One value per test: a `FoodValue` gets a new identity on every construction, so equal products must be the same instance.
    private let product: ProductCandidate = {
        let code = BarcodeScanModelTests.knownCode
        let food = FoodValue(name: "Haferdrink", reference: .per100ml, kcal: 59, protein: 1, carbs: 6.6, fat: 3, origin: .openFoodFacts, barcode: code)
        return ProductCandidate(barcode: code, name: "Haferdrink", brand: "Oatly", quantity: "1 l", food: food, energyUnknown: false,
                                valuesPerServingOnly: false)
    }()

    private func make(consent: Bool = true, online: Bool = true, signedIn: Bool = false, camera: FakeCamera = FakeCamera(status: .authorized),
                      scannerSupported: Bool = true) -> BarcodeScanModel {
        let own = ownFood
        return BarcodeScanModel(lookup: lookup, foodByBarcode: { Barcode.comparisonKey($0) == Barcode.comparisonKey(own.barcode ?? "") ? own : nil },
                                hasConsent: { consent }, isOnline: { online }, isSignedIn: { signedIn }, camera: camera,
                                isScannerSupported: scannerSupported)
    }

    private func started(_ model: BarcodeScanModel) async -> BarcodeScanModel {
        await model.start()
        return model
    }

    // MARK: Start

    @Test func start_authorizedCamera_scans() async {
        let model = await started(make())
        #expect(model.phase == .scanning)
    }

    @Test func start_undecidedCamera_asksOnceAndScansWhenGranted() async {
        let camera = FakeCamera(status: .notDetermined, grantsAccess: true)
        let model = await started(make(camera: camera))
        #expect(model.phase == .scanning)
        #expect(camera.requests == 1)
    }

    @Test func cameraDenied_offersManualEntry() async {
        for camera in [FakeCamera(status: .denied), FakeCamera(status: .notDetermined, grantsAccess: false)] {
            let model = await started(make(camera: camera))
            #expect(model.phase == .cameraDenied)
            model.showManualEntry()
            #expect(model.phase == .manualEntry)
        }
    }

    @Test func start_withoutScanner_goesStraightToManualEntry_andNeverAsksForTheCamera() async {
        let camera = FakeCamera(status: .notDetermined)
        let model = await started(make(camera: camera, scannerSupported: false))
        #expect(model.phase == .manualEntry)
        #expect(!model.isScannerAvailable)
        #expect(camera.requests == 0)
    }

    // MARK: Local lookup first

    @Test func scan_ownFood_opensAmountWithoutRequest() async {
        // Neither consent nor a connection is needed for a food that is already stored.
        let model = await started(make(consent: false, online: false))
        await model.handleScanned(Self.ownCode)
        #expect(model.phase == .ownFood(ownFood))
        #expect(lookup.barcodes.isEmpty)
    }

    // MARK: Online lookup

    @Test func scan_withoutConsent_sendsNothingAndAsksConsent() async {
        let model = await started(make(consent: false))
        await model.handleScanned(Self.knownCode)
        #expect(model.phase == .needsConsent(Self.knownCode))
        #expect(lookup.barcodes.isEmpty)
    }

    @Test func scan_consentGiven_runsLookupOnce() async {
        lookup.answer = product
        let model = await started(make(consent: false))
        await model.handleScanned(Self.knownCode)
        await model.consentGiven()
        #expect(model.phase == .found(product))
        #expect(lookup.barcodes == [Self.knownCode])
    }

    @Test func scan_consentDeclined_sendsNothing_andOffersToCreateTheFood() async {
        let model = await started(make(consent: false))
        await model.handleScanned(Self.knownCode)
        model.consentDeclined()
        #expect(model.phase == .notInOwnFoods(Self.knownCode))
        #expect(lookup.barcodes.isEmpty)
    }

    @Test func scan_withConsent_foundProduct_showsThePreview() async {
        lookup.answer = product
        let model = await started(make())
        await model.handleScanned(Self.knownCode)
        #expect(model.phase == .found(product))
        #expect(lookup.barcodes == [Self.knownCode])
    }

    @Test func scan_unknownProduct_offersLabelPhotoOnlyWhenSignedIn() async {
        lookup.answer = nil
        let signedOut = await started(make(signedIn: false))
        await signedOut.handleScanned(Self.knownCode)
        #expect(signedOut.phase == .notFound(Self.knownCode))
        #expect(!signedOut.offersLabelPhoto)

        let signedIn = await started(make(signedIn: true))
        await signedIn.handleScanned(Self.knownCode)
        #expect(signedIn.offersLabelPhoto)
    }

    @Test func scan_offline_sendsNothing() async {
        let model = await started(make(online: false))
        await model.handleScanned(Self.knownCode)
        #expect(model.phase == .failed(code: Self.knownCode, message: ProductLookupError.offline.message))
        #expect(lookup.barcodes.isEmpty)
    }

    @Test func scan_rateLimited_showsWaitText() async {
        lookup.error = ProductLookupError.rateLimited(wait: 18)
        let model = await started(make())
        await model.handleScanned(Self.knownCode)
        #expect(model.phase == .failed(code: Self.knownCode, message: ProductLookupError.rateLimited(wait: 18).message))
    }

    @Test func scan_unexpectedError_showsTheGenericText() async {
        lookup.error = URLError(.timedOut)
        let model = await started(make())
        await model.handleScanned(Self.knownCode)
        #expect(model.phase == .failed(code: Self.knownCode, message: ProductLookupError.failed.message))
    }

    @Test func retry_afterAFailure_asksAgainForTheSameCode() async {
        lookup.error = ProductLookupError.serverBusy
        let model = await started(make())
        await model.handleScanned(Self.knownCode)
        lookup.error = nil
        lookup.answer = product
        await model.retry()
        #expect(model.phase == .found(product))
        #expect(lookup.barcodes == [Self.knownCode, Self.knownCode])
    }

    // MARK: Input rules

    @Test func scan_invalidCode_sendsNothing_andKeepsScanning() async {
        let model = await started(make())
        await model.handleScanned("4008400404128")
        #expect(model.phase == .scanning, "a misread is ignored, the camera goes on")
        #expect(lookup.barcodes.isEmpty)
    }

    @Test func manualEntry_invalidCode_showsTheHint_andSendsNothing() async {
        let model = await started(make(scannerSupported: false))
        model.manualText = "12345"
        await model.submitManual()
        #expect(model.phase == .manualEntry)
        #expect(model.manualError == ProductLookupError.invalidBarcode.message)
        #expect(lookup.barcodes.isEmpty)
        model.manualText = "4 008400 404127"
        lookup.answer = product
        await model.submitManual()
        #expect(model.manualError == nil)
        #expect(model.phase == .found(product))
    }

    @Test func scan_secondCodeIgnoredUntilRescan() async {
        lookup.answer = product
        let model = await started(make())
        await model.handleScanned(Self.knownCode)
        await model.handleScanned(Self.ownCode)
        #expect(model.phase == .found(product), "a second code does not replace the first")
        #expect(lookup.barcodes == [Self.knownCode])
        model.rescan()
        #expect(model.phase == .scanning)
        await model.handleScanned(Self.ownCode)
        #expect(model.phase == .ownFood(ownFood))
    }

    @Test func rescan_withoutScanner_returnsToManualEntry() async {
        let model = await started(make(scannerSupported: false))
        model.manualText = Self.knownCode
        await model.submitManual()
        model.rescan()
        #expect(model.phase == .manualEntry)
        #expect(model.manualText.isEmpty)
    }

    // MARK: Taking the code over

    @Test func foodSeed_carriesTheBarcode_andStartsWithAnEmptyEnergyField() {
        let seed = BarcodeScanModel.foodSeed(barcode: Self.knownCode, withLabelPhoto: false)
        #expect(seed.food?.barcode == Self.knownCode)
        #expect(seed.energyUnknown && !seed.isExisting && !seed.startsWithLabelPhoto)
        #expect(BarcodeScanModel.foodSeed(barcode: Self.knownCode, withLabelPhoto: true).startsWithLabelPhoto)
    }
}
