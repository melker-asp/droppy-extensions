//
//  SpeedtestDroplet.swift
//  Speedtest
//
//  Main droplet class coordinating Speedtest execution, surfaces and state.
//

import AppKit
import Combine
import DroppyKit
import SwiftUI

/// The principal class Droppy's loader instantiates.
@objc(SpeedtestPrincipal)
public final class SpeedtestPrincipal: NSObject, DropletPrincipal {
    public override init() { super.init() }

    @MainActor public func makeDroplet() -> AnyObject { SpeedtestDroplet() }
}

/// Speedtest Droplet
@MainActor
public final class SpeedtestDroplet: NSObject, ObservableObject, Droplet, HUDPresenting, DropletURLHandling {
    public nonisolated static let id: DropletID = "speedtest"
    public static let widgetID: ShelfWidgetID = "speedtest"

    static let installCommand = "brew tap teamookla/speedtest && brew trust --formula teamookla/speedtest/speedtest && brew install speedtest"
    static let ooklaCLIPage = URL(string: "https://www.speedtest.net/apps/cli")!
    static let ooklaEULA = URL(string: "https://www.speedtest.net/about/eula")!
    static let ooklaTerms = URL(string: "https://www.speedtest.net/about/terms")!
    static let ooklaPrivacy = URL(string: "https://www.speedtest.net/about/privacy")!

    private enum Key {
        static let termsAccepted = "ooklaTermsAccepted"
        static let useAppleFallback = "useAppleFallback"
        static let showHUDOnComplete = "showHUDOnComplete"
        static let lastResult = "lastResult"
    }

    @Published public var runner: SpeedtestRunner
    @Published public private(set) var lastResult: SpeedtestResult?
    @Published public var termsAccepted = false {
        didSet { host?.preferences.setValue(termsAccepted, forKey: Key.termsAccepted) }
    }
    @Published public var useAppleFallback = true {
        didSet { host?.preferences.setValue(useAppleFallback, forKey: Key.useAppleFallback) }
    }
    @Published public var showHUDOnComplete = true {
        didSet { host?.preferences.setValue(showHUDOnComplete, forKey: Key.showHUDOnComplete) }
    }

    public var host: DropletHost?
    private var cancellables = Set<AnyCancellable>()
    private let activitySubject = CurrentValueSubject<LiveActivityState?, Never>(nil)
    private var resultDismissTimer: Task<Void, Never>?

    public var activityPublisher: AnyPublisher<LiveActivityState?, Never> {
        activitySubject.eraseToAnyPublisher()
    }

    var isHarness: Bool { host?.environment.isHarness == true }

    /// Lives as long as the droplet: views observe the droplet but read the
    /// runner's state, so the runner's changes have to redraw them too.
    private var runnerForwarding: AnyCancellable?

    public override init() {
        self.runner = SpeedtestRunner()
        super.init()
        runnerForwarding = runner.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    public func activate(host: DropletHost) throws {
        self.host = host
        let preferences = host.preferences
        termsAccepted = preferences.value(forKey: Key.termsAccepted, default: false)
        useAppleFallback = preferences.value(forKey: Key.useAppleFallback, default: true)
        showHUDOnComplete = preferences.value(forKey: Key.showHUDOnComplete, default: true)
        lastResult = preferences.value(forKey: Key.lastResult, as: SpeedtestResult.self)
        if isHarness, lastResult == nil {
            lastResult = .harnessDemo
        }
        // Builds before 1.0.0 kept their last result, sometimes a made-up one,
        // in Droppy's own defaults.
        UserDefaults.standard.removeObject(forKey: "droplet.speedtest.lastResult")

        runner.$state
            .sink { [weak self] state in self?.handleStateChange(state) }
            .store(in: &cancellables)
        runner.refreshCLIStatus()
        host.log.info("Speedtest droplet activated")
    }

    public func deactivate() {
        runner.cancel()
        resultDismissTimer?.cancel()
        resultDismissTimer = nil
        cancellables.removeAll()
        activitySubject.send(nil)
        host?.shelf.setHoldsOpen(false)
        host = nil
    }

    /// Handles `droppy://droplet/speedtest/run` and `droppy://droplet/speedtest/stop`,
    /// so a Thunderstorm quicklink or a script can start and stop a test.
    public func handle(_ request: DropletURLRequest) {
        switch request.path {
        case "", "run", "start": startTest()
        case "stop", "cancel": cancelTest()
        default: break
        }
    }

    // MARK: - Actions

    /// Starts the best test available: Ookla's when its CLI is installed and
    /// its terms accepted, Apple's when the CLI is missing and the fallback is on.
    public func startTest() {
        guard !runner.state.isRunning else { return }
        runner.noticeNewlyInstalledCLI()

        if isHarness {
            beginRun()
            runner.startHarnessDemo()
        } else if runner.isCLIAvailable {
            if termsAccepted {
                beginRun()
                runner.startOokla()
            } else {
                runner.state = .needsTerms
            }
        } else if useAppleFallback, runner.isAppleToolAvailable {
            startAppleTest()
        } else {
            runner.state = .cliMissing
        }
    }

    /// The user accepted Ookla's licence and privacy policy from the widget.
    public func acceptTermsAndStart() {
        termsAccepted = true
        runner.state = .idle
        startTest()
    }

    /// Runs Apple's networkQuality, whatever is installed.
    public func startAppleTest() {
        guard !runner.state.isRunning, runner.isAppleToolAvailable else { return }
        beginRun()
        runner.startApple()
    }

    public func cancelTest() {
        guard runner.state.isRunning else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
        runner.cancel()
    }

    private func beginRun() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
        resultDismissTimer?.cancel()
        resultDismissTimer = nil
    }

