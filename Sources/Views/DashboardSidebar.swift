import SwiftUI

struct DashboardSidebar: View {
    @Binding var selection: DashboardDestination
    let isConfigured: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brandHeader

            VStack(spacing: 4) {
                ForEach(DashboardDestination.allCases) { destination in
                    sidebarButton(for: destination)
                }
            }
            .padding(.horizontal, 10)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.cardBg)
    }

    private var brandHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(isConfigured ? Theme.statusGreen : Theme.statusOrange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Airtype")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(isConfigured ? "Ready" : "Setup required")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 20)
    }

    private func sidebarButton(for destination: DashboardDestination) -> some View {
        Button {
            selection = destination
        } label: {
            Label(destination.title, systemImage: destination.systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(
                    selection == destination ? Theme.textPrimary : Theme.textSecondary
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    selection == destination ? Theme.brand.opacity(0.14) : .clear,
                    in: .rect(cornerRadius: 6)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == destination ? .isSelected : [])
    }
}

private extension DashboardDestination {
    var title: String {
        switch self {
        case .home: "Home"
        case .history: "History"
        case .vocabulary: "Vocabulary"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .history: "clock.arrow.circlepath"
        case .vocabulary: "text.book.closed"
        case .settings: "gearshape"
        }
    }
}
