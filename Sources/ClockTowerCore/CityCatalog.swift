import Foundation

/// An offline GeoNames catalog. Search results have stable city IDs and start unpinned.
public enum CityCatalog {
    private struct Entry {
        let clock: CityClock
        let name: String
        let aliases: String
        let primary: String
        let searchable: String
    }

    private static let entries: [Entry] = {
        guard let url = Bundle.module.url(forResource: "cities", withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            preconditionFailure("Clock Tower's offline city catalog is missing from its resource bundle.")
        }
        var supportedZones = [String: Bool]()
        return text.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            precondition(fields.count == 7, "Invalid city catalog row")
            let supported = supportedZones[fields[3]] ?? (TimeZone(identifier: fields[3]) != nil)
            supportedZones[fields[3]] = supported
            // Older supported macOS releases may not know a newly introduced IANA zone.
            // Only offer cities the system can actually render, rather than guessing offsets.
            guard supported else { return nil }
            let clock = CityClock(id: identifier(for: Int(fields[0])!), name: fields[1], fullName: fields[2], timeZoneID: fields[3])
            return Entry(clock: clock, name: normalized(fields[1]), aliases: fields[5], primary: fields[6],
                         searchable: fields[6] + " " + fields[5].replacingOccurrences(of: "|", with: " "))
        }
    }()

    /// Matches city names, alternate spellings, regions, countries, and IANA zones.
    /// Results require a time zone recognized by the installed macOS time-zone database.
    /// Exact and prefix city matches rank first, then population from the source data.
    public static func search(_ query: String, limit: Int = 8) -> [CityClock] {
        let query = normalized(query)
        guard !query.isEmpty, limit > 0 else { return [] }
        let words = query.split(separator: " ").map(String.init)
        var ranked: [(Int, Int, CityClock)] = []
        func containsWords(_ text: String) -> Bool {
            words.allSatisfy { text.hasPrefix($0) || text.contains(" " + $0) }
        }
        for (index, entry) in entries.enumerated() {
            guard containsWords(entry.searchable) else { continue }
            let rank: Int
            if entry.name == query { rank = 0 }
            else if entry.name.hasPrefix(query) { rank = 1 }
            else if entry.aliases.split(separator: "|").contains(Substring(query)) { rank = 2 }
            else if containsWords(entry.primary) { rank = 3 }
            else { rank = 4 }
            ranked.append((rank, index, entry.clock))
        }
        return ranked.sorted { left, right in
            left.0 == right.0 ? left.1 < right.1 : left.0 < right.0
        }.prefix(limit).map { $0.2 }
    }

    /// GeoNames IDs occupy a dedicated UUID namespace, independent of user-visible names.
    static func identifier(for geonameID: Int) -> UUID {
        UUID(uuidString: String(format: "C10C7000-0000-4000-8000-%012llX", Int64(geonameID)))!
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
