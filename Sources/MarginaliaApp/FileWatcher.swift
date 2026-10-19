import Foundation
import CoreServices

/// Watches a file's parent directory (atomic saves replace the inode) plus the file descriptor itself.
/// Coalesces bursts and calls back on the main queue.
final class FileWatcher {
    private let url: URL
    private var stream: FSEventStreamRef?
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private var pending = false
    private let onChange: () -> Void

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url.standardizedFileURL
        self.onChange = onChange
        startStream()
        startSource()
    }

    deinit { stop() }

    private func startStream() {
        let dir = url.deletingLastPathComponent().path
        var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let cb: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let me = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            let arr = unsafeBitCast(paths, to: NSArray.self)
            let want = me.url.path
            for i in 0..<count {
                if let p = arr[i] as? String, p == want || p.hasPrefix(want) || want.hasPrefix(p) { me.fire(); break }
            }
        }
        stream = FSEventStreamCreate(nil, cb, &ctx, [dir] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.02,
                                     FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer))
        if let stream {
            FSEventStreamSetDispatchQueue(stream, .main)
            FSEventStreamStart(stream)
        }
    }

    private func startSource() {
        fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let s = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .rename, .extend], queue: .main)
        s.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = s.data
            self.fire()
            if flags.contains(.delete) || flags.contains(.rename) {
                // The inode went away (atomic replace). Re-arm on the new file shortly.
                s.cancel()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.startSource() }
            }
        }
        s.setCancelHandler { [fd] in close(fd) }
        source = s
        s.resume()
    }

    private func fire() {
        guard !pending else { return }
        pending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            guard let self else { return }
            self.pending = false
            self.onChange()
        }
    }

    func stop() {
        if let stream { FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) }
        stream = nil
        source?.cancel()
        source = nil
    }
}
