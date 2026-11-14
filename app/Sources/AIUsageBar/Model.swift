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
    @Published private(set) var updateAvailable: String?
    @Published var range: Range = .today
    @Published var excluded: Set<String> {
        didSet { UserDefaults.standard.set(Array(excluded).sorted(), forKey: "excludedTools") }
    }
    @Published private(set) var loginStatus: SMAppService.Status = SMAppService.mainApp.status

    private var env: [String: String]?
    private var timer: Timer?
    private static let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("com.verycuteapps.ai-usage-bar/last.json")

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
            Task { @MainActor in self?.refresh(); self?.checkForUpdate(); self?.refreshLoginStatus() }
        }
        checkForUpdate()
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

    /// Last 7 days of enabled-tool totals, oldest first.
    var lastWeek: [(day: Date, key: String, cost: Double)] {
        return (0..<7).reversed().map { back in
            let d = Calendar.current.date(byAdding: .day, value: -back, to: Calendar.current.startOfDay(for: Date()))!
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
        Task.detached(priority: .utility) {
            let env = cachedEnv ?? Shell.userEnvironment()
            let result = Shell.runCCUsage(env: env, since: since, until: until)
            await MainActor.run {
                self.env = env
                self.isRefreshing = false
                switch result {
                case .success(let data):
                    do {
                        let r = try UsageReport.decode(data)
                        self.costs = r.costsByDay
                        self.lastUpdated = Date()
                        self.error = nil
                        try? FileManager.default.createDirectory(at: Self.cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try? data.write(to: Self.cacheURL, options: .atomic)
                    } catch {
                        self.error = "Couldn't read ccusage output."
                    }
                case .failure(let e):
                    self.error = e.message
                }
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

    func refreshLoginStatus() { loginStatus = SMAppService.mainApp.status }

    // MARK: Update check (at most once a day)

    func checkForUpdate() {
        let d = UserDefaults.standard
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        if let latest = d.string(forKey: "latestVersion"), Version.isNewer(latest, than: current) {
            updateAvailable = latest
        }
        if let last = d.object(forKey: "lastUpdateCheck") as? Date, Date().timeIntervalSince(last) < 86_400 { return }
        d.set(Date(), forKey: "lastUpdateCheck")
        Task {
            guard let url = URL(string: "https://registry.npmjs.org/ai-usage-bar/latest"),
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let latest = obj["version"] as? String else { return }
            d.set(latest, forKey: "latestVersion")
            updateAvailable = Version.isNewer(latest, than: current) ? latest : nil
        }
    }
}

struct ShellError: Error { let message: String }

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

    static func findExecutable(_ name: String, path: String) -> String? {
        path.split(separator: ":").map { "\($0)/\(name)" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func runCCUsage(env: [String: String], since: String, until: String) -> Result<Data, ShellError> {
        guard let npx = findExecutable("npx", path: env["PATH"] ?? "") else {
            return .failure(ShellError(message: "Node.js is needed. Install it, then run npx ai-usage-bar again."))
        }
        return run(npx, ["--yes", "ccusage@latest", "daily", "--json", "--by-agent", "--since", since, "--until", until],
                   env: env, timeout: 90)
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

        if timedOut { return .failure(ShellError(message: "ccusage took longer than \(Int(timeout))s and was stopped.")) }
        guard p.terminationStatus == 0 else {
            let msg = String(data: errData, encoding: .utf8)?
                .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.last
            return .failure(ShellError(message: "ccusage failed: " + (msg.map { String($0.prefix(200)) } ?? "exit \(p.terminationStatus)")))
        }
        return .success(data)
    }
}
