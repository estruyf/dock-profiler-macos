import Darwin

/// Reads a process's command line. The kernel answers into a buffer the size of
/// `ARGMAX` — a megabyte — so the buffer is allocated once and reused for the
/// whole sweep: a fresh one per process turned a 4 ms scan into a 200 ms one.
/// Only processes running as this user answer; everything else is left alone.
final class ProcessArgumentReader {
    private let capacity: Int
    private let buffer: UnsafeMutablePointer<CChar>

    init?() {
        var maximum: Int32 = 0
        var size = MemoryLayout<Int32>.size
        var limits: [Int32] = [CTL_KERN, KERN_ARGMAX]
        guard sysctl(&limits, 2, &maximum, &size, nil, 0) == 0, maximum > 0 else { return nil }
        capacity = Int(maximum)
        buffer = .allocate(capacity: capacity)
    }

    deinit { buffer.deallocate() }

    /// The executable's path followed by its arguments.
    func arguments(of pid: pid_t) -> [String]? {
        var size = capacity
        var name: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        guard sysctl(&name, 3, buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }

        var count: Int32 = 0
        memcpy(&count, buffer, MemoryLayout<Int32>.size)
        var index = MemoryLayout<Int32>.size

        // The path, then padding, then argv — each null-terminated, with runs
        // of nulls between them.
        func next() -> String? {
            while index < size, buffer[index] == 0 { index += 1 }
            guard index < size else { return nil }
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            return String(decoding: UnsafeRawBufferPointer(start: buffer + start, count: index - start), as: UTF8.self)
        }

        guard let executable = next() else { return nil }
        var result = [executable]
        for _ in 0..<count {
            guard let argument = next() else { break }
            result.append(argument)
        }
        return result
    }
}
