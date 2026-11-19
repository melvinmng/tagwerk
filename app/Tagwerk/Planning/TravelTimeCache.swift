import Foundation
import TagwerkCore

/// Remembers travel times and looked-up places in a JSON file, so Apple Maps is asked once per trip and
/// the plan has values without network. The file holds at most 500 entries.
///
/// A travel time never expires for reading: once fetched it stays valid until a newer one replaces it, also while the
/// device is offline. It is only asked for again online, after 14 days (`needsRefresh`). A trip Apple Maps could not
/// answer (place not found, implausible) is remembered too (`rejected`), so a restart without network does not turn it
/// into a provisional block; it is asked again after one day.
///
/// Keys: `<from key>|<to key>|<transport>` for a trip, `place|<place key>` for the coordinates of a place.
struct TravelTimeCache: Equatable {
    struct Entry: Codable, Equatable {
        /// Rounded travel time; 0 for a trip under 3 minutes (not a block, but known).
        var minutes: Int?
        var latitude: Double?
        var longitude: Double?
        var storedAt: Date
        /// The trip has no usable answer. Optional, so files written before this field existed still decode.
        var rejected: Bool?
    }

    /// Age after which a travel time is asked for again (not after which it stops being used), and after which the
    /// coordinates of a looked-up place are looked up again.
    static let lifetime: TimeInterval = 14 * 86_400
    /// Age after which a rejected trip is asked for again.
    static let rejectedLifetime: TimeInterval = 86_400
    static let maximumEntries = 500

    private(set) var entries: [String: Entry]
    private let fileURL: URL?

    /// `fileURL == nil` keeps the cache in memory (tests, previews).
    init(fileURL: URL?) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let stored = try? JSONDecoder.iso.decode([String: Entry].self, from: data) {
            entries = stored
        } else {
            entries = [:]
        }
    }

    /// Where the app keeps the file: `Application Support/Tagwerk/travel-times.json`.
    static var defaultFileURL: URL? {
        guard let support = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                         appropriateFor: nil, create: true) else { return nil }
        let folder = support.appending(path: "Tagwerk", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "travel-times.json")
    }

    static func tripKey(from: TravelPlace, to: TravelPlace, transport: TravelTransport) -> String {
        "\(from.key)|\(to.key)|\(transport.rawValue)"
    }

    static func placeKey(_ place: TravelPlace) -> String { "place|\(place.key)" }

    /// The travel time of a trip of any age; `nil` when unknown or rejected (a time of 0 is a known value).
    func minutes(forTrip key: String) -> Int? {
        guard let entry = entries[key], entry.rejected != true else { return nil }
        return entry.minutes
    }

    /// Apple Maps could not answer this trip when it was asked last.
    func isRejected(forTrip key: String) -> Bool {
        entries[key]?.rejected == true
    }

    /// Whether the trip should be asked for (again): not known at all, or known for longer than its lifetime.
    func needsRefresh(forTrip key: String, now: Date) -> Bool {
        guard let entry = entries[key] else { return true }
        return now.timeIntervalSince(entry.storedAt) >= (entry.rejected == true ? Self.rejectedLifetime : Self.lifetime)
    }

    /// The newest travel time to this destination from any starting point with the same transport. Trips under
    /// 3 minutes (0), rejected trips and implausible values are not an answer for another starting point.
    func latestMinutes(toDestination destinationKey: String, transport: TravelTransport) -> Int? {
        let suffix = "|\(destinationKey)|\(transport.rawValue)"
        return entries
            .filter { $0.key.hasSuffix(suffix) && !$0.key.hasPrefix("place|") && $0.value.rejected != true }
            .compactMap { _, entry -> (Int, Date)? in
                guard let minutes = entry.minutes, minutes > 0, TravelPlausibility.isPlausibleTravelTime(minutes: minutes) else { return nil }
                return (minutes, entry.storedAt)
            }
            .max { $0.1 < $1.1 }?.0
    }

    /// The coordinates of a looked-up place; `nil` when unknown or expired.
    func coordinates(forPlace key: String, now: Date) -> (latitude: Double, longitude: Double)? {
        guard let entry = fresh(key, now: now), let latitude = entry.latitude, let longitude = entry.longitude else { return nil }
        return (latitude, longitude)
    }

    mutating func store(minutes: Int, forTrip key: String, now: Date) {
        entries[key] = Entry(minutes: minutes, latitude: nil, longitude: nil, storedAt: now, rejected: nil)
        trim()
    }

    /// Remembers that Apple Maps has no usable answer for the trip; replaces an older travel time.
    mutating func storeRejected(forTrip key: String, now: Date) {
        entries[key] = Entry(minutes: nil, latitude: nil, longitude: nil, storedAt: now, rejected: true)
        trim()
    }

    mutating func store(latitude: Double, longitude: Double, forPlace key: String, now: Date) {
        entries[key] = Entry(minutes: nil, latitude: latitude, longitude: longitude, storedAt: now, rejected: nil)
        trim()
    }

    /// Writes the file; a failure only means the next launch starts without these entries.
    func save() {
        guard let fileURL, let data = try? JSONEncoder.iso.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func fresh(_ key: String, now: Date) -> Entry? {
        guard let entry = entries[key], now.timeIntervalSince(entry.storedAt) < Self.lifetime else { return nil }
        return entry
    }

    /// Drops the oldest entries beyond the limit.
    private mutating func trim() {
        guard entries.count > Self.maximumEntries else { return }
        let oldest = entries.sorted { $0.value.storedAt < $1.value.storedAt }.prefix(entries.count - Self.maximumEntries)
        for (key, _) in oldest { entries[key] = nil }
    }
}

private extension JSONEncoder {
    static var iso: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var iso: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
