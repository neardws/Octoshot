import Darwin
import Foundation

public enum SubprocessRunner {
    public struct Output: Sendable {
        public let terminationStatus: Int32
        public let text: String
    }

    public enum Failure: Error, Equatable {
        case timedOut
    }

    public static func run(
        executable: URL,
        arguments: [String],
        currentDirectory: URL? = nil,
        environment: [String: String]? = nil,
        timeout: TimeInterval? = nil,
        outputLimit: Int = 64 * 1024
    ) async throws -> Output {
        try Task.checkCancellation()
        let state = RunState(outputLimit: max(0, outputLimit))
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                state.start(executable: executable, arguments: arguments,
                            currentDirectory: currentDirectory, environment: environment,
                            timeout: timeout, continuation: continuation)
            }
        } onCancel: {
            state.stop(with: CancellationError())
        }
    }
}

private final class RunState: @unchecked Sendable {
    private let lock = NSLock()
    private let process = Process()
    private let pipe = Pipe()
    private let outputLimit: Int
    private var output = Data()
    private var continuation: CheckedContinuation<SubprocessRunner.Output, Error>?
    private var stopError: Error?
    private var started = false
    private var exited = false
    private var reachedEOF = false
    private var finished = false
    private var timeoutWork: DispatchWorkItem?
    private var killWork: DispatchWorkItem?

    init(outputLimit: Int) {
        self.outputLimit = outputLimit
    }

    func start(executable: URL, arguments: [String], currentDirectory: URL?,
               environment: [String: String]?, timeout: TimeInterval?,
               continuation: CheckedContinuation<SubprocessRunner.Output, Error>) {
        lock.lock()
        defer { lock.unlock() }
        self.continuation = continuation
        if let stopError {
            closePipe()
            finish(.failure(stopError))
            return
        }
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.environment = environment
        process.standardOutput = pipe
        process.standardError = pipe
        process.terminationHandler = { [self] _ in
            lock.lock()
            exited = true
            completeIfReady()
            lock.unlock()
        }
        do {
            try process.run()
            started = true
            pipe.fileHandleForWriting.closeFile()
            DispatchQueue.global(qos: .utility).async { [self] in drain() }
            if let timeout {
                let work = DispatchWorkItem { [weak self] in
                    self?.stop(with: SubprocessRunner.Failure.timedOut)
                }
                timeoutWork = work
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + max(0, timeout), execute: work)
            }
        } catch {
            closePipe()
            finish(.failure(error))
        }
    }

    func stop(with error: Error) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished, stopError == nil else { return }
        stopError = error
        completeIfReady()
        guard started, !exited, process.isRunning else { return }
        process.terminate()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lock.lock()
            defer { self.lock.unlock() }
            if !self.finished, !self.exited, self.process.isRunning {
                kill(self.process.processIdentifier, SIGKILL)
            }
        }
        killWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func drain() {
        do {
            while let chunk = try pipe.fileHandleForReading.read(upToCount: 8192), !chunk.isEmpty {
                lock.lock()
                if outputLimit > 0 {
                    if chunk.count >= outputLimit {
                        output = Data(chunk.suffix(outputLimit))
                    } else {
                        let overflow = output.count + chunk.count - outputLimit
                        if overflow > 0 { output.removeFirst(overflow) }
                        output.append(chunk)
                    }
                }
                lock.unlock()
            }
        } catch {
            stop(with: error)
        }
        pipe.fileHandleForReading.closeFile()
        lock.lock()
        reachedEOF = true
        completeIfReady()
        lock.unlock()
    }

    private func completeIfReady() {
        guard exited else { return }
        if let stopError {
            finish(.failure(stopError))
        } else if reachedEOF {
            finish(.success(SubprocessRunner.Output(
                terminationStatus: process.terminationStatus,
                text: String(decoding: output, as: UTF8.self))))
        }
    }

    private func finish(_ result: Result<SubprocessRunner.Output, Error>) {
        guard !finished else { return }
        finished = true
        timeoutWork?.cancel()
        killWork?.cancel()
        process.terminationHandler = nil
        let completion = continuation
        continuation = nil
        completion?.resume(with: result)
    }

    private func closePipe() {
        pipe.fileHandleForReading.closeFile()
        pipe.fileHandleForWriting.closeFile()
    }
}
