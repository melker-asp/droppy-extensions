//
//  SpeedtestModels.swift
//  Speedtest
//
//  State and models for Speedtest by Ookla and Apple's networkQuality.
//

import Foundation

/// Which tool measured a result.
public enum SpeedtestProvider: String, Codable, Sendable {
    /// Ookla's official Speedtest CLI.
    case ookla
    /// Apple's built-in `networkQuality`, used when Ookla's CLI is missing.
    case apple

    public var displayName: String {
        switch self {
        case .ookla: return "Speedtest by Ookla"
        case .apple: return "Apple network quality"
        }
    }
}

/// Current execution state of the test.
public enum SpeedtestState: Equatable, Sendable {
    case idle
    /// Ookla's CLI is installed, but the user has not accepted Ookla's terms yet.
    case needsTerms
    /// Neither Ookla's CLI nor Apple's fallback can run.
    case cliMissing
    case preparing
    case ping(latency: Double, jitter: Double)
    case download(mbps: Double, progress: Double)
    case upload(mbps: Double, progress: Double)
    /// Apple's test, which reports nothing until it finishes.
    case measuring
    case completed(SpeedtestResult)
    case failed(String)

    public var isRunning: Bool {
        switch self {
        case .preparing, .ping, .download, .upload, .measuring:
            return true
        default:
            return false
        }
    }

    public var stageTitle: String {
        switch self {
        case .idle: return "Ready to test"
        case .needsTerms: return "Accept Ookla's terms to start"
        case .cliMissing: return "Speedtest CLI needed"
        case .preparing: return "Connecting to a server…"
        case .ping: return "Measuring ping…"
        case .download: return "Testing download…"
        case .upload: return "Testing upload…"
        case .measuring: return "Measuring with Apple's test…"
        case .completed: return "Done"
        case .failed(let message): return message
        }
    }
}

/// A finished test.
public struct SpeedtestResult: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let provider: SpeedtestProvider
    public let downloadMbps: Double
    public let uploadMbps: Double
    public let pingLatency: Double
    /// Ookla only.
    public let pingJitter: Double?
    /// Ookla only, and only when the server measured it.
    public let packetLoss: Double?
    /// Apple only: round trips per minute under load.
    public let responsivenessRPM: Double?
    public let isp: String?
    public let serverName: String?
    public let serverLocation: String?
    public let resultURL: String?

    public init(
        timestamp: Date = Date(),
        provider: SpeedtestProvider,
        downloadMbps: Double,
        uploadMbps: Double,
        pingLatency: Double,
        pingJitter: Double? = nil,
        packetLoss: Double? = nil,
        responsivenessRPM: Double? = nil,
        isp: String? = nil,
        serverName: String? = nil,
        serverLocation: String? = nil,
        resultURL: String? = nil
    ) {
        self.timestamp = timestamp
        self.provider = provider
        self.downloadMbps = downloadMbps
        self.uploadMbps = uploadMbps
        self.pingLatency = pingLatency
        self.pingJitter = pingJitter
        self.packetLoss = packetLoss
        self.responsivenessRPM = responsivenessRPM
        self.isp = isp
        self.serverName = serverName
        self.serverLocation = serverLocation
        self.resultURL = resultURL
    }

    public static func formattedSpeed(_ mbps: Double) -> String {
        if mbps >= 1000 {
            return String(format: "%.2f Gbps", mbps / 1000.0)
        } else if mbps >= 100 {
            return String(format: "%.1f", mbps)
        } else {
            return String(format: "%.2f", mbps)
        }
    }

    /// Plain-text summary for the pasteboard.
    public var summaryText: String {
        var lines = [
            "\(provider.displayName) result",
            "Download: \(Self.formattedSpeed(downloadMbps)) Mbps",
            "Upload: \(Self.formattedSpeed(uploadMbps)) Mbps",
        ]
        if let jitter = pingJitter {
            lines.append(String(format: "Ping: %.1f ms (jitter %.1f ms)", pingLatency, jitter))
        } else {
            lines.append(String(format: "Ping: %.1f ms", pingLatency))
        }
        if let rpm = responsivenessRPM {
            lines.append(String(format: "Responsiveness: %.0f RPM", rpm))
        }
        if let url = resultURL {
            lines.append(url)
        }
        return lines.joined(separator: "\n")
    }

    /// Demo data for the harness only; never shown inside Droppy.
    static let harnessDemo = SpeedtestResult(
        provider: .ookla,
        downloadMbps: 485.4,
        uploadMbps: 242.8,
        pingLatency: 7.2,
        pingJitter: 0.9,
        packetLoss: 0,
        isp: "Example ISP",
        serverName: "Example server",
        serverLocation: "Stockholm",
        resultURL: "https://www.speedtest.net"
    )
}

// MARK: - Ookla CLI JSON

struct OoklaServerInfo: Decodable {
    let id: Int?
    let name: String?
    let location: String?
    let country: String?
    let host: String?
}

struct OoklaFinalResult: Decodable {
    struct PingSection: Decodable {
        let jitter: Double?
        let latency: Double?
    }
    struct SpeedSection: Decodable {
        let bandwidth: Int? // bytes per second
        let bytes: Int?
        let elapsed: Int?
    }
    struct ResultSection: Decodable {
        let id: String?
        let url: String?
    }

    let timestamp: String?
    let ping: PingSection?
    let download: SpeedSection?
    let upload: SpeedSection?
    let packetLoss: Double?
    let isp: String?
    let server: OoklaServerInfo?
    let result: ResultSection?
}

// MARK: - networkQuality JSON (`networkQuality -c`)

struct NetworkQualityResult: Decodable {
    /// Bits per second.
    let dl_throughput: Double?
    /// Bits per second.
    let ul_throughput: Double?
    /// Milliseconds, idle.
    let base_rtt: Double?
    /// Round trips per minute; newer macOS also splits it per direction.
    let responsiveness: Double?
    let dl_responsiveness: Double?
    let error_code: Int?
    let error_domain: String?
}
