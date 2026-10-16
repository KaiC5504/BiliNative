import XCTest
import BiliAPI
@testable import AppLogic

final class HistoryGroupingTests: XCTestCase {
    private let utc8 = TimeZone(secondsFromGMT: 8 * 3600)!

    private func unix(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Int64 {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc8
        return Int64(calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!.timeIntervalSince1970)
    }

    private func item(_ bvid: String, at viewAt: Int64) -> HistoryItem {
        HistoryItem(bvid: bvid, cid: 1, title: bvid, cover: "", ownerName: "", progress: 0, duration: 60, viewAt: viewAt, device: 1, part: nil)
    }

    private var now: Date { Date(timeIntervalSince1970: TimeInterval(unix(2026, 10, 17, 1, 0))) }

    func testGroupingTitles() {
        let items = [
            item("today", at: unix(2026, 10, 17, 0, 30)),
            item("yesterday", at: unix(2026, 10, 16, 23, 0)),
            item("sameYear", at: unix(2026, 10, 1, 8, 0)),
            item("lastYear", at: unix(2025, 12, 31, 12, 0)),
        ]
        let sections = HistoryGrouping.sections(items, now: now, timeZone: utc8)
        XCTAssertEqual(sections.map(\.title), ["今天", "昨天", "10月1日", "2025年12月31日"])
        XCTAssertEqual(sections.map { $0.items.map(\.bvid) }, [["today"], ["yesterday"], ["sameYear"], ["lastYear"]])
    }

    func testRowsOfOneDayShareASectionAndKeepTheirOrder() {
        let items = [
            item("a", at: unix(2026, 10, 16, 23, 0)),
            item("b", at: unix(2026, 10, 16, 9, 0)),
            item("c", at: unix(2026, 10, 16, 0, 5)),
            item("d", at: unix(2026, 10, 15, 23, 59)),
        ]
        let sections = HistoryGrouping.sections(items, now: now, timeZone: utc8)
        XCTAssertEqual(sections.map(\.title), ["昨天", "10月15日"])
        XCTAssertEqual(sections[0].items.map(\.bvid), ["a", "b", "c"])
    }

    func testTheGivenTimeZoneDecidesWhereMidnightFalls() {
        // Now is 01:00 on the 17th at +8 but 17:00 on the 16th in UTC, so a 23:00 row on the 16th is "yesterday" only at +8.
        let utc = TimeZone(secondsFromGMT: 0)!
        let late = [item("late", at: unix(2026, 10, 16, 23, 0))]
        XCTAssertEqual(HistoryGrouping.sections(late, now: now, timeZone: utc8).map(\.title), ["昨天"])
        XCTAssertEqual(HistoryGrouping.sections(late, now: now, timeZone: utc).map(\.title), ["今天"])
    }

    func testNoRowsNoSections() {
        XCTAssertTrue(HistoryGrouping.sections([], now: now, timeZone: utc8).isEmpty)
    }
}
