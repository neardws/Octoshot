import CryptoKit
import XCTest
@testable import OctoshotCore

final class DiaryMiniCPMTests: XCTestCase {
    private func window(_ offset: TimeInterval = 0) -> DiaryWindowSkeleton {
        let start = Date(timeIntervalSince1970: 1_700_000_000 + offset)
        return DiaryWindowSkeleton(start: start, end: start.addingTimeInterval(600), appDurations: ["cursor": 600],
            entries: [DiaryWindowEntry(appBundleID: "cursor", appName: "Cursor", windowTitle: "日报布局",
                                      textSnippets: ["骨架聚合"], urlHost: "example.com", duration: 600)])
    }

    private let good = "在「日报布局」里来回挪方块，八只手都替你累。"

    func testCatalogKeepsSmolDefaultAndMiniCPMOptional() {
        let model = EmbeddedModelID.miniCPMV46_4bit
        XCTAssertEqual(model.huggingFaceRepo, "mlx-community/MiniCPM-V-4.6-4bit")
        XCTAssertEqual(model.approximateSizeMB, 2200)
        XCTAssertTrue(model.licenseNote.contains("Apache-2.0"))
        XCTAssertTrue(EmbeddedAIModelPaths.directory(for: model).path.contains("Application Support/Octoshot/Models/"))
        XCTAssertNotEqual(model, .smolVLM2_500M_4bit)
    }

    func testAcceptsGroundedChineseSentence() {
        XCTAssertEqual(DiaryRoastQualityGate.accept(good, for: window()), good)
        XCTAssertLessThanOrEqual(good.count, 40)
    }

    func testRejectsLongEnglishEmptyAndMultipleSentences() {
        for output in ["", "   ", "Hello hello hello", String(repeating: "好", count: 41),
                       good + "又来一句。", good + "\n再来一句", "「日报布局」，你好！再见。"] {
            XCTAssertNil(DiaryRoastQualityGate.accept(output, for: window()), output)
        }
    }

    func testRejectsInventedChineseAndSkeletonRepetition() {
        for output in ["今天你刷了三小时视频。", "「炒股亏钱」，窗口开着，可不算已经搞定。",
                       "「日报布局」，你已经完成上线了。", "你今天一点用都没有。"] {
            XCTAssertNil(DiaryRoastQualityGate.accept(output, for: window()))
        }
    }

    func testFreeFormAnchorsIncludeChineseFragmentsAndCaseInsensitiveEnglish() {
        for output in [good, "布局还在眼前，八只手先歇会儿。", "骨架像拼图，八只手等着看。",
                       "cursor像个舞台，窗口标题比演员还忙。", "CUR像个舞台，窗口标题比演员还忙。"] {
            XCTAssertEqual(DiaryRoastQualityGate.accept(output, for: window()), output)
        }
        XCTAssertNil(DiaryRoastQualityGate.accept("八只手都替你累，窗口像个舞台。", for: window()))
        XCTAssertNil(DiaryRoastQualityGate.accept("日和cu在跳舞，八只手都替你累。", for: window()))
    }

    func testThinkingAndKnownPrefixAreStrippedButFormattingIsRejected() {
        XCTAssertEqual(DiaryRoastQualityGate.accept(" <think>私密\n思考</think> 吐槽：\(good) ", for: window()), good)
        for output in ["<think>未结束\(good)", "解释：\(good)", "**\(good)**", "- \(good)",
                       "_\(good)_", "吐槽：\n\(good)", "\(good)\u{2028}布局", "<b>\(good)</b>"] {
            XCTAssertNil(DiaryRoastQualityGate.accept(output, for: window()), output)
        }
    }

