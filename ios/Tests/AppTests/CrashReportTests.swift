#if DEV_TOOLS
import XCTest
import DevLog
@testable import BiliNative

final class CrashReportTests: XCTestCase {
    /// Shaped like `MXCallStackTree.jsonRepresentation()` for a crash: one stack per thread, each a chain of subFrames.
    private let crashTree = Data("""
    {
      "callStackPerThread": true,
      "callStacks": [
        {
          "threadAttributed": false,
          "callStackRootFrames": [
            {"binaryUUID": "AAAA-1111", "offsetIntoBinaryTextSegment": 4096, "sampleCount": 1,
             "binaryName": "libsystem_kernel.dylib", "address": 7516196864}
          ]
        },
        {
          "threadAttributed": true,
          "callStackRootFrames": [
            {"binaryUUID": "BBBB-2222", "offsetIntoBinaryTextSegment": 20268, "sampleCount": 1,
             "binaryName": "BiliNative", "address": 4295035692,
             "subFrames": [
               {"binaryUUID": "CCCC-3333", "offsetIntoBinaryTextSegment": 255, "sampleCount": 1,
                "binaryName": "UIKitCore", "address": 6442451199,
                "subFrames": [
                  {"binaryUUID": "BBBB-2222", "offsetIntoBinaryTextSegment": 16, "sampleCount": 1,
                   "binaryName": "BiliNative", "address": 4295015440}
                ]}
             ]}
          ]
        }
      ]
    }
    """.utf8)

    /// Shaped like `MXCrashDiagnostic.jsonRepresentation()`.
    private let crashDiagnostic = Data("""
    {
      "version": "1.0.0",
      "diagnosticMetaData": {
        "appBuildVersion": "2",
        "appVersion": "0.1.0",
        "osVersion": "iPhone OS 26.0 (23A341)",
        "deviceType": "iPhone17,1",
        "platformArchitecture": "arm64e",
        "isTestFlightApp": true,
        "exceptionType": 1,
        "exceptionCode": 0,
        "signal": 11,
        "terminationReason": "Namespace SIGNAL, Code 11 Segmentation fault: 11",
        "exceptionReason": {"exceptionName": "NSInvalidArgumentException", "composedMessage": "bad view"},
        "pid": 812,
        "nothing": null
      }
    }
    """.utf8)

    func testCrashBecomesOneEventWithMetadataAndCrashedThreadFirst() throws {
        let events = CrashReport.events(kind: .crash, callStackTree: crashTree, diagnostic: crashDiagnostic,
                                        overrides: ["from": .init(1_760_000_000.0)])
        XCTAssertEqual(events.count, 1)
        let first = try XCTUnwrap(events.first)
        XCTAssertEqual(first["appVersion"], "0.1.0")
        XCTAssertEqual(first["appBuildVersion"], "2")
        XCTAssertEqual(first["exceptionType"], .int(1))
        XCTAssertEqual(first["exceptionTypeName"], "EXC_BAD_ACCESS")
        XCTAssertEqual(first["exceptionCode"], .int(0))
        XCTAssertEqual(first["signal"], .int(11))
        XCTAssertEqual(first["signalName"], "SIGSEGV")
        XCTAssertEqual(first["terminationReason"], "Namespace SIGNAL, Code 11 Segmentation fault: 11")
        XCTAssertEqual(first["exceptionReason.exceptionName"], "NSInvalidArgumentException")
        XCTAssertEqual(first["isTestFlightApp"], .bool(true))
        XCTAssertEqual(first["from"], .double(1_760_000_000))
        XCTAssertNil(first["nothing"])
        XCTAssertEqual(first["threads"], .int(2))
        XCTAssertEqual(first["part"], .int(1))
        XCTAssertEqual(first["parts"], .int(1))

        XCTAssertEqual(first["stack"], .string("""
        thread 1 (crashed)
          0 BiliNative +0x4f2c (0x100010b2c)
          1 UIKitCore +0xff (0x1800000ff)
          2 BiliNative +0x10 (0x10000bc10)
        thread 0
          0 libsystem_kernel.dylib +0x1000 (0x1c0001000)
        binaries
          BiliNative BBBB-2222
          UIKitCore CCCC-3333
          libsystem_kernel.dylib AAAA-1111
        """))
    }

    func testOverridesWinOverTheDiagnosticJSON() {
        let events = CrashReport.events(kind: .crash, callStackTree: crashTree, diagnostic: crashDiagnostic,
                                        overrides: ["signal": .init(6), "appBuildVersion": "3"])
        XCTAssertEqual(events.first?["signal"], .int(6))
        XCTAssertEqual(events.first?["signalName"], "SIGABRT")
        XCTAssertEqual(events.first?["appBuildVersion"], "3")
    }

