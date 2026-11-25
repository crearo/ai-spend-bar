import XCTest
@testable import AIUsageCore

final class DecodeTests: XCTestCase {
    func testRealOutput() throws {
        let url = Bundle.module.url(forResource: "daily", withExtension: "json", subdirectory: "Fixtures")!
        let r = try UsageReport.decode(Data(contentsOf: url))
        XCTAssertFalse(r.daily.isEmpty)
        let byDay = r.costsByDay
        for d in r.daily {
            let sum = byDay[d.day]!.values.reduce(0, +)
            XCTAssertEqual(sum, d.totalCost ?? 0, accuracy: 0.01)
        }
        XCTAssertNotNil(byDay[r.daily.last!.day]!["claude"])
    }
    func testMinimal() throws {
        let r = try UsageReport.decode(Data(#"{"daily":[{"period":"2026-11-01","totalCost":3,"metadata":{"agents":["codex"]}},{}]}"#.utf8))
        XCTAssertEqual(r.costsByDay["2026-11-01"]?["codex"], 3)
        XCTAssertEqual(try UsageReport.decode(Data("{}".utf8)).daily.count, 0)
    }
    func testCCUsageVersion() {
        XCTAssertEqual(CCUsageVersion.parse("ccusage 20.0.51\n"), "20.0.51")
        XCTAssertEqual(CCUsageVersion.parse("ERROR: noise\nccusage 21.0.0-beta.2"), "21.0.0-beta.2")
        XCTAssertNil(CCUsageVersion.parse(""))
        XCTAssertNil(CCUsageVersion.parse("ccusage latest"))
        XCTAssertNil(CCUsageVersion.parse("ccusage file:../evil"))
        XCTAssertNil(CCUsageVersion.parse("ccusage 1.2.3 extra"))
        XCTAssertNil(CCUsageVersion.parse("other 1.2.3"))
        XCTAssertNil(CCUsageVersion.parse("ccusage -..."))
        XCTAssertEqual(CCUsageVersion.validated("20.0.51"), "20.0.51")
        XCTAssertNil(CCUsageVersion.validated("github:evil/ccusage"))
        XCTAssertNil(CCUsageVersion.validated("1.2.3\n../evil"))
        XCTAssertNil(CCUsageVersion.validated("1.2.3\n"))
    }
    func testCCUsageCandidates() {
        // Real `npm view ccusage versions dist-tags --json` shape.
        let json = Data(#"{"versions":["20.0.51","20.1.0","20.1.1","20.1.2"],"dist-tags":{"latest":"20.1.2"}}"#.utf8)
        XCTAssertEqual(NPMPackageInfo.parse(json), NPMPackageInfo(versions: ["20.0.51", "20.1.0", "20.1.1", "20.1.2"], latest: "20.1.2"))
        XCTAssertEqual(NPMPackageInfo.parse(Data(#"["1.0.0","2.0.0"]"#.utf8)), NPMPackageInfo(versions: ["1.0.0", "2.0.0"], latest: nil))
        XCTAssertEqual(NPMPackageInfo.parse(Data(#""1.0.0""#.utf8))?.versions, ["1.0.0"])
        XCTAssertNil(NPMPackageInfo.parse(Data("npm error nope".utf8)))
        let all = ["20.0.9", "20.1.0-beta.1", "20.0.51", "20.1.2", "20.1.0", "20.1.1", "file:../evil"]
        // `latest` (20.1.2) is excluded by the caller; betas and bad specs skipped; numeric, not text, order.
        XCTAssertEqual(CCUsageVersion.candidates(all, excluding: ["20.1.2"], limit: 3), ["20.1.1", "20.1.0", "20.0.51"])
        XCTAssertEqual(CCUsageVersion.candidates(all, excluding: ["20.1.2", "20.1.1"], limit: 2), ["20.1.0", "20.0.51"])
        // Corporate filter: the list stops at 20.1.1 while latest says 20.1.2, so 20.1.1 is tried first.
        XCTAssertEqual(CCUsageVersion.candidates(["20.0.51", "20.1.0", "20.1.1"], excluding: ["20.1.2"], limit: 3),
                       ["20.1.1", "20.1.0", "20.0.51"])
        XCTAssertEqual(CCUsageVersion.candidates([], excluding: [], limit: 3), [])
    }
    func testNewestUpdate() {
        // Real list, including the stray pre-release.
        let all = ["0.0.0-stage", "20261114.3.0", "20261114.4.0", "20261114.5.0", "20261125.0.0", "20261125.1.0", "20261125.2.0"]
        XCTAssertEqual(Version.newestUpdate(in: all, current: "20261114.5"), "20261125.2.0")
        XCTAssertNil(Version.newestUpdate(in: all, current: "20261125.2"))
        // Corporate filter hides today's releases: offer the newest it allows, or nothing.
        XCTAssertEqual(Version.newestUpdate(in: ["20261114.5.0", "20261125.0.0"], current: "20261114.5"), "20261125.0.0")
        XCTAssertNil(Version.newestUpdate(in: ["20261114.3.0", "20261114.4.0", "20261114.5.0"], current: "20261114.5"))
        XCTAssertNil(Version.newestUpdate(in: ["99999999.0.0-beta", "github:evil/x"], current: "1"))
    }
    func testNPMErrorSummary() {
        // Real npm 11 output (a version that doesn't exist).
        let etarget = """
        npm error code ETARGET
        npm error notarget No matching version found for ccusage@999.0.0.
        npm error notarget In most cases you or one of your dependencies are requesting a package version that doesn't exist.
        npm error A complete log of this run can be found in: /Users/x/.npm/_logs/2026-11-25T06_50_55_159Z-debug-0.log
        """
        XCTAssertEqual(NPMError.summary(etarget), "No matching version found for ccusage@999.0.0. (ETARGET)")
        // A registry or security policy blocking the package (corporate npm proxies).
        let e403 = """
        npm error code E403
        npm error 403 403 Forbidden - GET https://npm.corp.example/ccusage - blocked by policy
        npm error 403 In most cases, you or one of your dependencies are requesting
        npm error A complete log of this run can be found in: /Users/x/.npm/_logs/a.log
        """
        XCTAssertEqual(NPMError.summary(e403), "403 Forbidden - GET https://npm.corp.example/ccusage - blocked by policy (E403)")
        let offline = """
        npm error code ECONNREFUSED
        npm error syscall connect
        npm error errno ECONNREFUSED
        npm error FetchError: request to https://registry.npmjs.org/ccusage failed, reason: connect ECONNREFUSED
        npm error A complete log of this run can be found in: /Users/x/a.log
        """
        XCTAssertEqual(NPMError.summary(offline),
                       "FetchError: request to https://registry.npmjs.org/ccusage failed, reason: connect ECONNREFUSED (ECONNREFUSED)")
        XCTAssertEqual(NPMError.summary("npm ERR! code E404\nnpm ERR! 404 Not Found - GET https://x/ccusage\n"),
                       "Not Found - GET https://x/ccusage (E404)")
        XCTAssertEqual(NPMError.summary("npm error code E401\nnpm error A complete log of this run can be found in: a.log"), "(E401)")
        // Not npm's format: ccusage itself failing.
        XCTAssertEqual(NPMError.summary("Error: no data\n\n"), "Error: no data")
        XCTAssertNil(NPMError.summary("\n"))
    }
    func testAutoUpdateBackoff() {
        let h: TimeInterval = 3_600
        XCTAssertEqual((0...8).map { AutoUpdate.wait(afterAttempts: $0) }, [0, h, 2*h, 4*h, 8*h, 16*h, 24*h, 24*h, 24*h])
        XCTAssertEqual(AutoUpdate.wait(afterAttempts: 1_000), 24*h)
        let t = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(AutoUpdate.isDue(attempts: 0, lastTry: nil, now: t))
        XCTAssertTrue(AutoUpdate.isDue(attempts: 3, lastTry: nil, now: t))
        XCTAssertFalse(AutoUpdate.isDue(attempts: 1, lastTry: t, now: t.addingTimeInterval(h - 1)))
        XCTAssertTrue(AutoUpdate.isDue(attempts: 1, lastTry: t, now: t.addingTimeInterval(h)))
        XCTAssertFalse(AutoUpdate.isDue(attempts: 9, lastTry: t, now: t.addingTimeInterval(23*h)))
        XCTAssertTrue(AutoUpdate.isDue(attempts: 9, lastTry: t, now: t.addingTimeInterval(24*h)))
    }
    func testVersion() {
        XCTAssertTrue(Version.isNewer("20261115.0.0", than: "20261114.3.0"))
        XCTAssertTrue(Version.isNewer("20261114.1.0", than: "20261114.0.9"))
        XCTAssertFalse(Version.isNewer("20261114.0.0", than: "20261114.0.0"))
        XCTAssertTrue(Version.isNewer("20261114.2.0", than: "20261114.1"))
        XCTAssertFalse(Version.isNewer("20261114.1.0", than: "20261114.1"))
        XCTAssertEqual(Version.display("20261114.2.0"), "20261114.2")
        XCTAssertEqual(Tools.name("foo"), "Foo")
    }
    func testCodexPricing() {
        let publicPrice = CodexPricing(dollarsPerCredit: nil)
        XCTAssertEqual(publicPrice.cost(apiCost: 10), 10)
        XCTAssertEqual(CodexPricing.credits(apiCost: 10), 250, accuracy: 1e-9)
        // $0.04 a credit is the public API price.
        XCTAssertEqual(CodexPricing(dollarsPerCredit: 0.04).cost(apiCost: 10), 10, accuracy: 1e-9)
        XCTAssertEqual(CodexPricing(dollarsPerCredit: 0.02).cost(apiCost: 10), 5, accuracy: 1e-9)

        let costs = ["2026-11-25": ["codex": 8.0, "claude": 20.0], "2026-11-24": ["claude": 3.0]]
        XCTAssertEqual(publicPrice.apply(costs), costs)
        let corporatePrice = CodexPricing(dollarsPerCredit: 0.01).apply(costs)
        XCTAssertEqual(corporatePrice["2026-11-25"]?["codex"] ?? 0, 2, accuracy: 1e-9)
        XCTAssertEqual(corporatePrice["2026-11-25"]?["claude"], 20)
        XCTAssertEqual(corporatePrice["2026-11-24"], ["claude": 3.0])
    }
    func testParseRate() {
        XCTAssertEqual(CodexPricing.parseRate("0.04"), 0.04)
        XCTAssertEqual(CodexPricing.parseRate(" $0.025 "), 0.025)
        XCTAssertEqual(CodexPricing.parseRate("$ 0.03"), 0.03)
        XCTAssertEqual(CodexPricing.parseRate("0,03"), 0.03)
        XCTAssertEqual(CodexPricing.parseRate(".05"), 0.05)
        XCTAssertEqual(CodexPricing.parseRate("1"), 1)
        for bad in ["", "0", "0.0", "-0.04", "abc", "0.04.1", "0.00001", "10", "1e-2", "$", "."] {
            XCTAssertNil(CodexPricing.parseRate(bad), bad)
        }
    }
}
