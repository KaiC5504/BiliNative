import XCTest
@testable import BiliAPI

final class RichTextTests: XCTestCase {
    private let doge = EmoteRef(url: "u", size: 1)

    private func runs(_ message: String, emotes: [String: EmoteRef] = [:], mentions: [String: Int64] = [:],
                      links: [String: LinkRef] = [:]) -> [RichRun] {
        RichText.runs(message, emotes: emotes, mentions: mentions, links: links)
    }

    func testRunsSplitEmotesMentionsLinksVideosAndTimestamps() {
        let runs = RichText.runs("看[doge]@小明 BV1GJ411x7h7 在03:15这里", emotes: ["[doge]": .init(url: "u", size: 1)],
                                 mentions: ["小明": 42], links: [:])
        XCTAssertEqual(runs, [.text("看"), .emote(token: "[doge]", url: "u", size: 1), .mention(name: "小明", mid: 42), .text(" "),
                              .video(id: "BV1GJ411x7h7"), .text(" 在"), .timestamp(label: "03:15", seconds: 195), .text("这里")])
    }

    func testRunsKeepEmojiAndUnknownTokens() {
        XCTAssertEqual(RichText.runs("😀[未知]😀[doge][doge]", emotes: ["[doge]": .init(url: "u", size: 1)], mentions: [:], links: [:]),
                       [.text("😀[未知]😀"), .emote(token: "[doge]", url: "u", size: 1), .emote(token: "[doge]", url: "u", size: 1)])
    }

    func testPlainAndEmptyMessages() {
        XCTAssertEqual(runs("没有任何标记"), [.text("没有任何标记")])
        XCTAssertEqual(runs(""), [])
        XCTAssertEqual(runs("[doge]", emotes: ["[doge]": doge]), [.emote(token: "[doge]", url: "u", size: 1)])
    }

    func testEmoteSizeIsCarried() {
        XCTAssertEqual(runs("[大]", emotes: ["[大]": .init(url: "big", size: 2)]), [.emote(token: "[大]", url: "big", size: 2)])
    }

    func testTheLongestMentionWinsAtOnePosition() {
        let found = runs("@小明明 和 @小明", mentions: ["小明": 1, "小明明": 2])
        XCTAssertEqual(found, [.mention(name: "小明明", mid: 2), .text(" 和 "), .mention(name: "小明", mid: 1)])
    }

    func testAMentionWithoutTheAtSignStaysText() {
        XCTAssertEqual(runs("小明 来了", mentions: ["小明": 1]), [.text("小明 来了")])
    }

    func testEachLinkKeyIsReplacedOnce() {
        let links = ["rick叔": LinkRef(title: "rick叔", url: "https://search.bilibili.com/all?keyword=rick")]
        let found = runs("rick叔的歌，rick叔真好", links: links)
        XCTAssertEqual(found, [.link(title: "rick叔", url: "https://search.bilibili.com/all?keyword=rick"), .text("的歌，rick叔真好")])
    }

    func testLinkKeysBeatVideoIdsAndEmotesBeatLinks() {
        let links = ["BV1GJ411x7h7": LinkRef(title: "某个视频", url: "https://www.bilibili.com/video/BV1GJ411x7h7")]
        XCTAssertEqual(runs("看 BV1GJ411x7h7 和 BV1AB411c7mD", links: links),
                       [.text("看 "), .link(title: "某个视频", url: "https://www.bilibili.com/video/BV1GJ411x7h7"),
                        .text(" 和 "), .video(id: "BV1AB411c7mD")])
        XCTAssertEqual(runs("[doge]", emotes: ["[doge]": doge], links: ["[doge]": LinkRef(title: "t", url: "x")]),
                       [.emote(token: "[doge]", url: "u", size: 1)])
    }

    func testVideoIds() {
        XCTAssertEqual(runs("av170001和BV1GJ411x7h7。"), [.video(id: "av170001"), .text("和"), .video(id: "BV1GJ411x7h7"), .text("。")])
        XCTAssertEqual(runs("BV1GJ411"), [.text("BV1GJ411")])
        XCTAssertEqual(runs("av 123 和 avatar"), [.text("av 123 和 avatar")])
        XCTAssertEqual(runs("BV1GJ411x7h!"), [.text("BV1GJ411x7h!")])
        XCTAssertEqual(runs("lav12"), [.text("lav12")])
    }

    func testTimestamps() {
        XCTAssertEqual(runs("1:05:09开始"), [.timestamp(label: "1:05:09", seconds: 3909), .text("开始")])
        XCTAssertEqual(runs("看12：30"), [.text("看"), .timestamp(label: "12：30", seconds: 750)])
        XCTAssertEqual(runs("00:00"), [.timestamp(label: "00:00", seconds: 0)])
        XCTAssertEqual(runs("03:15 03:20"), [.timestamp(label: "03:15", seconds: 195), .text(" "), .timestamp(label: "03:20", seconds: 200)])
    }

    func testNumbersThatAreNotTimestampsStayText() {
        XCTAssertEqual(runs("比例3:2"), [.text("比例3:2")])
        XCTAssertEqual(runs("1920:1080"), [.text("1920:1080")])
        XCTAssertEqual(runs("2024:15"), [.text("2024:15")])
        XCTAssertEqual(runs("03:156"), [.text("03:156")])
        XCTAssertEqual(runs("10:30:456"), [.timestamp(label: "10:30", seconds: 630), .text(":456")])
        XCTAssertEqual(runs("1:99"), [.text("1:99")])
    }

    func testSplittingNeverCutsACharacter() {
        // 1️⃣ is a digit plus two combining scalars, so it is one Character that is not the digit 1.
        XCTAssertEqual(runs("1\u{FE0F}\u{20E3}2:30"), [.text("1\u{FE0F}\u{20E3}"), .timestamp(label: "2:30", seconds: 150)])
        // A combining accent after the closing bracket makes the last Character something other than "]".
        let accented = "[doge]\u{301}"
        XCTAssertEqual(runs(accented, emotes: ["[doge]": doge]), [.text(accented)])
        XCTAssertEqual(runs("👨‍👩‍👧@小明", mentions: ["小明": 1]), [.text("👨‍👩‍👧"), .mention(name: "小明", mid: 1)])
    }

    func testTextAroundEveryKindIsMergedWhenNothingMatchesBetween() {
        XCTAssertEqual(runs("a[未知]b@没人c", emotes: ["[doge]": doge], mentions: ["小明": 1]), [.text("a[未知]b@没人c")])
    }
}
