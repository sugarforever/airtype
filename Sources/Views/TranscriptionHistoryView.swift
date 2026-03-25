import SwiftUI

struct TranscriptionHistoryView: View {
    @State private var entries: [TranscriptionHistory.Entry] = []
    @State private var copiedId: UUID?

    var body: some View {
        VStack(spacing: 0) {
            if entries.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No transcriptions yet")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                List {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(entry.date, style: .relative)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if !entry.inserted {
                                    Text("Not inserted")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(.orange)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.1))
                                        .clipShape(Capsule())
                                }
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(entry.text, forType: .string)
                                    copiedId = entry.id
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                        if copiedId == entry.id { copiedId = nil }
                                    }
                                } label: {
                                    Image(systemName: copiedId == entry.id ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 11))
                                        .foregroundStyle(copiedId == entry.id ? .green : .secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Copy to clipboard")
                            }
                            Text(entry.text)
                                .font(.system(size: 12))
                                .lineLimit(4)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 400)
        .onAppear { entries = TranscriptionHistory.shared.entries }
    }
}
