import CoreLocation
import Foundation
import MapKit
import Testing
@testable import Tagwerk

/// Which failures of a travel request mean "no network, ask again" and which mean "no such place or route".
struct TravelFailureTests {
    @Test func ownErrors_areSortedByCause() {
        #expect(TravelFailure.classify(TravelTimeError.addressNotFound) == .notFound)
        #expect(TravelFailure.classify(TravelTimeError.missingCoordinates) == .unresolvable)
        #expect(TravelFailure.classify(TravelTimeError.noReferencePoint) == .unresolvable)
    }

    @Test func networkErrors_areOffline() {
        for code in [URLError.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .dataNotAllowed] {
            #expect(TravelFailure.classify(URLError(code)) == .offline)
        }
    }

    @Test func mapKitNotFoundCodes_areNotFound() {
        #expect(TravelFailure.classify(MKError(.directionsNotFound)) == .notFound)
        #expect(TravelFailure.classify(MKError(.placemarkNotFound)) == .notFound)
    }

    @Test func mapKitServerProblems_areOffline() {
        #expect(TravelFailure.classify(MKError(.serverFailure)) == .offline)
        #expect(TravelFailure.classify(MKError(.loadingThrottled)) == .offline)
        #expect(TravelFailure.classify(MKError(.unknown)) == .offline)
        #expect(TravelFailure.classify(MKError(.decodingFailed)) == .offline)
    }

    @Test func networkErrorBelowAMapKitError_winsOverNotFound() {
        // MapKit reports "directions not available" for a request that failed without network.
        let underlying = URLError(.notConnectedToInternet) as NSError
        let wrapped = NSError(domain: MKError.errorDomain, code: Int(MKError.Code.directionsNotFound.rawValue),
                              userInfo: [NSUnderlyingErrorKey: underlying])
        #expect(TravelFailure.classify(wrapped) == .offline)
        let several = NSError(domain: MKError.errorDomain, code: Int(MKError.Code.directionsNotFound.rawValue),
                              userInfo: [NSMultipleUnderlyingErrorsKey: [underlying]])
        #expect(TravelFailure.classify(several) == .offline)
    }

    @Test func geocoderWithoutResult_isNotFound() {
        #expect(TravelFailure.classify(CLError(.geocodeFoundNoResult)) == .notFound)
        #expect(TravelFailure.classify(CLError(.network)) == .offline)
    }

    @Test func unknownErrors_countAsOffline() {
        struct Strange: Error {}
        #expect(TravelFailure.classify(Strange()) == .offline)
        #expect(TravelFailure.classify(CancellationError()) == .offline)
    }
}
