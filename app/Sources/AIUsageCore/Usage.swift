import Foundation

/// ccusage `daily --json --by-agent` output. Every field optional: decode defensively.
public struct UsageReport: Decodable, Sendable {
    public var daily: [Day]

    public struct Day: Decodable, Sendable {
        public var period: String?
        public var date: String?          // older ccusage versions
        public var totalCost: Double?
        public var agents: [Agent]?
        public var metadata: Metadata?

        public var day: String { period ?? date ?? "" }
    }
    public struct Agent: Decodable, Sendable {
        public var agent: String?
        public var totalCost: Double?
    }
    public struct Metadata: Decodable, Sendable {
        public var agents: [String]?
    }

    enum CodingKeys: String, CodingKey { case daily }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        daily = try c.decodeIfPresent([Day].self, forKey: .daily) ?? []
    }

    public static func decode(_ data: Data) throws -> UsageReport {
        try JSONDecoder().decode(UsageReport.self, from: data)
    }

    /// Cost per tool per day: ["2026-11-14": ["claude": 52.4, ...]].
    public var costsByDay: [String: [String: Double]] {
        var out: [String: [String: Double]] = [:]
        for d in daily {
            var m: [String: Double] = [:]
            if let agents = d.agents, !agents.isEmpty {
                for a in agents { m[a.agent ?? "unknown", default: 0] += a.totalCost ?? 0 }
            } else if let cost = d.totalCost {
                // No per-agent split: attribute to the only agent, else "all".
                let ids = d.metadata?.agents ?? []
                m[ids.count == 1 ? ids[0] : "all", default: 0] += cost
            }
            out[d.day, default: [:]].merge(m, uniquingKeysWith: +)
        }
        return out
    }
}

public enum Tools {
    public static func name(_ id: String) -> String {
        switch id {
        case "claude": "Claude Code"
        case "codex": "Codex"
        case "gemini": "Gemini CLI"
        case "opencode": "OpenCode"
        case "copilot": "Copilot CLI"
        case "amp": "Amp"
        case "droid": "Droid"
        default: id.prefix(1).uppercased() + id.dropFirst()
        }
    }
}

public enum Version {
    /// "20261114.2.0" (npm form) -> "20261114.2" (the form people see).
    public static func display(_ v: String) -> String {
        v.hasSuffix(".0") && v.split(separator: ".").count == 3 ? String(v.dropLast(2)) : v
    }

    /// Numeric part-by-part compare of date-based versions like 20261114.0.0.
    public static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
