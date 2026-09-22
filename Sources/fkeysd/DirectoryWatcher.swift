import Foundation

/// Fires `onChange` when the watched directory's contents change.
///
/// The hook writes via `mv`, so the directory itself changes on every update —
/// watching the directory is enough, no per-file watches needed.
final class DirectoryWatcher {
    private let descriptor: CInt
    private let source: DispatchSourceFileSystemObject

    init?(dir: URL, onChange: @escaping () -> Void) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        descriptor = open(dir.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )
        source.setEventHandler(handler: onChange)
        let fd = descriptor
        source.setCancelHandler { close(fd) }
        source.resume()
    }

    deinit {
        source.cancel()
    }
}
