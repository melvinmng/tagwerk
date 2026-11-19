import Foundation
import TagwerkCore

/// Remembers travel times and looked-up places in a JSON file, so Apple Maps is asked once per trip and
/// the plan has values without network. Entries expire after 14 days; the file holds at most 500 entries.
///
/// Keys: `<from key>|<to key>|<transport>` for a trip, `place|<place key>` for the coordinates of a place.
struct TravelTimeCache: Equatable {
    struct Entry: Codable, Equatable {
        /// Rounded travel time; 0 for a trip under 3 minutes (not a block, but known).
        var minutes: Int?
        var latitude: Double?
        var longitude: Double?
        var storedAt: Date
    }

    static let lifetime: TimeInterval = 14 * 86_400
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

    /// The travel time of a trip; `nil` when unknown or older than 14 days.
    func minutes(forTrip key: String, now: Date) -> Int? {
        guard let entry = fresh(key, now: now) else { return nil }
        return entry.minutes
    }

    /// The coordinates of a looked-up place; `nil` when unknown or expired.
    func coordinates(forPlace key: String, now: Date) -> (latitude: Double, longitude: Double)? {
        guard let entry = fresh(key, now: now), let latitude = entry.latitude, let longitude = entry.longitude else { return nil }
        return (latitude, longitude)
    }

    mutating func store(minutes: Int, forTrip key: String, now: Date) {
        entries[key] = Entry(minutes: minutes, latitude: nil, longitude: nil, storedAt: now)
        trim()
    }

    mutating func store(latitude: Double, longitude: Double, forPlace key: String, now: Date) {
        entries[key] = Entry(minutes: nil, latitude: latitude, longitude: longitude, storedAt: now)
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
