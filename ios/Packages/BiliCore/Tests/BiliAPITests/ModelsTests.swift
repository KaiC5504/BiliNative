import XCTest
import BiliShared
@testable import BiliAPI

final class ModelsTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> BiliEnvelope<T> {
        try JSONDecoder().decode(BiliEnvelope<T>.self, from: Data(json.utf8))
    }

    func testNavLoggedOutStillCarriesWBIKeys() throws {
        let envelope = try decode(NavInfo.self, Fixtures.navLoggedOut)
        XCTAssertEqual(envelope.code, -101)
        XCTAssertEqual(envelope.data?.isLogin, false)
        XCTAssertEqual(envelope.data?.imgURL, "https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png")
    }

    func testNavLoggedIn() throws {
        let nav = try XCTUnwrap(decode(NavInfo.self, Fixtures.navLoggedIn).data)
        XCTAssertTrue(nav.isLogin)
        XCTAssertTrue(nav.isVip)
        XCTAssertEqual(nav.mid, 12345)
        XCTAssertEqual(nav.uname, "测试用户")
    }

    func testView() throws {
        let view = try XCTUnwrap(decode(VideoView.self, Fixtures.view).data)
        XCTAssertEqual(view.bvid, "BV1GJ411x7h7")
        XCTAssertEqual(view.owner, "UP主")
        XCTAssertEqual(view.pages.map(\.cid), [137649199, 137649200])
        XCTAssertEqual(view.pages[1].part, "第二集")
    }

    func testErrorEnvelopeWithoutData() throws {
        let envelope = try decode(VideoView.self, Fixtures.notFound)
        XCTAssertEqual(envelope.code, -404)
        XCTAssertNil(envelope.data)
    }

    func testPlayURLFieldSpellings() throws {
        let info = try XCTUnwrap(decode(PlayURLInfo.self, Fixtures.playURL).data)
        let dash = try XCTUnwrap(info.dash)
        XCTAssertEqual(dash.duration, 214)
        XCTAssertEqual(dash.video.count, 4)
        let hevc = dash.video[0]
        XCTAssertEqual(hevc.baseURL, "https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/1/2/3/3-1-100151.m4s?deadline=1760000000&os=cosbv")
        XCTAssertEqual(hevc.backupURLs.count, 1)
        XCTAssertEqual(hevc.initialization, ByteRange(start: 0, end: 1104))
        XCTAssertEqual(hevc.indexRange, ByteRange(start: 1105, end: 1688))
        XCTAssertEqual(hevc.frameRate, "29.412")
        let snake = dash.video[1]
        XCTAssertEqual(snake.backupURLs, [])
        XCTAssertNil(snake.frameRate)
        XCTAssertEqual(snake.indexRange, ByteRange(start: 1001, end: 1600))
        XCTAssertEqual(dash.audio.map(\.id), [30216, 30280])
        XCTAssertFalse(info.hasDurl)
        XCTAssertEqual(info.qualityOptions.first, QualityOption(id: 127, name: "超高清 8K"))
    }

    func testDurlOnlyHasNoDash() throws {
        let info = try XCTUnwrap(decode(PlayURLInfo.self, Fixtures.durlOnly).data)
        XCTAssertNil(info.dash)
        XCTAssertTrue(info.hasDurl)
    }

    func testSnakeCaseOnlyStreamDecodesEveryField() throws {
        let dash = try XCTUnwrap(decode(PlayURLInfo.self, Fixtures.playURL).data?.dash)
        let snake = dash.video[1]
        XCTAssertEqual(snake.baseURL, "https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/1/2/3/3-1-100048.m4s?deadline=1760000000")
        XCTAssertEqual(snake.mimeType, "video/mp4")
        XCTAssertEqual(snake.initialization, ByteRange(start: 0, end: 1000))
    }

    func testCamelCaseOnlyStreamDecodesEveryField() throws {
        let dash = try XCTUnwrap(decode(PlayURLInfo.self, Fixtures.playURL).data?.dash)
        let av1 = dash.video[2]
        XCTAssertEqual(av1.baseURL, "https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/1/2/3/3-1-100113.m4s?deadline=1760000000")
        XCTAssertEqual(av1.mimeType, "video/mp4")
        XCTAssertEqual(av1.initialization, ByteRange(start: 0, end: 900))
        XCTAssertEqual(av1.indexRange, ByteRange(start: 901, end: 1500))
        XCTAssertEqual(av1.frameRate, "29.412")
    }

    func testNullBackupUrlDecodesAsEmpty() throws {
        let dash = try XCTUnwrap(decode(PlayURLInfo.self, Fixtures.playURL).data?.dash)
        XCTAssertEqual(dash.video[3].backupURLs, [])
        XCTAssertEqual(dash.audio[0].backupURLs, [])
    }

    func testEmptyFrameRateDecodesAsNil() throws {
        let dash = try XCTUnwrap(decode(PlayURLInfo.self, Fixtures.playURL).data?.dash)
        XCTAssertNil(dash.audio[0].frameRate)
    }

    func testUnknownFieldsAreIgnored() throws {
        // The playURL fixture already carries dolby, flac, minBufferTime and format beside the modelled fields.
        let info = try XCTUnwrap(decode(PlayURLInfo.self, Fixtures.playURL).data)
        XCTAssertEqual(info.quality, 120)
        let extra = #"{"code":0,"message":"0","brand_new":{"x":[1,2]},"data":{"bvid":"BV1GJ411x7h7","future_field":null,"pages":[{"cid":1,"page":1,"part":"p","duration":3,"dimension":{"width":1}}]}}"#
        let view = try XCTUnwrap(decode(VideoView.self, extra).data)
        XCTAssertEqual(view.pages.map(\.cid), [1])
    }

    func testDashNullWithDurlDecodes() throws {
        let json = #"{"code":0,"message":"0","data":{"quality":16,"accept_quality":[16],"accept_description":["流畅 360P"],"dash":null,"durl":[{"order":1,"url":"https://x/a.flv"}]}}"#
        let info = try XCTUnwrap(decode(PlayURLInfo.self, json).data)
        XCTAssertNil(info.dash)
        XCTAssertTrue(info.hasDurl)
    }

    func testBareMinimumPlayURLDecodes() throws {
        let info = try XCTUnwrap(decode(PlayURLInfo.self, #"{"code":0,"data":{}}"#).data)
        XCTAssertNil(info.dash)
        XCTAssertFalse(info.hasDurl)
        XCTAssertEqual(info.qualityOptions, [])
    }

    private func playURL(video: [String], audio: [String] = [], extra: String = "") -> String {
        #"{"code":0,"data":{"quality":80,"dash":{"duration":10,"video":[\#(video.joined(separator: ","))],"audio":[\#(audio.joined(separator: ","))]}\#(extra)}}"#
    }

    private func stream(id: Int = 80, extra: String) -> String {
        #"{"id":\#(id),"baseUrl":"https://h/a.m4s","bandwidth":1,"mimeType":"video/mp4","codecs":"avc1","codecid":7,\#(extra)}"#
    }

    private let goodBase = #""SegmentBase":{"Initialization":"0-9","indexRange":"10-19"}"#

    func testStreamWithoutSegmentBaseIsDroppedNotFatal() throws {
        let json = playURL(
            video: [stream(id: 64, extra: goodBase), stream(id: 80, extra: #""width":1"#), stream(id: 120, extra: goodBase)],
            audio: [#"{"id":30280,"codecs":"mp4a.40.2"}"#, stream(id: 30216, extra: goodBase)])
        let dash = try XCTUnwrap(decode(PlayURLInfo.self, json).data?.dash)
        XCTAssertEqual(dash.video.map(\.id), [64, 120])
        XCTAssertEqual(dash.audio.map(\.id), [30216])
    }

    func testStreamWithoutBaseURLIsDropped() throws {
        let noURL = #"{"id":80,"codecs":"avc1","SegmentBase":{"Initialization":"0-9","indexRange":"10-19"}}"#
        let dash = try XCTUnwrap(decode(PlayURLInfo.self, playURL(video: [noURL, stream(id: 64, extra: goodBase)])).data?.dash)
        XCTAssertEqual(dash.video.map(\.id), [64])
    }

    func testIncompleteSegmentBaseFallsThroughToOtherSpelling() throws {
        let both = stream(extra: #""SegmentBase":{"Initialization":"0-9"},"segment_base":{"initialization":"0-5","index_range":"6-11"}"#)
        let dash = try XCTUnwrap(decode(PlayURLInfo.self, playURL(video: [both])).data?.dash)
        XCTAssertEqual(dash.video.first?.initialization, ByteRange(start: 0, end: 5))
        XCTAssertEqual(dash.video.first?.indexRange, ByteRange(start: 6, end: 11))
        let reverse = stream(extra: #""segment_base":{"index_range":"junk"},"SegmentBase":{"Initialization":"0-9","indexRange":"10-19"}"#)
        let other = try XCTUnwrap(decode(PlayURLInfo.self, playURL(video: [reverse])).data?.dash)
        XCTAssertEqual(other.video.first?.indexRange, ByteRange(start: 10, end: 19))
    }

    func testFrameRateOnlyInSnakeCase() throws {
        let dash = try XCTUnwrap(decode(PlayURLInfo.self, playURL(video: [stream(extra: goodBase + #","frame_rate":"25""#)])).data?.dash)
        XCTAssertEqual(dash.video.first?.frameRate, "25")
    }

    func testBackupUrlOnlyInSnakeCase() throws {
        let dash = try XCTUnwrap(decode(PlayURLInfo.self, playURL(video: [stream(extra: goodBase + #","backup_url":["https://h/b.m4s"]"#)])).data?.dash)
        XCTAssertEqual(dash.video.first?.backupURLs, ["https://h/b.m4s"])
    }

    func testHasDurlNeedsANonEmptyArray() throws {
        for (extra, expected) in [(#","durl":null"#, false), (#","durl":[]"#, false), ("", false),
                                  (#","durl":[{"order":1,"url":"https://x/a.flv"}]"#, true)] {
            let info = try XCTUnwrap(decode(PlayURLInfo.self, playURL(video: [], extra: extra)).data)
            XCTAssertEqual(info.hasDurl, expected, extra)
        }
    }

    func testSPI() throws {
        let spi = try XCTUnwrap(decode(SPIInfo.self, Fixtures.spi).data)
        XCTAssertEqual(spi.b3, "B3-VALUE-infoc")
        XCTAssertEqual(spi.b4, "B4-VALUE")
    }
}
