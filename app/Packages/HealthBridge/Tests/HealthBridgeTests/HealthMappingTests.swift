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

struct HealthRequestStatusTests {
    @Test func shouldRequest_isNotAsked_unnecessary_isAsked() {
        #expect(!HealthMapping.isAsked(.shouldRequest, shareStatuses: []))
        #expect(!HealthMapping.isAsked(.shouldRequest, shareStatuses: [.sharingAuthorized]))
        #expect(HealthMapping.isAsked(.unnecessary, shareStatuses: []))
        #expect(HealthMapping.isAsked(.unnecessary, shareStatuses: [.notDetermined]))
    }

    @Test func unknown_readOnlyGroup_countsAsAsked() {
        // No write type tells more: an unknown answer never brings the button back.
        #expect(HealthMapping.isAsked(.unknown, shareStatuses: []))
    }

    @Test func unknown_withAnsweredWriteType_countsAsAsked() {
        #expect(HealthMapping.isAsked(.unknown, shareStatuses: [.notDetermined, .sharingAuthorized]))
        #expect(HealthMapping.isAsked(.unknown, shareStatuses: [.sharingDenied, .sharingDenied]))
    }

    @Test func unknown_withoutAnyAnsweredWriteType_countsAsNotAsked() {
        // Nothing was ever answered, so the sheet is still due; this keeps a never-asked user from seeing "denied".
        #expect(!HealthMapping.isAsked(.unknown, shareStatuses: [.notDetermined, .notDetermined]))
    }

    @Test func access_unknownStatus_ofAnAskedUser_neverBecomesNotDetermined() {
        let granted = Dictionary(uniqueKeysWithValues: HealthShareKind.allCases.map { ($0, HKAuthorizationStatus.sharingAuthorized) })
        #expect(HealthMapping.access(status: .unknown, shareStatuses: granted) == .authorized)
        var partial = granted
        partial[.water] = .sharingDenied
        #expect(HealthMapping.access(status: .unknown, shareStatuses: partial) == .partial([.water]))
        let refused = Dictionary(uniqueKeysWithValues: HealthShareKind.allCases.map { ($0, HKAuthorizationStatus.sharingDenied) })
        #expect(HealthMapping.access(status: .unknown, shareStatuses: refused) == .denied)
    }

    @Test func access_unknownStatus_ofANeverAskedUser_staysNotDetermined() {
        let fresh = Dictionary(uniqueKeysWithValues: HealthShareKind.allCases.map { ($0, HKAuthorizationStatus.notDetermined) })
        #expect(HealthMapping.access(status: .unknown, shareStatuses: fresh) == .notDetermined)
        #expect(HealthMapping.access(status: .shouldRequest, shareStatuses: fresh) == .notDetermined)
    }

    @Test func access_unnecessary_usesTheWriteStatuses() {
        var statuses = Dictionary(uniqueKeysWithValues: HealthShareKind.allCases.map { ($0, HKAuthorizationStatus.sharingAuthorized) })
        #expect(HealthMapping.access(status: .unnecessary, shareStatuses: statuses) == .authorized)
        statuses[.workouts] = .sharingDenied
        #expect(HealthMapping.access(status: .unnecessary, shareStatuses: statuses) == .partial([.workouts]))
    }

    @Test func group_andSteps_useTheSameRule() {
        #expect(HealthMapping.groupAccess(.unknown, shareStatuses: [.notDetermined]) == .notAsked)
        #expect(HealthMapping.groupAccess(.unknown, shareStatuses: [.sharingAuthorized]) == .asked)
        #expect(HealthMapping.groupAccess(.unknown) == .asked)
        #expect(HealthMapping.stepsAccess(.unknown) == .asked)
        #expect(HealthMapping.stepsAccess(.shouldRequest) == .notAsked)
    }

    @Test func writeAccess_mapsTheAuthorizationStatus() {
        #expect(HealthMapping.writeAccess(.sharingAuthorized) == .allowed)
        #expect(HealthMapping.writeAccess(.sharingDenied) == .denied)
        #expect(HealthMapping.writeAccess(.notDetermined) == .notAsked)
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
        for group in [HealthAccessGroup.moreNutrients, .body, .height] {
            let types = identifiers(HealthKitStore.shareTypes(of: group))
            #expect(!types.isEmpty)
            #expect(types.isDisjoint(with: core), "\(group) must not share a type with the core group")
        }
    }

