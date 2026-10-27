import CryptoKit
import Foundation
import SQLite3

public enum DiaryStoreError: Error {
    case sqlite(String)
    case invalidPayload
    case unsafeDirectory
}

public final class DiaryStore {
    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Octoshot/Diary", isDirectory: true)
    }

    public let directory: URL
    public let databaseURL: URL
    private var database: OpaquePointer?
    private let keyProvider: DiaryKeyProvider
    private let clock: () -> Date
    private let lock = NSLock()

    public init(directory: URL = DiaryStore.defaultDirectory,
                keyProvider: DiaryKeyProvider = KeychainDiaryKeyProvider(),
                fileManager: FileManager = .default, clock: @escaping () -> Date = Date.init) throws {
        self.directory = directory
        self.databaseURL = directory.appendingPathComponent("diary.sqlite")
        self.keyProvider = keyProvider
        self.clock = clock
        try Self.prepareDirectory(directory, fileManager: fileManager)
        var excludedDirectory = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try excludedDirectory.setResourceValues(values)
        let marker = directory.appendingPathComponent(".metadata_never_index")
        if !fileManager.fileExists(atPath: marker.path) {
            try Data().write(to: marker, options: .withoutOverwriting)
        }
        if (try? databaseURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw DiaryStoreError.unsafeDirectory
        }
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let error = message()
            sqlite3_close(database)
            database = nil
            throw DiaryStoreError.sqlite(error)
        }
        do {
            sqlite3_busy_timeout(database, 5_000)
            try execute("PRAGMA secure_delete = ON")
            try execute("CREATE TABLE IF NOT EXISTS entries (id INTEGER PRIMARY KEY, window_start INTEGER NOT NULL, window_end INTEGER NOT NULL, created_at INTEGER NOT NULL, payload BLOB NOT NULL)")
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: databaseURL.path)
        } catch {
            sqlite3_close(database)
            database = nil
            throw error
        }
    }

    deinit { sqlite3_close(database) }

    @discardableResult
    public func insert(_ skeleton: DiaryWindowSkeleton) throws -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        let start = Int64(skeleton.start.timeIntervalSince1970.rounded(.down))
        let end = Int64(skeleton.end.timeIntervalSince1970.rounded(.down))
        let created = Int64(clock().timeIntervalSince1970.rounded(.down))
        let key = try keyProvider.key()
        guard key.bitCount == 256 else { throw DiaryKeyError.invalidKey }
        let encrypted = try AES.GCM.seal(JSONEncoder().encode(skeleton), using: key,
                                         authenticating: metadata(start, end, created))
        guard let payload = encrypted.combined else { throw DiaryStoreError.invalidPayload }
        let statement = try prepare("INSERT INTO entries(window_start, window_end, created_at, payload) VALUES (?, ?, ?, ?)")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, start)
        sqlite3_bind_int64(statement, 2, end)
        sqlite3_bind_int64(statement, 3, created)
        let status = payload.withUnsafeBytes {
            sqlite3_bind_blob(statement, 4, $0.baseAddress, Int32($0.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        guard status == SQLITE_OK, sqlite3_step(statement) == SQLITE_DONE else { throw DiaryStoreError.sqlite(message()) }
        return sqlite3_last_insert_rowid(database)
    }

    public func fetch(range: Range<Date>) throws -> [DiaryWindowSkeleton] {
        lock.lock()
        defer { lock.unlock() }
        let statement = try prepare("SELECT window_start, window_end, created_at, payload FROM entries WHERE window_start < ? AND window_end > ? ORDER BY window_start, id")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, range.upperBound.timeIntervalSince1970)
        sqlite3_bind_double(statement, 2, range.lowerBound.timeIntervalSince1970)
        var results: [DiaryWindowSkeleton] = []
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            guard let bytes = sqlite3_column_blob(statement, 3) else { throw DiaryStoreError.invalidPayload }
            let payload = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 3)))
            let aad = metadata(sqlite3_column_int64(statement, 0), sqlite3_column_int64(statement, 1), sqlite3_column_int64(statement, 2))
            let plaintext = try AES.GCM.open(AES.GCM.SealedBox(combined: payload), using: keyProvider.key(), authenticating: aad)
            results.append(try JSONDecoder().decode(DiaryWindowSkeleton.self, from: plaintext))
            status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE else { throw DiaryStoreError.sqlite(message()) }
        return results
    }

    public func deleteAll() throws {
        lock.lock()
        defer { lock.unlock() }
        try execute("DELETE FROM entries")
    }

    public func purge(olderThan cutoff: Date) throws {
        lock.lock()
        defer { lock.unlock() }
        let statement = try prepare("DELETE FROM entries WHERE window_end < ?")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, cutoff.timeIntervalSince1970)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw DiaryStoreError.sqlite(message()) }
    }

    static func prepareDirectory(_ directory: URL, fileManager: FileManager) throws {
        if (try? directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw DiaryStoreError.unsafeDirectory
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    private func metadata(_ start: Int64, _ end: Int64, _ created: Int64) -> Data {
        Data("diary-v1:\(start):\(end):\(created)".utf8)
    }

    private func message() -> String { String(cString: sqlite3_errmsg(database)) }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw DiaryStoreError.sqlite(message())
        }
        return statement
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw DiaryStoreError.sqlite(message()) }
    }
}
