import XCTest
@testable import OctoshotCore

@MainActor
final class DiaryOllamaTests: XCTestCase {
    private let good = "在「日报布局」里来回挪方块，八只手都替你累。"

    private func window(_ offset: TimeInterval = 0) -> DiaryWindowSkeleton {
        let start = Date(timeIntervalSince1970: 1_700_000_000 + offset)
        return DiaryWindowSkeleton(start: start, end: start.addingTimeInterval(600), appDurations: ["cursor": 600],
            entries: [DiaryWindowEntry(appBundleID: "cursor", appName: "Cursor", windowTitle: "日报布局",
                textSnippets: ["骨架聚合"], urlHost: "example.com", duration: 600)])
    }

    private func defaults() -> UserDefaults {
        let name = "DiaryOllamaTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    private func response(_ request: URLRequest, _ payload: [String: Any], status: Int = 200) throws -> (Data, HTTPURLResponse) {
        (try JSONSerialization.data(withJSONObject: payload),
         HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    private func fixture(_ request: URLRequest, version: String = "0.40.5", model: String = DiaryOllamaConfiguration.defaultModel,
                         output: String? = nil) throws -> (Data, HTTPURLResponse) {
        switch request.url!.lastPathComponent {
        case "version": return try response(request, ["version": version])
        case "tags": return try response(request, ["models": [["name": model]]])
        default: return try response(request, ["message": ["content": output ?? good]])
        }
    }

    func testVersionParsingAndNumericComparison() {
        XCTAssertLessThan(DiaryOllamaVersion("0.40.5-rc1")!, DiaryOllamaVersion("0.40.5")!)
        XCTAssertLessThan(DiaryOllamaVersion("0.40.5-rc.2")!, DiaryOllamaVersion("0.40.5-rc.10")!)
        XCTAssertEqual(DiaryOllamaVersion("0.40.5+build.2"), DiaryOllamaVersion("0.40.5"))
        XCTAssertLessThan(DiaryOllamaVersion("0.9.100")!, DiaryOllamaVersion("0.40.5")!)
        XCTAssertLessThan(DiaryOllamaVersion("0.40.4")!, DiaryOllamaVersion("0.40.5")!)
        XCTAssertGreaterThan(DiaryOllamaVersion("0.100.0")!, DiaryOllamaVersion("0.40.5")!)
        XCTAssertGreaterThan(DiaryOllamaVersion("1.0.0")!, DiaryOllamaVersion("0.40.5")!)
        for invalid in ["", "0.40", "0.40.5.1", "0.-40.5", "banana", "０.40.5"] {
            XCTAssertNil(DiaryOllamaVersion(invalid))
        }
    }

    func testConfigurationPersistsAndDefaultsNeverUseLatest() throws {
        let store = defaults()
        XCTAssertEqual(DiaryOllamaConfiguration.load(from: store), .init())
        let config = DiaryOllamaConfiguration(baseURL: "http://localhost:12345", model: "custom/model:1b")
        config.save(to: store)
        XCTAssertEqual(DiaryOllamaConfiguration.load(from: store), config)
        XCTAssertEqual(try config.endpoint("chat").absoluteString, "http://localhost:12345/api/chat")
        XCTAssertEqual(DiaryOllamaConfiguration.defaultModel, "openbmb/minicpm-v4.7:1b")
    }

    func testRejectsRemoteAndCredentialedEndpoints() {
        for address in ["https://example.com", "file:///tmp/model", "http://127.0.0.1@example.com", "http://user@localhost:11434", "http://localhost?key=secret"] {
            XCTAssertThrowsError(try DiaryOllamaConfiguration(baseURL: address).endpoint("chat"))
        }
        XCTAssertNoThrow(try DiaryOllamaConfiguration(baseURL: "http://[::1]:11434").endpoint("chat"))
    }

    func testNotRunning() async {
        let client = DiaryOllamaClient(transport: { _ in throw URLError(.cannotConnectToHost) })
        let status = await client.detect()
        XCTAssertEqual(status, .notRunning)
    }

    func testVersionTooOldDoesNotQueryTags() async {
        var paths: [String] = []
        let client = DiaryOllamaClient(transport: { request in
            paths.append(request.url!.lastPathComponent)
            return try self.fixture(request, version: "0.40.4")
        })
        let status = await client.detect()
        XCTAssertEqual(status, .versionTooOld(found: "0.40.4"))
        XCTAssertEqual(paths, ["version"])
    }

    func testModelMatchingRequiresExactTag() async {
        for model in ["openbmb/minicpm-v4.7", "openbmb/minicpm-v4.7:latest", "other:1b"] {
            let client = DiaryOllamaClient(transport: { try self.fixture($0, model: model) })
            let status = await client.detect()
            XCTAssertEqual(status, .modelMissing)
        }
    }

    func testReadyIncludingVersionSuffix() async {
        let client = DiaryOllamaClient(transport: { try self.fixture($0, version: "0.40.6-rc1") })
        let status = await client.detect()
        XCTAssertEqual(status, .ready)
    }

    func testModelOverrideAndModelAliasField() async {
        let client = DiaryOllamaClient(configuration: .init(model: "local/custom:2b"), transport: { request in
            if request.url!.lastPathComponent == "tags" {
                return try self.response(request, ["models": [["model": "local/custom:2b"]]])
            }
            return try self.fixture(request)
        })
        let status = await client.detect()
        XCTAssertEqual(status, .ready)
    }

    func testHTTPAndMalformedVersionBecomeError() async {
        let client = DiaryOllamaClient(transport: { try self.response($0, [:], status: 503) })
        let status = await client.detect()
        XCTAssertEqual(status, .error("Ollama HTTP 503"))
        let invalid = DiaryOllamaClient(transport: { try self.fixture($0, version: "unknown") })
        guard case .error = await invalid.detect() else { return XCTFail("Expected version error") }
    }

    func testChatRequestContractAndThinkingRemoval() async throws {
        var requests: [URLRequest] = []
        let client = DiaryOllamaClient(transport: { request in
            requests.append(request)
            return try self.fixture(request, output: "<think>private\nreasoning</think>\n\(self.good)")
        })
        let image = Data([1, 2, 3])
        let output = try await client.chat(skeleton: DiaryRoastQualityGate.prompt(for: window()), image: image)
        XCTAssertEqual(output, good)
        XCTAssertEqual(requests.map { $0.url!.path }, ["/api/version", "/api/tags", "/api/chat"])
        XCTAssertEqual(requests.map(\.httpMethod), ["GET", "GET", "POST"])
        let request = try XCTUnwrap(requests.last)
        XCTAssertEqual(request.timeoutInterval, 30)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, DiaryOllamaConfiguration.defaultModel)
        XCTAssertEqual(body["stream"] as? Bool, false)
        XCTAssertEqual(body["think"] as? Bool, false)
        XCTAssertEqual(body["keep_alive"] as? String, "2m")
        let options = try XCTUnwrap(body["options"] as? [String: Any])
        XCTAssertEqual(options["num_predict"] as? Int, 64)
        XCTAssertEqual(options["temperature"] as? Double, 0.7)
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.map { $0["role"] as? String }, ["system", "user"])
        XCTAssertTrue((messages[0]["content"] as? String)?.contains("AX/OCR") == true)
        XCTAssertTrue((messages[0]["content"] as? String)?.contains("自由句式") == true)
        XCTAssertFalse((messages[0]["content"] as? String)?.contains("结尾格式") == true)
        XCTAssertTrue((messages[1]["content"] as? String)?.contains("骨架聚合") == true)
        XCTAssertEqual(messages[1]["images"] as? [String], [image.base64EncodedString()])
    }