    @Test func height_hasItsOwnShareGroup_soTheBodyStatusStaysAsItWas() {
        // Height must not join the group `body`: that would put the status of everyone who already allowed the weight back to
        // "should request" and stop mirroring weights.
        #expect(identifiers(HealthKitStore.shareTypes(of: .body)) == [
            HKQuantityTypeIdentifier.bodyMass.rawValue, HKQuantityTypeIdentifier.bodyFatPercentage.rawValue])
        #expect(identifiers(HealthKitStore.shareTypes(of: .height)) == [HKQuantityTypeIdentifier.height.rawValue])
        #expect(HealthKitStore.readTypes(of: .height).isEmpty)
    }

    @Test func consentSheet_asksForEverythingTheAppNeedsAtOnce() {
        let share = identifiers(HealthKitStore.consentShareTypes)
        let read = identifiers(HealthKitStore.consentReadTypes)
        // The core group and the groups the Health card used to leave to separate prompts.
        #expect(share.isSuperset(of: identifiers(HealthKitStore.shareTypes)))
        #expect(share.isSuperset(of: identifiers(HealthKitStore.shareTypes(of: .body))))
        #expect(share.isSuperset(of: identifiers(HealthKitStore.shareTypes(of: .height))))
        #expect(read.isSuperset(of: identifiers(HealthKitStore.connectReadTypes)))
        #expect(read.isSuperset(of: identifiers(HealthKitStore.readTypes(of: .activeEnergy))))
        #expect(read.isSuperset(of: identifiers(HealthKitStore.readTypes(of: .body))))
        // Optional extras stay behind their own switches in the settings.
        #expect(read.isDisjoint(with: identifiers(HealthKitStore.readTypes(of: .foreignNutrition))))
        #expect(read.isDisjoint(with: identifiers(HealthKitStore.readTypes(of: .bodyProfile))))
        #expect(share.isDisjoint(with: identifiers(HealthKitStore.shareTypes(of: .moreNutrients))))
    }

    @Test func foreignNutrition_readOnly_doesNotChangeShareStatus() {
        // Reading the nutrition of other apps asks for read access only; the write status of the core group stays as it is.
        #expect(HealthKitStore.shareTypes(of: .foreignNutrition).isEmpty)
        #expect(HealthKitStore.shareTypes(of: .activeEnergy).isEmpty)
        #expect(HealthKitStore.shareTypes(of: .bodyProfile).isEmpty)
        #expect(!HealthKitStore.readTypes(of: .foreignNutrition).isEmpty)
        #expect(HealthKitStore.readTypes(of: .height).isEmpty)
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

    @Test func foreignWeights_pairsBodyFatOfTheSameSourceAndMoment() {
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let scale = HealthMapping.WeightSample(id: UUID(), date: day, kilograms: 81, metadata: nil, sourceBundleID: "com.withings",
                                               sourceName: "Waage")
        func fat(_ offset: Double, _ fraction: Double, bundle: String) -> HealthMapping.BodyFatSample {
            HealthMapping.BodyFatSample(date: day.addingTimeInterval(offset), fraction: fraction, metadata: nil, sourceBundleID: bundle,
                                        sourceName: bundle)
        }
        let paired = HealthMapping.foreignWeights([scale], bodyFat: [fat(30, 0.231, bundle: "com.withings"),
                                                                     fat(5, 0.40, bundle: "com.other"),
                                                                     fat(3_600, 0.30, bundle: "com.withings"),
                                                                     fat(0, 0.45, bundle: "local.tagwerk.app")],
                                                  ownBundleID: "local.tagwerk.app")
        #expect(paired.count == 1)
        #expect(abs((paired[0].bodyFatPercent ?? 0) - 23.1) < 0.0001, "only the fat value of the same source close in time belongs to the weight")
        #expect(HealthMapping.foreignWeights([scale], ownBundleID: "local.tagwerk.app")[0].bodyFatPercent == nil)
    }
}

struct ForeignNutritionMappingTests {
    private let monday = Date(timeIntervalSince1970: 1_800_000_000)
    private var tuesday: Date { monday.addingTimeInterval(86_400) }

    private func series(_ type: HealthMapping.ForeignType, _ days: [(Date, Double?, [String])]) -> HealthMapping.ForeignSeries {
        HealthMapping.ForeignSeries(type: type, days: days.map { (start: $0.0, value: $0.1, sources: $0.2) })
    }

    @Test func foreignPredicate_excludesMarkerAndOwnSource() {
        // HKSource.default() needs a host app, so a stand-in predicate takes the place of the own source.
        let format = HealthMapping.foreignPredicate(ownSource: NSPredicate(format: "TRUEPREDICATE")).predicateFormat
        #expect(format.contains("NOT"), "the exclusion is part of the predicate: a statistics query cannot filter afterwards")
        #expect(format.contains(HealthMapping.markerKey), "samples with Tagwerk's marker are excluded")
        #expect(format.components(separatedBy: "NOT").count - 1 >= 2, "both the marker and the own source are negated")
    }

