import Foundation
#if SWIFT_PACKAGE
import VocabularyCore
#endif

enum StreamingTranscriptionEvent: Sendable {
    case partial(String)
    case final_(String)
    case error(Error)
}

protocol StreamingTranscriptionService: AnyObject, Sendable {
    var events: AsyncStream<StreamingTranscriptionEvent> { get }
    func connect() async throws
    func startSession(context: TranscriptionContext) async throws
    func sendAudio(_ data: Data) async
    func endAudio() async throws
    func disconnect() async
}
