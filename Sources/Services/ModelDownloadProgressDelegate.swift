import Foundation

/// Bridges async URLSession download byte counts to the pinned HuggingFace
/// client's per-task download delegate. On macOS, download(for:delegate:) does
/// not deliver didWriteData, although the task's byte counts change throughout
/// the transfer. Keeping the library's delegate preserves its resume offsets
/// and weighted parent Progress instead of inventing a second progress total.
final class ModelDownloadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    // URLSession retains this delegate until invalidation. Observations live for
    // the installation session; all access to the collection is protected.
    private let lock = NSLock()
    private var observations: [NSKeyValueObservation] = []

    static func makeSession(configuration: URLSessionConfiguration = .default) -> URLSession {
        URLSession(configuration: configuration, delegate: ModelDownloadProgressDelegate(), delegateQueue: nil)
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        guard let downloadTask = task as? URLSessionDownloadTask else { return }
        let observation = downloadTask.observe(\.countOfBytesReceived, options: [.old, .new]) { [weak session] task, change in
            guard let session,
                  let delegate = task.delegate as? URLSessionDownloadDelegate else { return }
            let received = task.countOfBytesReceived
            delegate.urlSession?(
                session,
                downloadTask: task,
                didWriteData: max(0, received - (change.oldValue ?? 0)),
                totalBytesWritten: received,
                totalBytesExpectedToWrite: task.countOfBytesExpectedToReceive
            )
        }
        lock.withLock { observations.append(observation) }
    }

    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        let retained = lock.withLock {
            let retained = observations
            observations.removeAll()
            return retained
        }
        retained.forEach { $0.invalidate() }
    }
}
