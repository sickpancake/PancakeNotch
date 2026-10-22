import Foundation

/// Pay-per-use prices in US dollars per million tokens, built into the app so AI Usage stays offline
/// (ADR-0037). From Anthropic's and OpenAI's pricing pages on 2026-10-21, cross-checked with LiteLLM's
/// table (MIT, © Berri AI). A model that isn't here counts as "no known price", never a guess.
struct ModelPrice: Sendable {
    var input: Double
    var output: Double
    /// Claude: writing the prompt cache for 5 minutes / 1 hour. OpenAI doesn't charge for cache writes.
    var cacheWrite5m: Double
    var cacheWrite1h: Double
    var cacheRead: Double
    /// Prompts over `threshold` tokens cost `long` instead (Haiku 5.5 over 100k, GPT models over 272k).
    var long: (threshold: Int64, price: LongPrice)?
    /// Claude's fast mode doubles the price on the models that have it.
    var hasFastMode = false

    struct LongPrice: Sendable {
        var input: Double
        var output: Double
        var cacheWrite5m: Double
        var cacheWrite1h: Double
        var cacheRead: Double
    }

    static func claude(_ input: Double, _ output: Double, read: Double, fast: Bool = false) -> ModelPrice {
        ModelPrice(input: input, output: output, cacheWrite5m: input * 1.25, cacheWrite1h: input * 2, cacheRead: read, hasFastMode: fast)
    }

    static func openAI(_ input: Double, cached: Double, _ output: Double, long: (Double, Double, Double)? = nil) -> ModelPrice {
        ModelPrice(input: input, output: output, cacheWrite5m: input, cacheWrite1h: input, cacheRead: cached,
                   long: long.map { (272_000, LongPrice(input: $0.0, output: $0.2, cacheWrite5m: $0.0, cacheWrite1h: $0.0, cacheRead: $0.1)) })
    }
}

enum ModelPrices {
    /// Longest names first, so "claude-opus-4-5" wins over "claude-opus-4".
    private static let table: [(name: String, price: ModelPrice)] = [
        ("claude-fable-5-1", .claude(10, 50, read: 0.25)),
        ("claude-fable-5", .claude(10, 50, read: 1)),
        ("claude-opus-5-5", .claude(4, 20, read: 0.20, fast: true)),
        ("claude-opus-5", .claude(5, 25, read: 0.50, fast: true)),
        ("claude-opus-4-8", .claude(5, 25, read: 0.50, fast: true)),
        ("claude-opus-4-7", .claude(5, 25, read: 0.50)),
        ("claude-opus-4-6", .claude(5, 25, read: 0.50)),
        ("claude-opus-4-5", .claude(5, 25, read: 0.50)),
        ("claude-opus-4-1", .claude(15, 75, read: 1.50)),
        ("claude-opus-4", .claude(15, 75, read: 1.50)),
        ("claude-sonnet-5-5", .claude(2, 10, read: 0.10)),
        ("claude-sonnet-5", .claude(2, 10, read: 0.20)),
        ("claude-sonnet-4-6", .claude(3, 15, read: 0.30)),
        ("claude-sonnet-4-5", .claude(3, 15, read: 0.30)),
        ("claude-sonnet-4", .claude(3, 15, read: 0.30)),
        ("claude-3-7-sonnet", .claude(3, 15, read: 0.30)),
        ("claude-haiku-5-5", ModelPrice(input: 0.10, output: 0.50, cacheWrite5m: 0.125, cacheWrite1h: 0.20, cacheRead: 0.01,
                                        long: (100_000, .init(input: 0.50, output: 2.50, cacheWrite5m: 0.625, cacheWrite1h: 1, cacheRead: 0.05)))),
        ("claude-haiku-4-5", .claude(1, 5, read: 0.10)),
        ("claude-3-5-haiku", .claude(0.80, 4, read: 0.08)),
        ("gpt-6-astra", .openAI(10, cached: 1, 50, long: (20, 2, 75))),
        ("gpt-6.1-sol", .openAI(2, cached: 0.10, 10, long: (4, 0.20, 15))),
        ("gpt-6-sol", .openAI(2, cached: 0.20, 10, long: (4, 0.40, 15))),
        ("gpt-6-luna", .openAI(0.10, cached: 0.01, 0.50, long: (0.20, 0.02, 0.75))),
        ("gpt-5.5", .openAI(5, cached: 0.50, 30, long: (10, 1, 45))),
        ("gpt-5.3-codex", .openAI(1.75, cached: 0.175, 14)),
        ("o4-mini", .openAI(1.10, cached: 0.275, 4.40)),
        ("o3", .openAI(2, cached: 0.50, 8)),
    ].sorted { $0.name.count > $1.name.count }

