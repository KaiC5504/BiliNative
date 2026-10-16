import XCTest
import BiliShared
@testable import DashHLS

final class PlaylistBuilderTests: XCTestCase {
    func testCodecMapping() {
        XCTAssertEqual(CodecMapper.video(codecs: "hev1.1.6.L153.90", qualityID: 120, sampleEntry: "hvc1"),
                       HLSVideoCodec(codecs: "hvc1.1.6.L153.90", supplemental: nil, videoRange: "SDR"))
        XCTAssertEqual(CodecMapper.video(codecs: "hev1.1.6.L153.90", qualityID: 120, sampleEntry: "hev1").codecs, "hev1.1.6.L153.90")
        XCTAssertEqual(CodecMapper.video(codecs: "hev1.1.6.L153.90", qualityID: 120, sampleEntry: nil).codecs, "hev1.1.6.L153.90")
        XCTAssertEqual(CodecMapper.video(codecs: "hev1.2.4.L153.90", qualityID: 125, sampleEntry: "hvc1").videoRange, "PQ")
        XCTAssertEqual(CodecMapper.video(codecs: "dvh1.08.07", qualityID: 126, sampleEntry: "hvc1"),
                       HLSVideoCodec(codecs: "hvc1.2.4.L153.b0", supplemental: "dvh1.08.07/db4h", videoRange: "HLG"))
        XCTAssertEqual(CodecMapper.video(codecs: "dvh1.08.06", qualityID: 126, sampleEntry: "hvc1"),
                       HLSVideoCodec(codecs: "hvc1.2.4.L150", supplemental: "dvh1.08.06/db1p", videoRange: "PQ"))
        XCTAssertEqual(CodecMapper.video(codecs: "dvh1.05.06", qualityID: 126, sampleEntry: "dvh1").videoRange, "PQ")
        XCTAssertEqual(CodecMapper.video(codecs: "avc1.640034", qualityID: 80, sampleEntry: "avc1").codecs, "avc1.640034")
    }

    func testFrameRateFormatting() {
        XCTAssertEqual(CodecMapper.frameRate("29.412"), "29.412")
        XCTAssertEqual(CodecMapper.frameRate("60"), "60.000")
        XCTAssertEqual(CodecMapper.frameRate(nil), "30.000")
        XCTAssertEqual(CodecMapper.frameRate("abc"), "30.000")
        XCTAssertEqual(CodecMapper.frameRate("inf"), "30.000")
        XCTAssertEqual(CodecMapper.frameRate("0"), "30.000")
        XCTAssertEqual(CodecMapper.frameRate("-24"), "30.000")
    }

    func testMediaPlaylist() {
        let segments = [
            MediaSegment(index: 0, range: ByteRange(start: 1689, end: 50_000)!, startTime: 0, duration: 4.004),
            MediaSegment(index: 1, range: ByteRange(start: 50_001, end: 90_000)!, startTime: 4.004, duration: 3.5),
        ]
        let text = PlaylistBuilder.media(HLSTrack(uri: "v.mp4", initRange: ByteRange(start: 0, end: 1104)!, segments: segments))
        XCTAssertEqual(text, """
        #EXTM3U
        #EXT-X-VERSION:7
        #EXT-X-TARGETDURATION:5
        #EXT-X-MEDIA-SEQUENCE:0
        #EXT-X-PLAYLIST-TYPE:VOD
        #EXT-X-INDEPENDENT-SEGMENTS
        #EXT-X-MAP:URI="v.mp4",BYTERANGE="1105@0"
        #EXTINF:4.004,
        #EXT-X-BYTERANGE:48312@1689
        v.mp4
        #EXTINF:3.500,
        #EXT-X-BYTERANGE:40000@50001
        v.mp4
        #EXT-X-ENDLIST

        """)
    }

    func testMediaPlaylistTargetDurationIsCeilOfLongestSegment() {
        func target(_ durations: [Double]) -> String {
            let segments = durations.enumerated().map {
                MediaSegment(index: $0.offset, range: ByteRange(start: Int64($0.offset) * 100, end: Int64($0.offset) * 100 + 99)!,
                             startTime: 0, duration: $0.element)
            }
            let text = PlaylistBuilder.media(HLSTrack(uri: "v.mp4", initRange: ByteRange(start: 0, end: 9)!, segments: segments))
            return text.split(separator: "\n").first { $0.hasPrefix("#EXT-X-TARGETDURATION") }.map(String.init) ?? ""
        }
        XCTAssertEqual(target([4.0]), "#EXT-X-TARGETDURATION:4")
        XCTAssertEqual(target([4.0, 4.01]), "#EXT-X-TARGETDURATION:5")
        XCTAssertEqual(target([0.4]), "#EXT-X-TARGETDURATION:1")
        XCTAssertEqual(target([]), "#EXT-X-TARGETDURATION:1")
    }

    func testMasterPlaylist() {
        let variant = HLSVariant(codec: HLSVideoCodec(codecs: "hvc1.2.4.L153.b0", supplemental: "dvh1.08.07/db4h", videoRange: "HLG"),
                                 audioCodecs: "mp4a.40.2", averageBandwidth: 12_320_000, width: 3840, height: 2160, frameRate: "29.412")
        XCTAssertEqual(PlaylistBuilder.master(variant, videoPlaylist: "v.m3u8", audioPlaylist: "a.m3u8"), """
        #EXTM3U
        #EXT-X-VERSION:7
        #EXT-X-INDEPENDENT-SEGMENTS
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="default",DEFAULT=YES,AUTOSELECT=YES,URI="a.m3u8"
        #EXT-X-STREAM-INF:BANDWIDTH=18480000,AVERAGE-BANDWIDTH=12320000,CODECS="hvc1.2.4.L153.b0,mp4a.40.2",SUPPLEMENTAL-CODECS="dvh1.08.07/db4h",RESOLUTION=3840x2160,FRAME-RATE=29.412,VIDEO-RANGE=HLG,AUDIO="audio"
        v.m3u8

        """)
    }

    func testMasterPlaylistOmitsSupplementalCodecsWhenAbsent() {
        let variant = HLSVariant(codec: HLSVideoCodec(codecs: "avc1.640034", supplemental: nil, videoRange: "SDR"),
                                 audioCodecs: "mp4a.40.2", averageBandwidth: 1_000_000, width: 1920, height: 1080, frameRate: "30.000")
        let text = PlaylistBuilder.master(variant, videoPlaylist: "v.m3u8", audioPlaylist: "a.m3u8")
        XCTAssertFalse(text.contains("SUPPLEMENTAL-CODECS"))
        XCTAssertTrue(text.contains("BANDWIDTH=1500000,AVERAGE-BANDWIDTH=1000000,CODECS=\"avc1.640034,mp4a.40.2\",RESOLUTION=1920x1080"))
    }
}
