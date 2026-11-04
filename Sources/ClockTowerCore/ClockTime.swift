import Foundation

public enum ClockTime {
    private static func calendar(in zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    public static func text(_ date: Date, zone: String, use24Hour: Bool) -> String {
        guard let zone = TimeZone(identifier: zone) else { return "—" }
        let parts = calendar(in: zone).dateComponents([.hour, .minute], from: date)
        guard let hour = parts.hour, let minute = parts.minute else { return "—" }
        return use24Hour ? String(format: "%02d:%02d", hour, minute)
            : String(format: "%d:%02d %@", (hour + 11) % 12 + 1, minute, hour < 12 ? "AM" : "PM")
    }

    public static func isDay(_ date: Date, zone: String) -> Bool {
        guard let zone = TimeZone(identifier: zone) else { return false }
        return (4..<21).contains(calendar(in: zone).component(.hour, from: date))
    }

    /// Compare the calendar dates at the same instant, including across the International Date Line.
    public static func dayDifference(at date: Date, in city: TimeZone, relativeTo local: TimeZone = .autoupdatingCurrent) -> Int {
        let utc = calendar(in: TimeZone.gmt)
        let localDay = utc.startOfDay(for: date.addingTimeInterval(TimeInterval(local.secondsFromGMT(for: date))))
        let cityDay = utc.startOfDay(for: date.addingTimeInterval(TimeInterval(city.secondsFromGMT(for: date))))
        return utc.dateComponents([.day], from: localDay, to: cityDay).day!
    }

    // The slider measures elapsed minutes from local midnight. The repeated hour on a
    // fall-back day has two positions, and no position represents a skipped spring hour.
    public static func previewRange(for date: Date, zone: TimeZone = .autoupdatingCurrent) -> ClosedRange<Double> {
        let day = calendar(in: zone).dateInterval(of: .day, for: date)!
        return 0...max(0, floor(day.duration / 60) - 1)
    }

    public static func minute(of date: Date, zone: TimeZone = .autoupdatingCurrent) -> Double {
        floor(date.timeIntervalSince(calendar(in: zone).startOfDay(for: date)) / 60)
    }

    public static func preview(on date: Date, minute: Double, zone: TimeZone = .autoupdatingCurrent) -> Date {
        let range = previewRange(for: date, zone: zone)
        return calendar(in: zone).startOfDay(for: date)
            .addingTimeInterval(min(max(range.lowerBound, minute.rounded()), range.upperBound) * 60)
    }

    public static func nextMinute(after date: Date) -> Date {
        Date(timeIntervalSince1970: (floor(date.timeIntervalSince1970 / 60) + 1) * 60)
    }

    public static func menuTitle(_ settings: Settings, at date: Date) -> String {
        var pieces = [String]()
        if settings.showDate {
            pieces.append(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
        }
        pieces += settings.clocks.filter(\.isPinned).map { clock in
            let name = settings.compact ? compactName(clock.name) : clock.name
            return name + " " + text(date, zone: clock.timeZoneID, use24Hour: settings.use24Hour)
        }
        return pieces.joined(separator: "   ")
    }

    private static func compactName(_ name: String) -> String {
        // Keep custom emoji labels intact, including flags, keycaps and joined emoji.
        if name.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation || $0.value == 0xFE0F || $0.value == 0x20E3 }) {
            return name
        }
        let words = name.split(whereSeparator: \.isWhitespace)
        if (2...3).contains(words.count) {
            return words.map { Int($0) == nil ? String($0.prefix(1)) : String($0) }.joined().uppercased()
        }
        return String(name.prefix(3)).uppercased()
    }
}
