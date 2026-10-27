import CryptoKit
import Foundation
import XCTest
@testable import OctoshotCore

final class YijiangDiaryStoreTests: XCTestCase {
    private var root: URL!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("YijiangDiary-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    private func store(key: DiaryKeyProvider = InMemoryDiaryKeyProvider()) throws -> DiaryStore {
        try DiaryStore(directory: root.appendingPathComponent("Diary"), keyProvider: key, clock: { self.now })
    }

    private func skeleton(end: Date? = nil) -> DiaryWindowSkeleton {
        let end = end ?? now
        let sample = DiaryActivitySample(timestamp: end.addingTimeInterval(-600), appBundleID: "test.editor",
                                         appName: "Synthetic Editor", windowTitle: "UNIQUE_PRIVATE_TITLE",
                                         focusedText: "UNIQUE_PRIVATE_BODY")
        return DiaryWindowSkeleton(start: sample.timestamp, end: end, appDurations: [sample.appBundleID: 600],
                                   entries: [DiaryWindowEntry(appBundleID: sample.appBundleID, appName: sample.appName,
                                                             windowTitle: sample.windowTitle, textSnippets: [sample.focusedText!],
                                                             duration: 600)], keyframe: sample)
    }

    private var allDates: Range<Date> { Date(timeIntervalSince1970: 0)..<Date(timeIntervalSince1970: 4_000_000_000) }

