import AIUsageCore
import Foundation
import ServiceManagement

enum Range: String, CaseIterable, Identifiable {
    case today = "Today", week = "Week", month = "Month"
    var id: String { rawValue }
}

@MainActor
final class UsageModel: ObservableObject {
    @Published private(set) var costs: [String: [String: Double]] = [:]  // day -> tool -> $
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var error: String?
    /// The older ccusage the last refresh fell back to because `@latest` failed.
    @Published private(set) var fallbackVersion: String?
    @Published private(set) var updateAvailable: String?
    @Published var range: Range = .today
    @Published var excluded: Set<String> {
        didSet { UserDefaults.standard.set(Array(excluded).sorted(), forKey: "excludedTools") }
    }
    @Published private(set) var loginStatus: SMAppService.Status = SMAppService.mainApp.status
    @Published private(set) var isUpdating = false
    /// Setting (on by default; switch in the panel).
    @Published var autoUpdate = UserDefaults.standard.object(forKey: "autoUpdate") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoUpdate, forKey: "autoUpdate"); if autoUpdate { maybeAutoUpdate() } }
    }

    private var env: [String: String]?
    private var isSample = false
    private var timer: Timer?
    private static let lastGoodVersionKey = "ccusageLastGoodVersion"
    private static let lastGoodVersionCheckedKey = "ccusageLastGoodVersionCheckedAt"
    private static let olderSearchFailedKey = "ccusageOlderSearchFailedAt"
    private static let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("com.verycuteapps.ai-usage-bar/last.json")

    /// Sample data for screenshots (`--snapshot`): no refresh, no login item, no network.
    init(sample costs: [String: [String: Double]]) {
        excluded = []
        self.costs = costs
        lastUpdated = Date().addingTimeInterval(-25)
        loginStatus = .enabled
        isSample = true
    }

    init() {
        excluded = Set(UserDefaults.standard.stringArray(forKey: "excludedTools") ?? [])
        if let data = try? Data(contentsOf: Self.cacheURL), let r = try? UsageReport.decode(data) {
            costs = r.costsByDay
            lastUpdated = (try? Self.cacheURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        }
        if !UserDefaults.standard.bool(forKey: "didAutoRegisterLogin") {
            UserDefaults.standard.set(true, forKey: "didAutoRegisterLogin")
            try? SMAppService.mainApp.register()
        }
        loginStatus = SMAppService.mainApp.status
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh(); self?.checkForUpdate(); self?.refreshLoginStatus()
            }
        }
        checkForUpdate()
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Only the copy installed by the installer updates itself (not dev builds).
    private static var isInstalledCopy: Bool {
        Bundle.main.bundlePath == FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/AI Spend Bar.app").path
    }

    // MARK: Derived values

    static func dayKey(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    private func start(of r: Range, now: Date = Date()) -> Date {
        var cal = Calendar(identifier: .gregorian); cal.firstWeekday = 2  // Monday
        switch r {
        case .today: return cal.startOfDay(for: now)
        case .week: return cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        case .month: return cal.dateInterval(of: .month, for: now)?.start ?? now
        }
    }

    private func days(in r: Range) -> [String] {
        var out: [String] = []
        var d = start(of: r)
        let end = Date()
        while d <= end { out.append(Self.dayKey(d)); d = Calendar.current.date(byAdding: .day, value: 1, to: d)! }
        return out
    }

    /// Tools with any cost in the last 30 days, biggest first.
    var tools: [String] {
        let cutoff = Self.dayKey(Calendar.current.date(byAdding: .day, value: -29, to: Date())!)
        var sums: [String: Double] = [:]
        for (day, m) in costs where day >= cutoff { for (t, c) in m { sums[t, default: 0] += c } }
        return sums.filter { $0.value > 0 }.sorted { $0.value > $1.value }.map(\.key)
    }

    /// Whether a tool's cost counts toward totals. A lone tool always counts, and so does
    /// everything if every listed tool was switched off, so the total never reads $0 for no reason.
    func isCounted(_ tool: String) -> Bool {
        let all = tools
        if all.count <= 1 || all.allSatisfy({ excluded.contains($0) }) { return true }
        return !excluded.contains(tool)
    }

    private var countedCount: Int { tools.filter(isCounted).count }

    /// The switch is only offered with several tools, and the last one on can't be turned off.
    func canToggle(_ tool: String) -> Bool { tools.count > 1 && !(isCounted(tool) && countedCount == 1) }

    func cost(tool: String, range r: Range) -> Double {
        days(in: r).reduce(0) { $0 + (costs[$1]?[tool] ?? 0) }
    }

    func total(_ r: Range) -> Double {
        return days(in: r).reduce(0) { acc, day in
            acc + (costs[day] ?? [:]).filter { isCounted($0.key) }.values.reduce(0, +)
        }
    }

    /// Daily enabled-tool totals for the chart, oldest first. Today shows the last 7 days for
    /// context; Week shows Mon–Sun of this week; Month shows every day of this month.
    /// Future days are included with no cost so bars keep a steady width.
    func chartDays(_ r: Range) -> [(day: Date, key: String, cost: Double)] {
        var cal = Calendar(identifier: .gregorian); cal.firstWeekday = 2  // Monday
        let today = cal.startOfDay(for: Date())
        let first: Date, count: Int
        switch r {
        case .today: first = cal.date(byAdding: .day, value: -6, to: today)!; count = 7
        case .week: first = start(of: .week); count = 7
        case .month:
            first = start(of: .month)
            count = cal.range(of: .day, in: .month, for: today)?.count ?? 30
        }
        return (0..<count).map { i in
            let d = cal.date(byAdding: .day, value: i, to: first)!
            let k = Self.dayKey(d)
            return (d, k, (costs[k] ?? [:]).filter { isCounted($0.key) }.values.reduce(0, +))
        }
    }

    var hasData: Bool { lastUpdated != nil }

    var menuLabel: String {
        guard hasData else { return "AI …" }
        // ⚠︎ while start at login is off, so the fix is visible without opening the panel.
        return "AI $\(Int(total(.today).rounded()))" + (error != nil ? " ·" : "")
            + (loginStatus != .enabled ? " ⚠︎" : "")
    }

    // MARK: Refresh

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        let cachedEnv = env
        let since = Self.yyyymmdd(Calendar.current.date(byAdding: .day, value: -34, to: Date())!)
        let until = Self.yyyymmdd(Date())
        let d = UserDefaults.standard
        let lastGood = d.string(forKey: Self.lastGoodVersionKey).flatMap(CCUsageVersion.validated)
        let shouldCheckVersion = (d.object(forKey: Self.lastGoodVersionCheckedKey) as? Date)
            .map { Date().timeIntervalSince($0) >= 86_400 } ?? true
        // Searching older releases downloads each one, so after a search finds nothing, wait an hour.
        let searchOlder = (d.object(forKey: Self.olderSearchFailedKey) as? Date)
            .map { Date().timeIntervalSince($0) >= 3_600 } ?? true
        Task.detached(priority: .utility) {
            let env = cachedEnv ?? Shell.userEnvironment()
            let result = CCUsage.fetch(env: env, since: since, until: until, lastGood: lastGood, searchOlder: searchOlder)
            await MainActor.run {
                self.env = env
                self.isRefreshing = false
                switch result {
                case .success(let fetched):
                    if fetched.foundBySearch, let v = fetched.fallbackVersion {
                        d.set(v, forKey: Self.lastGoodVersionKey)
                        d.removeObject(forKey: Self.olderSearchFailedKey)
                    }
                    do {
                        let r = try UsageReport.decode(fetched.data)
                        self.costs = r.costsByDay
                        self.lastUpdated = Date()
                        self.error = nil
                        self.fallbackVersion = fetched.fallbackVersion
                        try? FileManager.default.createDirectory(at: Self.cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try? fetched.data.write(to: Self.cacheURL, options: .atomic)
                    } catch {
                        self.error = "Couldn't read ccusage output."
                    }
                case .failure(let e):
                    self.error = e.message
                    if searchOlder, !e.timedOut { d.set(Date(), forKey: Self.olderSearchFailedKey) }
                }
            }
            // After a good `@latest` run, note which version that was (daily), so a later failure
            // of `@latest` has something to fall back to.
            guard shouldCheckVersion, case .success(let fetched) = result, fetched.fallbackVersion == nil else { return }
            let version = CCUsage.latestVersion(env: env)
            await MainActor.run {
                UserDefaults.standard.set(Date(), forKey: Self.lastGoodVersionCheckedKey)
                if let version { UserDefaults.standard.set(version, forKey: Self.lastGoodVersionKey) }
            }
        }
    }

    private static func yyyymmdd(_ d: Date) -> String { dayKey(d).replacingOccurrences(of: "-", with: "") }

    // MARK: Login item

    func setStartAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Login item change failed: \(error)")
        }
        loginStatus = SMAppService.mainApp.status
    }

    func refreshLoginStatus() {
        guard !isSample else { return }
        loginStatus = SMAppService.mainApp.status
    }

    // MARK: Update check (at most once a day)

    func checkForUpdate() {
        guard !isSample else { return }
        let d = UserDefaults.standard
        let current = Self.appVersion
        if let latest = d.string(forKey: "latestVersion"), Version.isNewer(latest, than: current) {
            updateAvailable = latest
            maybeAutoUpdate()
        }
        if let last = d.object(forKey: "lastUpdateCheck") as? Date, Date().timeIntervalSince(last) < 86_400 { return }
        d.set(Date(), forKey: "lastUpdateCheck")
        Task {
            guard let url = URL(string: "https://registry.npmjs.org/ai-spend-bar/latest"),
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let latest = obj["version"] as? String else { return }
            d.set(latest, forKey: "latestVersion")
            updateAvailable = Version.isNewer(latest, than: current) ? latest : nil
            maybeAutoUpdate()
        }
    }

    // MARK: Updating

    /// Automatic updates: quietly run the same installer people used to install the app.
    /// One try per version, so a failing update doesn't loop.
    func maybeAutoUpdate() {
        guard autoUpdate, let v = updateAvailable else { return }
        let d = UserDefaults.standard
        guard d.string(forKey: "autoUpdateTried") != v else { return }
        d.set(v, forKey: "autoUpdateTried")
        installUpdate()
    }

    /// Runs `npx ai-spend-bar@latest`, which quits this app, replaces it in ~/Applications and reopens it.
    func installUpdate() {
        guard !isSample, !isUpdating, Self.isInstalledCopy else { return }
        isUpdating = true
        let cachedEnv = env
        let log = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/AI Spend Bar/update.log")
        Task.detached {
            let env = cachedEnv ?? Shell.userEnvironment()
            let started = Shell.launch("npx", ["--yes", "ai-spend-bar@latest"], env: env, log: log) {
                // Still running after the installer finished means it failed; let the user retry.
                Task { @MainActor in self.isUpdating = false }
            }
            if !started { await MainActor.run { self.isUpdating = false } }
        }
    }

}

