import Foundation
import Testing
@testable import Pong

@MainActor
struct PongGameTests {
    private func playing(ball: CGPoint, velocity: CGVector, playerY: CGFloat = PongGame.court.height / 2) -> PongState {
        var state = PongState()
        state.phase = .playing
        state.ball = ball
        state.velocity = velocity
        state.playerY = playerY
        return state
    }

    @Test func ballBouncesOffTheTopWall() {
        let game = PongGame()
        game.load(playing(ball: CGPoint(x: 280, y: 10), velocity: CGVector(dx: 100, dy: -200)))
        game.advance(by: 0.1)
        #expect(game.state.velocity.dy > 0)
        #expect(game.state.ball.y >= PongGame.ballSize / 2)
    }

    @Test func playerPaddleReturnsTheBallFaster() {
        let game = PongGame()
        var hits = 0
        game.onPaddleHit = { hits += 1 }
        game.load(playing(ball: CGPoint(x: 60, y: 100), velocity: CGVector(dx: -300, dy: 0), playerY: 100))
        game.advance(by: 0.2)
        #expect(hits == 1)
        #expect(game.state.velocity.dx > 300)
        #expect(game.state.playerScore == 0 && game.state.cpuScore == 0)
    }

    @Test func offCentreHitSendsTheBallAtAnAngle() {
        let game = PongGame()
        game.load(playing(ball: CGPoint(x: 60, y: 115), velocity: CGVector(dx: -300, dy: 0), playerY: 100))
        game.advance(by: 0.2)
        #expect(game.state.velocity.dx > 0)
        #expect(game.state.velocity.dy > 0)
    }

    @Test func aMissScoresForTheCPUAndServesAgain() {
        let game = PongGame()
        game.load(playing(ball: CGPoint(x: 60, y: 180), velocity: CGVector(dx: -300, dy: 0), playerY: 20))
        game.advance(by: 0.5)
        #expect(game.state.cpuScore == 1)
        guard case .serving = game.state.phase else {
            Issue.record("expected a serve, got \(game.state.phase)")
            return
        }
        #expect(game.state.ball == PongGame.centre)
    }

    @Test func theMatchEndsAtElevenPoints() {
        let game = PongGame()
        var result: Bool?
        game.onMatchOver = { result = $0 }
        var state = playing(ball: CGPoint(x: 60, y: 180), velocity: CGVector(dx: -300, dy: 0), playerY: 20)
        state.cpuScore = PongGame.pointsToWin - 1
        game.load(state)
        game.advance(by: 0.5)
        #expect(game.state.phase == .over(playerWon: false))
        #expect(result == false)
    }

    @Test func pausingFreezesTheRally() {
        let game = PongGame()
        game.load(playing(ball: CGPoint(x: 280, y: 100), velocity: CGVector(dx: 200, dy: 0)))
        game.primaryAction()
        game.advance(by: 0.5)
        #expect(game.state.isPaused)
        #expect(game.state.ball == CGPoint(x: 280, y: 100))
    }

    @Test func thePaddleFollowsThePointerAtOnceBetweenRallies() {
        let game = PongGame()
        game.steer(toward: 30)
        #expect(game.state.playerY == 30)
        game.steer(toward: 0)
        #expect(game.state.playerY == PongGame.paddleSize.height / 2)
    }

    @Test func midRallyThePaddleChasesThePointerAtCappedSpeed() {
        let game = PongGame()
        game.load(playing(ball: CGPoint(x: 280, y: 100), velocity: CGVector(dx: 100, dy: 0), playerY: 100))
        game.steer(toward: 170)
        #expect(game.state.playerY == 100)
        game.advance(by: 0.02)
        #expect(game.state.playerY > 100 && game.state.playerY < 170)
        game.advance(by: 0.2)
        #expect(game.state.playerY == 170)
    }

    @Test func aClickServesThenStartsTheRally() {
        let game = PongGame()
        game.primaryAction()
        guard case .serving = game.state.phase else {
            Issue.record("expected a serve, got \(game.state.phase)")
            return
        }
        game.advance(by: PongGame.serveDelay + 0.05)
        #expect(game.state.phase == .playing)
        #expect(abs(game.state.velocity.dx) > 0)
    }
}