    private func frame(_ janitor: DiaryJanitor, name: String = UUID().uuidString, modified: Date? = nil) throws -> URL {
        let url = janitor.framesDirectory.appendingPathComponent(name + ".png")
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")!
        try png.write(to: url)
        if let modified { try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path) }
        return url
    }

    func testEncryptedRoundTripReopenAndNoPlaintextBytes() throws {
        let key = InMemoryDiaryKeyProvider()
        var database: DiaryStore? = try store(key: key)
        let value = skeleton()
        try database!.insert(value)
        XCTAssertEqual(try database!.fetch(range: allDates), [value])
        let file = database!.databaseURL
        database = nil
        let bytes = try Data(contentsOf: file)
        for secret in ["UNIQUE_PRIVATE_TITLE", "UNIQUE_PRIVATE_BODY", "test.editor", "Synthetic Editor"] {
            XCTAssertNil(bytes.range(of: Data(secret.utf8)))
        }
        let reopened = try store(key: key)
        XCTAssertEqual(try reopened.fetch(range: allDates), [value])
    }

    func testWrongKeyFails() throws {
        let database = try store()
        try database.insert(skeleton())
        let wrong = try store()
        XCTAssertThrowsError(try wrong.fetch(range: allDates))
    }

    func testStorePermissionsAndIndexMarker() throws {
        let database = try store()
        let attributes = try FileManager.default.attributesOfItem(atPath: database.directory.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        XCTAssertEqual(try Data(contentsOf: database.directory.appendingPathComponent(".metadata_never_index")).count, 0)
        XCTAssertEqual(try database.directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
    }

    func testFetchOverlapPurgeAndDeleteAll() throws {
        let database = try store()
        let old = skeleton(end: now.addingTimeInterval(-40 * 86_400))
        try database.insert(old)
        try database.insert(skeleton())
        XCTAssertEqual(try database.fetch(range: now.addingTimeInterval(-100)..<now).count, 1)
        XCTAssertTrue(try database.fetch(range: now..<now.addingTimeInterval(600)).isEmpty)
        try database.purge(olderThan: now.addingTimeInterval(-30 * 86_400))
        XCTAssertEqual(try database.fetch(range: allDates), [skeleton()])
        try database.deleteAll()
        XCTAssertTrue(try database.fetch(range: allDates).isEmpty)
    }

    func testProcessedFrameDeletedImmediatelyAndMissingIsHarmless() throws {
        let janitor = try DiaryJanitor(store: store())
        let file = try frame(janitor)
        try janitor.markProcessed(file)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertNoThrow(try janitor.markProcessed(file))
    }

    func testFailedFramesExpireWithInjectedClockAndRetention() throws {
        let database = try store()
        try database.insert(skeleton(end: now.addingTimeInterval(-31 * 86_400)))
        try database.insert(skeleton())
        let janitor = try DiaryJanitor(store: database, clock: { self.now })
        let old = try frame(janitor, modified: now.addingTimeInterval(-86_401))
        let boundary = try frame(janitor, modified: now.addingTimeInterval(-86_400))
        let fresh = try frame(janitor, modified: now.addingTimeInterval(-86_399))
        try janitor.runCleanup()
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: boundary.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fresh.path))
        XCTAssertEqual(try database.fetch(range: allDates).count, 1)
    }

    func testRetentionOptionsAndForever() throws {
        let database = try store()
        for days in [7, 30, 90, nil] as [Int?] {
            try database.deleteAll()
            try database.insert(skeleton(end: now.addingTimeInterval(-100 * 86_400)))
            let janitor = try DiaryJanitor(store: database, policy: DiaryCleanupPolicy(retentionDays: days))
            try janitor.runCleanup(now: now)
            XCTAssertEqual(try database.fetch(range: allDates).count, days == nil ? 1 : 0)
        }
    }

    func testJanitorRejectsOutsideFilesAndSymlinks() throws {
        let janitor = try DiaryJanitor(store: store())
        let outside = root.appendingPathComponent("keep.png")
        try Data([1]).write(to: outside)
        XCTAssertThrowsError(try janitor.markProcessed(outside))
        let link = janitor.framesDirectory.appendingPathComponent("link.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        XCTAssertThrowsError(try janitor.markProcessed(link))
        try janitor.runCleanup(now: now.addingTimeInterval(1_000_000))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func testOfflineJSONReplaySixWindows() throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("YijiangDiaryReplay.json")
        let decoded = try MockDiaryActivitySource(json: Data(contentsOf: fixture))
        let database = try store()
        let janitor = try DiaryJanitor(store: database)
        var samples: [DiaryActivitySample] = []
        var frameFiles: [URL] = []
        while var sample = decoded.nextSample() {
            let file = try frame(janitor)
            frameFiles.append(file)
            sample.keyframeURL = file
            samples.append(sample)
        }
        let recorder = DiaryRecorder(source: MockDiaryActivitySource(samples: samples), store: database, janitor: janitor)
        while try recorder.recordNext() {}
        try recorder.finish(at: samples[0].timestamp.addingTimeInterval(3_600))
        let windows = try database.fetch(range: allDates)
        XCTAssertEqual(windows.count, 6)
        XCTAssertEqual(windows.flatMap { $0.entries.map(\.windowTitle) }, ["Plan", "Code", "Research", "Outline", "Review", "Wrap up"])
        XCTAssertEqual(windows.flatMap { $0.entries.map(\.appBundleID) }, ["test.notes", "test.editor", "test.browser", "test.notes", "test.editor", "test.notes"])
        XCTAssertEqual(windows[1].appDurations["test.editor"], 300)
        XCTAssertEqual(windows[0].entries[0].textSnippets, ["Contact ••• for synthetic notes"])
        let json = String(decoding: try JSONEncoder().encode(windows), as: UTF8.self)
        XCTAssertFalse(json.contains("com.1password"))
        XCTAssertFalse(json.contains("synthetic@example.com"))
        XCTAssertFalse(json.contains("EXCLUDED_SECRET"))
        XCTAssertEqual(windows.compactMap(\.keyframe).count, 6)
        XCTAssertTrue(frameFiles.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: janitor.framesDirectory.path).isEmpty)
    }

    func testRecorderUnavailableAndInjectedClock() throws {
        let database = try store()
        let janitor = try DiaryJanitor(store: database)
        let sample = DiaryActivitySample(timestamp: now, appBundleID: "test.editor", appName: "Editor", windowTitle: "Draft")
        let recorder = DiaryRecorder(source: MockDiaryActivitySource(samples: [sample]), store: database,
                                     janitor: janitor, clock: { self.now.addingTimeInterval(120) })
        XCTAssertTrue(try recorder.recordNext())
        try recorder.recordUnavailable()
        try recorder.finish(at: now.addingTimeInterval(600))
        XCTAssertEqual(try database.fetch(range: allDates).flatMap { $0.appDurations.values }.reduce(0, +), 120)
    }
}
