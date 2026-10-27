//
//  SpeedtestRunner.swift
//  Speedtest
//
//  Runs Ookla's Speedtest CLI (streaming JSON) or Apple's networkQuality
//  (one JSON object at the end) and turns their output into SpeedtestState.
//

import Combine
import Foundation

@MainActor
public final class SpeedtestRunner: ObservableObject {
    @Published public internal(set) var state: SpeedtestState = .idle
    @Published public private(set) var cliPath: String?
    @Published public private(set) var isCLIAvailable: Bool = false
    @Published public private(set) var isCheckingCLI: Bool = false
    /// The last download speed of the run in progress, kept for the upload stage.
    @Published public private(set) var runDownloadMbps: Double?

    /// Apple's tool ships with macOS 12 and later.
    public nonisolated static let appleToolPath = "/usr/bin/networkQuality"

    public var isAppleToolAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: Self.appleToolPath)
    }

    private var currentProcess: Process?
    private var readTask: Task<Void, Never>?
    private var demoTask: Task<Void, Never>?
    /// Bumped on every start and cancel, so output from a run the user
    /// stopped can never overwrite the state of the next one.
    private var runID = 0

    public init() {}

    // MARK: - Finding the CLI

    /// Looks for Ookla's `speedtest` binary off the main actor, because the
    /// login-shell fallback can take a while and this runs inside Droppy.
    public func refreshCLIStatus() {
        guard !isCheckingCLI else { return }
        isCheckingCLI = true
        Task.detached(priority: .utility) { [weak self] in
            let path = Self.locateBinary()
            await MainActor.run {
                guard let self else { return }
                self.cliPath = path
                self.isCLIAvailable = path != nil
                self.isCheckingCLI = false
                if path != nil, self.state == .cliMissing {
                    self.state = .idle
                }
            }
        }
    }

    /// Blocking; call it off the main actor.
    nonisolated static func locateBinary() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "/opt/homebrew/bin/speedtest",
            "/usr/local/bin/speedtest",
            "\(home)/.local/bin/speedtest",
            "\(home)/bin/speedtest",
        ]
        if let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return path
        }

        // Fallback: whatever the user's login shell finds on its PATH.
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "command -v speedtest"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty,
              FileManager.default.isExecutableFile(atPath: output) else {
            return nil
        }
        return output
    }

    // MARK: - Running

    /// Stops the running test, if any, and returns to idle.
    public func cancel() {
        stopCurrentWork()
        if state.isRunning {
            state = .idle
        }
    }

    /// Runs Ookla's CLI. Only call this once the user has accepted Ookla's
    /// licence and privacy policy in the droplet: the flags pass that answer on.
    func startOokla() {
        guard !state.isRunning, let path = cliPath else { return }
        launch(
            path: path,
            arguments: ["--format=jsonl", "--progress=yes", "--accept-license", "--accept-gdpr"],
            initialState: .preparing,
            onLine: { [weak self] line in self?.parseOoklaLine(line) },
            onExit: { [weak self] status, _, stderr in
                guard let self, self.state.isRunning else { return }
                // A clean exit always ends in a "result" line; anything else failed.
                self.state = .failed(Self.failureMessage(stderr: stderr, status: status))
            }
        )
    }

    /// Runs Apple's networkQuality, which prints one JSON object when it finishes.
    func startApple() {
        guard !state.isRunning, isAppleToolAvailable else { return }
        launch(
            path: Self.appleToolPath,
            arguments: ["-c"],
            initialState: .measuring,
            onLine: nil,
            onExit: { [weak self] status, stdout, stderr in
                guard let self, self.state.isRunning else { return }
                if let result = Self.parseAppleResult(stdout) {
                    self.state = .completed(result)
                } else {
                    self.state = .failed(Self.failureMessage(stderr: stderr, status: status))
                }
            }
        )
    }

    /// Plays a test with made-up numbers. Harness only: Droppy never shows it.
    func startHarnessDemo() {
        guard !state.isRunning else { return }
        stopCurrentWork()
        state = .preparing
        let id = runID

        var steps: [(SpeedtestState, UInt64)] = [(.ping(latency: 7.2, jitter: 0.9), 350_000_000)]
        steps += [65.0, 185.0, 340.0, 460.0, 485.4].enumerated().map { index, speed in
            (SpeedtestState.download(mbps: speed, progress: Double(index + 1) / 5), UInt64(300_000_000))
        }
        steps += [45.0, 125.0, 210.0, 242.8].enumerated().map { index, speed in
            (SpeedtestState.upload(mbps: speed, progress: Double(index + 1) / 4), UInt64(300_000_000))
        }
        steps.append((.completed(.harnessDemo), 300_000_000))
        let demoSteps = steps

        demoTask = Task { @MainActor [weak self] in
            for (next, delay) in demoSteps {
                try? await Task.sleep(nanoseconds: delay)
                guard let self, !Task.isCancelled, self.runID == id else { return }
                if case .download(let mbps, _) = next {
                    self.runDownloadMbps = mbps
                }
                self.state = next
            }
        }
    }

    private func stopCurrentWork() {
        runID += 1
        runDownloadMbps = nil
        demoTask?.cancel()
        demoTask = nil
        readTask?.cancel()
        readTask = nil
        if let process = currentProcess, process.isRunning {
            process.terminate()
        }
        currentProcess = nil
    }

    /// Starts `path`, feeds each stdout line to `onLine` on the main actor
    /// while it runs, and calls `onExit` with the whole output once it ends.
    private func launch(
        path: String,
        arguments: [String],
        initialState: SpeedtestState,
        onLine: ((String) -> Void)?,
        onExit: @escaping (_ status: Int32, _ stdout: String, _ stderr: String) -> Void
    ) {
        stopCurrentWork()
        let id = runID

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            state = .failed("Couldn't start the test: \(error.localizedDescription)")
            return
        }
        currentProcess = process
        state = initialState

        let stdout = stdoutPipe.fileHandleForReading
        let stderr = stderrPipe.fileHandleForReading
        readTask = Task.detached(priority: .userInitiated) { [weak self] in
            // Drain stderr alongside stdout so a chatty tool can't fill the pipe and stall.
            async let errorText: String = {
                String(data: stderr.readDataToEndOfFile(), encoding: .utf8) ?? ""
            }()

            var lines: [String] = []
            do {
                for try await line in stdout.bytes.lines {
                    lines.append(line)
                    if let onLine {
                        await MainActor.run {
                            guard let self, self.runID == id else { return }
                            onLine(line)
                        }
                    }
                }
            } catch {
                // The pipe closed early; whatever arrived is handled below.
            }

            let errorOutput = await errorText
            process.waitUntilExit()
            let status = process.terminationStatus
            let output = lines.joined(separator: "\n")
            await MainActor.run {
                guard let self, self.runID == id else { return }
                self.currentProcess = nil
                self.readTask = nil
                onExit(status, output, errorOutput)
            }
        }
    }

    private nonisolated static func failureMessage(stderr: String, status: Int32) -> String {
        let firstLine = stderr
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        if let firstLine {
            // Ookla's CLI writes its own errors as JSON on stderr.
            if let data = firstLine.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = (json["message"] ?? json["error"]) as? String {
                return message
            }
            return firstLine
        }
        return "The test stopped (exit code \(status))"
    }

    // MARK: - Ookla output

    private func parseOoklaLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }

        switch type {
        case "testStart":
            state = .preparing

        case "ping":
            if let ping = json["ping"] as? [String: Any] {
                state = .ping(
                    latency: ping["latency"] as? Double ?? 0,
                    jitter: ping["jitter"] as? Double ?? 0
                )
            }

        case "download":
            if let section = json["download"] as? [String: Any] {
                let mbps = Self.mbps(fromBytesPerSecond: section["bandwidth"] as? Double ?? 0)
                runDownloadMbps = mbps
                state = .download(mbps: mbps, progress: section["progress"] as? Double ?? 0)
            }

        case "upload":
            if let section = json["upload"] as? [String: Any] {
                state = .upload(
                    mbps: Self.mbps(fromBytesPerSecond: section["bandwidth"] as? Double ?? 0),
                    progress: section["progress"] as? Double ?? 0
                )
            }

        case "result":
            if let final = try? JSONDecoder().decode(OoklaFinalResult.self, from: data) {
                state = .completed(SpeedtestResult(
                    provider: .ookla,
                    downloadMbps: Self.mbps(fromBytesPerSecond: Double(final.download?.bandwidth ?? 0)),
                    uploadMbps: Self.mbps(fromBytesPerSecond: Double(final.upload?.bandwidth ?? 0)),
                    pingLatency: final.ping?.latency ?? 0,
                    pingJitter: final.ping?.jitter,
                    packetLoss: final.packetLoss,
                    isp: final.isp,
                    serverName: final.server?.name,
                    serverLocation: final.server?.location,
                    resultURL: final.result?.url
                ))
            }

        case "log":
            if json["level"] as? String == "error", let message = json["message"] as? String {
                state = .failed(message)
            }

        default:
            break
        }
    }

    private nonisolated static func mbps(fromBytesPerSecond bandwidth: Double) -> Double {
        bandwidth * 8 / 1_000_000
    }

    // MARK: - Apple output

    nonisolated static func parseAppleResult(_ output: String) -> SpeedtestResult? {
        // The JSON object is the whole output; skip anything printed before it.
        guard let start = output.firstIndex(of: "{"),
              let data = String(output[start...]).data(using: .utf8),
              let parsed = try? JSONDecoder().decode(NetworkQualityResult.self, from: data),
              parsed.error_code == nil,
              let download = parsed.dl_throughput,
              let upload = parsed.ul_throughput else {
            return nil
        }
        return SpeedtestResult(
            provider: .apple,
            downloadMbps: download / 1_000_000,
            uploadMbps: upload / 1_000_000,
            pingLatency: parsed.base_rtt ?? 0,
            responsivenessRPM: parsed.responsiveness ?? parsed.dl_responsiveness
        )
    }
}
