import ClockTowerCore
import Foundation
import XCTest

final class ClockTimeTests: XCTestCase {
    private func instant(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    func testAstanaTransitionAndNoonToday() {
        for (utc, expected) in [
            ("2024-02-29T17:59:00Z", "23:59"),
            ("2024-02-29T18:00:00Z", "23:00"),
            ("2026-11-04T12:00:00Z", "17:00"),
        ] {
            XCTAssertEqual(ClockTime.text(instant(utc), zone: "Asia/Almaty", use24Hour: true), expected, utc)
        }
    }

    func testPreviewAndFormattingAcrossBothDSTChanges() {
        let ny = TimeZone(identifier: "America/New_York")!
        for (utc, lastMinute, start, end) in [
            ("2026-03-08T06:30:00Z", 1379.0, "01:30", "03:30"),
            ("2026-11-01T05:30:00Z", 1499.0, "01:30", "01:30"),
        ] {
            let date = instant(utc)
            XCTAssertEqual(ClockTime.previewRange(for: date, zone: ny).upperBound, lastMinute)
            let preview = ClockTime.preview(on: date, minute: ClockTime.minute(of: date, zone: ny) + 60, zone: ny)
            XCTAssertEqual(preview.timeIntervalSince(date), 3600)
            XCTAssertEqual(ClockTime.text(date, zone: ny.identifier, use24Hour: true), start)
            XCTAssertEqual(ClockTime.text(preview, zone: ny.identifier, use24Hour: true), end)
            XCTAssertEqual(ClockTime.text(preview, zone: "Asia/Kathmandu", use24Hour: true),
                           lastMinute == 1379 ? "13:15" : "12:15")
        }
    }

    func testMenuTitleFollowsPinOrderAndDisplayPreferences() {
        let now = instant("2026-11-04T12:00:00Z")
        var settings = Settings(clocks: [
            CityClock(name: "Astana", fullName: "Astana, KZ", timeZoneID: "Asia/Almaty", isPinned: true),
            CityClock(name: "London", fullName: "London, GB", timeZoneID: "Europe/London"),
            CityClock(name: "New York", fullName: "New York, US", timeZoneID: "America/New_York", isPinned: true)
        ])
        XCTAssertEqual(ClockTime.menuTitle(settings, at: now), "Astana 17:00   New York 07:00")
        settings.compact = true
        settings.use24Hour = false
        XCTAssertEqual(ClockTime.menuTitle(settings, at: now), "AST 5:00 PM   NY 7:00 AM")
        settings.clocks = []
        XCTAssertEqual(ClockTime.menuTitle(settings, at: now), "")
        settings.showDate = true
        XCTAssertFalse(ClockTime.menuTitle(settings, at: now).isEmpty)
    }

    func testMinuteRolloverAcrossMidnight() {
        let before = instant("2026-11-04T18:59:59Z").addingTimeInterval(0.75)
        let next = ClockTime.nextMinute(after: before)
        XCTAssertEqual(next.timeIntervalSince(before), 0.25)
        XCTAssertEqual(ClockTime.text(before, zone: "Asia/Almaty", use24Hour: false), "11:59 PM")
        XCTAssertEqual(ClockTime.text(next, zone: "Asia/Almaty", use24Hour: false), "12:00 AM")
        XCTAssertEqual(ClockTime.nextMinute(after: next).timeIntervalSince(next), 60)
    }
}