struct ShellError: Error {
    let message: String
    var timedOut = false
}

/// Runs `ccusage@latest`; if that fails (say the registry can't resolve the newest release),
/// retries with the last version that worked so usage keeps updating. With no such version
/// (a fresh install) or if it fails too, tries a few older releases, newest first.
enum CCUsage {
    struct Fetched: Sendable {
        let data: Data
        let fallbackVersion: String?
        /// The fallback came from searching older releases, so it's a new last-good version.
        var foundBySearch = false
    }

    static let olderReleasesToTry = 3

    static func fetch(env: [String: String], since: String, until: String, lastGood: String?,
                      searchOlder: Bool) -> Result<Fetched, ShellError> {
        let args = ["daily", "--json", "--by-agent", "--since", since, "--until", until]
        let e: ShellError
        switch Shell.runCCUsage(version: "latest", args, env: env, timeout: 90) {
        case .success(let data): return .success(Fetched(data: data, fallbackVersion: nil))
        case .failure(let err): e = err
        }
        // A timeout would likely repeat, and doubling the wait helps nobody.
        guard !e.timedOut else { return .failure(e) }
        if let v = lastGood {
            switch Shell.runCCUsage(version: v, args, env: env, timeout: 90) {
            case .success(let data): return .success(Fetched(data: data, fallbackVersion: v))
            case .failure(let err) where err.timedOut: return .failure(e)
            case .failure: break
            }
        }
        guard searchOlder else { return .failure(e) }
        let tried: Set<String> = lastGood.map { [$0] } ?? []
        for v in CCUsageVersion.candidates(publishedVersions(env: env), excluding: tried, limit: olderReleasesToTry) {
            switch Shell.runCCUsage(version: v, args, env: env, timeout: 90) {
            case .success(let data): return .success(Fetched(data: data, fallbackVersion: v, foundBySearch: true))
            case .failure(let err) where err.timedOut: return .failure(e)
            case .failure: continue
            }
        }
        return .failure(e)
    }

