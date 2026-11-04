import Foundation

public struct CityClock: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var fullName: String
    public var timeZoneID: String
    public var isPinned: Bool

    public init(id: UUID = UUID(), name: String, fullName: String, timeZoneID: String, isPinned: Bool = false) {
        self.id = id
        self.name = name
        self.fullName = fullName
        self.timeZoneID = timeZoneID
        self.isPinned = isPinned
    }
}

public struct Settings: Equatable, Codable {
    public var clocks: [CityClock]
    public var use24Hour: Bool
    public var compact: Bool
    public var showDate: Bool
    public var collapsed: Bool

    public init(clocks: [CityClock], use24Hour: Bool = true, compact: Bool = false, showDate: Bool = false, collapsed: Bool = false) {
        self.clocks = clocks
        self.use24Hour = use24Hour
        self.compact = compact
        self.showDate = showDate
        self.collapsed = collapsed
    }

    public static let defaults = Settings(clocks: [
        CityClock(id: CityCatalog.identifier(for: 2950159), name: "Berlin", fullName: "Berlin, DE", timeZoneID: "Europe/Berlin", isPinned: true),
        CityClock(id: CityCatalog.identifier(for: 5128581), name: "New York", fullName: "New York, US", timeZoneID: "America/New_York", isPinned: true)
    ])
}

public enum SettingsError: LocalizedError {
    case invalidSettings(String)

    public var errorDescription: String? {
        switch self {
        case .invalidSettings(let reason): return "Cannot read or save Clock Tower settings: \(reason)"
        }
    }
}

/// Keeps Clock Tower settings separate from Hovrly. Legacy settings are only read.
public final class SettingsStore {
    public let settingsURL: URL
    private let legacySettingsURLs: [URL]

    public convenience init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.init(settingsURL: support.appendingPathComponent("Clock Tower/settings.json"),
                  legacySettingsURLs: [support.appendingPathComponent("Hovrly/settings.json"),
                                       support.appendingPathComponent("hovrly/settings.json")])
    }

    /// A nil legacy URL disables import. This is also useful for portable settings.
    public convenience init(settingsURL: URL, legacySettingsURL: URL?) {
        self.init(settingsURL: settingsURL, legacySettingsURLs: legacySettingsURL.map { [$0] } ?? [])
    }

    private init(settingsURL: URL, legacySettingsURLs: [URL]) {
        self.settingsURL = settingsURL
        self.legacySettingsURLs = legacySettingsURLs
    }

    /// The first successful load writes an independent snapshot, so import happens once.
    /// Invalid files throw and stay untouched; an empty clock list is valid.
    public func load() throws -> Settings {
        if FileManager.default.fileExists(atPath: settingsURL.path) {
            return try decodeNative(Data(contentsOf: settingsURL))
        }
        let legacyURL = legacySettingsURLs.first { FileManager.default.fileExists(atPath: $0.path) }
        let settings: Settings
        if let legacyURL {
            settings = try importLegacy(Data(contentsOf: legacyURL))
        } else {
            settings = .defaults
        }
        try save(settings)
        return settings
    }

    public func save(_ settings: Settings) throws {
        try validate(settings)
        // A UI may show defaults after a load error. Never let that overwrite damaged data.
        if FileManager.default.fileExists(atPath: settingsURL.path) {
            _ = try decodeNative(Data(contentsOf: settingsURL))
        } else if let legacy = legacySettingsURLs.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            // Preserve the opportunity to repair and import a damaged legacy file, even
            // when a caller tries to save fallback defaults after load() throws.
            _ = try importLegacy(Data(contentsOf: legacy))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: settingsURL, options: .atomic)
    }

    private func decodeNative(_ data: Data) throws -> Settings {
        let settings = try JSONDecoder().decode(Settings.self, from: data)
        try validate(settings)
        return settings
    }

    private func validate(_ settings: Settings) throws {
        var ids = Set<UUID>()
        for clock in settings.clocks {
            guard !clock.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !clock.fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SettingsError.invalidSettings("A clock has an empty name.")
            }
            guard TimeZone(identifier: clock.timeZoneID) != nil else {
                throw SettingsError.invalidSettings("Unknown time zone: \(clock.timeZoneID).")
            }
            guard ids.insert(clock.id).inserted else {
                throw SettingsError.invalidSettings("Two clocks have the same identifier.")
            }
        }
    }

    private struct LegacySettings: Decodable {
        var clocks: [LegacyClock]
        var twentyfourhour: String?
        var compact: String?
        var date: String?
        var collapse: String?
    }

    private struct LegacyClock: Decodable {
        var name: String
        var full: String
        var timezone: String
        var tray: Bool

        enum CodingKeys: String, CodingKey { case name, full, timezone, tray }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            name = try values.decode(String.self, forKey: .name)
            full = try values.decode(String.self, forKey: .full)
            timezone = try values.decode(String.self, forKey: .timezone)
            if let boolean = try? values.decode(Bool.self, forKey: .tray) {
                tray = boolean
            } else {
                let integer = try values.decode(Int.self, forKey: .tray)
                guard integer == 0 || integer == 1 else {
                    throw SettingsError.invalidSettings("Hovrly has an invalid pin value.")
                }
                tray = integer == 1
            }
        }
    }

    private func importLegacy(_ data: Data) throws -> Settings {
        let old = try JSONDecoder().decode(LegacySettings.self, from: data)
        func preference(_ value: String?, fallback: Bool) throws -> Bool {
            guard let value else { return fallback }
            switch value {
            case "on": return true
            case "off": return false
            default: throw SettingsError.invalidSettings("Hovrly has an invalid preference value.")
            }
        }
        var usedIDs = Set<UUID>()
        let clocks = old.clocks.map { clock -> CityClock in
            // Match original full names when available. Renamed legacy rows have no original
            // city ID; preserve those as independent clocks rather than guessing from the zone.
            let match = CityCatalog.search(clock.name, limit: 100).first {
                $0.name == clock.name && $0.timeZoneID == clock.timezone &&
                ($0.fullName == clock.full || clock.full == "\(clock.name), \($0.fullName.suffix(2))")
            }
            let proposedID = match?.id ?? UUID()
            let id = usedIDs.insert(proposedID).inserted ? proposedID : UUID()
            usedIDs.insert(id)
            return CityClock(id: id, name: clock.name, fullName: clock.full, timeZoneID: clock.timezone, isPinned: clock.tray)
        }
        let settings = try Settings(clocks: clocks,
                                    use24Hour: preference(old.twentyfourhour, fallback: true),
                                    compact: preference(old.compact, fallback: false),
                                    showDate: preference(old.date, fallback: false),
                                    collapsed: preference(old.collapse, fallback: false))
        try validate(settings)
        return settings
    }
}
