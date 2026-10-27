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

/// The leading wing: dynamic Apple SF Symbol indicating current test stage
private struct SpeedtestLiveActivityLeading: View {
    @ObservedObject var droplet: SpeedtestDroplet

    var body: some View {
        HStack(spacing: DroppySpacing.xsm) {
            Image(systemName: iconName)
                .font(.system(size: DroppyLiveActivityMetrics.iconSize, weight: .semibold))
                .foregroundStyle(iconColor)
                .id(iconName)
                .transition(DroppyTransition.compactContent)
        }
        .padding(.trailing, DroppySpacing.xs)
    }

    private var iconName: String {
        switch droplet.runner.state {
        case .preparing:
            return "antenna.radiowaves.left.and.right"
        case .ping:
            return "waveform.path.ecg"
        case .download:
            return "arrow.down.circle.fill"
        case .upload:
            return "arrow.up.circle.fill"
        case .completed:
            return "checkmark.circle.fill"
        default:
            return "speedometer"
        }
    }

    private var iconColor: Color {
        switch droplet.runner.state {
        case .download: return .teal
        case .upload: return .blue
        case .completed: return .green
        case .ping, .preparing: return .teal
        default: return AdaptiveColors.notchSurfacePrimaryText
        }
    }
}

/// The trailing wing: live speed or status with monospaced digits
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
        case .preparing:
            return "Ansluter…"
        case .ping(let latency, _):
            return "\(String(format: "%.0f", latency)) ms"
        case .download(let mbps, _):
            return "↓ \(SpeedtestResult.formattedSpeed(mbps))"
        case .upload(let mbps, _):
            return "↑ \(SpeedtestResult.formattedSpeed(mbps))"
        case .completed(let result):
            return "↓ \(SpeedtestResult.formattedSpeed(result.downloadMbps))"
        default:
            return ""
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
            SettingsSearchEntry(title: "Speedtest CLI", keywords: ["ookla", "cli", "installera", "terminal", "brew"]),
            SettingsSearchEntry(title: "Mätningar", keywords: ["hastighet", "ping", "bredband", "wifi", "mbps", "nätverk"])
        ]
    }
}

private struct SpeedtestSettings: View {
    @ObservedObject var droplet: SpeedtestDroplet

    var body: some View {
        DropletSettingsPane {
            DropletSettingsSection {
                settingsSectionHeader("Ookla Speedtest CLI")
            } content: {
                DropletSettingsCard {
                    if droplet.runner.isCLIAvailable, let path = droplet.runner.cliPath {
                        DropletControlRow(title: "Installerad och redo") {
                            HStack(spacing: DroppySpacing.sm) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(.green)
                                DropletValuePill(text: path)
                            }
                        }
                    } else {
                        DropletStackedRow(
                            title: "CLI saknas",
                            infoTip: "Speedtest by Ookla kräver det officiella CLI-verktyget för att köra skarpa mätningar."
                        ) {
                            VStack(alignment: .leading, spacing: DroppySpacing.sm) {
                                Text("För att köra mätningar installerar du Ooklas CLI i Terminalen med Homebrew:")
                                    .font(.callout)
                                    .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)

                                HStack(spacing: DroppySpacing.sm) {
                                    Text("brew install speedtest")
                                        .font(.system(.callout, design: .monospaced))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(AdaptiveColors.notchSurfaceCardFill)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))

                                    Button("Kopiera kommando") {
                                        droplet.copyBrewInstallCommand()
                                    }
                                    .buttonStyle(.borderedProminent)

                                    Button("Kontrollera igen") {
                                        droplet.runner.refreshCLIStatus()
                                    }
                                    .buttonStyle(.bordered)
                                }

                                Link(
                                    "Läs mer på speedtest.net/apps/cli",
                                    destination: URL(string: "https://www.speedtest.net/apps/cli")!
                                )
                                .font(.callout)
                            }
                        }
                    }
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("Notiser & Feedback")
            } content: {
                DropletSettingsCard {
                    DropletToggleRow(
                        title: "Visa HUD-notis när mätningen är klar",
                        subtitle: "Visar en diskret notis med sammanfattning av ned- och uppladdning.",
                        isOn: $droplet.showHUDOnComplete
                    )
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("Test & Simulering")
            } content: {
                DropletSettingsCard {
                    DropletControlRow(
                        title: "Simulerat test",
                        infoTip: "Kör en snabb animerad mätning för att prova notchen och hyllan utan CLI."
                    ) {
                        Button("Kör test") {
                            droplet.startSimulatedTest()
                        }
                        .buttonStyle(.bordered)
                        .disabled(droplet.runner.state.isRunning)
                    }
                }
            }
        }
    }
}
