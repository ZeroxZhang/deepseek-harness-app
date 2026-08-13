/**
 * DeepSeek Harness — plain-text logging to `~/Library/Logs/DeepSeekHarness/`.
 *
 * Two logs: `app.log` (this app's lifecycle) and `server.log` (stdout/stderr
 * of the spawned `dsh web` server). Handles are opened per write so nothing
 * dangles across re-spawns.
 */

import Foundation

enum AppLog {
    /** Directory holding both logs; created on first access. */
    static let dir: URL = {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")
        let dir = base.appendingPathComponent("Logs/DeepSeekHarness", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /** Lifecycle log of the app itself. */
    static let appLogURL = dir.appendingPathComponent("app.log")

    /** stdout/stderr of the spawned `dsh web` server. */
    static let serverLogURL = dir.appendingPathComponent("server.log")

    /** Open a seeked-to-end handle for the server log (appends across spawns). */
    static func serverLogHandle() -> FileHandle? {
        if !FileManager.default.fileExists(atPath: serverLogURL.path) {
            FileManager.default.createFile(atPath: serverLogURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: serverLogURL) else { return nil }
        handle.seekToEndOfFile()
        return handle
    }

    static func info(_ message: String) { write("INFO", message) }
    static func error(_ message: String) { write("ERROR", message) }

    private static func write(_ level: String, _ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(stamp) [\(level)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if !FileManager.default.fileExists(atPath: appLogURL.path) {
            FileManager.default.createFile(atPath: appLogURL.path, contents: nil)
        }
        if let handle = try? FileHandle(forWritingTo: appLogURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        }
    }
}
