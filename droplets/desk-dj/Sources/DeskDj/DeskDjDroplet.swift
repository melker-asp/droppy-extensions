import AVFoundation
import Combine
import DroppyKit
import SwiftUI

@objc(DeskDjPrincipal)
public final class DeskDjPrincipal: NSObject, DropletPrincipal {
    public override init() { super.init() }
    @MainActor public func makeDroplet() -> AnyObject { DeskDjDroplet() }
}

enum Soundscape: String, CaseIterable, Codable, Identifiable {
    case rain, cafe, fireplace, brownNoise, drift
    var id: String { rawValue }
    var title: String { switch self { case .rain: "Rain"; case .cafe: "Cafe"; case .fireplace: "Fireplace"; case .brownNoise: "Brown noise"; case .drift: "Drift" } }
    var symbol: String { switch self { case .rain: "cloud.rain.fill"; case .cafe: "cup.and.saucer.fill"; case .fireplace: "flame.fill"; case .brownNoise: "waveform"; case .drift: "wind" } }
}

/// Generates looping ambient buffers, so Desk DJ needs no downloaded recordings.
final class AmbientEngine {
    private let engine = AVAudioEngine()
    private var players: [Soundscape: AVAudioPlayerNode] = [:]
    private var isPrepared = false

    func setVolume(_ volume: Float, for sound: Soundscape) {
        prepareIfNeeded()
        players[sound]?.volume = volume
    }

    func stop() { engine.stop(); isPrepared = false; players.removeAll() }

    private func prepareIfNeeded() {
        guard !isPrepared else { return }
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        for sound in Soundscape.allCases {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            player.scheduleBuffer(makeBuffer(for: sound, format: format), at: nil, options: .loops)
            player.play()
            players[sound] = player
        }
        do { try engine.start(); isPrepared = true }
        catch { players.values.forEach { $0.stop() }; players.removeAll() }
    }

    private func makeBuffer(for sound: Soundscape, format: AVAudioFormat) -> AVAudioPCMBuffer {
        let frames: AVAudioFrameCount = 88_200
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let left = buffer.floatChannelData![0]
        let right = buffer.floatChannelData![1]
        var seed: UInt32 = UInt32(sound.rawValue.utf8.reduce(17) { ($0 &* 31) &+ UInt32($1) })
        var smooth: Float = 0
        for frame in 0..<Int(frames) {
            seed = 1_664_525 &* seed &+ 1_013_904_223
            let white = Float(seed & 0xffff) / 32_767.5 - 1
            smooth = smooth * 0.985 + white * 0.015
            let time = Float(frame) / Float(format.sampleRate)
            let sample: Float
            switch sound {
            case .rain: sample = white * 0.24 + smooth * 0.55
            case .cafe: sample = smooth * 1.4 + sin(time * 2 * .pi * 196) * 0.025
            case .fireplace: sample = smooth * 0.45 + (abs(white) > 0.91 ? white * 0.55 : 0)
            case .brownNoise: sample = smooth * 2.7
            case .drift: sample = sin(time * 2 * .pi * 220) * 0.10 + sin(time * 2 * .pi * 277.18) * 0.06 + smooth * 0.12
            }
            left[frame] = sample; right[frame] = sample * 0.97
        }
        return buffer
    }
}

@MainActor
public final class DeskDjDroplet: NSObject, ObservableObject, Droplet {
    public nonisolated static let id: DropletID = "desk-dj"
    static let widgetID: ShelfWidgetID = "mixer"
    static let mixerSurface: ExpandedSurfaceID = "mixer"

    private var host: DropletHost?
    private let audio = AmbientEngine()
    private var mixerPresentation: ExpandedSurfacePresentation?
    @Published private(set) var levels: [Soundscape: Double] = [:]

    public func activate(host: DropletHost) throws {
        self.host = host
        for sound in Soundscape.allCases {
            let level = host.preferences.value(forKey: "level.\(sound.rawValue)", default: defaultLevel(for: sound))
            levels[sound] = level; audio.setVolume(Float(level), for: sound)
        }
    }

    public func deactivate() {
        if mixerPresentation != nil { host?.notchSurface.dismissExpandedSurface(Self.mixerSurface) }
        mixerPresentation = nil; host?.shelf.setHoldsOpen(false); audio.stop(); host = nil
    }

    func level(for sound: Soundscape) -> Double { levels[sound, default: 0] }
    func levelBinding(for sound: Soundscape) -> Binding<Double> { Binding(get: { self.level(for: sound) }, set: { self.setLevel($0, for: sound) }) }
    func setLevel(_ level: Double, for sound: Soundscape) {
        let value = min(max(level, 0), 1)
        levels[sound] = value; audio.setVolume(Float(value), for: sound)
        host?.preferences.setValue(value, forKey: "level.\(sound.rawValue)")
    }
    func toggle(_ sound: Soundscape) { setLevel(level(for: sound) > 0 ? 0 : defaultLevel(for: sound), for: sound) }
    func stopAll() { Soundscape.allCases.forEach { setLevel(0, for: $0) }; host?.shelf.setHoldsOpen(false) }
    func openMixer() {
        guard let host, mixerPresentation == nil else { return }
        mixerPresentation = host.notchSurface.presentExpandedSurface(ExpandedSurfacePresentationRequest(surfaceID: Self.mixerSurface, opensShelf: true))
        host.shelf.setHoldsOpen(true)
    }
    func closeMixer() { host?.notchSurface.dismissExpandedSurface(Self.mixerSurface) }
    private func defaultLevel(for sound: Soundscape) -> Double { switch sound { case .rain: 0.28; case .cafe, .fireplace, .brownNoise, .drift: 0 } }
}

