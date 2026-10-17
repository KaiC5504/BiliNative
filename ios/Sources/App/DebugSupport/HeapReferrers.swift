#if DEBUG
import Darwin
import Foundation
import ObjectiveC

/// Who holds an object: scans every malloc block of this process for a pointer to it, then for pointers to those
/// blocks, a few levels up. A stand-in for `leaks --traceTree`, which cannot read simulator processes on the CI
/// runner. Strong and unowned references show; weak ones do not (they point at a side table).
enum HeapReferrers {
    private struct Block {
        let start: UInt
        let size: Int
    }

    nonisolated(unsafe) private static var ranges: UnsafeMutablePointer<vm_range_t>?
    nonisolated(unsafe) private static var capacity = 0
    nonisolated(unsafe) private static var count = 0

    /// Called by the zone enumerator with the zone locked: it must not allocate.
    private static let recorder: @convention(c) (task_t, UnsafeMutableRawPointer?, UInt32, UnsafeMutablePointer<vm_range_t>?, UInt32) -> Void = { _, _, _, found, number in
        guard let found, let ranges = HeapReferrers.ranges else { return }
        var index = 0
        while index < Int(number), HeapReferrers.count < HeapReferrers.capacity {
            ranges[HeapReferrers.count] = found[index]
            HeapReferrers.count += 1
            index += 1
        }
    }

    private static let reader: @convention(c) (task_t, vm_address_t, vm_size_t, UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> kern_return_t = { _, address, _, out in
        out?.pointee = UnsafeMutableRawPointer(bitPattern: address)
        return KERN_SUCCESS
    }

    private static func blocks() -> [Block] {
        capacity = 4_000_000
        ranges = UnsafeMutablePointer<vm_range_t>.allocate(capacity: capacity)
        count = 0
        defer {
            ranges?.deallocate()
            ranges = nil
        }
        var zones: UnsafeMutablePointer<vm_address_t>?
        var zoneCount: UInt32 = 0
        guard malloc_get_all_zones(mach_task_self_, reader, &zones, &zoneCount) == KERN_SUCCESS, let zones else { return [] }
        for index in 0..<Int(zoneCount) {
            guard let zone = UnsafeMutablePointer<malloc_zone_t>(bitPattern: zones[index]),
                  let introspect = zone.pointee.introspect, let enumerator = introspect.pointee.enumerator else { continue }
            introspect.pointee.force_lock?(zone)
            _ = enumerator(mach_task_self_, nil, UInt32(MALLOC_PTR_IN_USE_RANGE_TYPE), zones[index], reader, recorder)
            introspect.pointee.force_unlock?(zone)
        }
        var result: [Block] = []
        result.reserveCapacity(count)
        for index in 0..<count {
            result.append(Block(start: UInt(ranges![index].address), size: Int(ranges![index].size)))
        }
        return result
    }

    private static func classNames() -> [UInt: String] {
        var count: UInt32 = 0
        guard let list = objc_copyClassList(&count) else { return [:] }
        defer { free(UnsafeMutableRawPointer(list)) }
        // Read as plain addresses: touching some classes as Swift values sends them messages they forward and trap on.
        let raw = UnsafeRawPointer(list)
        var names: [UInt: String] = [:]
        for index in 0..<Int(count) {
            let address = raw.load(fromByteOffset: index * MemoryLayout<UInt>.size, as: UInt.self)
            names[address] = String(cString: class_getName(unsafeBitCast(address, to: AnyClass.self)))
        }
        return names
    }

    /// A tree of who points at `target`, `depth` levels up, at most `fanout` holders each. One pass over the heap
    /// per level.
    static func report(for target: AnyObject, depth: Int = 8, fanout: Int = 5) -> String {
        let names = classNames()
        let all = blocks().filter { $0.size >= 8 && $0.size < 64 << 20 }
        let targetAddress = UInt(bitPattern: Unmanaged.passUnretained(target).toOpaque())
        let low = all.map(\.start).min() ?? 0
        let high = all.map { $0.start + UInt($0.size) }.max() ?? 0

        func name(of block: Block) -> String {
            let isa = UnsafePointer<UInt>(bitPattern: block.start)!.pointee
            for mask: UInt in [~0, 0x0000_000f_ffff_fff8, 0x0000_7fff_ffff_fff8] {
                if let name = names[isa & mask] { return name }
            }
            return "block"
        }

        var holders: [UInt: [Block]] = [:]
        var seen: Set<UInt> = [targetAddress]
        var frontier: Set<UInt> = [targetAddress]
        for _ in 0..<depth where !frontier.isEmpty {
            var found: [UInt: [Block]] = [:]
            for block in all {
                let words = UnsafePointer<UInt>(bitPattern: block.start)!
                for index in 0..<(block.size / 8) {
                    let word = words[index]
                    guard word >= low, word < high, frontier.contains(word), word != block.start else { continue }
                    if found[word, default: []].count < fanout, !(found[word]?.contains { $0.start == block.start } ?? false) {
                        found[word, default: []].append(block)
                    }
                }
            }
            var next: Set<UInt> = []
            for (address, blocks) in found {
                holders[address] = blocks
                for block in blocks where !seen.contains(block.start) {
                    seen.insert(block.start)
                    next.insert(block.start)
                }
            }
            frontier = next
        }

        var lines = ["\(String(describing: type(of: target))) \(String(targetAddress, radix: 16)), \(all.count) heap blocks"]
        var printed: Set<UInt> = []
        func emit(_ address: UInt, level: Int) {
            let indent = String(repeating: "  ", count: level + 1)
            guard let found = holders[address], !found.isEmpty else {
                if level < depth { lines.append(indent + "(no heap holder: a global, a static, the stack or a run loop)") }
                return
            }
            for block in found {
                let again = printed.contains(block.start)
                lines.append("\(indent)<- \(name(of: block)) \(String(block.start, radix: 16)) size \(block.size)\(again ? " (above)" : "")")
                guard !again else { continue }
                printed.insert(block.start)
                emit(block.start, level: level + 1)
            }
        }
        emit(targetAddress, level: 0)
        return lines.joined(separator: "\n")
    }
}
#endif
