import Darwin
import Foundation
import XCTest
import OctoshotCore

final class SubprocessRunnerTests: XCTestCase {
    private let shell = URL(fileURLWithPath: "/bin/sh")

    private func bounded(_ operation: @escaping () async throws -> Void) async {
        let completed = expectation(description: "Subprocess completes without hanging")
        let task = Task {
            defer { completed.fulfill() }
            do { try await operation() }
            catch { XCTFail("Unexpected error: \(error)") }
        }
        await fulfillment(of: [completed], timeout: 10)
        task.cancel()
    }

    private func largeOutput(status: Int32) async throws {
        let result = try await SubprocessRunner.run(
            executable: shell,
            arguments: ["-c", """
                /usr/bin/head -c 1200000 /dev/zero | /usr/bin/tr '\\000' x
                /usr/bin/head -c 1200000 /dev/zero | /usr/bin/tr '\\000' y >&2
                printf 'STDOUT-END\\n'
                printf 'STDERR-END\\n' >&2
                exit \(status)
                """], timeout: 5)
        XCTAssertEqual(result.terminationStatus, status)
        XCTAssertEqual(result.text.utf8.count, 64 * 1024)
        XCTAssertTrue(result.text.hasSuffix("STDOUT-END\nSTDERR-END\n"))
    }

    func testLargeMergedOutputExitsSuccessfully() async {
        await bounded { try await self.largeOutput(status: 0) }
    }

    func testLargeMergedOutputPreservesNonzeroStatus() async {
        await bounded { try await self.largeOutput(status: 3) }
    }

    private func stoppedProcess(ignoreTermination: Bool, timeout: TimeInterval?) async throws {
        let pidFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: pidFile) }
        let script = (ignoreTermination ? "trap '' TERM; " : "") + "echo $$ > \"$1\"; exec /bin/sleep 30"
        let task = Task {
            try await SubprocessRunner.run(executable: shell,
                                          arguments: ["-c", script, "test", pidFile.path],
                                          timeout: timeout ?? 5)
        }
        defer { task.cancel() }
        var processID: Int32?
        let readyDeadline = Date().addingTimeInterval(2)
        while processID == nil, Date() < readyDeadline {
            if let text = try? String(contentsOf: pidFile, encoding: .utf8) {
                processID = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            if processID == nil { try await Task.sleep(nanoseconds: 10_000_000) }
        }
        let pid = try XCTUnwrap(processID)
        XCTAssertEqual(kill(pid, 0), 0)
        let stopStart = Date()
        if timeout == nil { task.cancel() }
        do {
            _ = try await task.value
            XCTFail("Expected cancellation or timeout")
        } catch {
            if timeout == nil {
                XCTAssertTrue(error is CancellationError, "\(error)")
            } else {
                XCTAssertEqual(error as? SubprocessRunner.Failure, .timedOut)
            }
        }
        XCTAssertLessThan(Date().timeIntervalSince(stopStart), 3)
        XCTAssertEqual(kill(pid, 0), -1)
        XCTAssertEqual(errno, ESRCH)
    }

    func testCancellationStopsProcess() async {
        await bounded { try await self.stoppedProcess(ignoreTermination: false, timeout: nil) }
    }

    func testCancellationKillsProcessIgnoringTermination() async {
        await bounded { try await self.stoppedProcess(ignoreTermination: true, timeout: nil) }
    }

    func testTimeoutStopsProcess() async {
        await bounded { try await self.stoppedProcess(ignoreTermination: false, timeout: 0.5) }
    }

    func testAlreadyCancelledTaskDoesNotLaunch() async {
        await bounded {
            let marker = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: marker) }
            let task = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return try await SubprocessRunner.run(
                    executable: self.shell, arguments: ["-c", "echo launched > \"$1\"", "test", marker.path])
            }
            do {
                _ = try await task.value
                XCTFail("Expected cancellation")
            } catch {
                XCTAssertTrue(error is CancellationError)
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        }
    }

    func testMissingExecutablePreservesLaunchError() async {
        await bounded {
            let missing = URL(fileURLWithPath: "/nonexistent-octoshot-\(UUID().uuidString)")
            let process = Process()
            process.executableURL = missing
            var original: NSError?
            do { try process.run() } catch { original = error as NSError }
            do {
                _ = try await SubprocessRunner.run(executable: missing, arguments: [])
                XCTFail("Expected launch failure")
            } catch {
                XCTAssertEqual((error as NSError).domain, original?.domain)
                XCTAssertEqual((error as NSError).code, original?.code)
            }
        }
    }

    func testTruncatedUTF8UsesLossyDecoding() async {
        await bounded {
            let result = try await SubprocessRunner.run(
                executable: self.shell, arguments: ["-c", "printf '\\342\\202\\254END'"],
                timeout: 5, outputLimit: 4)
            XCTAssertEqual(result.text, "\u{FFFD}END")
        }
    }

    func testWaitsForPipeEOFAfterProcessExit() async {
        await bounded {
            let result = try await SubprocessRunner.run(
                executable: self.shell,
                arguments: ["-c", "(sleep 0.2; printf 'LAST-BYTES' >&2) & printf 'FIRST-'; exit 0"],
                timeout: 5)
            XCTAssertEqual(result.text, "FIRST-LAST-BYTES")
            XCTAssertEqual(result.terminationStatus, 0)
        }
    }
}
