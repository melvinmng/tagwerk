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
        // The further nutrients are unknown here, so they are removed (never written as 0).
        #expect(plan.removals == [.carbs, .fat, .fiber, .sugar, .saturatedFat, .sodium])
    }

    @Test func nutrientPlan_unknown_isRemovedNotWritten() {
        let meal = HealthMeal(id: id, date: .now, version: 1, kcal: 400, protein: 10, carbs: 50, fat: 5, fiber: nil, sugar: 12,
                              saturatedFat: nil, salt: nil, estimated: false)
        let plan = HealthMapping.nutrientPlan(for: meal)
        #expect(plan.writes.map(\.nutrient) == [.energy, .protein, .carbs, .fat, .sugar])
        #expect(plan.removals == [.fiber, .saturatedFat, .sodium])
    }

    @Test func nutrientPlan_zeroKnown_isRemoved() {
        let meal = HealthMeal(id: id, date: .now, version: 1, kcal: 400, protein: 10, carbs: 50, fat: 5, fiber: 0, sugar: 0,
                              saturatedFat: 0, salt: 0, estimated: false)
        let plan = HealthMapping.nutrientPlan(for: meal)
        #expect(plan.writes.map(\.nutrient) == [.energy, .protein, .carbs, .fat])
        #expect(plan.removals == [.fiber, .sugar, .saturatedFat, .sodium])
    }

    @Test func salt_writtenAsSodium() {
        let meal = HealthMeal(id: id, date: .now, version: 1, kcal: 400, protein: 0, carbs: 0, fat: 0, salt: 2.5, estimated: false)
        let sodium = HealthMapping.nutrientPlan(for: meal).writes.first { $0.nutrient == .sodium }
        #expect(sodium?.value == 1000, "2.5 g salt are 1 g sodium, written in milligrams")
        #expect(HealthMapping.Nutrient.sodium.unit == .gramUnit(with: .milli))
        #expect(HealthMapping.Nutrient.fiber.unit == .gram())
    }

    @Test func nutrients_coreFlagMatchesShareKinds() {
        #expect(HealthMapping.Nutrient.allCases.filter(\.isCore) == [.energy, .protein, .carbs, .fat])
        #expect(HealthMapping.Nutrient.fiber.shareKind == nil)
        #expect(HealthMapping.Nutrient.energy.shareKind == .energy)
    }

    @Test func save_skipsGroupNotAsked_andStillCountsAsMirrored() {
        let meal = HealthMeal(id: id, date: .now, version: 1, kcal: 400, protein: 10, carbs: 50, fat: 5, fiber: 6, salt: 1,
                              estimated: false)
        let outcome = HealthMapping.mealWrite(plan: HealthMapping.nutrientPlan(for: meal), mayWrite: { $0.isCore })
        #expect(outcome.writes.map(\.nutrient) == [.energy, .protein, .carbs, .fat])
        #expect(outcome.isComplete, "a skipped optional group does not keep the meal marked for retry")
    }

    @Test func save_coreDenied_keepsTheMealMarkedForRetry() {
        let meal = HealthMeal(id: id, date: .now, version: 1, kcal: 400, protein: 10, carbs: 50, fat: 5, fiber: 6, estimated: false)
        let outcome = HealthMapping.mealWrite(plan: HealthMapping.nutrientPlan(for: meal), mayWrite: { !$0.isCore })
        #expect(outcome.writes.map(\.nutrient) == [.fiber])
        #expect(!outcome.isComplete)
    }

    @Test func save_mealWithoutAnyValues_isComplete() {
        let meal = HealthMeal(id: id, date: .now, version: 1, kcal: 0, protein: 0, carbs: 0, fat: 0, estimated: false)
        #expect(HealthMapping.mealWrite(plan: HealthMapping.nutrientPlan(for: meal), mayWrite: { _ in false }).isComplete)
    }

    @Test func save_removalsOnlyForPermittedTypes() {
        let meal = HealthMeal(id: id, date: .now, version: 2, kcal: 400, protein: 10, carbs: 50, fat: 5, estimated: false)
        let outcome = HealthMapping.mealWrite(plan: HealthMapping.nutrientPlan(for: meal), mayWrite: { $0.isCore })
        #expect(outcome.removals.isEmpty, "the further nutrients are not removed where Tagwerk may not write")
        let all = HealthMapping.mealWrite(plan: HealthMapping.nutrientPlan(for: meal), mayWrite: { _ in true })
        #expect(all.removals == [.fiber, .sugar, .saturatedFat, .sodium])
    }

    @Test func deleteEntry_meal_alsoCoversTheFurtherNutrientTypes() {
        #expect(HealthMapping.extraDeleteIdentifiers(for: .meal)
            == [.dietaryFiber, .dietarySugar, .dietaryFatSaturated, .dietarySodium])
        #expect(HealthMapping.extraDeleteIdentifiers(for: .drink).isEmpty)
        #expect(HealthMapping.extraDeleteIdentifiers(for: .workout).isEmpty)
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

