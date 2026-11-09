import Foundation

struct UpdateChecker {
    static let releasePage = URL(string: "https://github.com/TerryZheng233/Klik./releases/latest")!
    private static let apiURL = URL(string: "https://api.github.com/repos/TerryZheng233/Klik./releases/latest")!

    enum Result: Equatable {
        case upToDate
        case available(String)
        case unavailable
    }

    static func check(currentVersion: String) async -> Result {
        var request = URLRequest(url: apiURL, timeoutInterval: 12)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Klik/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            return evaluate(data: data, status: (response as? HTTPURLResponse)?.statusCode,
                            currentVersion: currentVersion)
        } catch {
            return .unavailable
        }
    }

    static func evaluate(data: Data, status: Int?, currentVersion: String) -> Result {
        struct Release: Decodable { let tag_name: String }
        guard status == 200, let release = try? JSONDecoder().decode(Release.self, from: data),
              let latest = components(release.tag_name), let current = components(currentVersion) else {
            return .unavailable
        }
        let count = max(latest.count, current.count)
        for index in 0..<count {
            let lhs = index < latest.count ? latest[index] : 0
            let rhs = index < current.count ? current[index] : 0
            if lhs > rhs { return .available(release.tag_name) }
            if lhs < rhs { return .upToDate }
        }
        return .upToDate
    }

    private static func components(_ version: String) -> [Int]? {
        let clean = version.hasPrefix("v") ? String(version.dropFirst()) : version
        let pieces = clean.split(separator: ".", omittingEmptySubsequences: false)
        guard !pieces.isEmpty, pieces.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              pieces.count <= 4 else { return nil }
        let numbers = pieces.compactMap { Int($0) }
        return numbers.count == pieces.count ? numbers : nil
    }
}
