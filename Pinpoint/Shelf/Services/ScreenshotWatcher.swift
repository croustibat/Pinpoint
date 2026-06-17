import CoreServices
import Foundation

struct ScreenshotWatcherEvent: Sendable {
    let changedURLs: [URL]
    let requiresFullRescan: Bool
}

final class ScreenshotWatcher {
    private let queue = DispatchQueue(label: "com.snapshelf.watcher", qos: .utility)
    private var stream: FSEventStreamRef?
    private var pendingURLs = Set<URL>()
    private var pendingFullRescan = false
    private var debounceWorkItem: DispatchWorkItem?

    func startMonitoring(
        folderURL: URL,
        onEvent: @escaping @Sendable (ScreenshotWatcherEvent) -> Void
    ) {
        stopMonitoring()

        let callback = Self.makeCallback()
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [folderURL.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.25,
            flags
        ) else {
            return
        }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)

        self.onEvent = onEvent
    }

    func stopMonitoring() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        pendingURLs.removeAll()
        pendingFullRescan = false
        onEvent = nil

        guard let stream else { return }

        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit {
        stopMonitoring()
    }

    private var onEvent: (@Sendable (ScreenshotWatcherEvent) -> Void)?

    private static func makeCallback() -> FSEventStreamCallback {
        { _, info, eventCount, eventPaths, eventFlags, _ in
            guard let info else { return }
            let watcher = Unmanaged<ScreenshotWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.handleEvents(
                count: eventCount,
                eventPaths: unsafeBitCast(eventPaths, to: NSArray.self),
                eventFlags: eventFlags
            )
        }
    }

    private func handleEvents(
        count: Int,
        eventPaths: NSArray,
        eventFlags: UnsafePointer<FSEventStreamEventFlags>
    ) {
        guard let onEvent else { return }

        var requiresFullRescan = false
        var changedURLs = Set<URL>()

        for index in 0..<count {
            let flags = eventFlags[index]

            if flags & UInt32(kFSEventStreamEventFlagMustScanSubDirs) != 0 ||
                flags & UInt32(kFSEventStreamEventFlagRootChanged) != 0 {
                requiresFullRescan = true
            }

            guard let path = eventPaths[index] as? String else {
                requiresFullRescan = true
                continue
            }

            changedURLs.insert(URL(fileURLWithPath: path))
        }

        pendingFullRescan = pendingFullRescan || requiresFullRescan
        pendingURLs.formUnion(changedURLs)
        scheduleDelivery(onEvent: onEvent)
    }

    private func scheduleDelivery(onEvent: @escaping @Sendable (ScreenshotWatcherEvent) -> Void) {
        debounceWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }

            let event = ScreenshotWatcherEvent(
                changedURLs: Array(self.pendingURLs),
                requiresFullRescan: self.pendingFullRescan
            )

            self.pendingURLs.removeAll()
            self.pendingFullRescan = false

            onEvent(event)
        }

        debounceWorkItem = workItem
        queue.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }
}
