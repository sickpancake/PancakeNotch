import Foundation

/// One memory and CPU reading of PancakeNotch (and its Now Playing helper) at a moment.
public struct HealthSample: Sendable, Equatable {
    public var date: Date
    /// The app's physical footprint: the memory figure Activity Monitor shows.
    public var footprintBytes: UInt64
    /// The Now Playing helper's footprint, or 0 when it isn't running.
    public var helperFootprintBytes: UInt64
    /// CPU use of the app and helper together, as a percentage of one core.
    public var cpuPercent: Double

    public init(date: Date, footprintBytes: UInt64, helperFootprintBytes: UInt64, cpuPercent: Double) {
        self.date = date
        self.footprintBytes = footprintBytes
        self.helperFootprintBytes = helperFootprintBytes
        self.cpuPercent = cpuPercent
    }

    /// App and helper together: what counts against the memory budget (ADR-0006).
    public var totalFootprintBytes: UInt64 { footprintBytes + helperFootprintBytes }
}

/// One entry in a top list: a song or video, an artist or channel, an app or a module.
public struct RankedItem: Sendable, Equatable, Identifiable {
    /// Stable key: "title<US>artist" for songs and videos, the artist or channel, the bundle ID, or the module ID.
    public var id: String
    public var title: String
    public var subtitle: String?
    /// What the list is ranked by: seconds listened, or a count for modules.
    public var value: Double
    /// How many times: plays for songs, videos, creators and apps; uses for modules.
    public var count: Int

    public init(id: String, title: String, subtitle: String? = nil, value: Double, count: Int) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.value = value
        self.count = count
    }
}

/// What was listened to, or what was watched, over a range of days (see `PlayKind`).
public struct PlaySummary: Sendable, Equatable {
    /// Seconds on each day, aligned with `StatsSummary.days`.
    public var secondsPerDay: [Double]
    /// Plays on each day, aligned with `StatsSummary.days`.
    public var playsPerDay: [Int]
    public var totalSeconds: Double
    public var totalPlays: Int
    /// Songs or videos, at most five, most time first. `subtitle` is the artist or channel.
    public var top: [RankedItem]
    /// Artists or channels.
    public var topCreators: [RankedItem]
    /// `id` and `title` are the app's bundle ID; the page looks up its name and icon.
    public var topApps: [RankedItem]

    public init(
        secondsPerDay: [Double] = [],
        playsPerDay: [Int] = [],
        totalSeconds: Double = 0,
        totalPlays: Int = 0,
        top: [RankedItem] = [],
        topCreators: [RankedItem] = [],
        topApps: [RankedItem] = []
    ) {
        self.secondsPerDay = secondsPerDay
        self.playsPerDay = playsPerDay
        self.totalSeconds = totalSeconds
        self.totalPlays = totalPlays
        self.top = top
        self.topCreators = topCreators
        self.topApps = topApps
    }

    public static let empty = PlaySummary()
}

/// Everything the Statistics page shows for a range of days. Small on purpose: per-day arrays,
/// top fives and at most ~300 health samples, never whole tables.
public struct StatsSummary: Sendable, Equatable {
    /// The start of each local calendar day in the range, oldest first; the last one is today.
    public var days: [Date]
    /// Music, podcasts and audiobooks.
    public var listening: PlaySummary
    /// Videos and streams.
    public var watching: PlaySummary
    /// Notch opens on each day, aligned with `days`.
    public var opensPerDay: [Int]
    public var totalOpens: Int
    /// Module IDs ("nowPlaying", "shelf", …), most used first; `value` and `count` are the uses.
    public var moduleUses: [RankedItem]
    public var shelved: Int
    public var airDropped: Int
    /// Samples taken in the range, oldest first, thinned out evenly to at most `maxHealthSamples`.
    public var health: [HealthSample]

    public static let maxHealthSamples = 300

    public init(
        days: [Date] = [],
        listening: PlaySummary = .empty,
        watching: PlaySummary = .empty,
        opensPerDay: [Int] = [],
        totalOpens: Int = 0,
        moduleUses: [RankedItem] = [],
        shelved: Int = 0,
        airDropped: Int = 0,
        health: [HealthSample] = []
    ) {
        self.days = days
        self.listening = listening
        self.watching = watching
        self.opensPerDay = opensPerDay
        self.totalOpens = totalOpens
        self.moduleUses = moduleUses
        self.shelved = shelved
        self.airDropped = airDropped
        self.health = health
    }

    public static let empty = StatsSummary()
}