    public func copyInstallCommand() {
        guard host?.workspace.copyToPasteboard(Self.installCommand) == true else { return }
        presentHUD(
            title: "Install command copied",
            subtitle: "Paste it in Terminal",
            symbol: "terminal.fill"
        )
    }

    public func copyLastResult() {
        guard let result = lastResult,
              host?.workspace.copyToPasteboard(result.summaryText) == true else { return }
        presentHUD(
            title: "Result copied",
            subtitle: Self.speedSummary(result),
            symbol: "doc.on.doc.fill"
        )
    }

    public func openResultInBrowser() {
        let url = lastResult?.resultURL.flatMap(URL.init(string:)) ?? URL(string: "https://www.speedtest.net")!
        host?.workspace.open(url)
    }

    public func openSettings() {
        host?.workspace.openSettings()
    }

    static func speedSummary(_ result: SpeedtestResult) -> String {
        "↓ \(SpeedtestResult.formattedSpeed(result.downloadMbps)) Mbps  •  ↑ \(SpeedtestResult.formattedSpeed(result.uploadMbps)) Mbps"
    }

    // MARK: - State

    private func handleStateChange(_ state: SpeedtestState) {
        switch state {
        case .preparing, .ping, .download, .upload, .measuring:
            host?.shelf.setHoldsOpen(true)
            activitySubject.send(
                LiveActivityState(
                    priority: 250,
                    accessibilityTitle: "Speedtest: \(state.stageTitle)",
                    isInteractive: true
                )
            )

        case .completed(let result):
            host?.shelf.setHoldsOpen(false)
            lastResult = result
            if !isHarness {
                host?.preferences.setValue(result, forKey: Key.lastResult)
            }

            // The wings show the final speed for a few seconds, then yield the seat.
            activitySubject.send(
                LiveActivityState(
                    priority: 250,
                    accessibilityTitle: "Speedtest done: \(SpeedtestResult.formattedSpeed(result.downloadMbps)) Mbps down",
                    isInteractive: false
                )
            )
            resultDismissTimer?.cancel()
            resultDismissTimer = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                guard !Task.isCancelled else { return }
                self?.activitySubject.send(nil)
            }

            if showHUDOnComplete {
                presentHUD(title: "Speedtest done", subtitle: Self.speedSummary(result), symbol: "speedometer")
            }

        case .failed(let message):
            host?.shelf.setHoldsOpen(false)
            activitySubject.send(nil)
            presentHUD(title: "Speedtest failed", subtitle: message, symbol: "exclamationmark.triangle.fill")

        case .idle, .needsTerms, .cliMissing:
            host?.shelf.setHoldsOpen(false)
            activitySubject.send(nil)
        }
    }

    private func presentHUD(title: String, subtitle: String, symbol: String) {
        guard let host else { return }
        let request = DropletHUDRequest(
            id: "speedtest-hud",
            duration: 3.5,
            priority: .normal,
            accessibilityLabel: "\(title): \(subtitle)",
            isExpanded: false
        ) {
            HStack(spacing: DroppySpacing.sm) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.teal)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, DroppySpacing.md)
            .padding(.vertical, DroppySpacing.sm)
        } expanded: {
            EmptyView()
        }
        _ = host.hud.present(request)
    }
}
