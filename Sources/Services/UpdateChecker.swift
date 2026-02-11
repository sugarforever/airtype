import Foundation

@MainActor
final class UpdateChecker: ObservableObject {
    @Published var updateAvailable = false
    @Published var latestVersion = ""

    private let versionURL = URL(string: "https://pub-9bc27f7ea4884bf89d219798d23f6dd2.r2.dev/releases/version.json")!
    static let downloadURL = URL(string: "https://pub-9bc27f7ea4884bf89d219798d23f6dd2.r2.dev/releases/Airtype-latest.dmg")!

    private var timer: Timer?

    init() {
        check()
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.check()
            }
        }
    }

    deinit {
        timer?.invalidate()
    }

    func check() {
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: versionURL)
                let response = try JSONDecoder().decode(VersionResponse.self, from: data)
                let remote = response.version.trimmingCharacters(in: .whitespaces)
                guard let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else { return }
                updateAvailable = isNewer(remote: remote, thanCurrent: current)
                if updateAvailable {
                    latestVersion = remote
                }
            } catch {
                // Silently fail — don't block the user
            }
        }
    }

    private func isNewer(remote: String, thanCurrent current: String) -> Bool {
        let r = parseVersion(remote)
        let c = parseVersion(current)
        for i in 0..<max(r.count, c.count) {
            let rv = i < r.count ? r[i] : 0
            let cv = i < c.count ? c[i] : 0
            if rv > cv { return true }
            if rv < cv { return false }
        }
        return false
    }

    private func parseVersion(_ v: String) -> [Int] {
        let stripped = v.hasPrefix("v") ? String(v.dropFirst()) : v
        return stripped.split(separator: ".").compactMap { Int($0) }
    }

    private struct VersionResponse: Decodable {
        let version: String
    }
}
