import AgentsCore
import SwiftUI

/// Text that may be an email: the part before the @ (after its first letter) is blurred until clicked
/// (ADR-0037). The blur covers stand-in letters, not the real ones, so nothing can be read back from it.
/// Other text shows as it is. Fonts and line limits come from the surrounding view.
public struct PrivateText: View {
    private let text: String
    private let revealed: Bool
    private let toggle: (() -> Void)?

    /// - Parameter toggle: shows or hides it on click; nil when a click should do something else (a button
    ///   around it).
    public init(_ text: String, revealed: Bool, toggle: (() -> Void)? = nil) {
        self.text = text
        self.revealed = revealed
        self.toggle = toggle
    }

    private static let standIn = "mxkqrtwbnzhlpdvs"

    public var body: some View {
        if let parts = EmailPrivacy.parts(text) {
            Group {
                if revealed {
                    Text(text)
                } else {
                    HStack(spacing: 0) {
                        Text(parts.first)
                        Text(Self.standIn.prefix(min(max(parts.hidden.count, 4), Self.standIn.count)))
                            .blur(radius: 3.5)
                        Text(parts.domain)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { toggle?() }
            .allowsHitTesting(toggle != nil)
            .help(toggle == nil ? Text(verbatim: "") : revealed ? Text("Click to hide") : Text("Click to show"))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(revealed ? Text(text) : Text("\(EmailPrivacy.masked(text)), partly hidden"))
            .accessibilityAddTraits(toggle == nil ? [] : .isButton)
            .accessibilityAction { toggle?() }
        } else {
            Text(text)
        }
    }
}
