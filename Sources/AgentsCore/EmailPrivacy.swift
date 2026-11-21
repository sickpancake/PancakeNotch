import Foundation

/// Emails are shown half hidden (ADR-0037): the part before the @, after its first letter, stays hidden
/// until the person clicks it, so a glance or a screen share doesn't give the address away.
public enum EmailPrivacy {
    /// "sam@studio.dev" → ("s", "am", "@studio.dev"); nil when the text isn't an email.
    public static func parts(_ text: String) -> (first: String, hidden: String, domain: String)? {
        guard let at = text.firstIndex(of: "@"), at != text.startIndex, text.index(after: at) != text.endIndex,
              !text.contains(" ") else { return nil }
        let second = text.index(after: text.startIndex)
        return (String(text[..<second]), String(text[second..<at]), String(text[at...]))
    }

    /// "s•••@studio.dev", for plain text (peeks, VoiceOver, menus). Other text comes back as it is.
    public static func masked(_ text: String) -> String {
        guard let parts = parts(text) else { return text }
        return parts.first + String(repeating: "•", count: min(max(parts.hidden.count, 3), 8)) + parts.domain
    }
}
