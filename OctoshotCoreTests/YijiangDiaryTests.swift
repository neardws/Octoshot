import XCTest
@testable import OctoshotCore

final class YijiangDiaryTests: XCTestCase {
    func testParseTimestampFromBasename() {
        let tz = TimeZone(secondsFromGMT: 8 * 3600)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        let parsed = YijiangDiaryFrameLoader.parseTimestamp(from: "2025-10-17T09-05-00+0800")
        XCTAssertNotNil(parsed)
        if let parsed {
            let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: parsed)
            XCTAssertEqual(comps.year, 2025)
            XCTAssertEqual(comps.month, 10)
            XCTAssertEqual(comps.day, 17)
            XCTAssertEqual(comps.hour, 9)
            XCTAssertEqual(comps.minute, 5)
        }
    }

    func testKeyframeSelectionOnAppSwitch() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let frames = [
            snapshot(at: t0, app: "Xcode", text: "func main()"),
            snapshot(at: t0.addingTimeInterval(30), app: "Xcode", text: "func main() {"),
            snapshot(at: t0.addingTimeInterval(60), app: "Safari", text: "Octoshot documentation"),
        ]
        let indices = YijiangDiaryKeyframeSelector.selectKeyframeIndices(from: frames)
        XCTAssertEqual(indices.first, 0)
        XCTAssertTrue(indices.contains(2))
    }

    func testWindowingTenMinuteBuckets() {
        let start = Date(timeIntervalSince1970: 0)
        let entries = [
            entry(at: start.addingTimeInterval(60), app: "Xcode"),
            entry(at: start.addingTimeInterval(8 * 60), app: "Xcode"),
            entry(at: start.addingTimeInterval(11 * 60), app: "Safari"),
        ]
        let windows = YijiangDiaryWindowing.assignWindows(to: entries, windowMinutes: 10)
        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows[0].entries.count, 2)
        XCTAssertEqual(windows[1].entries.count, 1)
    }

    func testDigestContainsYijiangVoice() {
        let start = Date(timeIntervalSince1970: 0)
        let window = YijiangDiaryTimelineWindow(
            start: start,
            end: start.addingTimeInterval(600),
            entries: [
                YijiangDiaryWindowEntry(
                    timestamp: start.addingTimeInterval(120),
                    frontmostApp: "Xcode",
                    textPreview: "struct Diary {}",
                    textSource: .accessibility,
                    vlmCaption: "[stub] 写 Swift",
                    isKeyframe: true
                ),
            ]
        )
        let md = YijiangDiaryDigestBuilder.buildDigest(windows: [window], day: start)
        XCTAssertTrue(md.contains("一酱今日吐槽日报"))
        XCTAssertTrue(md.contains("Xcode"))
        XCTAssertTrue(md.contains("时间线"))
    }

    func testTextJaccardDetectsChange() {
        let similar = YijiangDiaryKeyframeSelector.textJaccard("hello world", "hello world!")
        let different = YijiangDiaryKeyframeSelector.textJaccard("hello world", "completely other topic")
        XCTAssertGreaterThan(similar, different)
    }

    private func snapshot(at date: Date, app: String, text: String) -> YijiangDiaryFrameSnapshot {
        let frame = YijiangDiaryFrame(
            timestamp: date,
            imageURL: URL(fileURLWithPath: "/tmp/fake.png"),
            frontmostApp: app,
            accessibilityText: text
        )
        return YijiangDiaryFrameSnapshot(frame: frame, resolvedText: text, textSource: .accessibility)
    }

    private func entry(at date: Date, app: String) -> YijiangDiaryWindowEntry {
        YijiangDiaryWindowEntry(
            timestamp: date,
            frontmostApp: app,
            textPreview: "preview",
            textSource: .accessibility,
            vlmCaption: nil,
            isKeyframe: false
        )
    }
}