    func testHangTreeIndentsBranchesAndShowsSamples() {
        let tree = Data("""
        {"callStackPerThread": false, "callStacks": [{"threadAttributed": true, "callStackRootFrames": [
          {"binaryName": "BiliNative", "offsetIntoBinaryTextSegment": 1, "sampleCount": 10, "subFrames": [
            {"binaryName": "AVFCore", "offsetIntoBinaryTextSegment": 2, "sampleCount": 7, "subFrames": [
              {"binaryName": "AVFCore", "offsetIntoBinaryTextSegment": 4, "sampleCount": 7}]},
            {"binaryName": "UIKitCore", "offsetIntoBinaryTextSegment": 3, "sampleCount": 3}
          ]}
        ]}]}
        """.utf8)
        let events = CrashReport.events(kind: .hang, callStackTree: tree, diagnostic: nil)
        XCTAssertEqual(events.first?["stack"], .string("""
        samples (main)
          0 BiliNative +0x1 ×10
            1 AVFCore +0x2 ×7
              2 AVFCore +0x4 ×7
            3 UIKitCore +0x3 ×3
        """))
    }

    func testBigStacksSplitIntoPartsThatShareOneReportID() throws {
        let frames = (0..<150).map { index in
            #"{"binaryName": "BiliNative", "offsetIntoBinaryTextSegment": \#(index), "address": \#(4_295_000_000 + index)"#
        }
        let chain = frames.reversed().reduce("") { inner, frame in
            inner.isEmpty ? frame + "}" : frame + #", "subFrames": ["# + inner + "]}"
        }
        let tree = Data(#"{"callStackPerThread": true, "callStacks": [{"threadAttributed": true, "callStackRootFrames": ["#
                        .utf8 + Data(chain.utf8) + Data("]}]}".utf8))
        let events = CrashReport.events(kind: .crash, callStackTree: tree, diagnostic: crashDiagnostic, chunkBytes: 2_000)

        XCTAssertGreaterThan(events.count, 1)
        let id = try XCTUnwrap(events.first?["report"])
        XCTAssertTrue(events.allSatisfy { $0["report"] == id })
        XCTAssertEqual(events.map { $0["part"] }, (1...events.count).map { Optional(LogValue.int(Int64($0))) })
        XCTAssertTrue(events.allSatisfy { $0["parts"] == .int(Int64(events.count)) })
        XCTAssertEqual(events.first?["signal"], .int(11))
        XCTAssertNil(events.last?["signal"])

        var joined: [String] = []
        for event in events {
            guard case .string(let chunk)? = event["stack"] else { return XCTFail("missing stack") }
            XCTAssertLessThanOrEqual(chunk.utf8.count, 2_000)
            joined.append(chunk)
        }
        let lines = joined.joined(separator: "\n").split(separator: "\n")
        XCTAssertEqual(lines.count, 1 + 150)
        XCTAssertEqual(lines[150], "  149 BiliNative +0x95 (0x100008055)")
    }

    func testSameDiagnosticGetsTheSameIDAndADifferentOneDoesNot() {
        let once = CrashReport.events(kind: .crash, callStackTree: crashTree, diagnostic: crashDiagnostic)
        let again = CrashReport.events(kind: .crash, callStackTree: crashTree, diagnostic: crashDiagnostic)
        let other = CrashReport.events(kind: .crash, callStackTree: crashTree, diagnostic: crashDiagnostic,
                                       overrides: ["from": .init(1.0)])
        XCTAssertEqual(once.first?["report"], again.first?["report"])
        XCTAssertNotEqual(once.first?["report"], other.first?["report"])
    }

    func testAnUndecodableTreeIsSentAsItsRawJSON() {
        let events = CrashReport.events(kind: .crash, callStackTree: Data(#"{"callStacks": 3}"#.utf8),
                                        diagnostic: Data("{}".utf8))
        XCTAssertEqual(events.count, 1)
        XCTAssertNil(events.first?["threads"])
        XCTAssertEqual(events.first?["stackFormat"], "json")
        XCTAssertEqual(events.first?["stack"], #"{"callStacks": 3}"#)
    }

    func testLongLinesAreCutWithinTheLimit() {
        let chunks = CrashReport.split(String(repeating: "界", count: 200), maxBytes: 256)
        XCTAssertTrue(chunks.allSatisfy { $0.utf8.count <= 256 })
        XCTAssertEqual(chunks.joined(), String(repeating: "界", count: 200))
    }
}
#endif
