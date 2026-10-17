import XCTest

/// Real touches through the system on a video page opened from the 推荐 feed. The app tests can only ask the
/// gesture delegates what they would answer; build 7 passed those while UIKit never let the swipe begin.
final class SwipeBackUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-DemoData", "YES"]
        app.launch()
    }

    private var onHome: Bool { app.textFields.firstMatch.isHittable }

    private func openFromFeed() {
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 10))
        sleep(2)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.3)).tap()
        let left = expectation(for: NSPredicate { _, _ in !self.onHome }, evaluatedWith: nil)
        wait(for: [left], timeout: 10)
        sleep(3)
    }

    /// A thumb's swipe: a short touch, then a flick at about 1500 points a second, released while still moving
    /// (XCTest's `.fast` is about 400, slow enough that UIKit cancels a back swipe over half the screen).
    private func drag(fromX x: CGFloat, toX end: CGFloat, y: CGFloat) {
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: end, dy: y))
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: XCUIGestureVelocity(1500), thenHoldForDuration: 0)
        sleep(2)
    }

    private func expectHome(_ home: Bool, _ step: String, file: StaticString = #filePath, line: UInt = #line) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = step
        shot.lifetime = .keepAlways
        add(shot)
        XCTAssertEqual(onHome, home, home ? "\(step): did not go back" : "\(step): went back", file: file, line: line)
    }

    func testEdgeSwipeOnTheIntro() {
        openFromFeed()
        drag(fromX: 0, toX: 0.9, y: 0.75)
        expectHome(true, "edge on 简介")
    }

    func testEdgeSwipeOnThePlayer() {
        openFromFeed()
        drag(fromX: 0, toX: 0.9, y: 0.18)
        expectHome(true, "edge on the player")
    }

    func testSwipeInTheMiddleOfTheIntro() {
        openFromFeed()
        drag(fromX: 0.3, toX: 0.75, y: 0.75)
        expectHome(true, "middle of 简介")
    }

    /// 评论 pages back to 简介 first, as in the official app; the next swipe goes back.
    func testSwipeOnTheCommentsPagesToTheIntroFirst() {
        openFromFeed()
        drag(fromX: 0.8, toX: 0.1, y: 0.75)
        expectHome(false, "to 评论")
        drag(fromX: 0.3, toX: 0.9, y: 0.75)
        expectHome(false, "评论 back to 简介")
        drag(fromX: 0.3, toX: 0.9, y: 0.75)
        expectHome(true, "简介 back home")
    }

    /// A sideways drag on the player seeks.
    func testSwipeInTheMiddleOfThePlayerStays() {
        openFromFeed()
        drag(fromX: 0.3, toX: 0.9, y: 0.18)
        expectHome(false, "middle of the player")
    }

    /// 评论详情 closes first (sliding down) and the page stays.
    func testSwipeClosesTheReplyThreadFirst() {
        openFromFeed()
        drag(fromX: 0.8, toX: 0.1, y: 0.75)
        let replies = app.staticTexts.containing(NSPredicate(format: "label CONTAINS '条回复'")).firstMatch
        XCTAssertTrue(replies.waitForExistence(timeout: 8), "no reply thread in the demo comments")
        replies.tap()
        let header = app.staticTexts["评论详情"]
        XCTAssertTrue(header.waitForExistence(timeout: 5), "the thread did not open")
        drag(fromX: 0.3, toX: 0.75, y: 0.75)
        XCTAssertFalse(header.exists, "the swipe did not close the thread")
        expectHome(false, "thread closed")
    }

    /// The lists still scroll up and down while every drag waits for the swipe back.
    func testTheIntroStillScrolls() throws {
        openFromFeed()
        let height = app.frame.height
        let label = app.staticTexts.allElementsBoundByIndex.first { $0.frame.minY > height * 0.6 && $0.frame.minY < height * 0.9 }
        let text = try XCTUnwrap(label?.label, "no text low on 简介 to follow")
        let before = try XCTUnwrap(label).frame.minY
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        from.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
                   withVelocity: XCUIGestureVelocity(800), thenHoldForDuration: 0.3)
        let after = app.staticTexts[text].firstMatch
        XCTAssertTrue(!after.exists || after.frame.minY < before - 50, "简介 did not scroll: \(before) -> \(after.frame.minY)")
        expectHome(false, "scrolled")
    }
}
