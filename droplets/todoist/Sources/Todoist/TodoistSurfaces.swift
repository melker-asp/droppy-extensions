//
//  TodoistSurfaces.swift
//  Todoist
//
//  The live activity beside the notch before a task with a time, and the
//  settings pane.
//

import Combine
import DroppyKit
import SwiftUI

// MARK: - Live activity

extension TodoistDroplet: LiveActivityProviding {
    public var liveActivityState: AnyPublisher<LiveActivityState?, Never> {
        activityPublisher
    }

    public func liveActivitySeatDidChange(_ seat: DropletLiveActivitySeat) {}

    public func makeCompactLeading() -> AnyView {
        AnyView(
            Image(systemName: "checkmark.circle")
                .font(.system(size: DroppyLiveActivityMetrics.iconSize, weight: .medium))
                .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
        )
    }

    public func makeCompactTrailing() -> AnyView {
        AnyView(TodoistCountdownLabel(droplet: self))
    }

    /// Not mounted by Droppy: hovering the row opens the shelf, where the
    /// task is at the top of the list.
    public func makeExpanded(context: LiveActivityContext) -> AnyView {
        AnyView(EmptyView())
    }

    public func makeCompanionCompact(context: CompactLiveActivityContext) -> AnyView {
        makeCompactTrailing()
    }

    public func makeCompanionDetail(context: LiveActivityContext) -> AnyView? { nil }
}

/// The trailing wing: minutes until the task, or its time an hour or more out.
private struct TodoistCountdownLabel: View {
    @ObservedObject var droplet: TodoistDroplet

    var body: some View {
        let text = droplet.upcoming?.due?.time.map { TodoistDroplet.countdown(to: $0, now: droplet.now).short } ?? ""
        Text(text)
            .font(.system(size: DroppyLiveActivityMetrics.labelFontSize, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
            .lineLimit(1)
            .id(text)
            .transition(DroppyTransition.compactContent)
    }
}

// MARK: - Settings pane

extension TodoistDroplet: SettingsPaneProviding {
    public func makeSettingsPane(context: SettingsPaneContext) -> AnyView {
        AnyView(TodoistSettings(droplet: self))
    }

    public var settingsSearchEntries: [SettingsSearchEntry] {
        [
            SettingsSearchEntry(title: "API-token", keywords: ["todoist", "token", "konto", "anslut"]),
            SettingsSearchEntry(title: "Påminn före uppgifter", keywords: ["påminnelse", "notch", "deadline"]),
        ]
    }
}

private struct TodoistSettings: View {
    @ObservedObject var droplet: TodoistDroplet
    @State private var token = ""
    @State private var isConnecting = false
    @State private var error: String?

    var body: some View {
        DropletSettingsPane {
            DropletSettingsSection {
                settingsSectionHeader("Konto")
            } content: {
                DropletSettingsCard {
                    if droplet.hasToken {
                        DropletControlRow(title: droplet.accountName.map { "Ansluten som \($0)" } ?? "Ansluten") {
                            Button("Koppla från", role: .destructive) {
                                if DropletConfirmationDialog.present(
                                    title: "Koppla från Todoist?",
                                    message: "API-token tas bort från nyckelringen. Dina uppgifter i Todoist påverkas inte.",
                                    confirmTitle: "Koppla från",
                                    symbol: "xmark.circle"
                                ) {
                                    droplet.disconnect()
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                        DropletControlRow(title: "Senast hämtat") {
                            DropletValuePill(text: droplet.lastSync.map { Self.time.string(from: $0) } ?? "Aldrig")
                        }
                    } else {
                        DropletStackedRow(
                            title: "API-token",
                            infoTip: "Todoist, Inställningar, Integrationer, Utvecklare. Token sparas i nyckelringen."
                        ) {
                            VStack(alignment: .leading, spacing: DroppySpacing.sm) {
                                HStack(spacing: DroppySpacing.sm) {
                                    SecureField("Klistra in din token", text: $token)
                                        .textFieldStyle(.roundedBorder)
                                        .onSubmit(connect)
                                    Button(isConnecting ? "Ansluter…" : "Anslut", action: connect)
                                        .buttonStyle(.borderedProminent)
                                        .disabled(isConnecting || token.isEmpty)
                                }
                                if let error {
                                    Text(error)
                                        .font(.callout)
                                        .foregroundStyle(.red)
                                }
                                Link(
                                    "Hitta din token i Todoist",
                                    destination: URL(string: "https://app.todoist.com/app/settings/integrations/developer")!
                                )
                                .font(.callout)
                            }
                        }
                    }
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("Hyllan")
            } content: {
                DropletSettingsCard {
                    DropletToggleRow(
                        title: "Visa kommande uppgifter",
                        subtitle: "De närmaste tre uppgifterna efter idag, under rubriken Kommande.",
                        isOn: droplet.binding("showUpcoming", default: true) { droplet.relayout() }
                    )
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("Påminnelser")
            } content: {
                DropletSettingsCard {
                    DropletToggleRow(
                        title: "Påminn före uppgifter med klockslag",
                        subtitle: "Visar uppgiften och nedräkningen bredvid notchen, och ett kort på notchen när påminnelsen börjar.",
                        isOn: droplet.binding("remind", default: true)
                    )
                    if droplet.remindsBeforeTasks {
                        DropletSliderRow(
                            title: "Hur långt innan",
                            value: "\(Int(droplet.reminderLeadMinutes)) min",
                            binding: droplet.binding("remindLead", default: 15.0),
                            range: 5...60,
                            step: 5
                        )
                    }
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("Andra appar")
            } content: {
                DropletSettingsCard {
                    DropletToggleRow(
                        title: "Ta emot uppgifter från länkar",
                        subtitle: "Låter Todoist-clipet i DropClip och andra appar lägga till uppgifter via droppy://droplet/todoist/add. Länkar kan bara lägga till, aldrig läsa eller ta bort.",
                        isOn: droplet.binding("acceptLinks", default: true)
                    )
                }
            }
        }
    }

    private func connect() {
        guard !isConnecting else { return }
        isConnecting = true
        error = nil
        Task {
            error = await droplet.connect(token: token)
            if error == nil { token = "" }
            isConnecting = false
        }
    }

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}
