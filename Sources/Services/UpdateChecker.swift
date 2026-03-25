import Foundation

@MainActor
final class UpdateChecker: ObservableObject {
    @Published var updateAvailable = false
    @Published var latestVersion = ""
    @Published var downloadURL: URL?

    private let releaseURL = URL(string: "https://api.github.com/repos/sugarforever/airtype/releases/latest")!

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
                var request = URLRequest(url: releaseURL)
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                let (data, _) = try await URLSession.shared.data(for: request)
                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                let remote = release.tag_name
                guard let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else { return }
                updateAvailable = isNewer(remote: remote, thanCurrent: current)
                if updateAvailable {
                    latestVersion = remote
                    downloadURL = release.assets.first { $0.name.hasSuffix(".dmg") }
                        .map { URL(string: $0.browser_download_url) } ?? nil
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

    private struct GitHubRelease: Decodable {
        let tag_name: String
        let assets: [Asset]

        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
        }
    }
}
