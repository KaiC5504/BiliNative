import XCTest
@testable import AppLogic

final class TimeFormatTests: XCTestCase {
    private let utc8 = TimeZone(secondsFromGMT: 8 * 3600)!

    private func unix(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int = 0) -> Int64 {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc8
        let date = calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
        return Int64(date.timeIntervalSince1970)
    }

    func testClockAndPair() {
        XCTAssertEqual(TimeFormat.pair(1, 195), "00:01/03:15")
        XCTAssertEqual(TimeFormat.clock(3723), "1:02:03")
        XCTAssertEqual(TimeFormat.clock(195), "03:15")
        XCTAssertEqual(TimeFormat.clock(3599.9), "59:59")
        XCTAssertEqual(TimeFormat.clock(3600), "1:00:00")
    }

    func testClockClampsNonsense() {
        XCTAssertEqual(TimeFormat.clock(-5), "00:00")
        XCTAssertEqual(TimeFormat.clock(.nan), "00:00")
        XCTAssertEqual(TimeFormat.clock(.infinity), "00:00")
    }

    func testPublishInGivenTimeZone() {
        XCTAssertEqual(TimeFormat.publish(unix(2026, 10, 11, 21, 5), timeZone: utc8), "2026年10月11日 21:05")
        XCTAssertEqual(TimeFormat.publish(unix(2026, 1, 2, 3, 4), timeZone: utc8), "2026年1月2日 03:04")
        let utc = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(TimeFormat.publish(unix(2026, 10, 11, 1, 5), timeZone: utc), "2026年10月10日 17:05")
    }

    func testRelativeTimes() {
        let nowUnix = unix(2026, 10, 17, 22, 0)
        let now = Date(timeIntervalSince1970: TimeInterval(nowUnix))
        func rel(_ t: Int64) -> String { TimeFormat.relative(t, now: now, timeZone: utc8) }

        XCTAssertEqual(rel(nowUnix - 30), "刚刚")
        XCTAssertEqual(rel(nowUnix - 59), "刚刚")
        XCTAssertEqual(rel(nowUnix + 30), "刚刚")
        XCTAssertEqual(rel(nowUnix - 60), "1分钟前")
        XCTAssertEqual(rel(nowUnix - 5 * 60), "5分钟前")
        XCTAssertEqual(rel(nowUnix - 3600), "1小时前")
        XCTAssertEqual(rel(nowUnix - 3 * 3600), "3小时前")
        XCTAssertEqual(rel(nowUnix - 24 * 3600 + 1), "23小时前")
        XCTAssertEqual(rel(unix(2026, 10, 16, 21, 5)), "昨天 21:05")
        XCTAssertEqual(rel(unix(2026, 10, 16, 0, 30)), "昨天 00:30")
        XCTAssertEqual(rel(unix(2026, 10, 15, 23, 59)), "10-15")
        XCTAssertEqual(rel(unix(2026, 10, 1, 8, 0)), "10-01")
        XCTAssertEqual(rel(unix(2025, 10, 1, 8, 0)), "2025-10-01")
    }

    func testYesterdayFollowsTheGivenTimeZoneNotTheDeviceOne() {
        // 2026-10-16 07:00 at +8 is 2026-10-15 23:00 in UTC
        let now = Date(timeIntervalSince1970: TimeInterval(unix(2026, 10, 17, 9, 0)))
        let published = unix(2026, 10, 16, 7, 0)
        XCTAssertEqual(TimeFormat.relative(published, now: now, timeZone: utc8), "昨天 07:00")
        XCTAssertEqual(TimeFormat.relative(published, now: now, timeZone: TimeZone(secondsFromGMT: 0)!), "10-15")
    }
}
