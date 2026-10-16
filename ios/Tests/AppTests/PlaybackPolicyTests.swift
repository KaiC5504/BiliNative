import AVFoundation
import XCTest
@testable import BiliNative

final class PlaybackPolicyTests: XCTestCase {
    private let everyCodec = DebugSupport.codecDash([(80, 12, "hev1.1.6.L120.90"), (80, 13, "av01.0.08M.08"), (80, 7, "avc1.640032")])

    func testChoiceSkipsRejectedCodecs() {
        let first = PlaybackController.choose(everyCodec, quality: 80, codecOrder: [.hevc, .av1, .avc], excluded: [])
        XCTAssertEqual(first?.video.codecid, 12)
        let second = PlaybackController.choose(everyCodec, quality: 80, codecOrder: [.hevc, .av1, .avc], excluded: ["hevc"])
        XCTAssertEqual(second?.video.codecid, 13)
        let third = PlaybackController.choose(everyCodec, quality: 80, codecOrder: [.hevc, .av1, .avc], excluded: ["hevc", "av1"])
        XCTAssertEqual(third?.video.codecid, 7)
    }

    func testChoiceNeverFallsBackToARejectedCodec() {
        // TrackSelector's any-codec fallback would hand back the rejected stream here.
        let hevcOnly = DebugSupport.codecDash([(80, 12, "hvc1.1.6.L120.90")])
        XCTAssertNil(PlaybackController.choose(hevcOnly, quality: 80, codecOrder: [.avc], excluded: ["hevc"]))
        XCTAssertNil(PlaybackController.choose(everyCodec, quality: 80, codecOrder: [.hevc, .av1, .avc], excluded: ["hevc", "av1", "avc"]))
    }

    func testUnknownCodecsAreOnlyTriedBeforeAnyRejection() {
        let unknown = DebugSupport.codecDash([(80, 99, "xyz1"), (64, 7, "avc1.640028")])
        XCTAssertEqual(PlaybackController.choose(unknown, quality: 80, codecOrder: [.hevc], excluded: [])?.video.codecid, 99)
        let afterRejection = PlaybackController.choose(unknown, quality: 80, codecOrder: [.avc], excluded: ["hevc"])
        XCTAssertEqual(afterRejection?.video.codecid, 7)
        XCTAssertEqual(afterRejection?.video.id, 64)
    }

    func testRejectedCodecMovesToALowerQualityThatHasAnother() {
        let dash = DebugSupport.codecDash([(120, 12, "hvc1.2.4.L153.90"), (80, 12, "hvc1.1.6.L120.90"), (80, 7, "avc1.640032")])
        let choice = PlaybackController.choose(dash, quality: 120, codecOrder: [.avc], excluded: ["hevc"])
        XCTAssertEqual(choice?.video.id, 80)
        XCTAssertEqual(choice?.video.codecid, 7)
    }

    func testDirectModeSkipsHEV1ButKeepsHVC1() {
        let direct = PlaybackController.choose(everyCodec, quality: 80, codecOrder: [.hevc, .av1, .avc], excluded: [], skipHEV1: true)
        XCTAssertEqual(direct?.video.codecid, 13)
        let hvc1 = DebugSupport.codecDash([(80, 12, "hvc1.1.6.L120.90"), (80, 7, "avc1.640032")])
        XCTAssertEqual(PlaybackController.choose(hvc1, quality: 80, codecOrder: [.hevc, .avc], excluded: [], skipHEV1: true)?.video.codecid, 12)
    }

    func testDecoderErrorsAreFormatFailures() {
        let decode = NSError(domain: AVFoundationErrorDomain, code: AVError.Code.decodeFailed.rawValue)
        XCTAssertEqual(PlaybackController.classify(decode, log: []), .format)
        let parse = NSError(domain: AVFoundationErrorDomain, code: AVError.Code.failedToParse.rawValue)
        XCTAssertEqual(PlaybackController.classify(parse, log: []), .format)
    }

