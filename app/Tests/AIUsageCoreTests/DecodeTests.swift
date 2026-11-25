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
    func testVersion() {
        XCTAssertTrue(Version.isNewer("20261115.0.0", than: "20261114.3.0"))
        XCTAssertTrue(Version.isNewer("20261114.1.0", than: "20261114.0.9"))
        XCTAssertFalse(Version.isNewer("20261114.0.0", than: "20261114.0.0"))
        XCTAssertTrue(Version.isNewer("20261114.2.0", than: "20261114.1"))
        XCTAssertFalse(Version.isNewer("20261114.1.0", than: "20261114.1"))
        XCTAssertEqual(Version.display("20261114.2.0"), "20261114.2")
        XCTAssertEqual(Tools.name("foo"), "Foo")
    }
}
