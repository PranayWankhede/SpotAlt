import CoreServices
import Foundation

struct FileSystemEvent: Equatable {
    let path: String
    let isDirectory: Bool
    let requiresFullRescan: Bool
}

protocol FolderWatching: AnyObject {
    var onEvents: (([FileSystemEvent]) -> Void)? { get set }

    func start(watching locations: [URL])
    func stop()
}

final class FSEventsFolderWatcher: FolderWatching {
    var onEvents: (([FileSystemEvent]) -> Void)?

    private let queue = DispatchQueue(
        label: "com.spotalt.folder-watcher",
        qos: .utility
    )
    private var stream: FSEventStreamRef?

    deinit {
        stop()
    }

    func start(watching locations: [URL]) {
        stop()

        let paths = Array(Set(locations.map { $0.standardizedFileURL.path })).sorted()
        guard !paths.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = {
            _, clientInfo, eventCount, eventPaths, eventFlags, _ in
            guard let clientInfo else { return }
            let watcher = Unmanaged<FSEventsFolderWatcher>
                .fromOpaque(clientInfo)
                .takeUnretainedValue()
            let paths = eventPaths.assumingMemoryBound(
                to: UnsafePointer<CChar>.self
            )
            var events: [FileSystemEvent] = []
            events.reserveCapacity(eventCount)

            for index in 0..<eventCount {
                let flags = eventFlags[index]
                let recoveryFlags =
                    FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs)
                    | FSEventStreamEventFlags(kFSEventStreamEventFlagUserDropped)
                    | FSEventStreamEventFlags(kFSEventStreamEventFlagKernelDropped)
                    | FSEventStreamEventFlags(kFSEventStreamEventFlagEventIdsWrapped)
                    | FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged)

                events.append(
                    FileSystemEvent(
                        path: String(cString: paths[index]),
                        isDirectory: flags
                            & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir) != 0,
                        requiresFullRescan: flags & recoveryFlags != 0
                    )
                )
            }

            guard !events.isEmpty else { return }
            watcher.onEvents?(events)
        }
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagWatchRoot
                | kFSEventStreamCreateFlagNoDefer
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.35,
            flags
        ) else { return }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            stop()
            return
        }
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
