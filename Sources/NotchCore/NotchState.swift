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
