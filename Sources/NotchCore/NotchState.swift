/// The three visual states of the notch (ADR-0011).
public enum NotchState: String, Sendable, CaseIterable {
    /// Exactly the hardware notch: solid black, effectively invisible.
    case closed
    /// The notch grows small "ears" left and right for live info (e.g. album art while music plays).
    case compact
    /// The full panel.
    case expanded
}