    func testRejectsInventedNumbersDurationsDomainsAndHandles() {
        for output in ["日报布局折腾了42次，八只手都替你累。", "日报布局折腾三小时，八只手都替你累。",
                       "日报布局磨到十二点半，八只手都替你累。", "日报布局去了evil.com，八只手都替你累。",
                       "日报布局去了https://example.com/secret，真忙。", "日报布局交给@neil，八只手歇了。",
                       "日报布局去了坏人.中国，真忙。", "日报布局去了https://example.com/秘密，真忙。"] {
            XCTAssertNil(DiaryRoastQualityGate.accept(output, for: window()), output)
        }
        var grounded = window()
        grounded.entries[0].textSnippets += ["42次 三小时 十二点半 @neil @neil_dev"]
        for output in ["日报布局折腾了42次，八只手都替你累。", "日报布局磨了三小时，八只手都替你累。",
                       "日报布局交给@neil，八只手歇了。", "日报布局交给@neil_dev，八只手歇了。",
                       "example.com像本天书，八只手也得翻页。"] {
            XCTAssertEqual(DiaryRoastQualityGate.accept(output, for: grounded), output)
        }
        XCTAssertNil(DiaryRoastQualityGate.accept("日报布局折腾了4次，八只手都替你累。", for: grounded))
        let knownDomain = "日报布局旁边的example.com像本天书。"
        XCTAssertEqual(DiaryRoastQualityGate.accept(knownDomain, for: grounded), knownDomain)
    }

    func testRecognizablePersonalNamesNeedSkeletonEvidence() {
        for name in ["张三", "李四", "王老师"] {
            let output = "日报布局，\(name)也得挠头。"
            XCTAssertNil(DiaryRoastQualityGate.accept(output, for: window()))
            var grounded = window()
            grounded.entries[0].textSnippets += [name]
            XCTAssertEqual(DiaryRoastQualityGate.accept(output, for: grounded), output)
        }
    }

    func testRejectsInsultsEvenWhenGrounded() {
        for insult in ["废物", "蠢", "垃圾", "傻", "白痴", "去死", "滚", "智障", "一点用都没有"] {
            var grounded = window()
            grounded.entries[0].textSnippets += [insult]
            XCTAssertNil(DiaryRoastQualityGate.accept("日报布局里你真\(insult)。", for: grounded))
        }
    }

    func testFortyCharacterBoundaryAndChineseMajority() {
        let boundary = "日报布局" + String(repeating: "哎", count: 35) + "。"
        XCTAssertEqual(DiaryRoastQualityGate.accept(boundary, for: window()), boundary)
        XCTAssertNil(DiaryRoastQualityGate.accept(boundary + "哎", for: window()))
        XCTAssertNil(DiaryRoastQualityGate.accept("Cursor makes this layout look very busy。", for: window()))
    }

    func testCompletionClaimsNeedCorrespondingSkeletonWords() {
        for claim in ["已经搞定", "上线了", "修好了", "完成了", "已修复", "通过了"] {
            let output = "日报布局\(claim)，八只手先记账。"
            XCTAssertNil(DiaryRoastQualityGate.accept(output, for: window()), output)
            var grounded = window()
            grounded.entries[0].textSnippets += [claim]
            XCTAssertEqual(DiaryRoastQualityGate.accept(output, for: grounded), output)
        }
    }

    func testNearDuplicatesAndRuleCopiesAreRejected() {
        XCTAssertNil(DiaryRoastQualityGate.accept(good, for: window(), previousRoasts: [good]))
        XCTAssertNil(DiaryRoastQualityGate.accept(good.replacingOccurrences(of: "都", with: "也"),
                                                for: window(), previousRoasts: [good]))
        XCTAssertNil(DiaryRoastQualityGate.accept("Cursor 里有「日报布局」。", for: window()))
    }

    func testPromptContainsOnlySkeletonFactsAndCaps() {
        let prompt = DiaryRoastQualityGate.prompt(for: window())
        for text in ["40字", "一句中文", "不编造", "AX/OCR", "Cursor", "日报布局", "骨架聚合", "example.com", "600"] {
            XCTAssertTrue(prompt.contains(text), text)
        }
        XCTAssertFalse(prompt.contains("SmolVLM"))
        XCTAssertTrue(prompt.contains("自由句式"))
        XCTAssertFalse(prompt.contains("结尾只能"))
    }

