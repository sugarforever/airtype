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
    let mediaIdentifier: String?

    init(processIdentifier: Int32, isPlaying: Bool, mediaIdentifier: String? = nil) {
        self.processIdentifier = processIdentifier
        self.isPlaying = isPlaying
        self.mediaIdentifier = mediaIdentifier
    }
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
    private var pauseSentForRecording = false
    private var pausedSession: MediaPlaybackSession?

    init(mediaPlayback: any MediaPlaybackControlling) {
        self.mediaPlayback = mediaPlayback
    }

    convenience init() {
        self.init(mediaPlayback: SystemMediaPlaybackController())
    }

    func recordingDidStart() async {
        guard !pauseSentForRecording else {
            debugLog("Media interruption skipped: playback already paused by Airtype")
            return
        }
        let session = await mediaPlayback.currentSession()
        pauseSentForRecording = true
        guard mediaPlayback.pause() else {
            return
        }
        guard let session, session.isPlaying, session.mediaIdentifier != nil else { return }
        guard let currentSession = await mediaPlayback.currentSession(),
              currentSession.processIdentifier == session.processIdentifier,
              currentSession.mediaIdentifier == session.mediaIdentifier,
              !currentSession.isPlaying else { return }
        pausedSession = session
    }

    func recordingDidEnd() async {
        pauseSentForRecording = false
        guard let pausedSession else { return }
        self.pausedSession = nil
        guard let currentSession = await mediaPlayback.currentSession(),
              currentSession.processIdentifier == pausedSession.processIdentifier,
              currentSession.mediaIdentifier == pausedSession.mediaIdentifier else {
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
    private typealias NowPlayingInfoHandler = @convention(block) (CFDictionary?) -> Void
    private typealias GetNowPlayingInfo = @convention(c) (
        DispatchQueue,
        @escaping NowPlayingInfoHandler
    ) -> Void
    private typealias SendCommand = @convention(c) (Int32, CFDictionary?) -> Bool

    private static let frameworkPath =
        "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
    private static let playCommand: Int32 = 0
    private static let pauseCommand: Int32 = 1

    private let frameworkHandle: UnsafeMutableRawPointer?
    private let getPlaybackState: GetPlaybackState?
    private let getProcessIdentifier: GetProcessIdentifier?
    private let getNowPlayingInfo: GetNowPlayingInfo?
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
           let symbol = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") {
            getNowPlayingInfo = unsafeBitCast(symbol, to: GetNowPlayingInfo.self)
        } else {
            getNowPlayingInfo = nil
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
        guard let getPlaybackState, let getProcessIdentifier, let getNowPlayingInfo else { return nil }
        return await withCheckedContinuation { continuation in
            let query = MediaRemoteSessionQuery(continuation: continuation)
            getPlaybackState(.global(qos: .userInitiated)) { rawState in
                query.receive(playbackState: rawState)
            }
            getProcessIdentifier(.global(qos: .userInitiated)) { processIdentifier in
                query.receive(processIdentifier: processIdentifier)
            }
            getNowPlayingInfo(.global(qos: .userInitiated)) { info in
                query.receive(nowPlayingInfo: info)
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
    private var mediaIdentifier: String?
    private var receivedNowPlayingInfo = false

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

    func receive(nowPlayingInfo: CFDictionary?) {
        lock.lock()
        receivedNowPlayingInfo = true
        mediaIdentifier = nowPlayingMediaIdentifier(from: nowPlayingInfo)
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
        guard let continuation, let playbackState, let processIdentifier, receivedNowPlayingInfo else { return }
        self.continuation = nil
        continuation.resume(returning: MediaPlaybackSession(
            processIdentifier: processIdentifier,
            isPlaying: MediaRemotePlaybackState(rawValue: playbackState).isPlaying,
            mediaIdentifier: mediaIdentifier
        ))
    }
}

func nowPlayingMediaIdentifier(from dictionary: CFDictionary?) -> String? {
    guard let info = dictionary as? [String: Any] else { return nil }
    let identifierKeys = [
        "kMRMediaRemoteNowPlayingInfoContentItemIdentifier",
        "kMRMediaRemoteNowPlayingInfoExternalContentIdentifier",
        "kMRMediaRemoteNowPlayingInfoUniqueIdentifier"
    ]
    if let identifier = identifierKeys.compactMap({ info[$0] as? String }).first(where: { !$0.isEmpty }) {
        return "id:\(identifier)"
    }

    let titleKey = "kMRMediaRemoteNowPlayingInfoTitle"
    let durationKey = "kMRMediaRemoteNowPlayingInfoDuration"
    guard let title = info[titleKey] as? String,
          !title.isEmpty,
          let duration = info[durationKey] as? NSNumber else {
        return nil
    }
    let optionalMetadataKeys = [
        "kMRMediaRemoteNowPlayingInfoArtist",
        "kMRMediaRemoteNowPlayingInfoAlbum"
    ]
    let optionalComponents = optionalMetadataKeys.compactMap { key -> String? in
        guard let value = info[key] else { return nil }
        return "\(key)=\(value)"
    }
    return (["\(titleKey)=\(title)", "\(durationKey)=\(duration)"] + optionalComponents)
        .joined(separator: "|")
}
