#if DEV_TOOLS
import Foundation
import DevLog

/// Turns one MetricKit diagnostic into log events. Kept free of MetricKit so the conversion is testable with fixtures.
enum CrashReport {
    enum Kind: String {
        case crash, hang
    }

    /// Bytes of stack text per event, so a 30-thread crash stays a handful of readable lines in the jsonl.
    static let defaultChunkBytes = 12_000

    /// Field sets for one report: the first carries the metadata, every part carries `report`, `part`, `parts` and a
    /// slice of `stack`.
    static func events(kind: Kind, callStackTree: Data, diagnostic: Data?, overrides: [String: LogValue] = [:],
                       chunkBytes: Int = defaultChunkBytes) -> [[String: LogValue]] {
        var meta = diagnostic.map(metadataFields) ?? [:]
        meta.merge(overrides) { _, new in new }
        if case .int(let signal)? = meta["signal"], let name = signalName(signal) { meta["signalName"] = .init(name) }
        if case .int(let type)? = meta["exceptionType"], let name = exceptionTypeName(type) {
            meta["exceptionTypeName"] = .init(name)
        }

        // JSONDecoder stops at about 512 levels of nesting, which a deep recursion's frame chain can pass; the raw JSON
        // still symbolicates.
        let tree = try? JSONDecoder().decode(Tree.self, from: callStackTree)
        if tree == nil { meta["stackFormat"] = "json" }
        let stack = tree.map(render) ?? String(decoding: callStackTree, as: UTF8.self)
        let id = reportID(kind: kind, meta: meta, stack: stack)
        let chunks = split(stack, maxBytes: max(chunkBytes, 256))

        return chunks.enumerated().map { index, chunk in
            var fields: [String: LogValue] = index == 0 ? meta : [:]
            if index == 0, let tree { fields["threads"] = .init(tree.callStacks.count) }
            fields["report"] = .init(id)
            fields["part"] = .init(index + 1)
            fields["parts"] = .init(chunks.count)
            fields["stack"] = .init(chunk)
            return fields
        }
    }

    /// Scalars from the diagnostic's `diagnosticMetaData`; nested objects (the Objective-C exception reason) become
    /// dotted keys.
    static func metadataFields(_ diagnostic: Data) -> [String: LogValue] {
        guard case .object(let root)? = try? JSONDecoder().decode(JSON.self, from: diagnostic),
              case .object(let meta)? = root["diagnosticMetaData"] else { return [:] }
        var fields: [String: LogValue] = [:]
        flatten(meta, prefix: "", into: &fields)
        return fields
    }

    private static func flatten(_ object: [String: JSON], prefix: String, into fields: inout [String: LogValue]) {
        for (key, value) in object {
            let name = prefix + key
            switch value {
            case .null: break
            case .bool(let flag): fields[name] = .init(flag)
            case .int(let number): fields[name] = .init(number)
            case .double(let number): fields[name] = .init(number)
            case .string(let text): fields[name] = .init(text)
            case .array(let items): fields[name] = .init(items.map(\.text).joined(separator: ", "))
            case .object(let nested): flatten(nested, prefix: name + ".", into: &fields)
            }
        }
    }

    /// One line per frame. A plain chain keeps its indent; frames get indented once siblings appear, which only hang
    /// trees (samples merged across threads) have.
    static func render(_ tree: Tree) -> String {
        let perThread = tree.callStackPerThread ?? true
        var lines: [String] = []
        var binaries: [String: String] = [:]
        // The crashed thread first, since it is the one anyone reads.
        let ordered = tree.callStacks.enumerated().sorted { lhs, rhs in
            let left = lhs.element.threadAttributed == true, right = rhs.element.threadAttributed == true
            return left != right ? left : lhs.offset < rhs.offset
        }
        for (index, stack) in ordered {
            var header = perThread ? "thread \(index)" : "samples"
            if stack.threadAttributed == true { header += perThread ? " (crashed)" : " (main)" }
            lines.append(header)
            var counter = 0
            append(stack.callStackRootFrames, depth: 1, samples: !perThread, counter: &counter, lines: &lines,
                   binaries: &binaries)
        }
        if !binaries.isEmpty {
            lines.append("binaries")
            for name in binaries.keys.sorted() { lines.append("  \(name) \(binaries[name] ?? "")") }
        }
        return lines.joined(separator: "\n")
    }

    private static func append(_ frames: [Frame], depth: Int, samples: Bool, counter: inout Int, lines: inout [String],
                               binaries: inout [String: String]) {
        for frame in frames {
            let name = frame.binaryName ?? "?"
            if let uuid = frame.binaryUUID { binaries[name] = uuid }
            var line = String(repeating: "  ", count: depth) + "\(counter) \(name)"
            if let offset = frame.offsetIntoBinaryTextSegment { line += " +0x" + String(offset, radix: 16) }
            if let address = frame.address { line += " (0x" + String(address, radix: 16) + ")" }
            if samples, let count = frame.sampleCount { line += " ×\(count)" }
            lines.append(line)
            counter += 1
            let children = frame.subFrames ?? []
            let branches = frames.count > 1 || children.count > 1
            append(children, depth: depth + (branches ? 1 : 0), samples: samples, counter: &counter, lines: &lines,
                   binaries: &binaries)
        }
    }

