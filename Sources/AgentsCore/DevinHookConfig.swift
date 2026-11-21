import Foundation

/// A JSONC token index. Edits change hook tokens, not the user's comments or other settings.
struct DevinHookConfig {
    enum EditError: Error { case invalidHooks }

    private struct Item {
        let key: String?
        let tokens: Range<Int>
        let value: Range<Int>
        let comma: Int?
    }

    private let bytes: [UInt8]
    private let json: [UInt8]
    private let tokens: [Range<Int>]
    private var edits: [(Range<Int>, [UInt8])] = []
    let object: [String: Any]

    init?(_ data: Data) {
        let bytes = Array(data)
        var json = bytes
        var tokens: [Range<Int>] = []
        let whitespace: Set<UInt8> = [9, 10, 13, 32]
        let punctuation: Set<UInt8> = [0x7B, 0x7D, 0x5B, 0x5D, 0x2C, 0x3A]
        var i = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? 3 : 0
        while i < bytes.count {
            let start = i, byte = bytes[i]
            i += 1
            if whitespace.contains(byte) { continue }
            if byte == 0x2F, i < bytes.count, bytes[i] == 0x2F || bytes[i] == 0x2A {
                let line = bytes[i] == 0x2F
                i += 1
                if line {
                    while i < bytes.count, bytes[i] != 10, bytes[i] != 13 { i += 1 }
                } else {
                    while i + 1 < bytes.count, bytes[i] != 0x2A || bytes[i + 1] != 0x2F { i += 1 }
                    guard i + 1 < bytes.count else { return nil }
                    i += 2
                }
                for index in start..<i { json[index] = 32 }
                continue
            }
            if byte == 0x22 {
                while i < bytes.count {
                    let next = bytes[i]
                    i += 1
                    if next == 0x22 { break }
                    if next == 0x5C { i += 1 }
                }
                guard i <= bytes.count else { return nil }
            } else if !punctuation.contains(byte) {
                while i < bytes.count, !whitespace.contains(bytes[i]),
                      !punctuation.contains(bytes[i]), bytes[i] != 0x2F, bytes[i] != 0x22 { i += 1 }
            }
            tokens.append(start..<i)
        }
        guard let object = try? JSONSerialization.jsonObject(with: Data(json)) as? [String: Any],
              !tokens.isEmpty, bytes[tokens[0].lowerBound] == 0x7B else { return nil }
        self.bytes = bytes
        self.json = json
        self.tokens = tokens
        self.object = object
    }

    mutating func update(entries: [(name: String, group: [String: Any])], connect: Bool) throws -> Data {
        let root = items(in: 0..<tokens.count)
        let hookMembers = root.indices.filter { root[$0].key == "hooks" }
        let hooks = hookMembers.last.map { root[$0] }
        let groups = try entries.map { (name: $0.name, json: try encode($0.group)) }
        let newGroups = Dictionary(uniqueKeysWithValues: groups.map { ($0.name, $0.json) })
        let newEvents = groups.map { "\"\($0.name)\": [\($0.json)]" }

        if let hooks, byte(hooks.value.lowerBound) == 0x7B {
            let events = items(in: hooks.value)
            var removed: Set<Int> = []
            for (index, event) in events.enumerated() {
                guard let name = event.key, let group = newGroups[name] else { continue }
                guard byte(event.value.lowerBound) == 0x5B else {
                    if connect { throw EditError.invalidHooks }
                    continue
                }
                if updateGroups(in: event.value, adding: connect ? group : nil) { removed.insert(index) }
            }
            let added = connect ? zip(entries, newEvents).compactMap { entry, text in
                events.contains { $0.key == entry.name } ? nil : text
            } : []
            if removed.count == events.count, !events.isEmpty, let index = hookMembers.first, hookMembers.count == 1 {
                // Discard nested edits when removing the whole member.
                edits.removeAll()
                edit(root, in: 0..<tokens.count, removing: [index])
            } else {
                edit(events, in: hooks.value, removing: removed, adding: added)
            }
        } else if connect {
            guard hooks == nil else { throw EditError.invalidHooks }
            let property = "\"hooks\": {\n  " + newEvents.joined(separator: ",\n  ") + "\n}"
            edit(root, in: 0..<tokens.count, adding: [property])
        }
        var output = bytes
        for (range, replacement) in edits.sorted(by: {
            ($0.0.lowerBound, $0.0.upperBound) > ($1.0.lowerBound, $1.0.upperBound)
        }) {
            output.replaceSubrange(range, with: replacement)
        }
        return Data(output)
    }