    /// Short names Claude Code writes for some helpers.
    private static let aliases = ["opus": "claude-opus-5-5", "sonnet": "claude-sonnet-5-5", "haiku": "claude-haiku-5-5"]

    /// "claude-sonnet-4-5-20250929" → "claude-sonnet-4-5"; "anthropic/claude-opus-5-5[1m]" → "claude-opus-5-5".
    static func normalized(_ model: String) -> String {
        var name = model.lowercased()
        if let bracket = name.firstIndex(of: "[") { name = String(name[..<bracket]) }
        if let slash = name.lastIndex(of: "/") { name = String(name[name.index(after: slash)...]) }
        name = name.replacing(/-\d{8}$/, with: "")
        return aliases[name] ?? name
    }

    static func price(for model: String) -> ModelPrice? {
        let name = normalized(model)
        return table.first { name == $0.name || name.hasPrefix($0.name + "-") }?.price
    }

    /// One Claude message.
    static func claudeCost(model: String, input: Int64, output: Int64, cacheWrite5m: Int64, cacheWrite1h: Int64,
                           cacheRead: Int64, fast: Bool) -> Double? {
        guard let price = price(for: model) else { return nil }
        let prompt = input + cacheWrite5m + cacheWrite1h + cacheRead
        let rates = price.long.flatMap { prompt > $0.threshold ? $0.price : nil }
        let cost = Double(input) * (rates?.input ?? price.input)
            + Double(output) * (rates?.output ?? price.output)
            + Double(cacheWrite5m) * (rates?.cacheWrite5m ?? price.cacheWrite5m)
            + Double(cacheWrite1h) * (rates?.cacheWrite1h ?? price.cacheWrite1h)
            + Double(cacheRead) * (rates?.cacheRead ?? price.cacheRead)
        return cost / 1_000_000 * (fast && price.hasFastMode ? 2 : 1)
    }

    /// One Codex request: `input` without the cached part, `cached`, and `output` (reasoning is in it).
    /// `prompt` is the request's whole input, for the long-context price.
    static func codexCost(model: String, input: Int64, cached: Int64, output: Int64, prompt: Int64) -> Double? {
        guard let price = price(for: model) else { return nil }
        let rates = price.long.flatMap { prompt > $0.threshold ? $0.price : nil }
        let cost = Double(input) * (rates?.input ?? price.input)
            + Double(cached) * (rates?.cacheRead ?? price.cacheRead)
            + Double(output) * (rates?.output ?? price.output)
        return cost / 1_000_000
    }

    /// "Opus 5.5", "Sonnet 4.5", "GPT-6.1 Sol", "o3".
    static func displayName(_ model: String) -> String {
        let name = normalized(model)
        if name.hasPrefix("claude-") {
            var parts = name.dropFirst("claude-".count).split(separator: "-").map(String.init)
            // "claude-3-5-haiku" puts the version first.
            if let first = parts.first, first.allSatisfy(\.isNumber), let family = parts.last, !family.allSatisfy(\.isNumber) {
                parts = [family] + parts.dropLast()
            }
            guard let family = parts.first else { return model }
            let version = parts.dropFirst().filter { $0.allSatisfy(\.isNumber) }.joined(separator: ".")
            return version.isEmpty ? family.capitalized : "\(family.capitalized) \(version)"
        }
        if name.hasPrefix("gpt-") {
            let parts = name.dropFirst("gpt-".count).split(separator: "-").map(String.init)
            guard let version = parts.first else { return model }
            let rest = parts.dropFirst().map { $0 == "codex" ? "Codex" : $0.capitalized }
            return (["GPT-\(version)"] + rest).joined(separator: " ")
        }
        // "o3", "o4-mini" stay as OpenAI writes them; "codex-auto-review" → "Codex auto review".
        if name.first == "o", name.dropFirst().first?.isNumber == true { return name }
        let words = name.split(separator: "-").joined(separator: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}