    @Test func dailyForeignNutrition_perNutrientNilWhenNoSamples() {
        let days = HealthMapping.foreignDays([series(.energy, [(monday, 340, ["Yazio"])]), series(.protein, [(monday, nil, [])]),
                                              series(.fiber, [(monday, 12, ["Yazio"])])])
        #expect(days.count == 1)
        let intake = days[0].intake
        #expect(intake.kcal == 340 && intake.nutrients.fiber == 12)
        #expect(intake.protein == nil, "no sample is not 0")
        #expect(intake.carbs == nil && intake.fat == nil && intake.waterMilliliters == nil)
        #expect(intake.nutrients.sugar == nil && intake.nutrients.salt == nil)
    }

    @Test func dailyForeignNutrition_dropsDaysWithoutAnyValue() {
        let days = HealthMapping.foreignDays([series(.energy, [(monday, nil, []), (tuesday, 100, ["Lifesum"])])])
        #expect(days.map(\.start) == [tuesday])
    }

    @Test func dailyForeignNutrition_sodiumToSalt() {
        let days = HealthMapping.foreignDays([series(.sodium, [(monday, 1000, ["Yazio"])])])
        #expect(days.first?.intake.nutrients.salt == 2.5, "1000 mg sodium are 2.5 g salt")
    }

    @Test func dailyForeignNutrition_waterStaysInMilliliters() {
        let days = HealthMapping.foreignDays([series(.water, [(monday, 750, ["Wasser-App"])])])
        #expect(days.first?.intake.waterMilliliters == 750)
        #expect(HealthMapping.ForeignType.water.unit == .literUnit(with: .milli))
    }

    @Test func dailyForeignNutrition_namesSources() {
        let days = HealthMapping.foreignDays([series(.energy, [(monday, 300, ["Yazio", "Lifesum"])]),
                                              series(.protein, [(monday, 20, ["Lifesum", "FDDB"])])])
        #expect(days.first?.intake.sources == ["FDDB", "Lifesum", "Yazio"])
    }

    @Test func dailyForeignNutrition_daysAreOldestFirst() {
        let days = HealthMapping.foreignDays([series(.energy, [(tuesday, 1, ["A"]), (monday, 2, ["A"])])])
        #expect(days.map(\.start) == [monday, tuesday])
    }

    @Test func foreignTypes_coverAllNutritionTypesOfTheGroup() {
        let types = Set(HealthMapping.ForeignType.allCases.map { HKQuantityType($0.identifier).identifier })
        #expect(types == Set(HealthKitStore.readTypes(of: .foreignNutrition).map(\.identifier)))
    }
}

struct BodyProfileMappingTests {
    private struct ReadFailure: Error {}

    @Test func bodyProfile_mapsLatestHeight() {
        let old = Date(timeIntervalSince1970: 1_000_000_000), recent = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(HealthMapping.latestHeightCm([(old, 1.78), (recent, 1.80)]) == 180)
        #expect(HealthMapping.latestHeightCm([(recent, 1.80), (old, 1.78)]) == 180, "the order of the samples does not matter")
        #expect(HealthMapping.latestHeightCm([]) == nil)
        #expect(HealthMapping.latestHeightCm([(recent, 0)]) == nil, "a zero height is no measurement")
    }

    @Test func bodyProfile_sexNotSetOrOther_isNil() {
        #expect(HealthMapping.formulaSex(.female) == .female)
        #expect(HealthMapping.formulaSex(.male) == .male)
        #expect(HealthMapping.formulaSex(.other) == nil)
        #expect(HealthMapping.formulaSex(.notSet) == nil)
        #expect(HealthMapping.formulaSex(nil) == nil)
    }

    @Test func bodyProfile_throwingCharacteristic_isNil() {
        let thrown: Int? = HealthMapping.profileField { throw ReadFailure() }
        #expect(thrown == nil)
        let value: Int? = HealthMapping.profileField { 1987 }
        #expect(value == 1987)
        let missing: Int? = HealthMapping.profileField { nil }
        #expect(missing == nil)
        // One failing field leaves the others as they are.
        let profile = HealthBodyProfile(heightCm: 180, birthYear: thrown, sex: .female)
        #expect(profile.heightCm == 180 && profile.birthYear == nil && profile.sex == .female)
    }

    @Test func bodyProfile_emptyHasNoFields() {
        #expect(HealthBodyProfile.empty == HealthBodyProfile(heightCm: nil, birthYear: nil, sex: nil))
    }

    @Test func accessAllows_followsTheDeniedKinds() {
        #expect(HealthAccess.authorized.allowsWriting(.activeEnergy))
        #expect(HealthAccess.partial([.activeEnergy, .water]).allowsWriting(.energy))
        #expect(!HealthAccess.partial([.activeEnergy, .water]).allowsWriting(.activeEnergy))
        #expect(!HealthAccess.denied.allowsWriting(.energy))
        #expect(!HealthAccess.notDetermined.allowsWriting(.energy))
        #expect(!HealthAccess.unavailable.allowsWriting(.energy))
    }
}
