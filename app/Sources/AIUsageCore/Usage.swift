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

/// Codex at a company's own credit price instead of public API prices. OpenAI's Codex rate card
/// prices every model at exactly 25 credits per API dollar, so one credit is worth $0.04 of API
/// value, and ccusage's API cost converts straight to credits without a per-model table.
public struct CodexPricing: Equatable, Sendable {
    public static let publicDollarsPerCredit = 0.04
    /// Nil means public API prices.
    public var dollarsPerCredit: Double?

    public init(dollarsPerCredit: Double?) { self.dollarsPerCredit = dollarsPerCredit }

    public static func credits(apiCost: Double) -> Double { apiCost / publicDollarsPerCredit }

    public func cost(apiCost: Double) -> Double {
        guard let rate = dollarsPerCredit else { return apiCost }
        return Self.credits(apiCost: apiCost) * rate
    }

    /// The same day -> tool -> $ map with Codex at this price; other tools unchanged.
    public func apply(_ costs: [String: [String: Double]]) -> [String: [String: Double]] {
        guard dollarsPerCredit != nil else { return costs }
        return costs.mapValues { tools in
            var m = tools
            if let c = m["codex"] { m["codex"] = cost(apiCost: c) }
            return m
        }
    }

    /// What someone typed as a $ per credit ("0.03", "$0.025", " 0,03 "), or nil if it isn't a
    /// positive price under $10 with at most 4 decimals.
    public static func parseRate(_ text: String) -> Double? {
        var s = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        if s.hasPrefix("$") { s = String(s.dropFirst()).trimmingCharacters(in: .whitespaces) }
        guard s.range(of: #"\A[0-9]*\.?[0-9]{0,4}\z"#, options: .regularExpression) != nil,
              let v = Double(s), v > 0, v < 10 else { return nil }
        return v
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

public enum CCUsageVersion {
    /// The version from `ccusage --version` output ("ccusage 20.0.51"). npx may print
    /// noise first, so the last matching line wins.
    public static func parse(_ output: String) -> String? {
        for line in output.split(whereSeparator: \.isNewline).reversed() {
            let parts = line.split(separator: " ")
            if parts.count == 2, parts[0] == "ccusage", let v = validated(String(parts[1])) { return v }
        }
        return nil
    }

    /// `version` if it's plain semver. It's passed to npx as `ccusage@<version>`, where anything
    /// else (a path, URL or git spec) could install something other than ccusage from npm.
    public static func validated(_ version: String) -> String? {
        version.range(of: #"\A[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?\z"#, options: .regularExpression) != nil ? version : nil
    }

    /// Releases worth trying when `@latest` fails, newest first: stable semver only, minus any
    /// already tried. Pass the `latest` tag in `tried`: some setups (a corporate npm filter, say)
    /// hide new releases from the list but not from the tag, so the newest *listed* is often fine.
    public static func candidates(_ versions: [String], excluding tried: Set<String>, limit: Int) -> [String] {
        let stable = versions.compactMap(validated).filter { !$0.contains("-") }
            .sorted { Version.isNewer($0, than: $1) }
        return Array(stable.filter { !tried.contains($0) }.prefix(limit))
    }
}

/// `npm view <package> versions dist-tags --json`, as this Mac's npm sees it. The versions list
/// is what npm will actually install here, which can be less than the public registry shows.
public struct NPMPackageInfo: Equatable, Sendable {
    public var versions: [String]
    public var latest: String?

    public init(versions: [String], latest: String?) { self.versions = versions; self.latest = latest }

    public static func parse(_ json: Data) -> NPMPackageInfo? {
        guard let obj = try? JSONSerialization.jsonObject(with: json, options: .fragmentsAllowed) else { return nil }
        if let d = obj as? [String: Any] {
            let v = (d["versions"] as? [String]) ?? (d["versions"] as? String).map { [$0] } ?? []
            return NPMPackageInfo(versions: v, latest: (d["dist-tags"] as? [String: Any])?["latest"] as? String)
        }
        // Asked for `versions` alone: an array, or a bare string when there's one.
        if let v = (obj as? [String]) ?? (obj as? String).map({ [$0] }) { return NPMPackageInfo(versions: v, latest: nil) }
        return nil
    }
}

public enum NPMError {
    /// A short reason from a failed npx/npm run's stderr, e.g. "No matching version found for
    /// ccusage@9.0.0. (ETARGET)". npm prints its log path last, so the last line alone says nothing.
    public static func summary(_ stderr: String) -> String? {
        let lines = stderr.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        var code: String?
        var message: String?
        for line in lines {
            guard let body = stripPrefix(line) else { continue }
            if body.hasPrefix("code ") { code = code ?? String(body.dropFirst(5)); continue }
            if message == nil, !isNoise(body) { message = dropHeading(body) }
        }
        if message == nil, code == nil {
            // Not npm's format: the last line that isn't npm's log pointer.
            return lines.last { !$0.isEmpty && !isNoise(stripPrefix($0) ?? $0) }.map { String($0.prefix(200)) }
        }
        let text = [message, code.map { "(\($0))" }].compactMap { $0 }.joined(separator: " ")
        return String(text.prefix(200))
    }

    private static func stripPrefix(_ line: String) -> String? {
        for p in ["npm error ", "npm ERR! "] where line.hasPrefix(p) {
            return String(line.dropFirst(p.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func isNoise(_ body: String) -> Bool {
        let skip = ["A complete log of this run", "Log files were not written", "In most cases", "syscall ", "errno ", "path "]
        return body.isEmpty || skip.contains { dropHeading(body).hasPrefix($0) || body.hasPrefix($0) }
    }

    /// npm tags lines with a lowercase or numeric heading ("notarget No matching…", "403 403 Forbidden…").
    private static func dropHeading(_ body: String) -> String {
        let parts = body.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2, let next = parts[1].first, next.isUppercase || next.isNumber,
              parts[0].allSatisfy({ $0.isLowercase || $0.isNumber }) else { return body }
        return parts[1]
    }
}

/// Automatic updates never give up on a version; they back off instead, so a failing install
/// (or one that somehow relaunches the old app) can't run every minute or on every launch.
public enum AutoUpdate {
    /// Wait before the next try after `attempts` tries: none, then 1h, 2h, 4h, 8h, 16h, then daily.
    public static func wait(afterAttempts attempts: Int) -> TimeInterval {
        guard attempts > 0 else { return 0 }
        return min(3_600 * pow(2, Double(min(attempts - 1, 10))), 86_400)
    }

    public static func isDue(attempts: Int, lastTry: Date?, now: Date = Date()) -> Bool {
        guard let lastTry else { return true }
        return now.timeIntervalSince(lastTry) >= wait(afterAttempts: attempts)
    }
}

public enum Version {
    /// "20261114.2.0" (npm form) -> "20261114.2" (the form people see).
    public static func display(_ v: String) -> String {
        v.hasSuffix(".0") && v.split(separator: ".").count == 3 ? String(v.dropLast(2)) : v
    }

    /// The newest stable version in `versions` above `current`, or nil if there's none.
    /// "20261125.2.0" (npm) and "20261125.2" (app) count as the same version.
    public static func newestUpdate(in versions: [String], current: String) -> String? {
        versions.compactMap(CCUsageVersion.validated).filter { !$0.contains("-") && isNewer($0, than: current) }
            .max { isNewer($1, than: $0) }
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
