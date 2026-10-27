//
//  SpeedtestWidget.swift
//  Speedtest
//
//  The shelf widget and Thunderstorm launcher presentation,
//  crafted following Apple Human Interface Guidelines and DroppyKit design rules.
//

import AppKit
import DroppyKit
import SwiftUI

// MARK: - Descriptor

extension SpeedtestDroplet: ShelfWidgetProviding {
    public var widgetDescriptors: [ShelfWidgetDescriptor] {
        [
            ShelfWidgetDescriptor(
                id: Self.widgetID,
                title: "Speedtest",
                systemImage: "speedometer",
                layoutTraits: ShelfWidgetLayoutTraits(
                    preferredSoloWidth: 440,
                    preferredPairedWidth: 220,
                    contentHeight: .fixed(175)
                ),
                focusPolicy: .keyboardFocusable,
                searchKeywords: [
                    "speedtest", "ookla", "hastighet", "internet", "wifi",
                    "bredband", "ping", "download", "upload", "mbps", "nätverk"
                ]
            )
        ]
    }

    public func makeWidgetView(_ id: ShelfWidgetID, context: ShelfWidgetContext) -> AnyView {
        AnyView(SpeedtestWidget(droplet: self, context: context))
    }

    public func makeWidgetSettingsPopover(_ id: ShelfWidgetID) -> AnyView? { nil }
}

// MARK: - Main Widget View

struct SpeedtestWidget: View {
    @ObservedObject var droplet: SpeedtestDroplet
    let context: ShelfWidgetContext

    var body: some View {
        VStack(alignment: .leading, spacing: DroppySpacing.sm) {
            header
            if context.isCompact {
                pairedBody
            } else if isThunderstormWidth {
                thunderstormBody
            } else {
                soloBody
            }
            Spacer(minLength: 0)
        }
        .padding(context.contentInsets)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var isThunderstormWidth: Bool {
        context.availableSize.width >= 500
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DroppySpacing.xsm) {
            Image(systemName: "speedometer")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.teal)

            Text("Speedtest")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)

            if let isp = currentOrLastISP {
                Text("•")
                    .font(.system(size: 10))
                    .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                Text(isp)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: DroppySpacing.md)

            if droplet.runner.state.isRunning {
                Button {
                    droplet.cancelTest()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(DroppyCircleButtonStyle(size: 20, destructive: true, solidFill: nil, foregroundColorOverride: nil))
                .help("Avbryt mätning")
                .accessibilityLabel("Avbryt mätning")
            } else {
                Button {
                    if droplet.runner.isCLIAvailable {
                        droplet.startTest()
                    } else {
                        droplet.startSimulatedTest()
                    }
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(DroppyCircleButtonStyle(size: 20))
                .help("Starta hastighetstest")
                .accessibilityLabel("Starta hastighetstest")
            }
        }
    }

    // MARK: - Active Phase Status Capsule (Apple Native Feedback)

    private var activeStatusCapsule: some View {
        HStack(spacing: DroppySpacing.xs) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
                .frame(width: 14, height: 14)

            Text(droplet.runner.state.stageTitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                .lineLimit(1)

            Spacer(minLength: 0)

            if case .download(_, let progress) = droplet.runner.state {
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.teal)
            } else if case .upload(_, let progress) = droplet.runner.state {
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.blue)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(AdaptiveColors.notchSurfaceCardFill)
        .clipShape(Capsule(style: .continuous))
    }

    // MARK: - Paired Mode (Compact 220pt)

