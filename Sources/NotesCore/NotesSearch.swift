import Foundation

/// Finding notes by what's in them. Every word you type has to appear somewhere in the note (in any
/// order), ignoring upper and lower case and accents, so "cafe groc" finds "Groceries … Café".
public struct NotesSearch: Equatable, Sendable {
    /// The words typed, without spaces or repeats.
    public let terms: [String]
    public let scope: NotesSearchScope

    static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]

    public init(_ query: String, scope: NotesSearchScope = .titleAndText) {
        var terms: [String] = []
        for word in query.split(whereSeparator: \.isWhitespace).map(String.init)
        where !terms.contains(where: { $0.compare(word, options: Self.options) == .orderedSame }) {
            terms.append(word)
        }
        self.terms = terms
        self.scope = scope
    }

    /// Nothing typed (or only spaces): every note shows.
    public var isEmpty: Bool { terms.isEmpty }

    /// Whether a note has every word, in its title (titles only) or anywhere in it.
    public func matches(_ note: Note) -> Bool {
        guard !isEmpty else { return true }
        let text = scope == .titlesOnly ? note.title : note.text
        return terms.allSatisfy { text.range(of: $0, options: Self.options) != nil }
    }

    /// The notes that match, in the order given (so pinned notes stay first). `keeping` stays in even
    /// when it no longer matches: the note you're writing in shouldn't vanish mid-sentence.
    public func filter(_ notes: [Note], keeping kept: Note.ID? = nil) -> [Note] {
        guard !isEmpty else { return notes }
        return notes.filter { $0.id == kept || matches($0) }
    }

    /// Where the typed words appear in some text, in order, with overlapping ones joined.
    public func ranges(in text: String) -> [Range<String.Index>] {
        guard !isEmpty, !text.isEmpty else { return [] }
        var found: [Range<String.Index>] = []
        for term in terms {
            var start = text.startIndex
            while start < text.endIndex,
                  let range = text.range(of: term, options: Self.options, range: start..<text.endIndex) {
                found.append(range)
                start = range.upperBound
            }
        }
        found.sort { $0.lowerBound < $1.lowerBound }
        var merged: [Range<String.Index>] = []
        for range in found {
            if let last = merged.last, range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    /// The same places as `ranges(in:)`, as `NSRange`s for AppKit text views.
    public func nsRanges(in text: String) -> [NSRange] {
        ranges(in: text).map { NSRange($0, in: text) }
    }

    /// A one-line preview that starts just before the first match, so a word deep in a long note shows
    /// in its row instead of being cut off at the end. Starts at a word, with "…" in front.
    public func snippet(of preview: String, lead: Int = 24) -> String {
        guard scope == .titleAndText, let first = ranges(in: preview).first else { return preview }
        let offset = preview.distance(from: preview.startIndex, to: first.lowerBound)
        guard offset > lead else { return preview }
        var start = preview.index(first.lowerBound, offsetBy: -20)
        if let space = preview[start..<first.lowerBound].firstIndex(where: \.isWhitespace) {
            start = preview.index(after: space)
        }
        return "…" + preview[start...]
    }

    /// Splits text into runs, each marked as a match or not, for drawing highlights.
    public func runs(in text: String) -> [(text: Substring, isMatch: Bool)] {
        var runs: [(text: Substring, isMatch: Bool)] = []
        var cursor = text.startIndex
        for range in ranges(in: text) {
            if cursor < range.lowerBound { runs.append((text[cursor..<range.lowerBound], false)) }
            runs.append((text[range], true))
            cursor = range.upperBound
        }
        if cursor < text.endIndex { runs.append((text[cursor...], false)) }
        return runs
    }
}