struct HealthAccessGroupTests {
    private func identifiers(_ types: Set<HKSampleType>) -> Set<String> { Set(types.map(\.identifier)) }
    private func identifiers(_ types: Set<HKObjectType>) -> Set<String> { Set(types.map(\.identifier)) }

    @Test func coreTypes_unchanged() {
        // The status of the core group must not change for existing users: a new type here would stop the mirroring.
        let expectedShare: Set<String> = [
            HKQuantityTypeIdentifier.dietaryEnergyConsumed.rawValue, HKQuantityTypeIdentifier.dietaryProtein.rawValue,
            HKQuantityTypeIdentifier.dietaryCarbohydrates.rawValue, HKQuantityTypeIdentifier.dietaryFatTotal.rawValue,
            HKQuantityTypeIdentifier.dietaryWater.rawValue, HKQuantityTypeIdentifier.activeEnergyBurned.rawValue,
            HKObjectType.workoutType().identifier,
        ]
        #expect(identifiers(HealthKitStore.shareTypes) == expectedShare)
        #expect(identifiers(HealthKitStore.coreReadTypes) == [HKObjectType.workoutType().identifier])
        #expect(identifiers(HealthKitStore.connectReadTypes)
            == [HKObjectType.workoutType().identifier, HKQuantityTypeIdentifier.stepCount.rawValue])
        #expect(identifiers(HealthKitStore.stepReadTypes) == [HKQuantityTypeIdentifier.stepCount.rawValue])
    }

    @Test func group_status_notAskedThenAsked() {
        #expect(HealthMapping.groupAccess(.shouldRequest) == .notAsked)
        #expect(HealthMapping.groupAccess(.unnecessary) == .asked)
        #expect(HealthMapping.groupAccess(.unknown) == .asked)
    }

    @Test func writeGroups_disjointFromCoreShareTypes() {
        let core = identifiers(HealthKitStore.shareTypes)
        for group in [HealthAccessGroup.moreNutrients, .body] {
            let types = identifiers(HealthKitStore.shareTypes(of: group))
            #expect(!types.isEmpty)
            #expect(types.isDisjoint(with: core), "\(group) must not share a type with the core group")
        }
    }

    @Test func foreignNutrition_readOnly_doesNotChangeShareStatus() {
        // Reading the nutrition of other apps asks for read access only; the write status of the core group stays as it is.
        #expect(HealthKitStore.shareTypes(of: .foreignNutrition).isEmpty)
        #expect(HealthKitStore.shareTypes(of: .activeEnergy).isEmpty)
        #expect(HealthKitStore.shareTypes(of: .bodyProfile).isEmpty)
        #expect(!HealthKitStore.readTypes(of: .foreignNutrition).isEmpty)
    }

    @Test func readTypes_neverJoinTheCoreOrStepGroups() {
        let core = identifiers(HealthKitStore.coreReadTypes).union(identifiers(HealthKitStore.stepReadTypes))
        for group in HealthAccessGroup.allCases {
            #expect(identifiers(HealthKitStore.readTypes(of: group)).isDisjoint(with: core), "\(group) read types overlap")
        }
    }

    @Test func groups_coverTheTypesOfThePlan() {
        #expect(identifiers(HealthKitStore.readTypes(of: .activeEnergy)) == [HKQuantityTypeIdentifier.activeEnergyBurned.rawValue])
        #expect(identifiers(HealthKitStore.shareTypes(of: .moreNutrients)) == [
            HKQuantityTypeIdentifier.dietaryFiber.rawValue, HKQuantityTypeIdentifier.dietarySugar.rawValue,
            HKQuantityTypeIdentifier.dietaryFatSaturated.rawValue, HKQuantityTypeIdentifier.dietarySodium.rawValue])
        #expect(identifiers(HealthKitStore.shareTypes(of: .body)) == identifiers(HealthKitStore.readTypes(of: .body)))
        #expect(identifiers(HealthKitStore.readTypes(of: .bodyProfile)) == [
            HKQuantityTypeIdentifier.height.rawValue, HKCharacteristicTypeIdentifier.dateOfBirth.rawValue,
            HKCharacteristicTypeIdentifier.biologicalSex.rawValue])
        #expect(identifiers(HealthKitStore.readTypes(of: .foreignNutrition)).count == 9)
    }
}