    func testTextOnlyRequestOmitsImagesAndHonorsOverride() async throws {
        let client = DiaryOllamaClient(configuration: .init(model: "custom:1b"), transport: { request in
            if request.url!.lastPathComponent == "chat" {
                let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
                XCTAssertEqual(body["model"] as? String, "custom:1b")
                let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
                XCTAssertNil(messages.last?["images"])
            }
            return try self.fixture(request, model: "custom:1b")
        })
        _ = try await client.chat(skeleton: "合成骨架")
    }

    func testThinkingStrippingFailsClosedOnUnclosedTags() {
        XCTAssertEqual(DiaryOllamaClient.stripThinking("<think>a</think> <think>b</think>你好"), "你好")
        XCTAssertEqual(DiaryOllamaClient.stripThinking("<think>unfinished"), "")
        XCTAssertEqual(DiaryOllamaClient.stripThinking("你好</think>"), "")
    }

    func testTimeoutConnectionHTTPMalformedAndQualityFailuresPreserveReports() async {
        for mode in ["timeout", "connection", "http", "malformed", "long", "english", "invented", "insult", "empty"] {
            let client = DiaryOllamaClient(transport: { request in
                if mode == "connection" { throw URLError(.cannotConnectToHost) }
                guard request.url!.lastPathComponent == "chat" else { return try self.fixture(request) }
                switch mode {
                case "timeout": throw URLError(.timedOut)
                case "http": return try self.response(request, [:], status: 500)
                case "malformed": return try self.response(request, ["message": [:]])
                case "long": return try self.fixture(request, output: String(repeating: "好", count: 41))
                case "english": return try self.fixture(request, output: "You finished everything.")
                case "invented": return try self.fixture(request, output: "你已经完成了全部项目。")
                case "insult": return try self.fixture(request, output: "你真蠢。")
                default: return try self.fixture(request, output: "")
                }
            })
            let service = DiaryOllamaRoastService(defaults: defaults()) { client }
            let windows = [window(), window(600), window(1200), window(1800)]
            let roasts = await service.prepare(windows: windows)
            XCTAssertNotNil(service.disabledReason, mode)
            XCTAssertNotNil(service.lastFailureReason, mode)
            for entry in windows {
                XCTAssertEqual(roasts.roast(for: entry), DiaryPlaceholderRoastProvider().roast(for: entry), mode)
            }
            let report = DiaryReportBuilder().build(windows: windows, day: windows[0].start, roastProvider: roasts)
            XCTAssertEqual(report.timeline.map(\.skeleton), windows, mode)
            XCTAssertEqual(report.appDurations["cursor"], 2400, mode)
            XCTAssertEqual(report.timeline.count, 4, mode)
        }
    }

