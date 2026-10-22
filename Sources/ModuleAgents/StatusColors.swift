import AgentsCore
import SwiftUI

/// The few colors Agents and AI Usage use (ADR-0029, amended 2026-10-22): only on small status marks and
/// gauges, so a glance tells them apart. Backgrounds and text stay black, white and gray. The notch is
/// always dark, so these are the system colors' dark-mode values.
public enum StatusColors {
    public static let blue = Color(red: 10 / 255, green: 132 / 255, blue: 1)
    public static let orange = Color(red: 1, green: 159 / 255, blue: 10 / 255)
    public static let green = Color(red: 48 / 255, green: 209 / 255, blue: 88 / 255)
    public static let yellow = Color(red: 1, green: 214 / 255, blue: 10 / 255)
    public static let red = Color(red: 1, green: 69 / 255, blue: 58 / 255)
    public static let gray = Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255)

    /// Working blue, needs you orange, done green, stopped gray, error red.
    public static func color(for status: AgentStatus) -> Color {
        switch status {
        case .working: blue
        case .needsYou: orange
        case .done: green
        case .stopped: gray
        case .failed: red
        }
    }

    /// A limit's color by how much is left (0…100): green from half, yellow from 20%, orange from 10%, then red.
    public static func color(left percent: Double) -> Color {
        switch percent {
        case 50...: green
        case 20..<50: yellow
        case 10..<20: orange
        default: red
        }
    }
}