    /// Every published ccusage version, from the same registry npx uses. Empty if npm can't say.
    static func publishedVersions(env: [String: String]) -> [String] {
        guard let npm = Shell.findExecutable("npm", path: env["PATH"] ?? ""),
              case .success(let out) = Shell.run(npm, ["view", "ccusage", "versions", "--json"], env: env, timeout: 30)
        else { return [] }
        return CCUsageVersion.list(out)
    }

    static func latestVersion(env: [String: String]) -> String? {
        guard case .success(let out) = Shell.runCCUsage(version: "latest", ["--version"], env: env, timeout: 60) else { return nil }
        return String(data: out, encoding: .utf8).flatMap(CCUsageVersion.parse)
    }
}

enum Shell {
    /// Environment with the user's login-shell PATH plus Homebrew paths, and CLAUDE_CONFIG_DIR.
    static func userEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        var path = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        // Interactive login shell so ~/.zshrc runs too (nvm, volta, fnm usually live there).
        // A marker separates PATH from anything the rc files print.
        let shell = env["SHELL"].flatMap { FileManager.default.isExecutableFile(atPath: $0) ? $0 : nil } ?? "/bin/zsh"
        if case .success(let out) = run(shell, ["-ilc", "printf '__AIUB_PATH__%s\\n' \"$PATH\""], env: env, timeout: 10),
           let line = String(data: out, encoding: .utf8)?.components(separatedBy: "\n").last(where: { $0.hasPrefix("__AIUB_PATH__") }) {
            let p = String(line.dropFirst("__AIUB_PATH__".count)).trimmingCharacters(in: .whitespaces)
            if !p.isEmpty { path = p }
        }
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + path
        let dirs = claudeConfigDirs()
        if !dirs.isEmpty { env["CLAUDE_CONFIG_DIR"] = dirs.joined(separator: ",") }
        return env
    }

    static func claudeConfigDirs() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: home.path)) ?? []
        return names.filter { $0.hasPrefix(".claude") }.sorted().compactMap { name in
            let dir = home.appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { return nil }
            var projIsDir: ObjCBool = false
            let hasProjects = fm.fileExists(atPath: dir.appendingPathComponent("projects").path, isDirectory: &projIsDir) && projIsDir.boolValue
            let hasSettings = fm.fileExists(atPath: dir.appendingPathComponent("settings.json").path)
            return hasProjects || hasSettings ? dir.path : nil
        }
    }

    /// Starts `name` (found on PATH) without waiting; output goes to `log`. Returns false if it couldn't start.
    static func launch(_ name: String, _ args: [String], env: [String: String], log: URL,
                       onExit: @escaping @Sendable () -> Void) -> Bool {
        guard let exe = findExecutable(name, path: env["PATH"] ?? "") else { return false }
        try? FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: log.path, contents: nil)
        guard let out = try? FileHandle(forWritingTo: log) else { return false }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.environment = env
        p.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        p.standardOutput = out; p.standardError = out; p.standardInput = FileHandle.nullDevice
        p.terminationHandler = { _ in onExit() }
        do { try p.run() } catch { return false }
        return true
    }

    static func findExecutable(_ name: String, path: String) -> String? {
        path.split(separator: ":").map { "\($0)/\(name)" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// `version` is "latest" or a plain semver from `CCUsageVersion.validated`. A pinned version
    /// never changes, so npx uses its cached copy rather than asking the registry again.
    static func runCCUsage(version: String, _ args: [String], env: [String: String],
                           timeout: TimeInterval) -> Result<Data, ShellError> {
        guard let npx = findExecutable("npx", path: env["PATH"] ?? "") else {
            return .failure(ShellError(message: "Node.js is needed. Install it, then run npx ai-spend-bar again."))
        }
        let offline = version == "latest" ? [] : ["--prefer-offline"]
        return run(npx, ["--yes"] + offline + ["ccusage@\(version)"] + args, env: env, timeout: timeout)
    }

    static func run(_ exe: String, _ args: [String], env: [String: String], timeout: TimeInterval) -> Result<Data, ShellError> {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.environment = env
        p.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        let out = Pipe(), err = Pipe()
        p.standardOutput = out; p.standardError = err; p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return .failure(ShellError(message: "Couldn't start \(exe): \(error.localizedDescription)")) }

        var timedOut = false
        let killer = DispatchWorkItem { if p.isRunning { timedOut = true; p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        // Read stderr concurrently so neither pipe can fill up and block the child.
        var errData = Data()
        let g = DispatchGroup(); g.enter()
        DispatchQueue.global().async { errData = err.fileHandleForReading.readDataToEndOfFile(); g.leave() }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        g.wait()
        p.waitUntilExit()
        killer.cancel()

        if timedOut {
            return .failure(ShellError(message: "ccusage took longer than \(Int(timeout))s and was stopped.", timedOut: true))
        }
        guard p.terminationStatus == 0 else {
            let msg = String(data: errData, encoding: .utf8)?
                .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.last
            return .failure(ShellError(message: "ccusage failed: " + (msg.map { String($0.prefix(200)) } ?? "exit \(p.terminationStatus)")))
        }
        return .success(data)
    }
}