    func testRepeatedOutputFallsBackWithoutLosingFacts() async {
        let client = DiaryOllamaClient(transport: { try self.fixture($0) })
        let service = DiaryOllamaRoastService(defaults: defaults()) { client }
        let roasts = await service.prepare(windows: [window(), window(600)])
        XCTAssertEqual(roasts.roast(for: window()), good)
        XCTAssertEqual(roasts.roast(for: window(600)), DiaryPlaceholderRoastProvider().roast(for: window(600)))
        XCTAssertNotNil(service.lastFailureReason)
    }

    func testNearDuplicatesAcrossCallsAreScopedToReportDay() async {
        var calls = 0
        let client = DiaryOllamaClient(transport: { request in
            guard request.url!.lastPathComponent == "chat" else { return try self.fixture(request) }
            calls += 1
            return try self.fixture(request, output: calls == 2
                ? self.good.replacingOccurrences(of: "都", with: "也") : self.good)
        })
        let service = DiaryOllamaRoastService(defaults: defaults()) { client }
        let first = await service.prepare(windows: [window()])
        XCTAssertEqual(first.roast(for: window()), good)
        let repeated = await service.prepare(windows: [window(600)])
        XCTAssertEqual(repeated.roast(for: window(600)), DiaryPlaceholderRoastProvider().roast(for: window(600)))
        let tomorrow = await service.prepare(windows: [window(86400)])
        XCTAssertEqual(tomorrow.roast(for: window(86400)), good)
    }

    func testDailyBreakerPersistsAndResetsNextDay() async {
        let store = defaults()
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        var calls = 0
        let client = DiaryOllamaClient(transport: { _ in calls += 1; throw URLError(.cannotConnectToHost) })
        let service = DiaryOllamaRoastService(defaults: store, clock: { now }) { client }
        _ = await service.prepare(windows: (0..<5).map { window(Double($0) * 600) })
        XCTAssertEqual(calls, 3)
        let restarted = DiaryOllamaRoastService(defaults: store, clock: { now }) { client }
        _ = await restarted.prepare(windows: [window()])
        XCTAssertEqual(calls, 3)
        now = now.addingTimeInterval(86400)
        XCTAssertNil(restarted.disabledReason)
        _ = await restarted.prepare(windows: [window()])
        XCTAssertEqual(calls, 4)
    }

    func testSuccessResetsConsecutiveFailureCounter() async {
        var calls = 0
        let client = DiaryOllamaClient(transport: { request in
            guard request.url!.lastPathComponent == "chat" else { return try self.fixture(request) }
            calls += 1
            return try self.fixture(request, output: calls == 3 ? self.good : "invalid")
        })
        let service = DiaryOllamaRoastService(defaults: defaults()) { client }
        _ = await service.prepare(windows: (0..<5).map { window(Double($0) * 600) })
        XCTAssertEqual(calls, 5)
        XCTAssertNil(service.disabledReason)
    }

