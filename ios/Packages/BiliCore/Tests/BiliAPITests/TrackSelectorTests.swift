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

    func testDolbyVisionIsChosenWhenItIsTheRequestedQuality() {
        XCTAssertEqual(TrackSelector.choose(dash, quality: 127, codecOrder: [.hevc])?.video.id, 126)
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

    func testRequestedCodecAtLowerQuality() {
        let choice = TrackSelector.choose(dash, quality: 80, codecOrder: [.av1])
        XCTAssertEqual(choice?.video.codecid, 13)
        XCTAssertEqual(choice?.video.id, 80)
    }

    func testBestAudioIgnoresOrderAndNonAAC() throws {
        let template = try XCTUnwrap(dash.audio.first)
        func audio(_ id: Int, bandwidth: Int, codecs: String = "mp4a.40.2") -> DashStream {
            DashStream(id: id, baseURL: template.baseURL, backupURLs: [], bandwidth: bandwidth, mimeType: "audio/mp4", codecs: codecs,
                       codecid: 0, width: 0, height: 0, frameRate: nil, initialization: template.initialization, indexRange: template.indexRange)
        }
        let flac = audio(30251, bandwidth: 999_999, codecs: "fLaC")
        let streams = [audio(30232, bandwidth: 132_000), flac, audio(30216, bandwidth: 67_000), audio(30280, bandwidth: 192_000)]
        XCTAssertEqual(TrackSelector.bestAudio(streams)?.id, 30280)
        XCTAssertEqual(TrackSelector.bestAudio(streams.filter { $0.id != 30280 })?.id, 30232)
        XCTAssertEqual(TrackSelector.bestAudio(Array(streams.reversed()).filter { $0.id == 30216 || $0.id == 30251 })?.id, 30216)
        XCTAssertNil(TrackSelector.bestAudio([flac]))
    }

    func testNoUsableAudioMeansNoChoice() {
        let silent = Dash(duration: dash.duration, video: dash.video, audio: [])
        XCTAssertNil(TrackSelector.choose(silent, quality: 120, codecOrder: [.hevc]))
    }
}
