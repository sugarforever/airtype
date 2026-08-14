import Foundation
import Observation

@MainActor
@Observable
@available(macOS 14.0, *)
public final class HistoryPageModel {
    public typealias CopyText = @MainActor (String) -> Bool

    public var query = ""
    public private(set) var entries: [TranscriptionHistory.Entry]
    public private(set) var copiedID: UUID?
    public private(set) var isClearConfirmationPresented = false

    @ObservationIgnored private let history: TranscriptionHistory?
    @ObservationIgnored private let notificationCenter: NotificationCenter?
    @ObservationIgnored private let copyText: CopyText
    @ObservationIgnored private var notificationToken: NSObjectProtocol?

    public init(
        history: TranscriptionHistory = .shared,
        copyText: @escaping CopyText = { _ in false }
    ) {
        self.history = history
        self.notificationCenter = history.notificationCenter
        self.copyText = copyText
        self.entries = history.entries
        self.notificationToken = history.notificationCenter.addObserver(
            forName: .transcriptionHistoryDidChange,
            object: history,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reload()
            }
        }
    }

    public init(
        entries: [TranscriptionHistory.Entry],
        copyText: @escaping CopyText = { _ in false }
    ) {
        self.history = nil
        self.notificationCenter = nil
        self.copyText = copyText
        self.entries = entries
        self.notificationToken = nil
    }

    deinit {
        if let notificationToken {
            notificationCenter?.removeObserver(notificationToken)
        }
    }

    public var filteredEntries: [TranscriptionHistory.Entry] {
        guard !query.isEmpty else { return entries }
        return entries.filter { $0.text.localizedStandardContains(query) }
    }

    public func reload() {
        guard let history else { return }
        let latestEntries = history.entries
        if entries != latestEntries {
            entries = latestEntries
        }
    }

    public func copy(_ entry: TranscriptionHistory.Entry) {
        guard copyText(entry.text) else { return }
        if copiedID != entry.id {
            copiedID = entry.id
        }
    }

    public func clearCopyFeedback(for id: UUID) {
        guard copiedID == id else { return }
        copiedID = nil
    }

    public func requestClear() {
        if !isClearConfirmationPresented {
            isClearConfirmationPresented = true
        }
    }

    public func cancelClear() {
        if isClearConfirmationPresented {
            isClearConfirmationPresented = false
        }
    }

    public func confirmClear() {
        guard isClearConfirmationPresented else { return }
        history?.clear()
        if !entries.isEmpty {
            entries = []
        }
        isClearConfirmationPresented = false
    }
}