    func testNoNewFactFromKeyframe() {
        var skeleton = window()
        skeleton.keyframe = DiaryActivitySample(timestamp: skeleton.start, appBundleID: "secret", appName: "炒股亏钱",
                                                windowTitle: "股价", focusedText: "亏了三万")
        XCTAssertFalse(DiaryRoastQualityGate.prompt(for: skeleton).contains("亏了三万"))
        XCTAssertNil(DiaryRoastQualityGate.accept("「炒股亏钱」，窗口开着，可不算已经搞定。", for: skeleton))
    }

    @MainActor
    func testInferenceCaps() {
        XCTAssertEqual(DiaryMiniCPMRoastService.maxTokens, 64)
        XCTAssertEqual(DiaryMiniCPMRoastService.timeout, 30)
        XCTAssertEqual(DiaryMiniCPMRoastService.idleUnloadDelay, 300)
    }

    private func defaults() -> UserDefaults {
        let suite = "DiaryMiniCPMTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    @MainActor
    func testMissingModelDoesNotCallBackendAndBuildsReport() async {
        let service = DiaryMiniCPMRoastService(defaults: defaults(), installed: { false }) { _, _ in
            XCTFail("No model must never invoke any backend")
            return self.good
        }
        let roasts = await service.prepare(windows: [window()])
        let report = DiaryReportBuilder().build(windows: [window()], day: window().start, roastProvider: roasts)
        XCTAssertEqual(report.timeline.count, 1)
        XCTAssertNil(report.timeline[0].roast)
        XCTAssertNil(service.disabledReason)
    }

    @MainActor
    func testInjectedRoastAndOptionalImageReachReport() async {
        let image = Data([1, 2, 3])
        let service = DiaryMiniCPMRoastService(defaults: defaults(), installed: { true }) { prompt, received in
            XCTAssertEqual(received, image)
            XCTAssertTrue(prompt.contains("日报布局"))
            return self.good
        }
        let roasts = await service.prepare(windows: [window()], keyFrame: { _ in image })
        let report = DiaryReportBuilder().build(windows: [window()], day: window().start, roastProvider: roasts)
        XCTAssertEqual(report.timeline[0].roast, good)
        XCTAssertNil(report.closingRoast)
    }

    @MainActor
    func testThreeFailuresPersistAndResetNextCalendarDay() async {
        let store = defaults()
        var now = window().start
        var calls = 0
        let backend: DiaryMiniCPMRoastService.Backend = { _, _ in calls += 1; return "English garbage" }
        let service = DiaryMiniCPMRoastService(defaults: store, clock: { now }, installed: { true }, backend: backend)
        let roasts = await service.prepare(windows: (0..<5).map { window(Double($0) * 600) })
        XCTAssertTrue(roasts.lines.isEmpty)
        XCTAssertEqual(calls, 3)
        XCTAssertNotNil(service.disabledReason)
        let relaunched = DiaryMiniCPMRoastService(defaults: store, clock: { now }, installed: { true }, backend: backend)
        _ = await relaunched.prepare(windows: [window()])
        XCTAssertEqual(calls, 3)
        now = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        XCTAssertNil(relaunched.disabledReason)
        _ = await relaunched.prepare(windows: [window()])
        XCTAssertEqual(calls, 4)
    }

    @MainActor
    func testSuccessResetsConsecutiveFailures() async {
        var calls = 0
        let service = DiaryMiniCPMRoastService(defaults: defaults(), installed: { true }) { _, _ in
            calls += 1
            return calls == 3 ? self.good : "bad"
        }
        let roasts = await service.prepare(windows: (0..<5).map { window(Double($0) * 600) })
        XCTAssertEqual(calls, 5)
        XCTAssertEqual(roasts.lines.count, 1)
        XCTAssertNil(service.disabledReason)
    }

    @MainActor
    func testLoadFailureAndTimeoutRemainTextOnly() async {
        for code in [2, 3] {
            let service = DiaryMiniCPMRoastService(defaults: defaults(), installed: { true }) { _, _ in
                throw NSError(domain: "Octoshot.MLX", code: code, userInfo: [NSLocalizedDescriptionKey: "离线模拟加载失败或超时"])
            }
            let roasts = await service.prepare(windows: [window(), window(600), window(1200)])
            XCTAssertTrue(roasts.lines.isEmpty)
            XCTAssertTrue(service.disabledReason?.contains("离线模拟") == true)
        }
    }

    @MainActor
    func testConcurrentReportsSerializeBackendCalls() async {
        var active = 0
        var peak = 0
        let service = DiaryMiniCPMRoastService(defaults: defaults(), installed: { true }) { _, _ in
            active += 1
            peak = max(peak, active)
            defer { active -= 1 }
            try await Task.sleep(nanoseconds: 5_000_000)
            return self.good
        }
        async let first = service.prepare(windows: [window(), window(600)])
        async let second = service.prepare(windows: [window(1200)])
        let results = await (first, second)
        XCTAssertEqual(peak, 1)
        XCTAssertEqual(results.0.lines.count + results.1.lines.count, 3)
    }

    @MainActor
    func testDeadlineCancelsBackendAndTripsDailyBreaker() async {
        var cancellations = 0
        let service = DiaryMiniCPMRoastService(defaults: defaults(), installed: { true }) { _, _ in
            do { try await Task.sleep(nanoseconds: 1_000_000_000) }
            catch { cancellations += 1; throw error }
            return self.good
        }
        service.callTimeout = 0.005
        let roasts = await service.prepare(windows: [window(), window(600), window(1200), window(1800)])
        XCTAssertTrue(roasts.lines.isEmpty)
        XCTAssertEqual(cancellations, 3)
        XCTAssertTrue(service.disabledReason?.contains("超过30秒") == true)
    }

    @MainActor
    func testCallerCancellationDoesNotCountAsModelFailure() async {
        let service = DiaryMiniCPMRoastService(defaults: defaults(), installed: { true }) { _, _ in
            try await Task.sleep(nanoseconds: 1_000_000_000)
            return self.good
        }
        let task = Task { await service.prepare(windows: [window()]) }
        await Task.yield()
        task.cancel()
        let result = await task.value
        XCTAssertTrue(result.lines.isEmpty)
        XCTAssertNil(service.disabledReason)
    }

    private func directory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private var files: [DiaryModelFile] {
        ["config.json", "tokenizer.json", "model.safetensors"].map {
            DiaryModelFile(path: $0, size: 2, sha256: SHA256.hash(data: Data("{}".utf8)).map { String(format: "%02x", $0) }.joined())
        }
    }

    func testListingFiltersDirectoriesAndReadsLFSHashes() throws {
        let objects: [[String: Any]] = files.map { ["type": "file", "path": $0.path, "size": $0.size, "lfs": ["oid": $0.sha256!]] }
        let data = try JSONSerialization.data(withJSONObject: objects + [["type": "directory", "path": "assets"],
            ["type": "file", "path": ".gitattributes", "size": 10], ["type": "file", "path": "README.md", "size": 10]])
        XCTAssertEqual(try DiaryModelDownload.parseListing(data), files)
    }

    func testRejectsUnsafeAndIncompleteListings() throws {
        XCTAssertThrowsError(try DiaryModelDownload.validateListing([]))
        for path in ["../outside", "/outside", "folder/../../outside", ".verified-install.json", "folder\\bad"] {
            XCTAssertThrowsError(try DiaryModelDownload.validateListing(files + [.init(path: path, size: 1)]))
        }
        XCTAssertThrowsError(try DiaryModelDownload.validateListing(files + [files[0]]))
    }

    func testSpaceFailureDoesNotFetch() async throws {
        let directory = try directory()
        do {
            try await DiaryModelDownload.install(in: directory, listing: { self.files }, availableSpace: { _ in 1 }, fetch: { _, _ in
                XCTFail("Space check must run before download")
            })
            XCTFail("Must fail")
        } catch DiaryModelDownloadError.insufficientSpace { }
        XCTAssertFalse(EmbeddedAIModelPaths.isInstalled(.miniCPMV46_4bit, in: directory))
    }

    func testStubInstallResumeAndDeletedFileDetection() async throws {
        let directory = try directory()
        try Data("{}".utf8).write(to: directory.appendingPathComponent("config.json"))
        XCTAssertFalse(EmbeddedAIModelPaths.isInstalled(.miniCPMV46_4bit, in: directory))
        var fetched: [String] = []
        var progress: [Double] = []
        try await DiaryModelDownload.install(in: directory, listing: { self.files }, availableSpace: { _ in Int64.max }, fetch: { file, url in
            fetched.append(file.path)
            try Data("{}".utf8).write(to: url)
        }, progress: { fraction, _ in progress.append(fraction) })
        XCTAssertEqual(fetched, ["tokenizer.json", "model.safetensors"])
        XCTAssertEqual(progress.last, 1)
        XCTAssertTrue(EmbeddedAIModelPaths.isInstalled(.miniCPMV46_4bit, in: directory))
        try FileManager.default.removeItem(at: directory.appendingPathComponent("model.safetensors"))
        XCTAssertFalse(EmbeddedAIModelPaths.isInstalled(.miniCPMV46_4bit, in: directory))
    }

    func testHashFailureNeverMarksInstalled() async throws {
        let directory = try directory()
        do {
            try await DiaryModelDownload.install(in: directory, listing: { self.files }, availableSpace: { _ in Int64.max }, fetch: { _, url in
                try Data("xx".utf8).write(to: url)
            })
            XCTFail("Bad hash must fail")
        } catch DiaryModelDownloadError.invalidFile { }
        XCTAssertFalse(DiaryModelDownload.isInstalled(in: directory))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("config.json.partial").path))
    }

    func testExistingCorruptFileIsDownloadedAgain() async throws {
        let directory = try directory()
        try Data("xx".utf8).write(to: directory.appendingPathComponent("config.json"))
        var fetched: [String] = []
        try await DiaryModelDownload.install(in: directory, listing: { self.files }, availableSpace: { _ in Int64.max }, fetch: { file, url in
            fetched.append(file.path)
            try Data("{}".utf8).write(to: url)
        })
        XCTAssertEqual(fetched.count, 3)
        XCTAssertTrue(DiaryModelDownload.isInstalled(in: directory))
    }

    func testSymlinkedFilesCannotEscapeModelDirectory() async throws {
        let directory = try directory()
        let outside = try self.directory().appendingPathComponent("config.json")
        try Data("{}".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("config.json"), withDestinationURL: outside)
        do {
            try await DiaryModelDownload.install(in: directory, listing: { self.files }, availableSpace: { _ in Int64.max }, fetch: { _, _ in
                XCTFail("No request after unsafe destination")
            })
            XCTFail("Must reject symlink")
        } catch DiaryModelDownloadError.invalidListing { }
    }

    func testInterruptedDownloadCanResumeWithoutMarker() async throws {
        let directory = try directory()
        do {
            try await DiaryModelDownload.install(in: directory, listing: { self.files }, availableSpace: { _ in Int64.max }, fetch: { file, url in
                if file.path == "tokenizer.json" { throw URLError(.notConnectedToInternet) }
                try Data("{}".utf8).write(to: url)
            })
            XCTFail("Offline fixture must fail")
        } catch is URLError { }
        XCTAssertFalse(DiaryModelDownload.isInstalled(in: directory))
        var resumed: [String] = []
        try await DiaryModelDownload.install(in: directory, listing: { self.files }, availableSpace: { _ in Int64.max }, fetch: { file, url in
            resumed.append(file.path)
            try Data("{}".utf8).write(to: url)
        })
        XCTAssertEqual(resumed, ["tokenizer.json", "model.safetensors"])
        XCTAssertTrue(DiaryModelDownload.isInstalled(in: directory))
    }
}
