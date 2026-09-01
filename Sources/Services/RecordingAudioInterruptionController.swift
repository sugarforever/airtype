import Darwin
import Foundation

struct MediaRemotePlaybackState {
    let rawValue: Int32

    var isPlaying: Bool {
        rawValue == 1
    }
}

struct MediaPlaybackSession: Equatable {
    let processIdentifier: Int32
    let isPlaying: Bool
}

@MainActor
protocol MediaPlaybackControlling: AnyObject {
    func currentSession() async -> MediaPlaybackSession?
    func pause() -> Bool
    func resume()
}

@MainActor
final class RecordingAudioInterruptionController {
    private let mediaPlayback: any MediaPlaybackControlling
    private var pausedSession: MediaPlaybackSession?

    init(mediaPlayback: any MediaPlaybackControlling) {
        self.mediaPlayback = mediaPlayback
    }

    convenience init() {
        self.init(mediaPlayback: SystemMediaPlaybackController())
    }

    func recordingDidStart() async {
        guard pausedSession == nil else {
            debugLog("Media interruption skipped: playback already paused by Airtype")
            return
        }
        guard let session = await mediaPlayback.currentSession(), session.isPlaying else { return }
        guard await mediaPlayback.currentSession()?.processIdentifier == session.processIdentifier else {
            return
        }
        guard mediaPlayback.pause() else { return }
        guard await mediaPlayback.currentSession()?.processIdentifier == session.processIdentifier else {
            return
        }
        pausedSession = session
    }

    func recordingDidEnd() async {
        guard let pausedSession else { return }
        self.pausedSession = nil
        guard await mediaPlayback.currentSession()?.processIdentifier == pausedSession.processIdentifier else {
            return
        }
        mediaPlayback.resume()
    }
}

@MainActor
private final class SystemMediaPlaybackController: MediaPlaybackControlling {
    private typealias PlaybackStateHandler = @convention(block) (Int32) -> Void
    private typealias GetPlaybackState = @convention(c) (
        DispatchQueue,
        @escaping PlaybackStateHandler
    ) -> Void
    private typealias ProcessIdentifierHandler = @convention(block) (Int32) -> Void
    private typealias GetProcessIdentifier = @convention(c) (
        DispatchQueue,
        @escaping ProcessIdentifierHandler
    ) -> Void
    private typealias SendCommand = @convention(c) (Int32, CFDictionary?) -> Bool

    private static let frameworkPath =
        "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
    private static let playCommand: Int32 = 0
    private static let pauseCommand: Int32 = 1

    private let frameworkHandle: UnsafeMutableRawPointer?
    private let getPlaybackState: GetPlaybackState?
    private let getProcessIdentifier: GetProcessIdentifier?
    private let sendCommand: SendCommand?

    init() {
        let handle = dlopen(Self.frameworkPath, RTLD_LAZY)
        frameworkHandle = handle

        if let handle,
           let symbol = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationPlaybackState") {
            getPlaybackState = unsafeBitCast(symbol, to: GetPlaybackState.self)
        } else {
            getPlaybackState = nil
            debugLog("Media interruption unavailable: playback-state symbol missing")
        }

        if let handle,
           let symbol = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationPID") {
            getProcessIdentifier = unsafeBitCast(symbol, to: GetProcessIdentifier.self)
        } else {
            getProcessIdentifier = nil
        }

        if let handle,
           let symbol = dlsym(handle, "MRMediaRemoteSendCommand") {
            sendCommand = unsafeBitCast(symbol, to: SendCommand.self)
        } else {
            sendCommand = nil
            debugLog("Media interruption unavailable: command symbol missing")
        }
    }

    deinit {
        if let frameworkHandle {
            dlclose(frameworkHandle)
        }
    }

    func currentSession() async -> MediaPlaybackSession? {
        guard let getPlaybackState, let getProcessIdentifier else { return nil }
        return await withCheckedContinuation { continuation in
            let query = MediaRemoteSessionQuery(continuation: continuation)
            getPlaybackState(.global(qos: .userInitiated)) { rawState in
                query.receive(playbackState: rawState)
            }
            getProcessIdentifier(.global(qos: .userInitiated)) { processIdentifier in
                query.receive(processIdentifier: processIdentifier)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(300)) {
                query.timeout()
            }
        }
    }

    func pause() -> Bool {
        sendCommand?(Self.pauseCommand, nil) ?? false
    }

    func resume() {
        _ = sendCommand?(Self.playCommand, nil)
    }
}

private final class MediaRemoteSessionQuery: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<MediaPlaybackSession?, Never>?
    private var playbackState: Int32?
    private var processIdentifier: Int32?

    init(continuation: CheckedContinuation<MediaPlaybackSession?, Never>) {
        self.continuation = continuation
    }

    func receive(playbackState: Int32) {
        lock.lock()
        self.playbackState = playbackState
        finishIfReadyLocked()
        lock.unlock()
    }

    func receive(processIdentifier: Int32) {
        lock.lock()
        self.processIdentifier = processIdentifier
        finishIfReadyLocked()
        lock.unlock()
    }

    func timeout() {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: nil)
    }

    private func finishIfReadyLocked() {
        guard let continuation, let playbackState, let processIdentifier else { return }
        self.continuation = nil
        continuation.resume(returning: MediaPlaybackSession(
            processIdentifier: processIdentifier,
            isPlaying: MediaRemotePlaybackState(rawValue: playbackState).isPlaying
        ))
    }
}
