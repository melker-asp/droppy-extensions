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

    @Published public var runner: SpeedtestRunner
    @Published public var lastResult: SpeedtestResult?
    @Published public var showHUDOnComplete: Bool = true

    public var host: DropletHost?
    private var cancellables = Set<AnyCancellable>()
    private let activitySubject = CurrentValueSubject<LiveActivityState?, Never>(nil)
    private var resultDismissTimer: Task<Void, Never>?

    public var activityPublisher: AnyPublisher<LiveActivityState?, Never> {
        activitySubject.eraseToAnyPublisher()
    }

    public override init() {
        self.runner = SpeedtestRunner()
        super.init()
        loadPersistedResult()
        setupRunnerObservers()
    }

    public func activate(host: DropletHost) throws {
        self.host = host
        host.log.info("Speedtest droplet activated")
        runner.refreshCLIStatus()
    }

    public func deactivate() {
        cancelTest()
        cancellables.removeAll()
        host = nil
    }

    /// Primary droplet action (e.g. from Thunderstorm Return key or widget refresh).
    public func refresh() {
        if runner.isCLIAvailable {
            startTest()
        } else {
            startSimulatedTest()
        }
    }

    /// Handles `droppy://droplet/speedtest/...` URLs.
    public func handle(_ request: DropletURLRequest) {
        if request.path == "start" || request.path == "run" || request.path.isEmpty {
            refresh()
        }
    }

    // MARK: - Actions

    public func startTest() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
        resultDismissTimer?.cancel()
        resultDismissTimer = nil
        host?.shelf.setHoldsOpen(true)
        runner.startTest()
    }

    public func startSimulatedTest() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
        resultDismissTimer?.cancel()
        resultDismissTimer = nil
        host?.shelf.setHoldsOpen(true)
        runner.startSimulatedTest()
    }

    public func cancelTest() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
        runner.cancel()
        host?.shelf.setHoldsOpen(false)
        activitySubject.send(nil)
    }

    public func copyBrewInstallCommand() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("brew install speedtest", forType: .string)

        presentHUD(
            title: "Kopierade installationskommando",
            subtitle: "Kör: brew install speedtest",
            symbol: "terminal.fill"
        )
    }

    public func copyLastResult() {
        guard let res = lastResult else { return }
        let text = """
        Speedtest by Ookla Resultat:
        Nedladdning: \(SpeedtestResult.formattedSpeed(res.downloadMbps)) Mbps
        Uppladdning: \(SpeedtestResult.formattedSpeed(res.uploadMbps)) Mbps
        Ping: \(String(format: "%.1f", res.pingLatency)) ms (Jitter: \(String(format: "%.1f", res.pingJitter)) ms)
        \(res.resultURL ?? "")
        """
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        presentHUD(
            title: "Kopierade resultat",
            subtitle: "↓ \(SpeedtestResult.formattedSpeed(res.downloadMbps)) Mbps  •  ↑ \(SpeedtestResult.formattedSpeed(res.uploadMbps)) Mbps",
            symbol: "doc.on.doc.fill"
        )
    }

    public func openResultInBrowser() {
        if let urlString = lastResult?.resultURL, let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        } else if let url = URL(string: "https://www.speedtest.net") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Observers & State Management

    private func setupRunnerObservers() {
        runner.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handleStateChange(state)
            }
            .store(in: &cancellables)
    }

    private func handleStateChange(_ state: SpeedtestState) {
        switch state {
        case .preparing, .ping, .download, .upload:
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
            self.lastResult = result
            savePersistedResult(result)

            // Keep Live Activity showing final result for 6 seconds
            activitySubject.send(
                LiveActivityState(
                    priority: 250,
                    accessibilityTitle: "Speedtest klart: \(SpeedtestResult.formattedSpeed(result.downloadMbps)) Mbps",
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
                presentHUD(
                    title: "Speedtest klart",
                    subtitle: "↓ \(SpeedtestResult.formattedSpeed(result.downloadMbps)) Mbps  •  ↑ \(SpeedtestResult.formattedSpeed(result.uploadMbps)) Mbps",
                    symbol: "speedometer"
                )
            }

        case .failed(let error):
            host?.shelf.setHoldsOpen(false)
            activitySubject.send(nil)
            presentHUD(
                title: "Speedtest misslyckades",
                subtitle: error,
                symbol: "exclamationmark.triangle.fill"
            )

        case .idle, .checkingCLI, .cliMissing:
            host?.shelf.setHoldsOpen(false)
            activitySubject.send(nil)
        }
    }

    private func presentHUD(title: String, subtitle: String, symbol: String) {
        guard let host = host else { return }
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

    // MARK: - Persistence

    private func savePersistedResult(_ result: SpeedtestResult) {
        if let data = try? JSONEncoder().encode(result) {
            UserDefaults.standard.set(data, forKey: "droplet.speedtest.lastResult")
        }
    }

    private func loadPersistedResult() {
        if let data = UserDefaults.standard.data(forKey: "droplet.speedtest.lastResult"),
           let res = try? JSONDecoder().decode(SpeedtestResult.self, from: data) {
            self.lastResult = res
        }
    }
}
