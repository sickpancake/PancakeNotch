import Foundation

/// A deliberately small data reader, never a JavaScript evaluator. Recognizes literal arguments and
/// the recorded T3 batch shape (`const tasks = […]; tasks.map(async task => …({...task,…}))`).
/// Calls, interpolation, computed properties and unknown expressions cannot become task evidence.
enum DelegationScript {
    static func inputs(_ source: String) -> [[String: Any]] {
        guard source.utf8.count <= 4 * 1024 * 1024 else { return [] }
        var reader = Reader(source)
        var constants: [String: Any] = [:]
        var result: [[String: Any]] = []
        let tool = ["tools", ".", "mcp__t3_code__delegate_task", "("]
        while let token = reader.peek {
            if token == ";" { reader.index += 1; continue }
            if token == "const" {
                reader.index += 1
                guard let name = reader.take(), reader.consume(["="]), let value = reader.value(constants),
                      reader.peek == ";" || reader.peek == nil else { return [] }
                constants[name] = value
            } else if reader.consume(["await", "Promise", ".", "all", "("]) {
                guard let array = reader.take(), let values = constants[array] as? [[String: Any]],
                      reader.consume([".", "map", "(", "async"]), let parameter = reader.take(),
                      reader.consume(["=>", "{", "const"]), let variable = reader.take(),
                      reader.consume(["=", "await"] + tool) else { return [] }
                let start = reader.index
                var end: Int?
                for value in values {
                    var scope = constants; scope[parameter] = value
                    reader.index = start
                    guard let input = reader.value(scope) as? [String: Any], reader.consume([")"]),
                          end == nil || end == reader.index else { return [] }
                    end = reader.index; result.append(input)
                }
                guard end != nil, reader.consume([";", "text", "(", variable, ")", ";", "}", ")", ")"]) else { return [] }
            } else {
                let text = reader.consume(["text", "("])
                _ = reader.consume(["await"])
                guard reader.consume(tool), let input = reader.value(constants) as? [String: Any],
                      reader.consume([")"]), !text || reader.consume([")"]) else { return [] }
                result.append(input)
            }
        }
        return result
    }

    private struct Reader {
        var tokens: [String] = []
        var index = 0
        var peek: String? { index < tokens.count ? tokens[index] : nil }
        mutating func take() -> String? { defer { index += 1 }; return peek }
        mutating func consume(_ expected: [String]) -> Bool {
            guard tokens.dropFirst(index).prefix(expected.count).elementsEqual(expected) else { return false }
            index += expected.count
            return true
        }
        init(_ source: String) {
            let chars = Array(source)
            var i = 0
            while i < chars.count {
                let c = chars[i]
                if c.isWhitespace { i += 1; continue }
                if c == "/", i + 1 < chars.count, chars[i + 1] == "/" {
                    while i < chars.count, chars[i] != "\n" { i += 1 }; continue
                }
                if c == "/", i + 1 < chars.count, chars[i + 1] == "*" {
                    i += 2
                    while i + 1 < chars.count, !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }
                    i = min(chars.count, i + 2); continue
                }
                if c == "\"" || c == "'" || c == "`" {
                    let quote = c
                    i += 1
                    var value = "", valid = true, closed = false
                    while i < chars.count {
                        let c = chars[i]; i += 1
                        if c == quote { closed = true; break }
                        if quote == "`", c == "$", i < chars.count, chars[i] == "{" { valid = false }
                        if c == "\\", i < chars.count {
                            let escape = chars[i]; i += 1
                            switch escape {
                            case "n": value.append("\n")
                            case "r": value.append("\r")
                            case "t": value.append("\t")
                            case "\\", "\"", "'", "`", "$": value.append(escape)
                            case "u":
                                if i + 4 <= chars.count, let code = UInt32(String(chars[i..<i+4]), radix: 16), let scalar = UnicodeScalar(code) {
                                    value.unicodeScalars.append(scalar); i += 4
                                } else { valid = false }
                            default: valid = false
                            }
                        } else { value.append(c) }
                    }
                    if valid && closed, let data = try? JSONSerialization.data(withJSONObject: [value]),
                       let encoded = String(data: data, encoding: .utf8) { tokens.append(String(encoded.dropFirst().dropLast())) }
                    else { tokens.append("<unsupported>") }
                } else if c.isLetter || c == "_" || c == "$" || c.isNumber {
                    let start = i; i += 1
                    while i < chars.count, chars[i].isLetter || chars[i].isNumber || chars[i] == "_" || chars[i] == "$" { i += 1 }
                    tokens.append(String(chars[start..<i]))
                } else if i + 2 < chars.count, String(chars[i..<i+3]) == "..." {
                    tokens.append("..."); i += 3
                } else if i + 1 < chars.count, String(chars[i..<i+2]) == "=>" {
                    tokens.append("=>"); i += 2
                } else { tokens.append(String(c)); i += 1 }
            }
        }

        mutating func value(_ scope: [String: Any], depth: Int = 0) -> Any? {
            guard depth < 32, let token = take() else { return nil }
            var value: Any
            if token == "{" {
                var object: [String: Any] = [:]
                while peek != "}" {
                    guard let key = take() else { return nil }
                    if key == "..." {
                        guard let spread = self.value(scope, depth: depth + 1) as? [String: Any] else { return nil }
                        object.merge(spread) { _, new in new }
                    } else {
                        let name = decode(key) ?? key
                        guard take() == ":", let member = self.value(scope, depth: depth + 1) else { return nil }
                        object[name] = member
                    }
                    if peek == "," { index += 1 } else if peek != "}" { return nil }
                }
                index += 1; value = object
            } else if token == "[" {
                var array: [Any] = []
                while peek != "]" {
                    guard let member = self.value(scope, depth: depth + 1) else { return nil }
                    array.append(member)
                    if peek == "," { index += 1 } else if peek != "]" { return nil }
                }
                index += 1; value = array
            } else if let string = decode(token) { value = string }
            else if let known = scope[token] { value = known }
            else if token == "true" || token == "false" { value = token == "true" }
            else if token == "null" { value = NSNull() }
            else if let number = Double(token) { value = number }
            else { return nil }
            while peek == "+" {
                index += 1
                guard let lhs = value as? String, let rhs = self.value(scope, depth: depth + 1) as? String else { return nil }
                value = lhs + rhs
            }
            return value
        }
        func decode(_ token: String) -> String? {
            guard token.hasPrefix("\""), let data = "[\(token)]".data(using: .utf8) else { return nil }
            return (try? JSONSerialization.jsonObject(with: data) as? [String])?.first
        }
    }
}
