import Foundation

/// Notices when the menu changes the selected target.
///
/// Watches the containing directory rather than the selection file itself.
/// The file is replaced atomically, so its inode is gone after the first
/// write and a descriptor held on it would report one deletion and then go
/// deaf.
public final class TargetWatcher: @unchecked Sendable {
    private let selection: TargetSelection
    private let queue = DispatchQueue(label: "dev.steve.statsy.target-watcher")
    private var source: (any DispatchSourceFileSystemObject)?
    private var descriptor: CInt = -1

    public init(selection: TargetSelection = TargetSelection()) {
        self.selection = selection
    }

    deinit {
        stop()
    }

    /// Reports whenever the recorded target stops matching `known`.
    ///
    /// The caller says what it believes it is showing rather than the watcher
    /// assuming the file is already in agreement, because it need not be: the
    /// panel stops watching while its display is unplugged, and a target chosen
    /// in that window would otherwise never be reported. Starting from the
    /// caller's own belief turns that case into an ordinary change.
    ///
    /// A write that leaves the selection unchanged is swallowed either way: the
    /// panel would otherwise tear down a healthy provider and rebuild an
    /// identical one every time the file was touched.
    public func start(from known: Target, onChange: @escaping @MainActor (Target) -> Void) {
        stop()

        let directory = selection.url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write], queue: queue
        )
        var current = known
        let selection = selection
        source.setEventHandler {
            let next = selection.read()
            guard next != current else { return }
            current = next
            Task { @MainActor in onChange(next) }
        }
        source.setCancelHandler { [descriptor] in
            close(descriptor)
        }
        source.resume()
        self.source = source

        // Settle any change that happened while nothing was watching.
        let recorded = selection.read()
        if recorded != current {
            current = recorded
            Task { @MainActor in onChange(recorded) }
        }
    }

    public func stop() {
        source?.cancel()
        source = nil
        descriptor = -1
    }
}
