import AppKit
import SwiftUI
import Testing
@testable import NotchCore

/// Opt-in native hit testing: window event delivery can block on a busy/headless Mac.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["PANCAKENOTCH_HIT_PROBE"] == "1"))
@MainActor struct HomeHoldHitTests {
    private var buttonPresses = Counter()
    /// E = editing started, o = a module opened instead, c = notch closed, . = nothing.
    func hold(at fromTop: CGFloat, _ fx: CGFloat, ms: Int, roundButton: Bool = false) async throws -> String {
        let layout = NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982)))
        let m = NotchViewModel(layout: layout)
        m.snapshotClock = Date(timeIntervalSince1970: 0) // No native outside-click monitors in a synthetic window.
        m.modules = [RankedModule("timer")]
        m.home.opening = .home
        m.home.layout = HomeLayout(placements: [
            .init(kind: .nowPlaying, size: .large, slot: .init(page: 0, column: 0, row: 0)),
            .init(kind: .clock, size: .medium, slot: .init(page: 0, column: 2, row: 0)),
            .init(kind: .battery, size: .small, slot: .init(page: 0, column: 2, row: 1)),
            .init(kind: .keepAwake, size: .small, slot: .init(page: 0, column: 3, row: 1)),
            .init(kind: .agents, size: .large, slot: .init(page: 0, column: 4, row: 0)),
            .init(kind: .statistics, size: .small, slot: .init(page: 1, column: 0, row: 0))
        ])
        m.homeExtras = { kind, _, _ in
            guard kind == .battery else { return nil }
            if roundButton {
                return AnyView(NotchRoundButton(symbol: "play.fill", label: "Probe play") {
                    buttonPresses.value += 1
                }.frame(maxWidth: .infinity, maxHeight: .infinity))
            }
            return AnyView(Button { buttonPresses.value += 1 } label: {
                Text("Probe button").frame(maxWidth: .infinity, maxHeight: .infinity)
            }.buttonStyle(.plain))
        }
        m.open()
        m.hoverChanged(true)
        let frame = layout.windowFrame(for: .expanded)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: NotchView(model: m))
        host.frame = CGRect(origin: .zero, size: frame.size)
        window.contentView = host
        window.setFrameOrigin(CGPoint(x: -8000, y: -8000))
        window.orderFrontRegardless()
        defer { window.orderOut(nil); m.endHomeEditing() }
        try await Task.sleep(for: .milliseconds(150))
        let shape = layout.shapeSize(for: .expanded)
        let point = CGPoint(x: (frame.width - shape.width) / 2 + shape.width * fx, y: frame.height - fromTop)
        func send(_ type: NSEvent.EventType) {
            window.sendEvent(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                                timestamp: ProcessInfo.processInfo.systemUptime,
                                                windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                                clickCount: 1, pressure: 1)!)
        }
        send(.leftMouseDown)
        try await Task.sleep(for: .milliseconds(ms))
        let editing = m.isEditingHome
        send(.leftMouseUp)
        try await Task.sleep(for: .milliseconds(80))
        if editing {
            let survived = m.isEditingHome
            if fromTop >= 166 || fx < 0.05 || fx > 0.95 {
                send(.leftMouseDown)
                send(.leftMouseUp)
                try await Task.sleep(for: .milliseconds(80))
                #expect(!m.isEditingHome && m.state == .expanded, "Margin click ends editing without closing Home")
            }
            return survived ? "E" : "e"
        }
        if m.state != .expanded { return "c" }
        return m.showsHome ? "." : "o"
    }

    @Test func holdAcrossBody() async throws {
        let points: [(String, CGFloat, CGFloat)] = [
            ("top margin", 36, 0.52), ("first row", 70, 0.38),
            ("gap", 103, 0.52), ("second row", 140, 0.52),
            ("bottom strip", 172, 0.52), ("right gutter", 140, 0.97), ("left gutter", 140, 0.04),
            ("real button", 140, 0.42)
        ]
        for (name, y, x) in points {
            let result = try await hold(at: y, x, ms: 650)
            print("HOME HOLD \(name): \(result)")
            #expect(result == "E", "Hold at \(name) must survive release")
        }
        let roundHold = try await hold(at: 140, 0.42, ms: 650, roundButton: true)
        print("HOME HOLD NotchRoundButton: \(roundHold)")
        #expect(roundHold == "E")
        #expect(buttonPresses.value == 0, "Hold release must not activate either widget button")
        let click = try await hold(at: 140, 0.42, ms: 50)
        #expect(click == ".")
        #expect(buttonPresses.value == 1, "A quick click must still activate the real widget button")
        let roundClick = try await hold(at: 140, 0.42, ms: 50, roundButton: true)
        #expect(roundClick == ".")
        #expect(buttonPresses.value == 2, "A quick click must still activate NotchRoundButton")
    }
}

@MainActor private final class Counter { var value = 0 }