    func testGlobalSerializationAcrossDifferentClients() async throws {
        var active = 0
        var peak = 0
        let transport: DiaryOllamaClient.Transport = { request in
            active += 1
            peak = max(peak, active)
            defer { active -= 1 }
            try await Task.sleep(nanoseconds: 5_000_000)
            return try self.fixture(request)
        }
        let first = DiaryOllamaClient(transport: transport)
        let second = DiaryOllamaClient(transport: transport)
        async let firstResult = first.chat(skeleton: "first")
        async let secondResult = second.chat(skeleton: "second")
        _ = try await (firstResult, secondResult)
        XCTAssertEqual(peak, 1)
    }

    func testCancelledQueuedChatNeverReachesTransport() async throws {
        var secondCalls = 0
        let first = DiaryOllamaClient(transport: { request in
            try await Task.sleep(nanoseconds: 10_000_000)
            return try self.fixture(request)
        })
        let second = DiaryOllamaClient(transport: { request in
            secondCalls += 1
            return try self.fixture(request)
        })
        let firstTask = Task { try await first.chat(skeleton: "first") }
        await Task.yield()
        let secondTask = Task { try await second.chat(skeleton: "second") }
        secondTask.cancel()
        _ = try await firstTask.value
        do { _ = try await secondTask.value; XCTFail("Expected cancellation") }
        catch is CancellationError {} catch { XCTFail("Unexpected error \(error)") }
        XCTAssertEqual(secondCalls, 0)
    }

    func testEmptyDayNeverMakesHTTPRequests() async {
        let client = DiaryOllamaClient(transport: { _ in XCTFail("No network for empty day"); throw URLError(.cancelled) })
        let service = DiaryOllamaRoastService(defaults: defaults()) { client }
        let roasts = await service.prepare(windows: [])
        let report = DiaryReportBuilder().build(windows: [], day: Date(), roastProvider: roasts)
        XCTAssertTrue(report.timeline.isEmpty)
        XCTAssertNil(report.closingRoast)
    }

    func testServiceDeadlineCancelsSlowTransportAndFallsBack() async {
        var cancelled = false
        let client = DiaryOllamaClient(transport: { request in
            guard request.url!.lastPathComponent == "chat" else { return try self.fixture(request) }
            do { try await Task.sleep(nanoseconds: 5_000_000_000) }
            catch { cancelled = true; throw error }
            return try self.fixture(request)
        })
        let service = DiaryOllamaRoastService(defaults: defaults()) { client }
        service.callTimeout = 0.02
        let roasts = await service.prepare(windows: [window()])
        XCTAssertTrue(cancelled)
        XCTAssertNotNil(service.lastFailureReason)
        XCTAssertEqual(roasts.roast(for: window()), DiaryPlaceholderRoastProvider().roast(for: window()))
    }

    func testUnavailableModelOrOldVersionNeverPostsChat() async {
        for version in ["0.40.4", "0.40.5-rc1", "0.40.5"] {
            let client = DiaryOllamaClient(transport: { request in
                XCTAssertNotEqual(request.httpMethod, "POST")
                return try self.fixture(request, version: version, model: "wrong:latest")
            })
            let service = DiaryOllamaRoastService(defaults: defaults()) { client }
            let roasts = await service.prepare(windows: [window()])
            XCTAssertNotNil(service.lastFailureReason)
            XCTAssertEqual(roasts.roast(for: window()), DiaryPlaceholderRoastProvider().roast(for: window()))
        }
    }

    func testInjectedURLSessionUsesMockProtocol() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DiaryOllamaMockProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let client = DiaryOllamaClient(session: session)
        let output = try await client.chat(skeleton: "合成骨架")
        XCTAssertEqual(output, good)
    }
}

private final class DiaryOllamaMockProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let payload: [String: Any]
        switch request.url!.lastPathComponent {
        case "version": payload = ["version": "0.40.5"]
        case "tags": payload = ["models": [["name": DiaryOllamaConfiguration.defaultModel]]]
        default: payload = ["message": ["content": "在「日报布局」里来回挪方块，八只手都替你累。"]]
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: payload))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
