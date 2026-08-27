import SwiftUI

struct LocalModelDownloadSizeView: View {
    let model: LocalMLXModel

    @State private var estimate: ModelDownloadSizeEstimate?

    var body: some View {
        Text(label)
            .font(.system(size: 11))
            .foregroundStyle(Theme.textSecondary)
            .task(id: model.id) {
                estimate = nil
                let result = await ModelDownloadSizeProvider.shared.estimate(for: model)
                guard !Task.isCancelled else { return }
                estimate = result
            }
    }

    private var label: String {
        let value = estimate?.bytes ?? model.catalogDownloadSizeBytes
        let size = ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
        return "Estimated download: \(size)"
    }
}