    /// Returns true when removing the entire event. Its parent then removes its tokens.
    private mutating func updateGroups(in array: Range<Int>, adding group: String?) -> Bool {
        let groups = items(in: array)
        var removed: Set<Int> = []
        for (index, item) in groups.enumerated() {
            guard byte(item.value.lowerBound) == 0x7B else { continue }
            if isOurs(item) {
                removed.insert(index)
                continue
            }
            guard let hooks = items(in: item.value).last(where: { $0.key == "hooks" }),
                  byte(hooks.value.lowerBound) == 0x5B else { continue }
            let handlers = items(in: hooks.value)
            let ours = Set(handlers.indices.filter { isOurs(handlers[$0]) })
            if !ours.isEmpty, ours.count == handlers.count {
                removed.insert(index)
            } else {
                edit(handlers, in: hooks.value, removing: ours)
            }
        }
        if group == nil, !removed.isEmpty, removed.count == groups.count { return true }
        edit(groups, in: array, removing: removed, adding: group.map { [$0] } ?? [])
        return false
    }

    private func isOurs(_ item: Item) -> Bool {
        let range = tokens[item.value.lowerBound].lowerBound..<tokens[item.value.upperBound - 1].upperBound
        let value = try? JSONSerialization.jsonObject(with: Data(json[range]), options: .fragmentsAllowed)
        return HookFile.isOurs((value as? [String: Any])?["command"] as? String)
    }

    private func encode(_ group: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: group, options: [.sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }

    private func byte(_ token: Int) -> UInt8 { bytes[tokens[token].lowerBound] }

    private func items(in container: Range<Int>) -> [Item] {
        let keyed = byte(container.lowerBound) == 0x7B
        let end = container.upperBound - 1
        var i = container.lowerBound + 1
        var result: [Item] = []
        while i < end {
            let start = i
            let key = keyed ? (try? JSONSerialization.jsonObject(with: Data(json[tokens[i]]), options: .fragmentsAllowed)) as? String : nil
            if keyed { i += 2 }
            let valueStart = i
            var depth = 0
            repeat {
                switch byte(i) {
                case 0x7B, 0x5B: depth += 1
                case 0x7D, 0x5D: depth -= 1
                default: break
                }
                i += 1
            } while depth > 0 && i < end
            let comma = i < end && byte(i) == 0x2C ? i : nil
            result.append(Item(key: key, tokens: start..<i, value: valueStart..<i, comma: comma))
            if comma != nil { i += 1 }
        }
        return result
    }

    private mutating func edit(_ items: [Item], in container: Range<Int>, removing: Set<Int> = [], adding: [String] = []) {
        guard !removing.isEmpty || !adding.isEmpty else { return }
        let kept = items.indices.filter { !removing.contains($0) }
        let trailingComma = items.last?.comma != nil
        for (index, item) in items.enumerated() {
            if removing.contains(index) {
                let span = tokens[item.tokens.lowerBound].lowerBound..<tokens[item.tokens.upperBound - 1].upperBound
                if bytes[span].elementsEqual(json[span]) {
                    edits.append((span, []))
                } else {
                    for token in item.tokens { edits.append((tokens[token], [])) }
                }
            }
            if let comma = item.comma,
               removing.contains(index) || (index == kept.last && !trailingComma && adding.isEmpty) {
                edits.append((tokens[comma], []))
            }
        }
        guard !adding.isEmpty else { return }
        let close = tokens[container.upperBound - 1].lowerBound
        var line = close
        while line > 0, bytes[line - 1] == 32 || bytes[line - 1] == 9 { line -= 1 }
        // Append after any trailing comments so they remain next to the user's last entry.
        let ownLine = line > 0 && (bytes[line - 1] == 10 || bytes[line - 1] == 13)
        let indent = ownLine ? String(decoding: bytes[line..<close], as: UTF8.self) : ""
        let childIndent = indent + "  "
        let text = adding.map { childIndent + $0.replacingOccurrences(of: "\n", with: "\n" + childIndent) }
            .joined(separator: ",\n")
        let addition = (ownLine ? "" : "\n") + text + (trailingComma ? "," : "") + "\n"
        let position = ownLine ? line : close
        let separator = kept.last.flatMap { items[$0].comma == nil ? tokens[items[$0].tokens.upperBound - 1].upperBound : nil }
        if let separator, separator != position { edits.append((separator..<separator, [0x2C])) }
        edits.append((position..<position, Array(((separator == position ? "," : "") + addition).utf8)))
    }
}
