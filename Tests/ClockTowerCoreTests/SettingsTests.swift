import Foundation
import XCTest
@testable import ClockTowerCore

final class SettingsTests: XCTestCase {
    private func withStore(_ body: (SettingsStore, URL, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let current = directory.appendingPathComponent("Clock Tower/settings.json")
        let legacy = directory.appendingPathComponent("Hovrly/settings.json")
        try body(SettingsStore(settingsURL: current, legacySettingsURL: legacy), current, legacy)
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func testFirstLaunchPersistsDefaultsAndAnEmptyListSurvivesRelaunch() throws {
        try withStore { store, current, legacy in
            XCTAssertEqual(try store.load(), .defaults)
            let empty = Settings(clocks: [], use24Hour: false, compact: true, showDate: true, collapsed: true)
            try store.save(empty)
            try write(#"{"clocks":[{"name":"Ignored","full":"Ignored, GB","timezone":"Europe/London","tray":1}]}"#, to: legacy)
            XCTAssertEqual(try SettingsStore(settingsURL: current, legacySettingsURL: legacy).load(), empty)
        }
    }

    func testHovrlyImportPreservesOrderNamesPinsAndPreferencesWithoutChangingSource() throws {
        try withStore { store, current, legacy in
            let source = #"{"clocks":[{"name":"Home 🏡","full":"Home in Astana","timezone":"Asia/Almaty","tray":1},{"name":"New York","full":"New York, US","timezone":"America/New_York","tray":false}],"twentyfourhour":"off","compact":"on","date":"on","collapse":"on"}"#
            try write(source, to: legacy)
            let imported = try store.load()
            XCTAssertEqual(imported.clocks.map(\.name), ["Home 🏡", "New York"])
            XCTAssertEqual(imported.clocks.map(\.fullName), ["Home in Astana", "New York, US"])
            XCTAssertEqual(imported.clocks.map(\.timeZoneID), ["Asia/Almaty", "America/New_York"])
            XCTAssertEqual(imported.clocks.map(\.isPinned), [true, false])
            XCTAssertFalse(imported.use24Hour)
            XCTAssertTrue(imported.compact)
            XCTAssertTrue(imported.showDate)
            XCTAssertTrue(imported.collapsed)
            XCTAssertEqual(try String(contentsOf: legacy, encoding: .utf8), source)
            try write(#"{"clocks":[]}"#, to: legacy)
            XCTAssertEqual(try SettingsStore(settingsURL: current, legacySettingsURL: legacy).load(), imported)
        }
    }

    func testEmptyHovrlyListIsImportedWithMissingPreferenceDefaults() throws {
        try withStore { store, _, legacy in
            try write(#"{"clocks":[]}"#, to: legacy)
            XCTAssertEqual(try store.load(), Settings(clocks: []))
        }
    }

    func testInvalidLegacyDataIsLeftUntouchedAndDoesNotCreateDestination() throws {
        let invalidSources = [
            "{broken",
            #"{"clocks":[{"name":"Bad zone","full":"Bad zone","timezone":"Moon/Sea","tray":0}]}"#,
            #"{"clocks":[],"compact":"sometimes"}"#,
            #"{"clocks":[{"name":"Bad pin","full":"Bad pin","timezone":"UTC","tray":2}]}"#,
            #"{"clocks":[{"name":"Missing field","timezone":"UTC","tray":false}]}"#
        ]
        for source in invalidSources {
            try withStore { store, current, legacy in
                try write(source, to: legacy)
                XCTAssertThrowsError(try store.load(), source)
                XCTAssertThrowsError(try store.save(.defaults), source)
                XCTAssertFalse(FileManager.default.fileExists(atPath: current.path))
                XCTAssertEqual(try String(contentsOf: legacy, encoding: .utf8), source)
            }
        }
    }

    func testCorruptNativeSettingsCannotBeOverwrittenByFallbackOrLegacy() throws {
        try withStore { store, current, legacy in
            let source = #"{"clocks":[],"use24Hour":"broken"}"#
            try write(source, to: current)
            try write(#"{"clocks":[]}"#, to: legacy)
            XCTAssertThrowsError(try store.load())
            XCTAssertThrowsError(try store.save(.defaults))
            XCTAssertEqual(try String(contentsOf: current, encoding: .utf8), source)
        }
    }

    func testRoundTripPreservesClockIdentityAfterRenameAndRejectsInvalidUpdates() throws {
        try withStore { store, current, _ in
            var city = try XCTUnwrap(CityCatalog.search("Astana").first)
            let originalID = city.id
            city.name = "Team"
            city.fullName = "Team in Kazakhstan"
            city.isPinned = true
            let expected = Settings(clocks: [city], use24Hour: false)
            try store.save(expected)
            let reloaded = try store.load()
            XCTAssertEqual(reloaded, expected)
            XCTAssertEqual(reloaded.clocks.first?.id, originalID)
            XCTAssertEqual(CityCatalog.search("Astana").first?.id, originalID)
            let bytes = try Data(contentsOf: current)
            for invalid in [Settings(clocks: [city, city]), Settings(clocks: [CityClock(name: "Bad", fullName: "Bad", timeZoneID: "Moon/Sea")])] {
                XCTAssertThrowsError(try store.save(invalid))
                XCTAssertEqual(try Data(contentsOf: current), bytes)
            }
        }
    }
}
