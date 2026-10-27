//
//  PongGame.swift
//  Pong
//
//  The match: a ball, two paddles and a score, stepped on a fixed timestep so
//  the same inputs always give the same rally. The droplet decides when it
//  runs; the court view only draws it and reports where the pointer is.
//

import Foundation
import QuartzCore

enum PongDifficulty: String, Codable, CaseIterable, Sendable {
    case easy, normal, hard

    var title: String {
        switch self {
        case .easy: "Easy"
        case .normal: "Normal"
        case .hard: "Hard"
        }
    }

    /// How fast the CPU paddle moves, in points per second.
    var cpuSpeed: CGFloat {
        switch self {
        case .easy: 150
        case .normal: 210
        case .hard: 290
        }
    }

    /// How far from the ball the CPU aims, at most, re-rolled on every return.
    /// Aiming off-centre is what makes it send the ball back at an angle.
    var aimError: CGFloat {
        switch self {
        case .easy: 18
        case .normal: 12
        case .hard: 6
        }
    }

    var next: PongDifficulty {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

struct PongRecord: Codable, Equatable, Sendable {
    var wins = 0
    var losses = 0
}

struct PongState: Equatable {
    enum Phase: Equatable {
        /// Before the first serve of a match.
        case ready
        /// The ball waits at the centre for `remaining` seconds.
        case serving(remaining: TimeInterval)
        case playing
        case over(playerWon: Bool)
    }

    var phase: Phase = .ready
    var isPaused = false
    var ball = PongGame.centre
    var velocity = CGVector.zero
    var playerY = PongGame.court.height / 2
    var cpuY = PongGame.court.height / 2
    var playerScore = 0
    var cpuScore = 0

    /// A match is under way: serving or mid-rally, paused or not.
    var isInMatch: Bool {
        switch phase {
        case .serving, .playing: true
        case .ready, .over: false
        }
    }

    /// The clock is stepping this state.
    var isRunning: Bool { isInMatch && !isPaused }
}

@MainActor
final class PongGame: ObservableObject {
    /// The court in its own points. The view scales it to whatever the host
    /// hands the surface, so the physics never depend on the display.
    nonisolated static let court = CGSize(width: 560, height: 200)
    nonisolated static let centre = CGPoint(x: court.width / 2, y: court.height / 2)
    nonisolated static let paddleSize = CGSize(width: 6, height: 40)
    nonisolated static let paddleInset: CGFloat = 20
    nonisolated static let ballSize: CGFloat = 8
    nonisolated static let pointsToWin = 11
    /// How fast your paddle chases the pointer. Quick enough to feel direct,
    /// capped so a flick of the trackpad cannot teleport it past the ball.
    nonisolated static let playerSpeed: CGFloat = 1000
    nonisolated static let serveSpeed: CGFloat = 260
    nonisolated static let maxSpeed: CGFloat = 600
    nonisolated static let speedUp: CGFloat = 1.06
    nonisolated static let maxBounceAngle: CGFloat = .pi / 3
    nonisolated static let serveDelay: TimeInterval = 0.8
    /// Small enough that the fastest ball moves less than a paddle's width
    /// per step, so it can never tunnel through one.
    nonisolated static let step: TimeInterval = 1.0 / 240

    /// What the view draws. Published once per tick, not once per field.
    @Published private(set) var state = PongState()
    var difficulty: PongDifficulty = .normal
    var onPaddleHit: (() -> Void)?
    var onMatchOver: ((_ playerWon: Bool) -> Void)?

    private var sim = PongState()
    private var playerTarget: CGFloat?
    private var cpuAim: CGFloat = 0
    private var serveTowardPlayer = false
    private var timer: Timer?
    private var lastTick: CFTimeInterval = 0
    private var accumulator: TimeInterval = 0
    private var isPresented = false
    private var isFrozen = false

    // MARK: Controls

    /// A click: serve, pause, resume, or start a rematch.
    func primaryAction() {
        switch sim.phase {
        case .ready:
            serve(towardPlayer: .random())
        case .over:
            sim = PongState()
            serve(towardPlayer: .random())
        case .serving, .playing:
            sim.isPaused.toggle()
        }
        publish()
        updateTimer()
    }

    /// The pointer's height over the court, in court points.
    func steer(toward y: CGFloat) {
        let half = Self.paddleSize.height / 2
        let target = y.clamped(to: half...(Self.court.height - half))
        playerTarget = target
        // Between rallies nothing is stepping, so the paddle follows at once.
        if !sim.isRunning {
            sim.playerY = target
            publish()
        }
    }

    /// Stops the rally rather than letting the CPU score against a player who
    /// is not there: the pointer left the court, or the court closed.
    func pause() {
        guard sim.isRunning else { return }
        sim.isPaused = true
        publish()
        updateTimer()
    }

    // MARK: Lifecycle

    /// Whether the court is on screen. The clock only runs while it is.
    func setPresented(_ presented: Bool) {
        isPresented = presented
        if !presented { pause() }
        updateTimer()
    }

    /// The host's shelf spring is in flight: hold still until it settles.
    func setFrozen(_ frozen: Bool) {
        isFrozen = frozen
        updateTimer()
    }

    /// Replaces the state wholesale. For tests.
    func load(_ state: PongState) {
        sim = state
        publish()
    }

    // MARK: Clock

    private func updateTimer() {
        let shouldRun = isPresented && !isFrozen && sim.isRunning
        if shouldRun, timer == nil {
            lastTick = CACurrentMediaTime()
            accumulator = 0
            let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else if !shouldRun, let timer {
            timer.invalidate()
            self.timer = nil
        }
    }

    private func tick() {
        let now = CACurrentMediaTime()
        // After a stall (a busy main thread, a Mac waking up) the rally picks
        // up where it was instead of jumping ahead.
        advance(by: min(now - lastTick, 0.05))
        lastTick = now
    }

    /// Runs as many fixed steps as `elapsed` covers, then publishes.
    func advance(by elapsed: TimeInterval) {
        accumulator += elapsed
        while accumulator >= Self.step {
            accumulator -= Self.step
            simulate(CGFloat(Self.step))
        }
        publish()
        updateTimer()
    }

    private func publish() {
        if state != sim { state = sim }
    }

    // MARK: Simulation

    private func simulate(_ dt: CGFloat) {
        guard !sim.isPaused else { return }
        switch sim.phase {
        case .serving(let remaining):
            movePaddles(dt)
            let left = remaining - TimeInterval(dt)
            if left <= 0 { launch() } else { sim.phase = .serving(remaining: left) }
        case .playing:
            movePaddles(dt)
            moveBall(dt)
        case .ready, .over:
            break
        }
    }

    private func movePaddles(_ dt: CGFloat) {
        let half = Self.paddleSize.height / 2
        let range = half...(Self.court.height - half)

        if let playerTarget {
            let reach = Self.playerSpeed * dt
            sim.playerY = (sim.playerY + (playerTarget - sim.playerY).clamped(to: -reach...reach)).clamped(to: range)
        }

        // The CPU follows the ball only while it is coming its way and drifts
        // back to the middle otherwise, the way a person would.
        let target = sim.phase == .playing && sim.velocity.dx > 0 ? sim.ball.y + cpuAim : Self.court.height / 2
        let reach = difficulty.cpuSpeed * dt
        sim.cpuY = (sim.cpuY + (target - sim.cpuY).clamped(to: -reach...reach)).clamped(to: range)
    }

    private func moveBall(_ dt: CGFloat) {
        let r = Self.ballSize / 2
        var ball = CGPoint(x: sim.ball.x + sim.velocity.dx * dt, y: sim.ball.y + sim.velocity.dy * dt)

        if ball.y - r < 0 {
            ball.y = r
            sim.velocity.dy = abs(sim.velocity.dy)
        } else if ball.y + r > Self.court.height {
            ball.y = Self.court.height - r
            sim.velocity.dy = -abs(sim.velocity.dy)
        }

        let reach = Self.paddleSize.height / 2 + r
        let playerFace = Self.paddleInset + Self.paddleSize.width
        let cpuFace = Self.court.width - playerFace
        if sim.velocity.dx < 0, ball.x - r <= playerFace, ball.x >= Self.paddleInset,
           abs(ball.y - sim.playerY) <= reach {
            ball.x = playerFace + r
            returnBall(from: sim.playerY, at: ball.y, towardCPU: true)
        } else if sim.velocity.dx > 0, ball.x + r >= cpuFace, ball.x <= Self.court.width - Self.paddleInset,
                  abs(ball.y - sim.cpuY) <= reach {
            ball.x = cpuFace - r
            returnBall(from: sim.cpuY, at: ball.y, towardCPU: false)
        }
        sim.ball = ball

        if ball.x + r < 0 {
            score(playerWon: false)
        } else if ball.x - r > Self.court.width {
            score(playerWon: true)
        }
    }

    private func returnBall(from paddleY: CGFloat, at ballY: CGFloat, towardCPU: Bool) {
        // Where the ball meets the paddle sets the angle: the middle sends it
        // back flat, the ends at up to 60 degrees. Every return is faster.
        let offset = ((ballY - paddleY) / (Self.paddleSize.height / 2 + Self.ballSize / 2)).clamped(to: -1...1)
        let angle = offset * Self.maxBounceAngle
        let speed = min(hypot(sim.velocity.dx, sim.velocity.dy) * Self.speedUp, Self.maxSpeed)
        sim.velocity = CGVector(dx: (towardCPU ? 1 : -1) * speed * cos(angle), dy: speed * sin(angle))
        if towardCPU { cpuAim = .random(in: -difficulty.aimError...difficulty.aimError) }
        onPaddleHit?()
    }

    private func score(playerWon: Bool) {
        if playerWon { sim.playerScore += 1 } else { sim.cpuScore += 1 }
        if max(sim.playerScore, sim.cpuScore) >= Self.pointsToWin {
            sim.phase = .over(playerWon: playerWon)
            sim.ball = Self.centre
            sim.velocity = .zero
            onMatchOver?(playerWon)
        } else {
            // The next serve goes to whoever lost the point.
            serve(towardPlayer: !playerWon)
        }
    }

    private func serve(towardPlayer: Bool) {
        serveTowardPlayer = towardPlayer
        sim.ball = Self.centre
        sim.velocity = .zero
        sim.phase = .serving(remaining: Self.serveDelay)
    }

    private func launch() {
        let angle = CGFloat.random(in: -0.4...0.4)
        sim.velocity = CGVector(
            dx: (serveTowardPlayer ? -1 : 1) * Self.serveSpeed * cos(angle),
            dy: Self.serveSpeed * sin(angle)
        )
        sim.phase = .playing
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
