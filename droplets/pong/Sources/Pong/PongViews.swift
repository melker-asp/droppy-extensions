//
//  PongViews.swift
//  Pong
//

import DroppyKit
import SwiftUI

// MARK: - Court

/// The takeover: the court drawn from the game's state, and the pointer that
/// moves your paddle.
struct CourtView: View {
    @ObservedObject var game: PongGame
    let context: ExpandedSurfaceContext
    let onClose: () -> Void

    var body: some View {
        let state = game.state
        Canvas { canvas, size in
            let court = PongGame.court
            let scale = min(size.width / court.width, size.height / court.height)
            canvas.translateBy(
                x: (size.width - court.width * scale) / 2,
                y: (size.height - court.height * scale) / 2
            )
            canvas.scaleBy(x: scale, y: scale)
            Self.draw(state, in: &canvas)
        }
        .accessibilityLabel("Pong. You \(state.playerScore), CPU \(state.cpuScore)")
        .overlay {
            if !context.isPreview {
                PointerPad(
                    onMove: steer,
                    onClick: { game.primaryAction() },
                    onExit: { game.pause() }
                )
            }
        }
        .overlay(alignment: .bottom) {
            if let message = message(for: state) {
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                    .padding(.bottom, DroppySpacing.sm)
                    // Clicks go through to the pointer pad underneath.
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(DroppyCircleButtonStyle(size: 20))
            .help("Close")
            .accessibilityLabel("Close Pong")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: context.isHostShelfTransitioning, initial: true) { _, transitioning in
            game.setFrozen(transitioning)
        }
    }

    /// Maps the pointer's height in the view to the court, undoing the
    /// scale-to-fit the canvas draws with.
    private func steer(to y: CGFloat, in size: CGSize) {
        let court = PongGame.court
        let scale = min(size.width / court.width, size.height / court.height)
        guard scale > 0 else { return }
        game.steer(toward: (y - (size.height - court.height * scale) / 2) / scale)
    }

    private func message(for state: PongState) -> String? {
        if state.isPaused { return "Paused · click to resume" }
        switch state.phase {
        case .ready:
            return "Click to serve · move the pointer to steer"
        case .serving, .playing:
            return nil
        case .over(let playerWon):
            let score = "\(state.playerScore)–\(state.cpuScore)"
            return (playerWon ? "You win \(score)" : "CPU wins \(score)") + " · click for a rematch"
        }
    }

    private static func draw(_ state: PongState, in canvas: inout GraphicsContext) {
        let court = PongGame.court
        let midX = court.width / 2

        var net = Path()
        net.move(to: CGPoint(x: midX, y: 2))
        // Stops short of the bottom, where the hint line sits.
        net.addLine(to: CGPoint(x: midX, y: court.height - 30))
        canvas.stroke(
            net,
            with: .color(AdaptiveColors.notchSurfaceCardFill),
            style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 8])
        )

        for (score, x) in [(state.playerScore, midX - 44), (state.cpuScore, midX + 44)] {
            canvas.draw(
                Text("\(score)")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText),
                at: CGPoint(x: x, y: 26)
            )
        }

        // Your paddle carries the accent, so it is obvious which one is yours.
        let paddle = PongGame.paddleSize
        let paddles: [(x: CGFloat, y: CGFloat, color: Color)] = [
            (PongGame.paddleInset, state.playerY, AdaptiveColors.selectionBlueAuto),
            (court.width - PongGame.paddleInset - paddle.width, state.cpuY, AdaptiveColors.notchSurfacePrimaryText)
        ]
        for item in paddles {
            let rect = CGRect(x: item.x, y: item.y - paddle.height / 2, width: paddle.width, height: paddle.height)
            canvas.fill(
                Path(roundedRect: rect, cornerRadius: paddle.width / 2, style: .continuous),
                with: .color(item.color)
            )
        }

        let d = PongGame.ballSize
        canvas.fill(
            Path(ellipseIn: CGRect(x: state.ball.x - d / 2, y: state.ball.y - d / 2, width: d, height: d)),
            with: .color(AdaptiveColors.notchSurfacePrimaryText)
        )
    }
}

// MARK: - Shelf widget

/// The widget: your record against the CPU and the way into the court.
///
/// Solo and paired are different compositions: solo has room for the record,
/// the difficulty and a labelled Play button, paired for the record alone.
struct PongWidget: View {
    @ObservedObject var droplet: PongDroplet
    let context: ShelfWidgetContext

    var body: some View {
        VStack(alignment: .leading, spacing: DroppySpacing.sm) {
            HStack(spacing: DroppySpacing.xsm) {
                Image(systemName: "gamecontroller")
                    .font(.system(size: 12, weight: .medium))
                Text("Pong")
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
                if context.isCompact {
                    Button {
                        droplet.presentCourt()
                    } label: {
                        Image(systemName: "play.fill")
                    }
                    .buttonStyle(DroppyCircleButtonStyle(size: 20))
                    .help(playTitle)
                    .accessibilityLabel(playTitle)
                } else {
                    Button(droplet.difficulty.title) {
                        droplet.cycleDifficulty()
                    }
                    .buttonStyle(DroppyQuietButtonStyle(size: .small))
                    .help("Change how good the CPU is")
                    .accessibilityLabel("Difficulty, \(droplet.difficulty.title)")
                }
            }
            .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)

            if context.isCompact { compact } else { full }

            Spacer(minLength: 0)
        }
        .padding(context.contentInsets)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var full: some View {
        HStack(alignment: .center, spacing: DroppySpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
            }
            .lineLimit(1)
            Spacer(minLength: DroppySpacing.md)
            Button(playTitle) {
                droplet.presentCourt()
            }
            .buttonStyle(DroppyAccentButtonStyle(size: .small))
        }
    }

    private var compact: some View {
        Text(droplet.pausedScore.map { "\($0.player)–\($0.cpu)" } ?? "\(droplet.record.wins)–\(droplet.record.losses)")
            .font(.system(size: 22, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
    }

    private var playTitle: String {
        droplet.pausedScore == nil ? "Play" : "Resume"
    }

    private var headline: String {
        if let score = droplet.pausedScore {
            return "You \(score.player) · CPU \(score.cpu)"
        }
        let record = droplet.record
        return "\(record.wins) \(record.wins == 1 ? "win" : "wins") · \(record.losses) \(record.losses == 1 ? "loss" : "losses")"
    }

    private var detail: String {
        droplet.pausedScore == nil
            ? "Against the CPU, first to \(PongGame.pointsToWin)"
            : "Match paused"
    }
}
