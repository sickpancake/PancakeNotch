/// The three visual states of the notch (ADR-0011).
public enum NotchState: String, Sendable, CaseIterable, Comparable {
    /// Exactly the hardware notch: solid black, effectively invisible.
    case closed
    /// The notch grows small "ears" left and right for live info (e.g. album art while music plays).
    case compact
    /// The full panel.
    case expanded

    private var size: Int {
        switch self {
        case .closed: 0
        case .compact: 1
        case .expanded: 2
        }
    }

    public static func < (lhs: NotchState, rhs: NotchState) -> Bool { lhs.size < rhs.size }
}

/// User-adjustable notch behavior (Settings).
public struct NotchBehavior: Equatable, Sendable {
    /// How long the pointer must rest on the notch before it opens.
    public var openDelay: Duration
    /// How long after the pointer leaves before the notch closes.
    public var closeDelay: Duration
    /// Tap the trackpad lightly when the notch opens on hover.
    public var hapticOnOpen: Bool

    public init(openDelay: Duration = .milliseconds(150), closeDelay: Duration = .milliseconds(300), hapticOnOpen: Bool = false) {
        self.openDelay = openDelay
        self.closeDelay = closeDelay
        self.hapticOnOpen = hapticOnOpen
    }
}
