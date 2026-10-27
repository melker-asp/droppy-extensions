//
//  SpeedtestRunner.swift
//  Speedtest
//
//  Process runner for Ookla Speedtest CLI with streaming JSON parsing.
//

import Combine
import Foundation

@MainActor
public final class SpeedtestRunner: ObservableObject {
    @Published public private(set) var state: SpeedtestState = .idle
    @Published public private(set) var cliPath: String?
    @Published public private(set) var isCLIAvailable: Bool = false

    private var currentProcess: Process?
    private var simulationTask: Task<Void, Never>?

    public init() {
        refreshCLIStatus()
    }

    /// Checks if Ookla's speedtest CLI binary is available on the Mac.
    @discardableResult
    public func refreshCLIStatus() -> Bool {
        let path = Self.locateBinary()
        self.cliPath = path
        let available = path != nil
        self.isCLIAvailable = available
        return available
    }

    /// Locates the speedtest binary across standard macOS locations.
    public nonisolated static func locateBinary() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "/opt/homebrew/bin/speedtest",
            "/usr/local/bin/speedtest",
            "\(home)/.local/bin/speedtest",
            "\(home)/bin/speedtest",
            "/usr/bin/speedtest",
            "/bin/speedtest"
        ]

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Fallback: login shell 'which'
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "which speedtest"]
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !output.isEmpty, FileManager.default.isExecutableFile(atPath: output) {
                    return output
                }
            }
        } catch {
            return nil
        }

        return nil
    }

    /// Stops any active running process or simulation without resetting state to idle.
    private func stopCurrentWork() {
        simulationTask?.cancel()
        simulationTask = nil

        if let proc = currentProcess, proc.isRunning {
            proc.terminate()
        }
        currentProcess = nil
    }

    /// Explicit user-initiated cancellation.
    public func cancel() {
        stopCurrentWork()
        if state.isRunning {
            state = .idle
        }
    }

    /// Starts a real test using the official Ookla CLI.
    public func startTest() {
        guard !state.isRunning else { return }
        stopCurrentWork()

        guard let path = cliPath ?? Self.locateBinary() else {
            self.cliPath = nil
            self.isCLIAvailable = false
            self.state = .cliMissing
            return
        }

        self.cliPath = path
        self.isCLIAvailable = true
        // Immediate visual feedback
        self.state = .preparing

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        // Accepts Ookla license & GDPR non-interactively and streams JSON
        process.arguments = [
            "--format=json",
            "--progress=yes",
            "--accept-license",
            "--accept-gdpr"
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        self.currentProcess = process

        let handle = stdoutPipe.fileHandleForReading
        var buffer = Data()

        handle.readabilityHandler = { [weak self] fileHandle in
            let availableData = fileHandle.availableData
            guard !availableData.isEmpty else { return }

            DispatchQueue.main.async {
                guard let self = self else { return }
                buffer.append(availableData)
                self.processBuffer(&buffer)
            }
        }

        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                guard let self = self else { return }
                handle.readabilityHandler = nil
                self.currentProcess = nil

                if proc.terminationStatus != 0 {
                    if case .completed = self.state {
                        // Already completed cleanly
                    } else if self.state.isRunning {
                        let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                        let errMsg = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                        self.state = .failed(errMsg?.isEmpty == false ? errMsg! : "Processen avbröts (kod \(proc.terminationStatus))")
                    }
                }
            }
        }

        do {
            try process.run()
        } catch {
            self.state = .failed("Kunde inte starta speedtest: \(error.localizedDescription)")
        }
    }

    /// Starts an instant, realistic simulated test (for testing animations/UI).
    public func startSimulatedTest() {
        guard !state.isRunning else { return }
        stopCurrentWork()

        // Step 0: Immediate visual feedback: Preparing
        state = .preparing

        simulationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }

            // Step 1: Ping & Jitter stage
            state = .ping(latency: 7.2, jitter: 0.9)
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }

            // Step 2: Download ramp up
            let downloadSteps: [(Double, Double)] = [
                (65.0, 0.15), (185.0, 0.35), (340.0, 0.60), (460.0, 0.85), (485.4, 1.0)
            ]
            for (speed, progress) in downloadSteps {
                state = .download(mbps: speed, progress: progress)
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
            }

            // Step 3: Upload ramp up
            let uploadSteps: [(Double, Double)] = [
                (45.0, 0.20), (125.0, 0.50), (210.0, 0.80), (242.8, 1.0)
            ]
            for (speed, progress) in uploadSteps {
                state = .upload(mbps: speed, progress: progress)
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
            }

            // Step 4: Completed result
            let result = SpeedtestResult(
                downloadMbps: 485.4,
                uploadMbps: 242.8,
                pingLatency: 7.2,
                pingJitter: 0.9,
                packetLoss: 0.0,
                isp: "Bredband2",
                serverName: "Stockholm Server",
                serverLocation: "Stockholm",
                resultURL: "https://www.speedtest.net",
                isSimulated: true
            )
            state = .completed(result)
        }
    }

    // MARK: - JSON Stream Processing

    private func processBuffer(_ buffer: inout Data) {
        let newline = UInt8(ascii: "\n")
        while let index = buffer.firstIndex(of: newline) {
            let lineData = buffer.subdata(in: 0..<index)
            buffer.removeSubrange(0...index)

            if !lineData.isEmpty {
                parseJSONLine(lineData)
            }
        }
    }

    private func parseJSONLine(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }

        switch type {
        case "testStart":
            self.state = .preparing

        case "ping":
            if let pingDict = json["ping"] as? [String: Any] {
                let latency = pingDict["latency"] as? Double ?? 0
                let jitter = pingDict["jitter"] as? Double ?? 0
                self.state = .ping(latency: latency, jitter: jitter)
            }

        case "download":
            if let dlDict = json["download"] as? [String: Any] {
                let bandwidth = dlDict["bandwidth"] as? Double ?? 0
                let progress = dlDict["progress"] as? Double ?? 0
                let mbps = (bandwidth * 8.0) / 1_000_000.0
                self.state = .download(mbps: mbps, progress: progress)
            }

        case "upload":
            if let ulDict = json["upload"] as? [String: Any] {
                let bandwidth = ulDict["bandwidth"] as? Double ?? 0
                let progress = ulDict["progress"] as? Double ?? 0
                let mbps = (bandwidth * 8.0) / 1_000_000.0
                self.state = .upload(mbps: mbps, progress: progress)
            }

        case "result":
            if let finalResult = try? JSONDecoder().decode(OoklaFinalResult.self, from: data) {
                let dlBandwidth = Double(finalResult.download?.bandwidth ?? 0)
                let ulBandwidth = Double(finalResult.upload?.bandwidth ?? 0)
                let dlMbps = (dlBandwidth * 8.0) / 1_000_000.0
                let ulMbps = (ulBandwidth * 8.0) / 1_000_000.0

                let result = SpeedtestResult(
                    downloadMbps: dlMbps,
                    uploadMbps: ulMbps,
                    pingLatency: finalResult.ping?.latency ?? 0,
                    pingJitter: finalResult.ping?.jitter ?? 0,
                    packetLoss: finalResult.packetLoss,
                    isp: finalResult.isp,
                    serverName: finalResult.server?.name,
                    serverLocation: finalResult.server?.location,
                    resultURL: finalResult.result?.url,
                    isSimulated: false
                )
                self.state = .completed(result)
            }

        case "log":
            if let level = json["level"] as? String, level == "error",
               let message = json["message"] as? String {
                self.state = .failed(message)
            }

        default:
            break
        }
    }
}
