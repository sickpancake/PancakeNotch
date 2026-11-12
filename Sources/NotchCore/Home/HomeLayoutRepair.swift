import Foundation
import CoreFoundation

extension HomeLayout {
    /// Recovers each saved widget independently so one bad entry cannot erase Home.
    public static func decode(_ data: Data?) -> Self {
        guard let data, let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else { return .default }
        let version = integer(dictionary["version"]) ?? 0
        let saved = version < currentVersion ? migrate(dictionary, from: version) : dictionary
        guard let entries = saved["placements"] as? [Any] else { return .default }
        var result = Self(statisticsMetric: saved["statisticsMetric"] as? String)
        var seen: Set<HomeWidgetKind> = []
        var pending: [(HomeWidgetKind, HomeWidgetSize)] = []
        for case let entry as [String: Any] in entries {
            guard let name = entry["widget"] as? String, let kind = HomeWidgetKind(rawValue: name),
                  seen.insert(kind).inserted else { continue }
            let storedSize = (entry["size"] as? String).flatMap(HomeWidgetSize.init(rawValue:))
            let size = kind.sizes.last(where: { $0 <= (storedSize ?? .small) }) ?? kind.sizes[0]
            if let page = integer(entry["page"]), (0..<pageCount).contains(page),
               let column = integer(entry["column"]), column >= 0,
               let row = integer(entry["row"]), row >= 0 {
                let item = HomePlacement(kind: kind, size: size, slot: HomeSlot(page: page,
                    column: min(column, columns - size.columns), row: min(row, rows - size.rows)))
                if result.isFree(item) { result.placements.append(item); continue }
            }
            pending.append((kind, size))
        }
        for (kind, size) in pending {
            if case .success(let repaired) = result.adding(kind, size: size) { result = repaired }
        }
        return result
    }
    /// Older formats pass through this hook before their placements are repaired.
    static func migrate(_ object: [String: Any], from version: Int) -> [String: Any] { object }
    /// Writes the current flat JSON format.
    public func encoded() -> Data { (try? JSONEncoder().encode(self)) ?? Data() }
    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              let integer = Int(number.stringValue) else { return nil }
        return integer
    }
}

// Codable's decoder has no raw-JSON access. Preserve unknown values until the repair pass.
indirect enum JSONValue: Decodable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null
    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else { self = .number(try c.decode(Double.self)) }
    }
    var object: Any {
        switch self {
        case .object(let v): v.mapValues(\.object)
        case .array(let v): v.map(\.object)
        case .string(let v): v
        case .number(let v): v
        case .bool(let v): v
        case .null: NSNull()
        }
    }
}
