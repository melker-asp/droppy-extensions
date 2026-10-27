//
//  PointerPad.swift
//  Pong
//
//  The court's controller: the pointer. An AppKit view with an always-active
//  tracking area, because Droppy's notch panel is rarely the key window, and
//  tracking that only runs in the key window would never see the pointer.
//

import AppKit
import SwiftUI

struct PointerPad: NSViewRepresentable {
    /// The pointer's height from the top of the view, and the view's size.
    let onMove: (_ y: CGFloat, _ size: CGSize) -> Void
    let onClick: () -> Void
    let onExit: () -> Void

    func makeNSView(context: Context) -> PointerPadView {
        let view = PointerPadView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: PointerPadView, context: Context) {
        view.onMove = onMove
        view.onClick = onClick
        view.onExit = onExit
    }
}

final class PointerPadView: NSView {
    var onMove: ((CGFloat, CGSize) -> Void)?
    var onClick: (() -> Void)?
    var onExit: (() -> Void)?

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { report(event) }
    override func mouseMoved(with event: NSEvent) { report(event) }
    override func mouseDragged(with event: NSEvent) { report(event) }
    override func mouseExited(with event: NSEvent) { onExit?() }

    override func mouseDown(with event: NSEvent) {
        report(event)
        onClick?()
    }

    private func report(_ event: NSEvent) {
        onMove?(convert(event.locationInWindow, from: nil).y, bounds.size)
    }
}
