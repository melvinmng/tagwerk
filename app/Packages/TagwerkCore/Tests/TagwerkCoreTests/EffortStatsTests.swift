import Foundation
import Testing
@testable import TagwerkCore

struct EffortStatsTests {
    let now = instant(2026, 11, 19, 12, 0)

    private func sample(_ source: TaskSource = .local, labels: [String] = [], estimate: Int? = 30, actual: Int, daysAgo: Double = 1) -> EffortSample {
        EffortSample(source: source, labels: labels, estimateMinutes: estimate, actualMinutes: actual,
                     completedAt: now.addingTimeInterval(-daysAgo * 86_400))
    }

    @Test func groupNeedsThreeSamples() {
        let two = [sample(actual: 60), sample(actual: 45)]
        let group = EffortStats.groups(two, now: now).first { $0.kind == .source(.local) }
        #expect(group?.count == 2)
        #expect(group?.medianRatio == nil && group?.deviationPercent == nil)
        let three = EffortStats.groups(two + [sample(actual: 45)], now: now).first { $0.kind == .source(.local) }
        #expect(three?.count == 3)
        #expect(three?.medianRatio == 1.5)
        #expect(three?.deviationPercent == 50)
    }

    @Test func medianRatio_ignoresOutliers() {
        let samples = [sample(actual: 30), sample(actual: 30), sample(actual: 33), sample(actual: 300)]
        let group = EffortStats.groups(samples, now: now).first { $0.kind == .source(.local) }
        #expect(abs((group?.medianRatio ?? 0) - 1.05) < 0.0001)
        #expect(group?.deviationPercent == 5)
    }

    @Test func factor_prefersLabelOverSource() {
        var samples = (0..<3).map { _ in sample(.github, labels: ["Schreiben"], actual: 42) }       // ratio 1.4
        samples += (0..<4).map { _ in sample(.github, labels: [], actual: 24) }                       // ratio 0.8
        let withLabel = EffortStats.factor(source: .github, labels: ["Schreiben"], samples: samples, now: now)
        #expect(abs(withLabel - 1.4) < 0.0001)
        // Without a matching label the source decides: the median of 0.8 ×4 and 1.4 ×3 is the fourth value, 0.8.
        let withoutLabel = EffortStats.factor(source: .github, labels: ["Anderes"], samples: samples, now: now)
        #expect(abs(withoutLabel - 0.8) < 0.0001)
        // A label group below three samples is not used; the source median of the eight values is (0.8 + 1.4) / 2.
        let few = [sample(.github, labels: ["Selten"], actual: 60)] + samples
        #expect(abs(EffortStats.factor(source: .github, labels: ["Selten"], samples: few, now: now) - 1.1) < 0.0001)
        #expect(EffortStats.factor(source: .reminders, labels: [], samples: samples, now: now) == 1)
    }

    @Test func factor_isClamped() {
        let slow = (0..<3).map { _ in sample(actual: 120) }   // 4.0
        #expect(EffortStats.factor(source: .local, labels: [], samples: slow, now: now) == 2.0)
        let fast = (0..<3).map { _ in sample(actual: 3) }     // 0.1
        #expect(EffortStats.factor(source: .local, labels: [], samples: fast, now: now) == 0.5)
    }

    @Test func samplesOutsideWindow_areIgnored() {
        let old = (0..<3).map { _ in sample(actual: 60, daysAgo: 57) }
        #expect(EffortStats.groups(old, now: now).isEmpty)
        let edge = sample(actual: 60, daysAgo: 55)
        #expect(EffortStats.groups([edge], now: now).first?.count == 1)
        #expect(EffortStats.inWindow(old + [edge], now: now).count == 1)
    }

    @Test func expectedMinutes_roundToFive() {
        #expect(EffortStats.expectedMinutes(estimate: 30, factor: 1.4) == 40)
        #expect(EffortStats.expectedMinutes(estimate: 30, factor: 1.0) == 30)
        #expect(EffortStats.expectedMinutes(estimate: 10, factor: 0.5) == 5)
        #expect(EffortStats.expectedMinutes(estimate: 5, factor: 0.5) == 5)
    }

    @Test func samplesWithoutEstimate_areCountedSeparately() {
        let samples = [sample(estimate: nil, actual: 30), sample(estimate: 0, actual: 30), sample(actual: 30)]
        #expect(EffortStats.withoutEstimate(samples, now: now) == 2)
        #expect(EffortStats.groups(samples, now: now).first?.count == 1)
    }
}