    func testNetworkEvidenceWinsOverAFormatError() {
        let urlError = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        XCTAssertEqual(PlaybackController.classify(urlError, log: []), .network)
        let wrapped = NSError(domain: AVFoundationErrorDomain, code: AVError.Code.failedToParse.rawValue,
                              userInfo: [NSUnderlyingErrorKey: urlError])
        XCTAssertEqual(PlaybackController.classify(wrapped, log: []), .network)
        // An expired URL answers 403 with a body AVFoundation then fails to parse.
        let parse = NSError(domain: AVFoundationErrorDomain, code: AVError.Code.failedToParse.rawValue)
        let refused = PlaybackController.ErrorLogEntry(domain: "CoreMediaErrorDomain", status: -12660, comment: "HTTP 403: Forbidden")
        XCTAssertEqual(PlaybackController.classify(parse, log: [refused]), .network)
        let status = PlaybackController.ErrorLogEntry(domain: "CoreMediaErrorDomain", status: 410, comment: "")
        XCTAssertEqual(PlaybackController.classify(parse, log: [status]), .network)
    }

    func testOtherErrorsAreUnknown() {
        XCTAssertEqual(PlaybackController.classify(NSError(domain: "CoreMediaErrorDomain", code: -12345), log: []), .unknown)
        XCTAssertEqual(PlaybackController.classify(nil, log: []), .unknown)
    }

    func testAFormatFailureInBTRModeTriesTheNextCodecThere() {
        XCTAssertEqual(PlaybackController.reaction(to: .format, in: .ripper, sourceEntry: "hev1", played: false), .nextCodec(remember: true))
        XCTAssertEqual(PlaybackController.reaction(to: .format, in: .ripper, sourceEntry: nil, played: false), .nextCodec(remember: true))
        XCTAssertEqual(PlaybackController.reaction(to: .network, in: .ripper, sourceEntry: nil, played: false), .fallBackToDirect)
        XCTAssertEqual(PlaybackController.reaction(to: .unknown, in: .ripper, sourceEntry: nil, played: false), .fallBackToDirect)
    }

    func testDirectModeFailures() {
        XCTAssertEqual(PlaybackController.reaction(to: .format, in: .direct, sourceEntry: "hvc1", played: false), .nextCodec(remember: true))
        XCTAssertEqual(PlaybackController.reaction(to: .format, in: .directFallback, sourceEntry: "hev1", played: false), .nextCodec(remember: false))
        XCTAssertEqual(PlaybackController.reaction(to: .network, in: .direct, sourceEntry: nil, played: false), .restart)
        XCTAssertEqual(PlaybackController.reaction(to: .unknown, in: .directFallback, sourceEntry: nil, played: false), .restartOnceThenNextCodec)
    }

    func testAFormatFailureAfterPlayingIsNotRememberedAgainstTheCodec() {
        for mode: PlaybackController.Mode in [.ripper, .direct, .directFallback] {
            XCTAssertEqual(PlaybackController.reaction(to: .format, in: mode, sourceEntry: "hvc1", played: true), .nextCodec(remember: false),
                           "\(mode)")
        }
        XCTAssertEqual(PlaybackController.reaction(to: .network, in: .ripper, sourceEntry: nil, played: true), .fallBackToDirect)
        XCTAssertEqual(PlaybackController.reaction(to: .network, in: .direct, sourceEntry: nil, played: true), .restart)
    }

    func testDirectModePlaysAHEV1LabelOnlyOverHVC1Bytes() throws {
        let hev1 = try XCTUnwrap(PlaybackController.choose(everyCodec, quality: 80, codecOrder: [.hevc], excluded: [])).video
        XCTAssertFalse(PlaybackController.directCanPlay(hev1, sourceEntry: nil))
        XCTAssertFalse(PlaybackController.directCanPlay(hev1, sourceEntry: "hev1"))
        XCTAssertTrue(PlaybackController.directCanPlay(hev1, sourceEntry: "hvc1"))
        let avc = try XCTUnwrap(PlaybackController.choose(everyCodec, quality: 80, codecOrder: [.avc], excluded: [])).video
        XCTAssertTrue(PlaybackController.directCanPlay(avc, sourceEntry: nil))
    }