extension DeskDjDroplet: ShelfWidgetProviding {
    public var widgetDescriptors: [ShelfWidgetDescriptor] { [ShelfWidgetDescriptor(id: Self.widgetID, title: "Desk DJ", systemImage: "waveform", layoutTraits: ShelfWidgetLayoutTraits(preferredSoloWidth: 390, preferredPairedWidth: 180, contentHeight: .fixed(94)), searchKeywords: ["sound", "ambient", "focus", "rain", "noise"])] }
    public func makeWidgetView(_ id: ShelfWidgetID, context: ShelfWidgetContext) -> AnyView { AnyView(DeskDjWidget(droplet: self, context: context)) }
    public func makeWidgetSettingsPopover(_ id: ShelfWidgetID) -> AnyView? { nil }
}

extension DeskDjDroplet: ExpandedSurfaceHosting { public var expandedSurfaceProvider: (any ExpandedSurfaceProviding)? { self } }
extension DeskDjDroplet: ExpandedSurfaceProviding {
    public var expandedSurfaces: [ExpandedSurfaceDescriptor] { [ExpandedSurfaceDescriptor(id: Self.mixerSurface, title: "Desk DJ", systemImage: "waveform", suppresses: [.shelfWidgets, .autoCollapse])] }
    public func makeExpandedSurfaceView(_ id: ExpandedSurfaceID, context: ExpandedSurfaceContext) -> AnyView { AnyView(DeskDjMixer(droplet: self)) }
    public func expandedSurfaceSize(_ id: ExpandedSurfaceID, fitting proposal: ExpandedSurfaceSizeProposal) -> CGSize? { CGSize(width: min(460, proposal.maximumSize.width), height: min(330, proposal.maximumSize.height)) }
    public func expandedSurfaceDidDismiss(_ id: ExpandedSurfaceID, presentation: ExpandedSurfacePresentation, reason: ExpandedSurfaceDismissalReason) {
        guard presentation.id == mixerPresentation?.id else { return }; mixerPresentation = nil; host?.shelf.setHoldsOpen(false)
    }
}

private struct DeskDjWidget: View {
    @ObservedObject var droplet: DeskDjDroplet
    let context: ShelfWidgetContext
    var active: [Soundscape] { Soundscape.allCases.filter { droplet.level(for: $0) > 0.01 } }
    var body: some View {
        VStack(alignment: .leading, spacing: DroppySpacing.sm) {
            HStack(spacing: DroppySpacing.xsm) {
                Image(systemName: "waveform").font(.system(size: 12, weight: .medium)); Text("Desk DJ").font(.system(size: 12, weight: .semibold)); Spacer(minLength: 0)
                Button(action: droplet.openMixer) { Image(systemName: "slider.horizontal.3") }.buttonStyle(DroppyCircleButtonStyle(size: 20)).accessibilityLabel("Open mixer")
            }.foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
            if context.isCompact {
                Text(active.isEmpty ? "Quiet" : "\(active.count) live").font(.system(size: 20, weight: .semibold, design: .rounded)).foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
            } else {
                HStack(spacing: DroppySpacing.md) {
                    Text(active.isEmpty ? "Choose a soundscape" : active.map(\.title).joined(separator: " · ")).lineLimit(1).font(.system(size: 14, weight: .medium)).foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                    Spacer(minLength: 0); Button("Mix", action: droplet.openMixer).buttonStyle(DroppyAccentButtonStyle(size: .small))
                }
            }; Spacer(minLength: 0)
        }.padding(context.contentInsets).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct DeskDjMixer: View {
    @ObservedObject var droplet: DeskDjDroplet
    var body: some View {
        VStack(alignment: .leading, spacing: DroppySpacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: 2) { Text("Desk DJ").font(.system(size: 19, weight: .semibold, design: .rounded)); Text("Build a room that helps you stay put.").font(.system(size: 12)).foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText) }
                Spacer()
                Button(action: droplet.stopAll) { Image(systemName: "stop.fill") }.buttonStyle(DroppyCircleButtonStyle(size: 24)).accessibilityLabel("Stop all sounds")
                Button(action: droplet.closeMixer) { Image(systemName: "xmark") }.buttonStyle(DroppyCircleButtonStyle(size: 24)).accessibilityLabel("Close mixer")
            }
            VStack(spacing: 0) {
                ForEach(Soundscape.allCases) { sound in
                    if sound != Soundscape.allCases.first { Divider().padding(.leading, 32) }
                    HStack(spacing: DroppySpacing.sm) {
                        Button { droplet.toggle(sound) } label: { Image(systemName: sound.symbol).frame(width: 18) }.buttonStyle(DroppyCircleButtonStyle(size: 20)).accessibilityLabel("Toggle \(sound.title)")
                        Text(sound.title).font(.system(size: 14, weight: .medium)).frame(width: 92, alignment: .leading)
                        Slider(value: droplet.levelBinding(for: sound), in: 0...1).tint(AdaptiveColors.notchSurfacePrimaryText)
                        Text("\(Int(droplet.level(for: sound) * 100))%").font(.system(size: 12, design: .rounded)).monospacedDigit().foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText).frame(width: 32, alignment: .trailing)
                    }.padding(.vertical, DroppySpacing.xs)
                }
            }
        }.padding(DroppySpacing.lg).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
