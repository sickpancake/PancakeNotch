import Foundation

struct NotesEditorCountInput: Sendable {
    let text: String
    let selection: NSRange

    func measure() -> NotesEditorCounts? {
        guard !Task.isCancelled else { return nil }
        if selection.length > 0 {
            let text = text as NSString
            if selection.location >= 0, selection.location <= text.length,
               selection.length <= text.length - selection.location {
                return NotesEditorCounts.measure(text.substring(with: selection), isSelection: true)
            }
        }
        return NotesEditorCounts.measure(text)
    }

    func measureAfterPause() async -> NotesEditorCounts? {
        do { try await Task.sleep(for: .milliseconds(200)) } catch { return nil }
        // Tokenize off the main actor so a large paste doesn't interrupt typing.
        let worker = Task.detached(priority: .utility) { measure() }
        let result = await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
        return Task.isCancelled ? nil : result
    }
}

struct NotesEditorCounts: Equatable, Sendable {
    let words: Int
    let characters: Int
    let items: Int
    let isSelection: Bool

    static let empty = NotesEditorCounts(words: 0, characters: 0, items: 0, isSelection: false)

    static func measure(_ text: String, isSelection: Bool = false) -> NotesEditorCounts? {
        guard !Task.isCancelled else { return nil }
        var words = 0
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.byWords, .substringNotRequired]) { _, _, _, stop in
            words += 1
            stop = Task.isCancelled
        }
        guard !Task.isCancelled else { return nil }
        let characters = text.count
        guard !Task.isCancelled, let items = isSelection ? 0 : countItems(in: text) else { return nil }
        return NotesEditorCounts(words: words, characters: characters, items: items, isSelection: isSelection)
    }

    var summary: String {
        let wordCount = words == 1 ? String(localized: "1 word", comment: "Notes editor word count")
            : String(localized: "\(words) words", comment: "Notes editor word count")
        let characterCount = characters == 1 ? String(localized: "1 character", comment: "Notes editor character count")
            : String(localized: "\(characters) characters", comment: "Notes editor character count")
        if isSelection {
            return String(localized: "Selection · \(wordCount) · \(characterCount)", comment: "Notes editor counts for selected text")
        }
        if items > 0 {
            let itemCount = items == 1 ? String(localized: "1 item", comment: "Notes editor list item count")
                : String(localized: "\(items) items", comment: "Notes editor list item count")
            return String(localized: "\(itemCount) · \(wordCount) · \(characterCount)", comment: "Notes editor counts for a note with list items")
        }
        return String(localized: "\(wordCount) · \(characterCount)", comment: "Notes editor counts for a note")
    }

    private static func countItems(in text: String) -> Int? {
        var items = 0
        var remaining = text[...]
        while let end = remaining.firstIndex(where: \.isNewline) {
            guard !Task.isCancelled else { return nil }
            if isListItem(remaining[..<end]) { items += 1 }
            remaining = remaining[remaining.index(after: end)...]
        }
        guard !Task.isCancelled else { return nil }
        return isListItem(remaining) ? items + 1 : items
    }

    private static func isListItem(_ line: Substring) -> Bool {
        let content = line.drop(while: \.isWhitespace)
        guard let first = content.first else { return false }
        let afterMarker: Substring
        if "-*+•".contains(first) {
            afterMarker = content.dropFirst()
        } else {
            let afterNumber = content.drop(while: { $0.isASCII && $0.isNumber })
            guard afterNumber.startIndex != content.startIndex,
                  let marker = afterNumber.first, marker == "." || marker == ")" else { return false }
            afterMarker = afterNumber.dropFirst()
        }
        return afterMarker.first?.isWhitespace == true && afterMarker.contains { !$0.isWhitespace }
    }
}
