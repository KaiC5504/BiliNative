import XCTest
@testable import BiliAPI

final class TrackSelectorTests: XCTestCase {
    private var dash: Dash!

    override func setUpWithError() throws {
        let envelope = try JSONDecoder().decode(BiliEnvelope<PlayURLInfo>.self, from: Data(Fixtures.playURL.utf8))
        dash = try XCTUnwrap(envelope.data?.dash)
    }

    func testPrefersRequestedCodecAtRequestedQuality() {
        XCTAssertEqual(TrackSelector.choose(dash, quality: 120, codecOrder: [.hevc, .avc])?.video.codecs, "hev1.1.6.L153.90")
        XCTAssertEqual(TrackSelector.choose(dash, quality: 120, codecOrder: [.avc])?.video.codecs, "avc1.640034")
    }

    func testFallsToNextLowerQualityAndAnyCodec() {
        let choice = TrackSelector.choose(dash, quality: 116, codecOrder: [.hevc])
        XCTAssertEqual(choice?.video.id, 80)
        XCTAssertEqual(choice?.video.codecid, 13)
    }

    func testDolbyVisionCanBeExcluded() {
        XCTAssertEqual(TrackSelector.choose(dash, quality: 127, codecOrder: [.hevc])?.video.id, 126)
        XCTAssertEqual(TrackSelector.choose(dash, quality: 127, codecOrder: [.hevc], excludeDolbyVision: true)?.video.id, 120)
    }

    func testQualityBelowEverythingPicksLowest() {
        XCTAssertEqual(TrackSelector.choose(dash, quality: 16, codecOrder: [.hevc])?.video.id, 80)
    }

    func testBestAudioAndKinds() {
        XCTAssertEqual(TrackSelector.bestAudio(dash.audio)?.id, 30280)
        XCTAssertEqual(TrackSelector.codecKind(dash.video[3]), "dolby")
        XCTAssertEqual(TrackSelector.codecKind(dash.video[0]), "hevc")
        XCTAssertEqual(TrackSelector.codecKind(dash.video[2]), "av1")
        XCTAssertEqual(TrackSelector.codecKind(dash.video[1]), "avc")
    }

    func testNoUsableAudioMeansNoChoice() {
        let silent = Dash(duration: dash.duration, video: dash.video, audio: [])
        XCTAssertNil(TrackSelector.choose(silent, quality: 120, codecOrder: [.hevc]))
    }
}