    func testURLsCountAsStaleFiveMinutesBeforeTheirDeadline() throws {
        let signed = DebugSupport.headerFixture(withMoov: true).choice
        XCTAssertTrue(PlaybackController.urlsNearExpiry(signed, now: Date(timeIntervalSince1970: 0)))
        XCTAssertFalse(PlaybackController.urlsNearExpiry(signed, now: Date(timeIntervalSince1970: -1000)))
        let unsigned = try XCTUnwrap(PlaybackController.choose(everyCodec, quality: 80, codecOrder: [.avc], excluded: []))
        XCTAssertFalse(PlaybackController.urlsNearExpiry(unsigned, now: Date()))
    }

    func testPlayURLSummaryListsHostsNotURLs() {
        let summary = PlaybackController.playURLSummary(DebugSupport.codecPlayURL([(80, 12, "hev1.1.6.L120.90"), (64, 7, "avc1.640028")]))
        XCTAssertEqual(summary["accept"], "80,64")
        XCTAssertEqual(summary["streams"], "80:hev1.1.6.L120.90,64:avc1.640028")
        XCTAssertEqual(summary["videoHosts"], "primary.invalid")
        XCTAssertEqual(summary["audioHosts"], "primary.invalid")
        XCTAssertFalse(summary.values.contains { $0.contains("/") || $0.contains("m4s") })
    }

    func testOverlayNamesTheCodecAndRateActuallyPlaying() throws {
        let dash = DebugSupport.codecDash([(80, 12, "hev1.1.6.L120.90"), (80, 13, "av01.0.08M.08"), (80, 7, "avc1.640032")])
        let lines = dash.video.map { PlayingStream($0).line(qualityName: "1080P 高清") }
        XCTAssertEqual(lines, ["1080P 高清 · HEVC · 1.0 Mbps", "1080P 高清 · AV1 · 1.0 Mbps", "1080P 高清 · H.264 · 1.0 Mbps"])
        let dolby = try XCTUnwrap(DebugSupport.codecDash([(126, 12, "dvh1.08.07")]).video.first)
        XCTAssertEqual(PlayingStream(dolby).line(qualityName: nil), "126 · 杜比视界 · 1.0 Mbps")
    }

    func testSeekTimerTimesUserSeeksOnly() throws {
        let start = Date(timeIntervalSince1970: 1000)
        var timer = SeekTimer()
        XCTAssertFalse(timer.jumped(to: 30, at: start, rate: 0), "a seek while paused is not timed")
        XCTAssertNil(timer.playing(at: start.addingTimeInterval(5)))

        XCTAssertTrue(timer.jumped(to: 30, at: start, rate: 1))
        XCTAssertEqual(try XCTUnwrap(timer.playing(at: start.addingTimeInterval(0.8))), 800, accuracy: 0.1)
        XCTAssertFalse(timer.isRunning)

        timer.reloadBegan()
        XCTAssertFalse(timer.jumped(to: 42, at: start, rate: 1), "a reload's own seek is not the user's")
        XCTAssertNil(timer.playing(at: start.addingTimeInterval(2)))
        XCTAssertTrue(timer.jumped(to: 50, at: start, rate: 1), "after the reload played, seeks are timed again")
        timer.paused()
        XCTAssertNil(timer.playing(at: start.addingTimeInterval(9)), "a pause before resuming ends the timing")
    }

    func testSeekTimerEndsASeekThatNeverLeftPlaying() throws {
        let start = Date(timeIntervalSince1970: 1000)
        var timer = SeekTimer()
        XCTAssertTrue(timer.jumped(to: 30, at: start, rate: 1))
        XCTAssertNil(timer.ticked(position: 30.1, rate: 1, playing: true, at: start.addingTimeInterval(0.25)))
        XCTAssertNil(timer.ticked(position: 30.5, rate: 1, playing: false, at: start.addingTimeInterval(0.6)))
        // Moved 0.5 s by 0.75 s after the jump: playback resumed 0.25 s after it.
        XCTAssertEqual(try XCTUnwrap(timer.ticked(position: 30.5, rate: 1, playing: true, at: start.addingTimeInterval(0.75))), 250, accuracy: 0.1)
        XCTAssertFalse(timer.isRunning)
    }
}
