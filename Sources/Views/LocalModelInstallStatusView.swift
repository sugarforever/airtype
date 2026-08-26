import SwiftUI

/// Both entry points observe the same app-owned installation, even after reopening.
struct LocalModelInstallStatusView: View {
    @ObservedObject var manager: LocalModelManager
    let selectedModel: LocalMLXModel

    var body: some View {
        if manager.isInstalling || manager.model == selectedModel {
            if let phase = manager.phase {
                SettingsCardDivider()
                SettingsCardRow(label: "Install Status") {
                    VStack(alignment: .leading, spacing: 8) {
                        if let model = manager.model {
                            Text(model.rawValue)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        switch phase {
                        case .preparing:
                            activity("Preparing download…")
                        case .downloading(let fraction):
                            if let fraction {
                                ProgressView(value: fraction, total: 1) {
                                    HStack {
                                        Text("Downloading")
                                        Spacer()
                                        Text(fraction, format: .percent.precision(.fractionLength(0)))
                                            .monospacedDigit()
                                    }
                                }
                                .progressViewStyle(.linear)
                                .tint(Theme.brand)
                                .accessibilityLabel("Model download")
                                .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
                            } else {
                                activity("Downloading model files…")
                            }
                        case .loading:
                            activity("Download ready. Loading model…")
                        }
                    }
                    .font(.system(size: 11))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if let error = manager.lastError {
                SettingsCardDivider()
                SettingsCardRow(label: "Model Error") {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.statusRed)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if let status = manager.statusMessage {
                SettingsCardDivider()
                SettingsCardRow(label: "Install Status") {
                    Text(status)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private func activity(_ label: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .accessibilityHidden(true)
            Text(label)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