    private var pairedBody: some View {
        VStack(alignment: .leading, spacing: DroppySpacing.xs) {
            if droplet.runner.state.isRunning {
                liveRunningCompact
            } else if let result = droplet.lastResult {
                HStack(alignment: .firstTextBaseline) {
                    Text(SpeedtestResult.formattedSpeed(result.downloadMbps))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.teal)
                    Text("Mbps")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)

                    Spacer(minLength: 0)

                    Text("\(String(format: "%.0f", result.pingLatency)) ms")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                }

                HStack(spacing: DroppySpacing.md) {
                    Text("↑ \(SpeedtestResult.formattedSpeed(result.uploadMbps)) Mbps")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Redo att mäta")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                    Text("Klicka på Play för att starta")
                        .font(.system(size: 11))
                        .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                }
                .padding(.top, 2)
            }
        }
    }

    private var liveRunningCompact: some View {
        VStack(alignment: .leading, spacing: DroppySpacing.xs) {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                    .frame(width: 12, height: 12)
                Text(droplet.runner.state.stageTitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.teal)
                    .lineLimit(1)
            }

            switch droplet.runner.state {
            case .download(let mbps, _):
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("↓")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.teal)
                    Text(SpeedtestResult.formattedSpeed(mbps))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                    Text("Mbps")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                }
            case .upload(let mbps, _):
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("↑")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.blue)
                    Text(SpeedtestResult.formattedSpeed(mbps))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                    Text("Mbps")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                }
            case .ping(let latency, _):
                Text("\(String(format: "%.0f", latency)) ms ping")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
            default:
                HStack(spacing: 4) {
                    Text("Ansluter…")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                }
            }
        }
    }

    // MARK: - Solo Mode (Standard Shelf)

    private var soloBody: some View {
        VStack(alignment: .leading, spacing: DroppySpacing.sm) {
            // Live status feedback row when running
            if droplet.runner.state.isRunning {
                activeStatusCapsule
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if !droplet.runner.isCLIAvailable && droplet.lastResult == nil {
                cliMissingNotice(compact: true)
            }

            // Hero Metric Columns (Download & Upload)
            HStack(alignment: .top, spacing: DroppySpacing.lg) {
                // Download Column
                metricColumn(
                    title: "NEDLADDNING",
                    symbol: "arrow.down",
                    value: currentDownloadDisplay,
                    tint: Color.teal,
                    isActivePhase: isDownloadActive,
                    progress: currentDownloadProgress
                )

                // Upload Column
                metricColumn(
                    title: "UPPLADDNING",
                    symbol: "arrow.up",
                    value: currentUploadDisplay,
                    tint: Color.blue,
                    isActivePhase: isUploadActive,
                    progress: currentUploadProgress
                )
            }

            // Diagnostics Strip
            diagnosticsStrip
        }
        .animation(.easeInOut(duration: 0.25), value: droplet.runner.state.isRunning)
    }

    private func metricColumn(
        title: String,
        symbol: String,
        value: String,
        tint: Color,
        isActivePhase: Bool,
        progress: Double?
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isActivePhase ? tint : AdaptiveColors.notchSurfaceSecondaryText)
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isActivePhase ? tint : AdaptiveColors.notchSurfacePrimaryText)
                Text("Mbps")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
            }

            // Smooth Apple progress track
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 3)

                    if let prog = progress, prog > 0 {
                        Capsule(style: .continuous)
                            .fill(tint)
                            .frame(width: max(geo.size.width * CGFloat(prog), 4), height: 3)
                            .animation(.easeOut(duration: 0.2), value: prog)
                    }
                }
            }
            .frame(height: 3)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Thunderstorm Mode (Wide Launcher Canvas)

    private var thunderstormBody: some View {
        VStack(alignment: .leading, spacing: DroppySpacing.md) {
            if droplet.runner.state.isRunning {
                activeStatusCapsule
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if !droplet.runner.isCLIAvailable && droplet.lastResult == nil {
                cliMissingNotice(compact: false)
            }

            HStack(alignment: .center, spacing: DroppySpacing.xl) {
                // Left: Speeds
                HStack(spacing: DroppySpacing.xl) {
                    metricColumn(
                        title: "NEDLADDNING",
                        symbol: "arrow.down",
                        value: currentDownloadDisplay,
                        tint: Color.teal,
                        isActivePhase: isDownloadActive,
                        progress: currentDownloadProgress
                    )
                    .frame(minWidth: 150)

                    metricColumn(
                        title: "UPPLADDNING",
                        symbol: "arrow.up",
                        value: currentUploadDisplay,
                        tint: Color.blue,
                        isActivePhase: isUploadActive,
                        progress: currentUploadProgress
                    )
                    .frame(minWidth: 150)
                }

                Spacer(minLength: DroppySpacing.md)

                // Right: Action Buttons
                VStack(alignment: .trailing, spacing: DroppySpacing.xs) {
                    if let res = droplet.lastResult, res.resultURL != nil {
                        Button {
                            droplet.openResultInBrowser()
                        } label: {
                            Label("Öppna på speedtest.net", systemImage: "arrow.up.right")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Button {
                        droplet.copyLastResult()
                    } label: {
                        Label("Kopiera resultat", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(droplet.lastResult == nil)
                }
            }

            diagnosticsStrip
        }
        .animation(.easeInOut(duration: 0.25), value: droplet.runner.state.isRunning)
    }

    // MARK: - Diagnostics Strip

    private var diagnosticsStrip: some View {
        HStack(spacing: DroppySpacing.md) {
            statItem(label: "Ping", value: pingDisplay)
            divider
            statItem(label: "Jitter", value: jitterDisplay)
            divider
            statItem(label: "Förlust", value: packetLossDisplay)

            if let server = currentOrLastServer {
                divider
                statItem(label: "Server", value: server)
            }

            Spacer(minLength: 0)

            if let result = droplet.lastResult, !droplet.runner.state.isRunning {
                Text(result.timestamp, style: .time)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
            }
        }
        .padding(.top, DroppySpacing.xs)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .frame(width: 1, height: 10)
    }

    private func statItem(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label + ":")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
        }
    }

    // MARK: - Missing CLI Notice

    private func cliMissingNotice(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: DroppySpacing.xs) {
            HStack(spacing: DroppySpacing.xsm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.orange)
                Text("Ookla CLI krävs för skarpa mätningar")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
            }

            Text("Installera via Terminalen med Homebrew:")
                .font(.system(size: 11))
                .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)

            HStack(spacing: DroppySpacing.sm) {
                Text("brew install speedtest")
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AdaptiveColors.notchSurfaceCardFill)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Button("Kopiera") {
                    droplet.copyBrewInstallCommand()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Provkör simulering") {
                    droplet.startSimulatedTest()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - State Helpers

    private var isDownloadActive: Bool {
        if case .download = droplet.runner.state { return true }
        return false
    }

    private var isUploadActive: Bool {
        if case .upload = droplet.runner.state { return true }
        return false
    }

    private var currentDownloadProgress: Double? {
        switch droplet.runner.state {
        case .download(_, let progress): return progress
        case .upload, .completed: return 1.0
        default: return nil
        }
    }

    private var currentUploadProgress: Double? {
        switch droplet.runner.state {
        case .upload(_, let progress): return progress
        case .completed: return 1.0
        default: return nil
        }
    }

    private var currentDownloadDisplay: String {
        switch droplet.runner.state {
        case .preparing:
            return "…"
        case .ping:
            return "…"
        case .download(let mbps, _):
            return SpeedtestResult.formattedSpeed(mbps)
        case .upload, .completed:
            if let last = droplet.lastResult {
                return SpeedtestResult.formattedSpeed(last.downloadMbps)
            }
            return "—"
        default:
            if let last = droplet.lastResult {
                return SpeedtestResult.formattedSpeed(last.downloadMbps)
            }
            return "—"
        }
    }

    private var currentUploadDisplay: String {
        switch droplet.runner.state {
        case .preparing, .ping, .download:
            return "…"
        case .upload(let mbps, _):
            return SpeedtestResult.formattedSpeed(mbps)
        case .completed(let result):
            return SpeedtestResult.formattedSpeed(result.uploadMbps)
        default:
            if let last = droplet.lastResult {
                return SpeedtestResult.formattedSpeed(last.uploadMbps)
            }
            return "—"
        }
    }

    private var pingDisplay: String {
        switch droplet.runner.state {
        case .ping(let latency, _):
            return String(format: "%.0f ms", latency)
        case .completed(let res):
            return String(format: "%.0f ms", res.pingLatency)
        default:
            if let last = droplet.lastResult {
                return String(format: "%.0f ms", last.pingLatency)
            }
            return "—"
        }
    }

    private var jitterDisplay: String {
        switch droplet.runner.state {
        case .ping(_, let jitter):
            return String(format: "%.1f ms", jitter)
        case .completed(let res):
            return String(format: "%.1f ms", res.pingJitter)
        default:
            if let last = droplet.lastResult {
                return String(format: "%.1f ms", last.pingJitter)
            }
            return "—"
        }
    }

    private var packetLossDisplay: String {
        if let loss = droplet.lastResult?.packetLoss {
            return String(format: "%.1f%%", loss)
        }
        return "0%"
    }

    private var currentOrLastISP: String? {
        droplet.lastResult?.isp
    }

    private var currentOrLastServer: String? {
        droplet.lastResult?.serverName
    }
}
