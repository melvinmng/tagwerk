import Foundation

/// One measured completion.
public struct EffortSample: Sendable, Equatable {
    public let source: TaskSource
    public let labels: [String]
    public let estimateMinutes: Int?
    public let actualMinutes: Int
    public let completedAt: Date

    public init(source: TaskSource, labels: [String], estimateMinutes: Int?, actualMinutes: Int, completedAt: Date) {
        self.source = source
        self.labels = labels
        self.estimateMinutes = estimateMinutes
        self.actualMinutes = actualMinutes
        self.completedAt = completedAt
    }
}

/// What samples are grouped by.
public enum EffortGroupKind: Sendable, Hashable {
    case source(TaskSource)
    case label(String)
}

public struct EffortGroup: Sendable, Equatable {
    public let kind: EffortGroupKind
    /// Samples with an estimate in the window.
    public let count: Int
    /// Median of actual / estimate; `nil` with fewer than `EffortStats.minimumSamples` samples.
    public let medianRatio: Double?
    /// The same as a percentage deviation from the estimate (+40 = took 40 % longer); `nil` like `medianRatio`.
    public let deviationPercent: Int?
}

public enum EffortStats {
    public static let window: TimeInterval = 56 * 86_400
    public static let minimumSamples = 3
    public static let factorRange = 0.5...2.0

    /// Samples inside the window that ends at `now`.
    public static func inWindow(_ samples: [EffortSample], now: Date, window: TimeInterval = window) -> [EffortSample] {
        samples.filter { $0.completedAt <= now && $0.completedAt > now.addingTimeInterval(-window) }
    }

    /// Samples without an estimate (shown as "measured without estimate", never part of a ratio).
    public static func withoutEstimate(_ samples: [EffortSample], now: Date, window: TimeInterval = window) -> Int {
        inWindow(samples, now: now, window: window).filter { ($0.estimateMinutes ?? 0) <= 0 }.count
    }

    /// One group per source and per label with at least one sample. Sources first, then labels; larger groups first.
    public static func groups(_ samples: [EffortSample], window: TimeInterval = window, now: Date) -> [EffortGroup] {
        let usable = inWindow(samples, now: now, window: window).filter { ($0.estimateMinutes ?? 0) > 0 }
        var bySource: [TaskSource: [Double]] = [:]
        var byLabel: [String: [Double]] = [:]
        for sample in usable {
            let ratio = Double(sample.actualMinutes) / Double(sample.estimateMinutes ?? 1)
            bySource[sample.source, default: []].append(ratio)
            for label in Set(sample.labels) { byLabel[label, default: []].append(ratio) }
        }
        let sources = bySource.map { make(.source($0.key), ratios: $0.value) }
            .sorted { ($0.count, "\($0.kind)") > ($1.count, "\($1.kind)") }
        let labels = byLabel.map { make(.label($0.key), ratios: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : "\($0.kind)" < "\($1.kind)" }
        return sources + labels
    }

    /// Correction factor for a task: the label of the task with the most samples (of at least `minimumSamples`),
    /// otherwise its source, otherwise 1. Kept between 0.5 and 2.0.
    public static func factor(source: TaskSource, labels: [String], samples: [EffortSample], now: Date) -> Double {
        let all = groups(samples, now: now)
        let usableLabel = all.compactMap { group -> (count: Int, label: String, ratio: Double)? in
            guard case .label(let label) = group.kind, labels.contains(label), let ratio = group.medianRatio else { return nil }
            return (group.count, label, ratio)
        }.sorted { $0.count != $1.count ? $0.count > $1.count : $0.label < $1.label }.first
        if let usableLabel { return clamp(usableLabel.ratio) }
        if let group = all.first(where: { $0.kind == .source(source) }), let ratio = group.medianRatio { return clamp(ratio) }
        return 1
    }

    /// The estimate scaled by `factor`, rounded to 5 minutes (at least 5).
    public static func expectedMinutes(estimate: Int, factor: Double) -> Int {
        max(5, Int((Double(estimate) * factor / 5).rounded()) * 5)
    }

    private static func make(_ kind: EffortGroupKind, ratios: [Double]) -> EffortGroup {
        guard ratios.count >= minimumSamples else {
            return EffortGroup(kind: kind, count: ratios.count, medianRatio: nil, deviationPercent: nil)
        }
        let median = median(of: ratios)
        return EffortGroup(kind: kind, count: ratios.count, medianRatio: median, deviationPercent: Int(((median - 1) * 100).rounded()))
    }

    private static func median(of values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    private static func clamp(_ value: Double) -> Double { min(max(value, factorRange.lowerBound), factorRange.upperBound) }
}
