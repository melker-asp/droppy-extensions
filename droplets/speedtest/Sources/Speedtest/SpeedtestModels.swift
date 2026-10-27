//
//  SpeedtestModels.swift
//  Speedtest
//
//  State and models for Speedtest by Ookla.
//

import Foundation

/// Current execution state of the Speedtest.
public enum SpeedtestState: Equatable, Sendable {
    case idle
    case checkingCLI
    case cliMissing
    case preparing
    case ping(latency: Double, jitter: Double)
    case download(mbps: Double, progress: Double)
    case upload(mbps: Double, progress: Double)
    case completed(SpeedtestResult)
    case failed(String)

    public var isRunning: Bool {
        switch self {
        case .preparing, .ping, .download, .upload:
            return true
        default:
            return false
        }
    }

    public var stageTitle: String {
        switch self {
        case .idle: return "Redo att testa"
        case .checkingCLI: return "Söker Speedtest CLI…"
        case .cliMissing: return "Speedtest CLI krävs"
        case .preparing: return "Ansluter till server…"
        case .ping: return "Mäter svarstid (Ping)…"
        case .download: return "Testar nedladdning…"
        case .upload: return "Testar uppladdning…"
        case .completed: return "Klart"
        case .failed(let msg): return "Fel: \(msg)"
        }
    }
}

/// Completed speed test result with full diagnostics.
public struct SpeedtestResult: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let downloadMbps: Double
    public let uploadMbps: Double
    public let pingLatency: Double
    public let pingJitter: Double
    public let packetLoss: Double?
    public let isp: String?
    public let serverName: String?
    public let serverLocation: String?
    public let resultURL: String?
    public let isSimulated: Bool

    public init(
        timestamp: Date = Date(),
        downloadMbps: Double,
        uploadMbps: Double,
        pingLatency: Double,
        pingJitter: Double,
        packetLoss: Double? = nil,
        isp: String? = nil,
        serverName: String? = nil,
        serverLocation: String? = nil,
        resultURL: String? = nil,
        isSimulated: Bool = false
    ) {
        self.timestamp = timestamp
        self.downloadMbps = downloadMbps
        self.uploadMbps = uploadMbps
        self.pingLatency = pingLatency
        self.pingJitter = pingJitter
        self.packetLoss = packetLoss
        self.isp = isp
        self.serverName = serverName
        self.serverLocation = serverLocation
        self.resultURL = resultURL
        self.isSimulated = isSimulated
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
}

// MARK: - Ookla CLI JSON Streaming Models

struct OoklaTestStart: Decodable {
    let timestamp: String?
    let server: OoklaServerInfo?
    let isp: String?
}

struct OoklaServerInfo: Decodable {
    let id: Int?
    let name: String?
    let location: String?
    let country: String?
    let host: String?
}

struct OoklaPingEvent: Decodable {
    let jitter: Double?
    let latency: Double?
}

struct OoklaTransferEvent: Decodable {
    let bandwidth: Int? // bytes per second
    let bytes: Int?
    let elapsed: Int?
    let progress: Double?
}

struct OoklaFinalResult: Decodable {
    struct PingSection: Decodable {
        let jitter: Double?
        let latency: Double?
    }
    struct SpeedSection: Decodable {
        let bandwidth: Int?
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
