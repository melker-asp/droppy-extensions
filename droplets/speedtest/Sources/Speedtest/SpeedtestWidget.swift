//
//  SpeedtestWidget.swift
//  Speedtest
//
//  The shelf widget, also drawn wide when Thunderstorm shows it,
//  following Apple Human Interface Guidelines and DroppyKit design rules.
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
                    "speedtest", "ookla", "speed", "internet", "wifi",
                    "broadband", "ping", "download", "upload", "mbps", "network",
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

    private var state: SpeedtestState { droplet.runner.state }

    var body: some View {
        VStack(alignment: .leading, spacing: DroppySpacing.sm) {
            header
            if context.isCompact {
                pairedBody
            } else {
                wideOrSoloBody(isWide: context.availableSize.width >= 500)
            }
            Spacer(minLength: 0)
        }
        .padding(context.contentInsets)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

            if let source = sourceLabel {
                Text("•")
                    .font(.system(size: 10))
                    .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                Text(source)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: DroppySpacing.md)

            if state.isRunning {
                Button {
                    droplet.cancelTest()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(DroppyCircleButtonStyle(size: 20, destructive: true, solidFill: nil, foregroundColorOverride: nil))
                .help("Stop the test")
                .accessibilityLabel("Stop the test")
            } else {
                Button {
                    droplet.startTest()
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(DroppyCircleButtonStyle(size: 20))
                .help("Start a speed test")
                .accessibilityLabel("Start a speed test")
            }
        }
    }

    /// The ISP for an Ookla result, or which tool measured an Apple one.
    private var sourceLabel: String? {
        guard let result = droplet.lastResult else { return nil }
        switch result.provider {
        case .ookla: return result.isp
        case .apple: return result.provider.displayName
        }
    }

    // MARK: - Notices

    /// What stands between the user and a test, if anything.
    @ViewBuilder
    private func notice(compact: Bool) -> some View {
        switch state {
        case .needsTerms:
            noticeBlock(
                symbol: "doc.text",
                tint: .teal,
                title: "Accept Ookla's terms first",
                detail: compact ? nil : "Ookla's CLI runs only once you accept its license and privacy policy."
            ) {
                Button("Accept and run") { droplet.acceptTermsAndStart() }
                    .buttonStyle(DroppyAccentButtonStyle(size: .small))
                Button("Review") { droplet.openSettings() }
                    .buttonStyle(DroppyQuietButtonStyle(size: .small))
            }

        case .cliMissing:
            noticeBlock(
                symbol: "exclamationmark.triangle.fill",
                tint: .orange,
                title: "Install Ookla's Speedtest CLI",
                detail: compact ? nil : "Copy the Homebrew command and paste it in Terminal."
            ) {
                Button("Copy command") { droplet.copyInstallCommand() }
                    .buttonStyle(DroppyAccentButtonStyle(size: .small))
                Button("Settings") { droplet.openSettings() }
                    .buttonStyle(DroppyQuietButtonStyle(size: .small))
            }

        default:
            if !compact, droplet.lastResult == nil, !droplet.runner.isCLIAvailable,
               !droplet.runner.isCheckingCLI, !droplet.isHarness {
                noticeBlock(
                    symbol: "info.circle",
                    tint: AdaptiveColors.notchSurfaceSecondaryText,
                    title: "Tests use Apple's network test",
                    detail: "Install Ookla's CLI for Speedtest results."
                ) {
                    Button("Set up") { droplet.openSettings() }
                        .buttonStyle(DroppyQuietButtonStyle(size: .small))
                }
            }
        }
    }

    private func noticeBlock<Buttons: View>(
        symbol: String,
        tint: Color,
        title: String,
        detail: String?,
        @ViewBuilder buttons: () -> Buttons
    ) -> some View {
        VStack(alignment: .leading, spacing: DroppySpacing.xs) {
            HStack(spacing: DroppySpacing.xsm) {
                Image(systemName: symbol)
                    .font(.system(size: 12))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                    .lineLimit(1)
            }
            if let detail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                    .lineLimit(2)
            }
            HStack(spacing: DroppySpacing.sm) {
                buttons()
            }
        }
        .transition(DroppyTransition.element)
    }

    private var hasNotice: Bool {
        switch state {
        case .needsTerms, .cliMissing: return true
        default: return false
        }
    }

    // MARK: - Active stage

    private var activeStatusCapsule: some View {
        HStack(spacing: DroppySpacing.xs) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
                .frame(width: 14, height: 14)

            Text(state.stageTitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                .lineLimit(1)

            Spacer(minLength: 0)

            if case .download(_, let progress) = state {
                progressText(progress, tint: .teal)
            } else if case .upload(_, let progress) = state {
                progressText(progress, tint: .blue)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(AdaptiveColors.notchSurfaceCardFill)
        .clipShape(Capsule(style: .continuous))
        .transition(DroppyTransition.element)
    }

    private func progressText(_ progress: Double, tint: Color) -> some View {
        Text("\(Int(progress * 100))%")
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(tint)
    }

    // MARK: - Paired (220pt)

    @ViewBuilder
    private var pairedBody: some View {
        if hasNotice {
            notice(compact: true)
        } else if state.isRunning {
            liveRunningCompact
        } else if let result = droplet.lastResult {
            VStack(alignment: .leading, spacing: DroppySpacing.xs) {
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
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                }

                Text("↑ \(SpeedtestResult.formattedSpeed(result.uploadMbps)) Mbps")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ready to test")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                Text("Press play to start")
                    .font(.system(size: 11))
                    .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
            }
            .padding(.top, 2)
        }
    }

    private var liveRunningCompact: some View {
        VStack(alignment: .leading, spacing: DroppySpacing.xs) {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                    .frame(width: 12, height: 12)
                Text(state.stageTitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.teal)
                    .lineLimit(1)
            }

            switch state {
            case .download(let mbps, _):
                liveSpeed(arrow: "↓", mbps: mbps, tint: .teal)
            case .upload(let mbps, _):
                liveSpeed(arrow: "↑", mbps: mbps, tint: .blue)
            case .ping(let latency, _):
                Text("\(String(format: "%.0f", latency)) ms ping")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
            default:
                EmptyView()
            }
        }
    }

    private func liveSpeed(arrow: String, mbps: Double, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(arrow)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
            Text(SpeedtestResult.formattedSpeed(mbps))
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
            Text("Mbps")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
        }
    }

    // MARK: - Solo (shelf) and wide (Thunderstorm)

    private func wideOrSoloBody(isWide: Bool) -> some View {
        VStack(alignment: .leading, spacing: isWide ? DroppySpacing.md : DroppySpacing.sm) {
            if state.isRunning {
                activeStatusCapsule
            } else {
                notice(compact: false)
            }

            if !hasNotice {
                HStack(alignment: isWide ? .center : .top, spacing: isWide ? DroppySpacing.xl : DroppySpacing.lg) {
                    metricColumn(
                        title: "Download",
                        symbol: "arrow.down",
                        value: currentDownloadDisplay,
                        tint: .teal,
                        isActivePhase: isDownloadActive,
                        progress: currentDownloadProgress
                    )
                    .frame(minWidth: isWide ? 150 : nil)

                    metricColumn(
                        title: "Upload",
                        symbol: "arrow.up",
                        value: currentUploadDisplay,
                        tint: .blue,
                        isActivePhase: isUploadActive,
                        progress: currentUploadProgress
                    )
                    .frame(minWidth: isWide ? 150 : nil)

                    if isWide {
                        Spacer(minLength: DroppySpacing.md)
                        resultActions
                    }
                }

                diagnosticsStrip
            }
        }
        .animation(DroppyAnimation.state, value: state.isRunning)
        .animation(DroppyAnimation.state, value: hasNotice)
    }

    private var resultActions: some View {
        VStack(alignment: .trailing, spacing: DroppySpacing.xs) {
            if droplet.lastResult?.resultURL != nil {
                Button {
                    droplet.openResultInBrowser()
                } label: {
                    Label("Open on speedtest.net", systemImage: "arrow.up.right")
                }
                .buttonStyle(DroppyQuietButtonStyle(size: .small))
            }

            Button {
                droplet.copyLastResult()
            } label: {
                Label("Copy result", systemImage: "doc.on.doc")
            }
            .buttonStyle(DroppyQuietButtonStyle(size: .small))
            .disabled(droplet.lastResult == nil)
        }
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
                    .font(.system(size: 11, weight: .semibold))
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

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(AdaptiveColors.notchSurfaceCardFill)
                        .frame(height: 3)

                    if let progress, progress > 0 {
                        Capsule(style: .continuous)
                            .fill(tint)
                            .frame(width: max(geo.size.width * CGFloat(progress), 4), height: 3)
                            .animation(.easeOut(duration: 0.2), value: progress)
                    }
                }
            }
            .frame(height: 3)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value) megabits per second")
    }

    // MARK: - Diagnostics

    private var diagnosticsStrip: some View {
        HStack(spacing: DroppySpacing.md) {
            statItem(label: "Ping", value: pingDisplay)

            if let rpm = shownResult?.responsivenessRPM {
                divider
                statItem(label: "Responsiveness", value: String(format: "%.0f RPM", rpm))
            } else {
                divider
                statItem(label: "Jitter", value: jitterDisplay)
            }

            if let loss = shownResult?.packetLoss {
                divider
                statItem(label: "Loss", value: String(format: "%.1f%%", loss))
            }

            if let server = shownResult?.serverName {
                divider
                statItem(label: "Server", value: server)
            }

            Spacer(minLength: 0)

            if let result = droplet.lastResult, !state.isRunning {
                Text(result.timestamp, style: .time)
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
            }
        }
        .lineLimit(1)
        .padding(.top, DroppySpacing.xs)
    }

    private var divider: some View {
        Capsule(style: .continuous)
            .fill(AdaptiveColors.notchSurfaceCardFill)
            .frame(width: 1, height: 10)
    }

    private func statItem(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
        }
    }

    // MARK: - State helpers

    /// The result the strip describes: none while a new test is running.
    private var shownResult: SpeedtestResult? {
        state.isRunning ? nil : droplet.lastResult
    }

    private var isDownloadActive: Bool {
        if case .download = state { return true }
        return false
    }

    private var isUploadActive: Bool {
        if case .upload = state { return true }
        return false
    }

    private var currentDownloadProgress: Double? {
        switch state {
        case .download(_, let progress): return progress
        case .upload, .completed: return 1.0
        default: return nil
        }
    }

    private var currentUploadProgress: Double? {
        switch state {
        case .upload(_, let progress): return progress
        case .completed: return 1.0
        default: return nil
        }
    }

    private var currentDownloadDisplay: String {
        switch state {
        case .preparing, .ping, .measuring:
            return "…"
        case .download(let mbps, _):
            return SpeedtestResult.formattedSpeed(mbps)
        case .upload:
            return droplet.runner.runDownloadMbps.map(SpeedtestResult.formattedSpeed) ?? "…"
        default:
            return droplet.lastResult.map { SpeedtestResult.formattedSpeed($0.downloadMbps) } ?? "—"
        }
    }

    private var currentUploadDisplay: String {
        switch state {
        case .preparing, .ping, .download, .measuring:
            return "…"
        case .upload(let mbps, _):
            return SpeedtestResult.formattedSpeed(mbps)
        default:
            return droplet.lastResult.map { SpeedtestResult.formattedSpeed($0.uploadMbps) } ?? "—"
        }
    }

    private var pingDisplay: String {
        if case .ping(let latency, _) = state {
            return String(format: "%.0f ms", latency)
        }
        return shownResult.map { String(format: "%.0f ms", $0.pingLatency) } ?? "—"
    }

    private var jitterDisplay: String {
        if case .ping(_, let jitter) = state {
            return String(format: "%.1f ms", jitter)
        }
        return shownResult?.pingJitter.map { String(format: "%.1f ms", $0) } ?? "—"
    }
}
