//
//  PongDroplet.swift
//  Pong
//
//  Pong on the notch: a court that takes the shelf over, a CPU on the other
//  side, and a shelf widget with your record and the way in.
//

import AppKit
import Combine
import DroppyKit
import SwiftUI

/// The class Droppy's loader instantiates, named in the bundle's
/// `NSPrincipalClass`. Keep it empty: it runs before the host is ready.
@objc(PongPrincipal)
public final class PongPrincipal: NSObject, DropletPrincipal {
    public override init() { super.init() }

    @MainActor public func makeDroplet() -> AnyObject { PongDroplet() }
}

/// The score of a match that was left mid-rally.
struct PongScore: Equatable {
    let player: Int
    let cpu: Int
}

/// Pong.
@MainActor
public final class PongDroplet: NSObject, ObservableObject, Droplet {
    /// Must equal `DroppyDropletID` in the bundle's Info.plist and `id` in
    /// droplet.json. The loader refuses the bundle if the three disagree.
    public nonisolated static let id: DropletID = "pong"

    static let widgetID: ShelfWidgetID = "pong"
    static let courtSurface: ExpandedSurfaceID = "court"
    private static let recordKey = "record"
    private static let difficultyKey = "difficulty"

    private var host: DropletHost?
    let game = PongGame()
    private var courtPresentation: ExpandedSurfacePresentation?

    @Published private(set) var record = PongRecord()
    @Published private(set) var difficulty: PongDifficulty = .normal
    /// Shown on the widget until the match is resumed.
    @Published private(set) var pausedScore: PongScore?

    public func activate(host: DropletHost) throws {
        self.host = host
        record = host.preferences.value(forKey: Self.recordKey, default: PongRecord())
        difficulty = host.preferences.value(forKey: Self.difficultyKey, default: PongDifficulty.normal)
        game.difficulty = difficulty
        game.onPaddleHit = { [weak self] in self?.host?.feedback.play(.tick) }
        game.onMatchOver = { [weak self] playerWon in self?.matchOver(playerWon: playerWon) }

        host.shortcuts.register(
            id: "play",
            title: "Play Pong",
            defaultShortcut: DropletKeyboardShortcut(
                keyCode: 35, // P
                modifiers: NSEvent.ModifierFlags([.control, .option]).rawValue
            )
        ) { [weak self] in
            self?.toggleCourt()
        }
    }

    public func deactivate() {
        // Everything activate() started is torn down here. The shortcut is
        // unregistered by the host; the game's clock stops with the court.
        if courtPresentation != nil {
            host?.notchSurface.dismissExpandedSurface(Self.courtSurface)
        }
        courtPresentation = nil
        game.setPresented(false)
        game.onPaddleHit = nil
        game.onMatchOver = nil
        host = nil
    }

    // MARK: Court

    /// Takes the notch over with the court. A paused match comes back paused.
    func presentCourt() {
        guard let host, courtPresentation == nil else { return }
        courtPresentation = host.notchSurface.presentExpandedSurface(
            ExpandedSurfacePresentationRequest(surfaceID: Self.courtSurface, opensShelf: true)
        )
        if courtPresentation != nil {
            game.setPresented(true)
        } else {
            host.log.info("the host refused the court")
        }
    }

    func closeCourt() {
        host?.notchSurface.dismissExpandedSurface(Self.courtSurface)
    }

    private func toggleCourt() {
        if courtPresentation == nil { presentCourt() } else { closeCourt() }
    }

    func cycleDifficulty() {
        difficulty = difficulty.next
        game.difficulty = difficulty
        host?.preferences.setValue(difficulty, forKey: Self.difficultyKey)
    }

    private func matchOver(playerWon: Bool) {
        if playerWon { record.wins += 1 } else { record.losses += 1 }
        host?.preferences.setValue(record, forKey: Self.recordKey)
        host?.feedback.play(playerWon ? .success : .failure)
    }
}

// MARK: - Shelf widget

extension PongDroplet: ShelfWidgetProviding {
    public var widgetDescriptors: [ShelfWidgetDescriptor] {
        [
            ShelfWidgetDescriptor(
                id: Self.widgetID,
                title: "Pong",
                systemImage: "gamecontroller",
                layoutTraits: ShelfWidgetLayoutTraits(
                    preferredSoloWidth: 360,
                    preferredPairedWidth: 180,
                    // Tall enough that the bottom line clears the shelf's
                    // corner, 34pt on a solo island.
                    contentHeight: .fixed(76)
                ),
                searchKeywords: ["game", "arcade", "paddle"]
            )
        ]
    }

    public func makeWidgetView(_ id: ShelfWidgetID, context: ShelfWidgetContext) -> AnyView {
        AnyView(PongWidget(droplet: self, context: context))
    }

    public func makeWidgetSettingsPopover(_ id: ShelfWidgetID) -> AnyView? { nil }
}

// MARK: - Court surface

extension PongDroplet: ExpandedSurfaceHosting {
    public var expandedSurfaceProvider: (any ExpandedSurfaceProviding)? { self }
}

extension PongDroplet: ExpandedSurfaceProviding {
    public var expandedSurfaces: [ExpandedSurfaceDescriptor] {
        [
            ExpandedSurfaceDescriptor(
                id: Self.courtSurface,
                title: "Pong",
                systemImage: "gamecontroller",
                // A game is watched, not pointed at, and a stray swipe must
                // not end a rally. A click outside still closes it, and so
                // does the close button.
                suppresses: [.shelfWidgets, .favoritesBar, .floatingNavLane, .notificationBanners, .autoCollapse, .swipeGestures]
            )
        ]
    }

    public func makeExpandedSurfaceView(_ id: ExpandedSurfaceID, context: ExpandedSurfaceContext) -> AnyView {
        guard id == Self.courtSurface else { return AnyView(EmptyView()) }
        return AnyView(CourtView(game: game, context: context, onClose: { [weak self] in self?.closeCourt() }))
    }

    public func expandedSurfaceSize(_ id: ExpandedSurfaceID, fitting proposal: ExpandedSurfaceSizeProposal) -> CGSize? {
        CGSize(
            width: min(PongGame.court.width, proposal.maximumSize.width),
            height: min(PongGame.court.height, proposal.maximumSize.height)
        )
    }

    public func expandedSurfaceDidDismiss(
        _ id: ExpandedSurfaceID,
        presentation: ExpandedSurfacePresentation,
        reason: ExpandedSurfaceDismissalReason
    ) {
        // Compared by presentation, not surface: a late teardown must not stop
        // a court the user has already opened again.
        guard presentation.id == courtPresentation?.id else { return }
        courtPresentation = nil
        game.setPresented(false)
        let state = game.state
        pausedScore = state.isInMatch ? PongScore(player: state.playerScore, cpu: state.cpuScore) : nil
    }
}
