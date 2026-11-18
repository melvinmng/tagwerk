import Foundation
import HealthKit
import Testing
import TagwerkCore
@testable import HealthBridge

struct HealthMappingTests {
    let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    @Test func syncIdentifier_format() {
        #expect(HealthMapping.syncIdentifier(.meal, id: id, part: "energy") == "tagwerk.meal.11111111-2222-3333-4444-555555555555.energy")
        #expect(HealthMapping.syncIdentifier(.drink, id: id) == "tagwerk.drink.11111111-2222-3333-4444-555555555555")
    }

    @Test func metadata_containsSyncKeysEntryIDAndMarkers() {
        let metadata = HealthMapping.metadata(syncIdentifier: "tagwerk.drink.x", entryID: id, version: 3, estimated: true,
                                              userEntered: true)
        #expect(metadata[HKMetadataKeySyncIdentifier] as? String == "tagwerk.drink.x")
        #expect(metadata[HKMetadataKeySyncVersion] as? Int == 3)
        #expect(metadata[HealthMapping.entryIDKey] as? String == id.uuidString)
        #expect(metadata[HealthMapping.markerKey] as? Int == 1)
        #expect(metadata[HealthMapping.estimatedKey] as? Int == 1)
        #expect(metadata[HKMetadataKeyWasUserEntered] as? Bool == true)
    }

    @Test func metadata_withoutEstimate_hasNoEstimateMarker() {
        let metadata = HealthMapping.metadata(syncIdentifier: "s", entryID: id, version: 1, estimated: false, userEntered: false)
        #expect(metadata[HealthMapping.estimatedKey] == nil)
        #expect(metadata[HKMetadataKeyWasUserEntered] == nil)
    }

    @Test func nutrients_splitIntoWritesAndRemovals() {
        let meal = HealthMeal(id: id, date: .now, version: 2, kcal: 520, protein: 22, carbs: 0, fat: -1, estimated: true)
        let plan = HealthMapping.nutrientPlan(for: meal)
        #expect(plan.writes.map(\.nutrient) == [.energy, .protein])
        #expect(plan.writes.map(\.value) == [520, 22])
        #expect(plan.removals == [.carbs, .fat])
    }

    @Test func activityMapping_allCasesDistinctExceptOther() {
        let types = WorkoutActivity.allCases.map(HealthMapping.activityType)
        #expect(Set(types).count == WorkoutActivity.allCases.count)
        #expect(HealthMapping.activityType(.strength) == .traditionalStrengthTraining)
        #expect(HealthMapping.activityType(.other) == .other)
    }

    @Test func foreignActivityName_knownAndFallback() {
        #expect(HealthMapping.activityName(.running) == "Laufen")
        #expect(HealthMapping.activityName(.functionalStrengthTraining) == "Krafttraining")
        #expect(HealthMapping.activityName(.curling) == "Training")
    }

    @Test func isOwn_bySourceOrMarker() {
        #expect(HealthMapping.isOwn(metadata: nil, sourceBundleID: "local.tagwerk.app", ownBundleID: "local.tagwerk.app"))
        #expect(HealthMapping.isOwn(metadata: [HealthMapping.markerKey: 1], sourceBundleID: "com.apple.health",
                                    ownBundleID: "local.tagwerk.app"))
        #expect(!HealthMapping.isOwn(metadata: [:], sourceBundleID: "com.apple.health.watch", ownBundleID: "local.tagwerk.app"))
        #expect(!HealthMapping.isOwn(metadata: nil, sourceBundleID: "com.apple.health", ownBundleID: nil))
    }

    @Test func access_fromShareStatuses() {
        #expect(HealthMapping.access(shouldRequest: true, denied: []) == .notDetermined)
        #expect(HealthMapping.access(shouldRequest: false, denied: []) == .authorized)
        #expect(HealthMapping.access(shouldRequest: false, denied: [.water, .workouts]) == .partial([.water, .workouts]))
        #expect(HealthMapping.access(shouldRequest: false, denied: Set(HealthShareKind.allCases)) == .denied)
        #expect(HealthShareKind.water.displayName == "Wasser")
    }

    @Test func stepsAccess_shouldRequest_isNotAsked_otherwiseAsked() {
        #expect(HealthMapping.stepsAccess(.shouldRequest) == .notAsked)
        #expect(HealthMapping.stepsAccess(.unnecessary) == .asked)
        #expect(HealthMapping.stepsAccess(.unknown) == .asked)
    }

    /// The access of existing users must not fall back to "not asked" because a new read type appeared:
    /// the step type is asked for separately and never part of the core status query.
    @Test func access_ignoresStepType() {
        let stepType = HKQuantityType(.stepCount)
        #expect(!HealthKitStore.coreReadTypes.contains(stepType))
        #expect(HealthKitStore.coreReadTypes == [HKObjectType.workoutType()])
        #expect(HealthKitStore.stepReadTypes == [stepType])
        // The combined request of the Health card asks for both groups at once.
        #expect(HealthKitStore.connectReadTypes == HealthKitStore.coreReadTypes.union(HealthKitStore.stepReadTypes))
    }

    @Test func dailySteps_roundsSumsToInt_dropsDaysWithoutStatistics() {
        let monday = Date(timeIntervalSince1970: 1_795_100_000)
        let tuesday = monday.addingTimeInterval(86_400)
        let wednesday = tuesday.addingTimeInterval(86_400)
        let result = HealthMapping.dailySteps([(monday, 8239.6), (tuesday, nil), (wednesday, 0)])
        #expect(result == [DailySteps(start: monday, count: 8240), DailySteps(start: wednesday, count: 0)])
    }
}
