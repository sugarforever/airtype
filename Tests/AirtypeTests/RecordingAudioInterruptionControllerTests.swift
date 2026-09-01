import XCTest
@testable import Airtype

@MainActor
final class RecordingAudioInterruptionControllerTests: XCTestCase {
    func testOnlyNowPlayingPlayingStateIsTreatedAsActivePlayback() {
        XCTAssertFalse(MediaRemotePlaybackState(rawValue: 0).isPlaying)
        XCTAssertTrue(MediaRemotePlaybackState(rawValue: 1).isPlaying)
        XCTAssertFalse(MediaRemotePlaybackState(rawValue: 2).isPlaying)
        XCTAssertFalse(MediaRemotePlaybackState(rawValue: 3).isPlaying)
    }

    func testRecordingTemporarilyPausesActivePlayback() async {
        let playback = TestMediaPlayback(session: .init(processIdentifier: 42, isPlaying: true))
        let controller = RecordingAudioInterruptionController(mediaPlayback: playback)

        await controller.recordingDidStart()
        XCTAssertEqual(playback.pauseCallCount, 1)

        await controller.recordingDidEnd()
        XCTAssertEqual(playback.resumeCallCount, 1)
    }

    func testRecordingDoesNotStartPlaybackThatWasAlreadyPaused() async {
        let playback = TestMediaPlayback(session: .init(processIdentifier: 42, isPlaying: false))
        let controller = RecordingAudioInterruptionController(mediaPlayback: playback)

        await controller.recordingDidStart()
        XCTAssertEqual(playback.pauseCallCount, 0)
        await controller.recordingDidEnd()

        XCTAssertEqual(playback.resumeCallCount, 0)
    }

    func testDuplicateRecordingStartDoesNotTogglePlaybackBackOn() async {
        let playback = TestMediaPlayback(session: .init(processIdentifier: 42, isPlaying: true))
        let controller = RecordingAudioInterruptionController(mediaPlayback: playback)

        await controller.recordingDidStart()
        await controller.recordingDidStart()

        XCTAssertEqual(playback.pauseCallCount, 1)
    }

    func testRecordingDoesNotResumeDifferentPlaybackSession() async {
        let playback = TestMediaPlayback(session: .init(processIdentifier: 42, isPlaying: true))
        let controller = RecordingAudioInterruptionController(mediaPlayback: playback)

        await controller.recordingDidStart()
        playback.session = .init(processIdentifier: 99, isPlaying: false)
        await controller.recordingDidEnd()

        XCTAssertEqual(playback.resumeCallCount, 0)
    }

    func testOwnerChangeDuringPauseDoesNotStartTheNewSession() async {
        let playback = TestMediaPlayback(session: .init(processIdentifier: 42, isPlaying: true))
        playback.sessionAfterPause = .init(processIdentifier: 99, isPlaying: false)
        let controller = RecordingAudioInterruptionController(mediaPlayback: playback)

        await controller.recordingDidStart()
        XCTAssertEqual(playback.resumeCallCount, 0)

        await controller.recordingDidEnd()
        XCTAssertEqual(playback.resumeCallCount, 0)
    }
}

@MainActor
private final class TestMediaPlayback: MediaPlaybackControlling {
    var session: MediaPlaybackSession?
    var sessionAfterPause: MediaPlaybackSession?
    private(set) var pauseCallCount = 0
    private(set) var resumeCallCount = 0

    init(session: MediaPlaybackSession?) {
        self.session = session
    }

    func currentSession() async -> MediaPlaybackSession? {
        session
    }

    func pause() -> Bool {
        pauseCallCount += 1
        if let sessionAfterPause {
            session = sessionAfterPause
        }
        return true
    }

    func resume() {
        resumeCallCount += 1
    }
}
