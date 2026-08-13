/**
 * DeepSeek Harness — server lifecycle.
 *
 * Attaches to a `dsh web` server already serving the harness on the configured
 * port, or spawns one from the harness checkout (`node --import tsx/esm
 * apps/cli/src/bin.ts web --port <port>`). A spawned server is owned by this
 * app and is terminated on quit; an attached server is left untouched.
 */

import Foundation
import Darwin

final class ServerController {
    /** Startup failure: a user-facing message. */
    struct StartFailure: Error {
        let message: String
    }

    /** Outcome handed to the UI once the server URL is usable (or not). */
    struct StartOutcome {
        let url: URL
        /** true when this app spawned the server and owns its lifetime. */
        let spawned: Bool
    }

    private let checkInterval: TimeInterval = 0.5
    private let spawnTimeout: TimeInterval = 90

    private var child: Process?
    private var spawnedByUs = false
    private var stopped = false
    private var lastFailure: String?

    /** http://127.0.0.1:<port>/ */
    var baseURL: URL { URL(string: "http://127.0.0.1:\(AppConfig.port)/")! }

    /**
     * Ensure a usable server exists, then report the URL. Runs on a background
     * queue; the completion is delivered on the main queue.
     */
    func start(_ completion: @escaping (Result<StartOutcome, StartFailure>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            switch self.probeServer() {
            case .harness:
                AppLog.info("server: already serving the harness on \(self.baseURL.absoluteString) — attaching")
                DispatchQueue.main.async {
                    completion(.success(StartOutcome(url: self.baseURL, spawned: false)))
                }
                return
            case .occupied:
                let detail = self.lastFailure ?? "port \(AppConfig.port) is taken by another program"
                AppLog.error("server: \(detail)")
                DispatchQueue.main.async { completion(.failure(StartFailure(message: detail))) }
                return
            case .down:
                break
            }

            AppLog.info("server: nothing on port \(AppConfig.port) — spawning `dsh web`")
            if !self.spawnChild() {
                let detail = self.lastFailure ?? "failed to launch node"
                DispatchQueue.main.async { completion(.failure(StartFailure(message: detail))) }
                return
            }

            let deadline = Date().addingTimeInterval(self.spawnTimeout)
            while Date() < deadline && !self.stopped {
                Thread.sleep(forTimeInterval: self.checkInterval)
                if case .harness = self.probeServer() {
                    AppLog.info("server: ready (spawned by this app)")
                    DispatchQueue.main.async {
                        completion(.success(StartOutcome(url: self.baseURL, spawned: true)))
                    }
                    return
                }
                if self.child == nil {
                    // The child exited before serving: surface why instead of polling to the timeout.
                    break
                }
            }
            let detail = self.lastFailure
                ?? (self.child == nil
                    ? "the server process exited during startup"
                    : "the server did not become ready within \(Int(self.spawnTimeout))s")
            AppLog.error("server: startup failed — \(detail)")
            self.killChild()
            DispatchQueue.main.async { completion(.failure(StartFailure(message: detail))) }
        }
    }

    /** Terminate the child we spawned, waiting briefly for a clean shutdown. */
    func stop() {
        stopped = true
        guard spawnedByUs else { return }
        guard let child = child else { return }
        AppLog.info("server: stopping spawned child (pid \(child.processIdentifier))")
        if child.isRunning {
            child.terminate() // SIGTERM: dsh's shutdown controller disposes the tree
            let deadline = Date().addingTimeInterval(6)
            while child.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.2)
            }
            if child.isRunning {
                AppLog.error("server: child ignored SIGTERM — sending SIGKILL")
                kill(child.processIdentifier, SIGKILL)
            }
        }
        self.child = nil
    }

    // MARK: internals

    private enum Probe { case harness, occupied, down }

    private func probeServer() -> Probe {
        var request = URLRequest(url: baseURL)
        request.timeoutInterval = 3
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let semaphore = DispatchSemaphore(value: 0)
        var verdict = Probe.down
        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            guard let http = response as? HTTPURLResponse, let data = data else {
                semaphore.signal()
                return
            }
            if http.statusCode == 200 {
                let head = String(data: Data(data.prefix(8192)), encoding: .utf8) ?? ""
                verdict = head.contains("__DSH_BOOT__") ? .harness : .occupied
                if verdict == .occupied {
                    self.lastFailure = "port \(AppConfig.port) is already in use by another program"
                }
            } else {
                verdict = .occupied
                self.lastFailure = "port \(AppConfig.port) answered with HTTP \(http.statusCode), not the DeepSeek Harness UI"
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 3.5)
        task.cancel()
        return verdict
    }

    /** @returns true when the node process was started. */
    private func spawnChild() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: AppConfig.resolvedNodePath)
        process.arguments = [
            "--import", "tsx/esm",
            AppConfig.resolvedHarnessRoot + "/apps/cli/src/bin.ts",
            "web", "--port", AppConfig.port,
        ]
        process.currentDirectoryURL = URL(fileURLWithPath: AppConfig.resolvedHarnessRoot)

        var env = ProcessInfo.processInfo.environment
        // Finder-launched apps inherit a minimal PATH; make node's bin dir and
        // the usual prefixes available to the server and anything it spawns.
        let nodeDir = (AppConfig.resolvedNodePath as NSString).deletingLastPathComponent
        let inherited = env["PATH"] ?? ""
        env["PATH"] = [nodeDir, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
            .filter { !$0.isEmpty }
            .joined(separator: ":") + (inherited.isEmpty ? "" : ":\(inherited)")
        env["NO_COLOR"] = "1"
        process.environment = env

        process.standardOutput = AppLog.serverLogHandle() ?? FileHandle.nullDevice
        process.standardError = process.standardOutput

        process.terminationHandler = { [weak self] finished in
            let code = finished.terminationStatus
            let reason = finished.terminationReason
            AppLog.info("server: child exited (status \(code), reason \(reason.rawValue))")
            self?.child = nil
        }

        do {
            try process.run()
        } catch {
            lastFailure = "could not launch node (\(error.localizedDescription))"
            AppLog.error("server: \(lastFailure!)")
            return false
        }
        child = process
        spawnedByUs = true
        return true
    }

    private func killChild() {
        guard let child = child else { return }
        if child.isRunning {
            child.terminate()
            let deadline = Date().addingTimeInterval(4)
            while child.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
        }
        self.child = nil
    }
}
