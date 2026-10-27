//
//  SpeedtestSurfaces.swift
//  Speedtest
//
//  Live activity beside the notch and settings pane for Speedtest,
//  following Apple Human Interface Guidelines and DroppyKit design rules.
//

import Combine
import DroppyKit
import SwiftUI

// MARK: - Live Activity (Notch Wings)

extension SpeedtestDroplet: LiveActivityProviding {
    public var liveActivityState: AnyPublisher<LiveActivityState?, Never> {
        activityPublisher
    }

    public func liveActivitySeatDidChange(_ seat: DropletLiveActivitySeat) {}

    public func makeCompactLeading() -> AnyView {
        AnyView(SpeedtestLiveActivityLeading(droplet: self))
    }

    public func makeCompactTrailing() -> AnyView {
        AnyView(SpeedtestLiveActivityTrailing(droplet: self))
    }

    public func makeExpanded(context: LiveActivityContext) -> AnyView {
        AnyView(EmptyView())
    }

    public func makeCompanionCompact(context: CompactLiveActivityContext) -> AnyView {
        makeCompactTrailing()
    }

    public func makeCompanionDetail(context: LiveActivityContext) -> AnyView? { nil }
}

/// The leading wing: an SF Symbol for the current stage.
private struct SpeedtestLiveActivityLeading: View {
    @ObservedObject var droplet: SpeedtestDroplet

    var body: some View {
        Image(systemName: iconName)
            .font(.system(size: DroppyLiveActivityMetrics.iconSize, weight: .semibold))
            .foregroundStyle(iconColor)
            .id(iconName)
            .transition(DroppyTransition.compactContent)
            .padding(.trailing, DroppySpacing.xs)
    }

    private var iconName: String {
        switch droplet.runner.state {
        case .preparing: return "antenna.radiowaves.left.and.right"
        case .ping: return "waveform.path.ecg"
        case .download: return "arrow.down.circle.fill"
        case .upload: return "arrow.up.circle.fill"
        case .completed: return "checkmark.circle.fill"
        default: return "speedometer"
        }
    }

    private var iconColor: Color {
        switch droplet.runner.state {
        case .upload: return .blue
        case .completed: return .green
        case .preparing, .ping, .download, .measuring: return .teal
        default: return AdaptiveColors.notchSurfacePrimaryText
        }
    }
}

/// The trailing wing: live speed or status with monospaced digits.
private struct SpeedtestLiveActivityTrailing: View {
    @ObservedObject var droplet: SpeedtestDroplet

    var body: some View {
        Text(statusText)
            .font(.system(size: DroppyLiveActivityMetrics.labelFontSize, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
            .lineLimit(1)
            .padding(.leading, DroppySpacing.xs)
            .id(statusText)
            .transition(DroppyTransition.compactContent)
    }

    private var statusText: String {
        switch droplet.runner.state {
        case .preparing: return "Connecting…"
        case .measuring: return "Testing…"
        case .ping(let latency, _): return "\(String(format: "%.0f", latency)) ms"
        case .download(let mbps, _): return "↓ \(SpeedtestResult.formattedSpeed(mbps))"
        case .upload(let mbps, _): return "↑ \(SpeedtestResult.formattedSpeed(mbps))"
        case .completed(let result): return "↓ \(SpeedtestResult.formattedSpeed(result.downloadMbps))"
        default: return ""
        }
    }
}

// MARK: - Settings Pane

extension SpeedtestDroplet: SettingsPaneProviding {
    public func makeSettingsPane(context: SettingsPaneContext) -> AnyView {
        AnyView(SpeedtestSettings(droplet: self))
    }

    public var settingsSearchEntries: [SettingsSearchEntry] {
        [
            SettingsSearchEntry(title: "Speedtest CLI", keywords: ["ookla", "cli", "install", "terminal", "brew", "homebrew"]),
            SettingsSearchEntry(title: "Ookla's terms", keywords: ["license", "licence", "privacy", "gdpr", "eula"]),
            SettingsSearchEntry(title: "Apple's network test", keywords: ["networkquality", "fallback", "responsiveness", "rpm"]),
            SettingsSearchEntry(title: "Notifications", keywords: ["hud", "speed", "ping", "mbps", "network"]),
        ]
    }
}

private struct SpeedtestSettings: View {
    @ObservedObject var droplet: SpeedtestDroplet

    var body: some View {
        DropletSettingsPane {
            DropletSettingsSection {
                settingsSectionHeader("Speedtest CLI")
            } content: {
                DropletSettingsCard {
                    cliRow
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("Ookla's terms")
            } content: {
                DropletSettingsCard {
                    DropletToggleRow(
                        title: "Accept Ookla's license and privacy policy",
                        subtitle: "Ookla's CLI asks for this before its first test. Speedtest passes your answer on each time it runs it.",
                        isOn: $droplet.termsAccepted
                    )
                    DropletStackedRow(title: "Read them on speedtest.net") {
                        HStack(spacing: DroppySpacing.md) {
                            Link("License", destination: SpeedtestDroplet.ooklaEULA)
                            Link("Terms of use", destination: SpeedtestDroplet.ooklaTerms)
                            Link("Privacy policy", destination: SpeedtestDroplet.ooklaPrivacy)
                        }
                        .font(.callout)
                    }
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("Without Ookla's CLI")
            } content: {
                DropletSettingsCard {
                    DropletToggleRow(
                        title: "Use Apple's network test",
                        subtitle: "Measures with networkQuality, built into macOS, when Ookla's CLI isn't installed. Results come from Apple's servers, not Ookla's.",
                        isOn: $droplet.useAppleFallback
                    )
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("Notifications")
            } content: {
                DropletSettingsCard {
                    DropletToggleRow(
                        title: "Show a HUD when a test finishes",
                        subtitle: "A short summary of download and upload speed by the notch.",
                        isOn: $droplet.showHUDOnComplete
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var cliRow: some View {
        if droplet.runner.isCLIAvailable, let path = droplet.runner.cliPath {
            DropletControlRow(title: "Installed") {
                DropletValuePill(text: path)
            }
        } else {
            DropletStackedRow(
                title: droplet.runner.isCheckingCLI ? "Looking for Ookla's CLI…" : "Not installed",
                infoTip: "Speedtest runs Ookla's official command-line tool. Install it with Homebrew."
            ) {
                VStack(alignment: .leading, spacing: DroppySpacing.sm) {
                    Text("Paste this in Terminal to install it with Homebrew:")
                        .font(.callout)
                        .foregroundStyle(AdaptiveColors.secondaryTextAuto)

                    Text(SpeedtestDroplet.installCommand)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)

                    HStack(spacing: DroppySpacing.sm) {
                        Button("Copy command") {
                            droplet.copyInstallCommand()
                        }
                        .buttonStyle(DroppyAccentButtonStyle(size: .small))

                        Button("Check again") {
                            droplet.runner.refreshCLIStatus()
                        }
                        .buttonStyle(DroppyQuietButtonStyle(size: .small))
                        .disabled(droplet.runner.isCheckingCLI)

                        Link("About the CLI", destination: SpeedtestDroplet.ooklaCLIPage)
                            .font(.callout)
                    }
                }
            }
        }
    }
}