    /// Cuts at line ends; a single line longer than `maxBytes` is cut inside.
    static func split(_ text: String, maxBytes: Int) -> [String] {
        var chunks: [String] = []
        var current = ""
        var currentBytes = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var piece = String(line)
            while piece.utf8.count > maxBytes {
                if !current.isEmpty {
                    chunks.append(current)
                    current = ""
                    currentBytes = 0
                }
                var head = ""
                var headBytes = 0
                for character in piece {
                    let size = String(character).utf8.count
                    if headBytes + size > maxBytes { break }
                    head.append(character)
                    headBytes += size
                }
                chunks.append(head)
                piece.removeFirst(head.count)
            }
            let size = piece.utf8.count + (current.isEmpty ? 0 : 1)
            if currentBytes + size > maxBytes, !current.isEmpty {
                chunks.append(current)
                current = piece
                currentBytes = piece.utf8.count
            } else {
                current += current.isEmpty ? piece : "\n" + piece
                currentBytes += size
            }
        }
        if !current.isEmpty || chunks.isEmpty { chunks.append(current) }
        return chunks
    }

    /// Stable across launches for the same diagnostic, so a payload MetricKit hands over twice is sent once.
    static func reportID(kind: Kind, meta: [String: LogValue], stack: String) -> String {
        var text = kind.rawValue
        for key in meta.keys.sorted() { text += "|\(key)=\(meta[key].map(describe) ?? "")" }
        text += "|" + stack
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }

    private static func describe(_ value: LogValue) -> String {
        switch value {
        case .string(let text): return text
        case .int(let number): return String(number)
        case .double(let number): return String(number)
        case .bool(let flag): return String(flag)
        }
    }

    static func signalName(_ signal: Int64) -> String? {
        let names: [Int64: String] = [
            1: "SIGHUP", 2: "SIGINT", 3: "SIGQUIT", 4: "SIGILL", 5: "SIGTRAP", 6: "SIGABRT", 7: "SIGEMT", 8: "SIGFPE",
            9: "SIGKILL", 10: "SIGBUS", 11: "SIGSEGV", 12: "SIGSYS", 13: "SIGPIPE", 14: "SIGALRM", 15: "SIGTERM",
        ]
        return names[signal]
    }

    /// Mach exception types from <mach/exception_types.h>.
    static func exceptionTypeName(_ type: Int64) -> String? {
        let names: [Int64: String] = [
            1: "EXC_BAD_ACCESS", 2: "EXC_BAD_INSTRUCTION", 3: "EXC_ARITHMETIC", 4: "EXC_EMULATION", 5: "EXC_SOFTWARE",
            6: "EXC_BREAKPOINT", 7: "EXC_SYSCALL", 8: "EXC_MACH_SYSCALL", 9: "EXC_RPC_ALERT", 10: "EXC_CRASH",
            11: "EXC_RESOURCE", 12: "EXC_GUARD", 13: "EXC_CORPSE_NOTIFY",
        ]
        return names[type]
    }

    /// The shape of `MXCallStackTree.jsonRepresentation()`.
    struct Tree: Decodable {
        var callStackPerThread: Bool?
        var callStacks: [CallStack]
    }

    struct CallStack: Decodable {
        var threadAttributed: Bool?
        var callStackRootFrames: [Frame]
    }

    struct Frame: Decodable {
        var binaryUUID: String?
        var offsetIntoBinaryTextSegment: Int64?
        var sampleCount: Int?
        var binaryName: String?
        var address: UInt64?
        var subFrames: [Frame]?
    }

    enum JSON: Decodable {
        case null
        case bool(Bool)
        case int(Int64)
        case double(Double)
        case string(String)
        case array([JSON])
        case object([String: JSON])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                self = .null
            } else if let value = try? container.decode(Bool.self) {
                self = .bool(value)
            } else if let value = try? container.decode(Int64.self) {
                self = .int(value)
            } else if let value = try? container.decode(Double.self) {
                self = .double(value)
            } else if let value = try? container.decode(String.self) {
                self = .string(value)
            } else if let value = try? container.decode([JSON].self) {
                self = .array(value)
            } else {
                self = .object(try container.decode([String: JSON].self))
            }
        }

        var text: String {
            switch self {
            case .null: return "null"
            case .bool(let flag): return String(flag)
            case .int(let number): return String(number)
            case .double(let number): return String(number)
            case .string(let text): return text
            case .array(let items): return "[" + items.map(\.text).joined(separator: ", ") + "]"
            case .object(let object): return "{" + object.keys.sorted().map { "\($0): \(object[$0]!.text)" }.joined(separator: ", ") + "}"
            }
        }
    }
}
#endif