struct DailyActiveEnergyMappingTests {
    @Test func dailyActiveEnergy_dropsDaysWithoutStatistics() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let sums: [(start: Date, value: Double?)] = [(start, 512.4), (start.addingTimeInterval(86_400), nil),
                                                       (start.addingTimeInterval(172_800), 0)]
        let days = HealthMapping.dailyActiveEnergy(sums)
        #expect(days.map(\.start) == [start, start.addingTimeInterval(172_800)])
        #expect(days.map(\.kilocalories) == [512.4, 0])
    }

    @Test func dailyActiveEnergy_neverNegative() {
        #expect(HealthMapping.dailyActiveEnergy([(Date(timeIntervalSince1970: 0), -3)]).first?.kilocalories == 0)
    }
}

struct WeightMappingTests {
    let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    @Test func syncIdentifier_weight() {
        #expect(HealthMapping.syncIdentifier(.weight, id: id, part: "mass") == "tagwerk.weight.11111111-2222-3333-4444-555555555555.mass")
        #expect(HealthMapping.syncIdentifier(.weight, id: id, part: "bodyFat").hasSuffix(".bodyFat"))
    }

    @Test func save_weight_deniedReturnsFalse() {
        let weight = HealthWeight(id: id, date: .now, version: 1, kilograms: 81.4, bodyFatPercent: 22)
        let denied = HealthMapping.weightWrite(for: weight, mayWrite: { _ in false })
        #expect(!denied.isComplete)
        #expect(denied.writes.isEmpty && denied.removals.isEmpty)
        // Only the body fat is denied: the weight is written and the entry counts as mirrored.
        let partial = HealthMapping.weightWrite(for: weight, mayWrite: { $0 == .mass })
        #expect(partial.isComplete)
        #expect(partial.writes.map(\.part) == [.mass] && partial.writes.first?.value == 81.4)
    }

    @Test func weightWrite_bodyFatIsAFraction_andAnEditWithoutItRemovesTheOldSample() {
        let both = HealthMapping.weightWrite(for: HealthWeight(id: id, date: .now, version: 1, kilograms: 80, bodyFatPercent: 25),
                                             mayWrite: { _ in true })
        #expect(both.writes.map(\.part) == [.mass, .bodyFat])
        #expect(both.writes.last?.value == 0.25)
        #expect(both.removals.isEmpty)
        let massOnly = HealthMapping.weightWrite(for: HealthWeight(id: id, date: .now, version: 2, kilograms: 80, bodyFatPercent: nil),
                                                 mayWrite: { _ in true })
        #expect(massOnly.writes.map(\.part) == [.mass])
        #expect(massOnly.removals == [.bodyFat])
    }

    @Test func weightUnits() {
        #expect(HealthMapping.WeightPart.mass.unit == .gramUnit(with: .kilo))
        #expect(HealthMapping.WeightPart.bodyFat.unit == .percent())
    }

    @Test func deleteEntry_weight_onlyBodyTypes() {
        #expect(HealthMapping.extraDeleteIdentifiers(for: .weight) == [.bodyMass, .bodyFatPercentage])
        #expect(HealthEntryKind.weight.shareKinds.isEmpty, "a weight never touches the core group")
    }

    @Test func foreignWeights_filtersOwn() {
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        func sample(_ offset: Double, _ kg: Double, bundle: String, marker: Bool = false) -> HealthMapping.WeightSample {
            HealthMapping.WeightSample(id: UUID(), date: day.addingTimeInterval(offset), kilograms: kg,
                                       metadata: marker ? [HealthMapping.markerKey: 1] : nil, sourceBundleID: bundle, sourceName: bundle)
        }
        let result = HealthMapping.foreignWeights([sample(3, 81.0, bundle: "com.withings"), sample(1, 82.0, bundle: "local.tagwerk.app"),
                                                   sample(2, 80.5, bundle: "com.apple.health", marker: true),
                                                   sample(0, 79.9, bundle: "com.apple.health")],
                                                  ownBundleID: "local.tagwerk.app")
        #expect(result.map(\.kilograms) == [79.9, 81.0], "own samples (by source and by marker) are dropped, the rest is oldest first")
        #expect(result.map(\.sourceName) == ["com.apple.health", "com.withings"])
    }
}
