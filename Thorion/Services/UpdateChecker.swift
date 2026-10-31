import AppKit
import Defaults
import Foundation
import Observation
import UserNotifications
import os.log

/// Checks GitHub Releases for a newer Thorion version and notifies the user.
@MainActor
@Observable
final class UpdateChecker {
    static let shared = UpdateChecker()

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, downloadURL: URL)
        case failed(message: String)
    }

    static let releasesPageURL = URL(string: "https://github.com/cavaldos/Thorion/releases/latest")
    private static let latestReleaseAPIURL = URL(
        string: "https://api.github.com/repos/cavaldos/Thorion/releases/latest")
    private static let automaticCheckInterval: Duration = .seconds(24 * 60 * 60)
    nonisolated static let notificationURLKey = "downloadURL"

    private(set) var status: Status = .idle
    private var automaticCheckTask: Task<Void, Never>?

    private let logger = Logger(subsystem: "com.thorion.app", category: "UpdateChecker")

    private init() {}

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    func startAutomaticChecks() {
        automaticCheckTask?.cancel()
        automaticCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                if Defaults[.automaticallyCheckForUpdates] {
                    await self?.checkForUpdates(userInitiated: false)
                }
                try? await Task.sleep(for: Self.automaticCheckInterval)
            }
        }
    }

    func checkForUpdates(userInitiated: Bool) async {
        guard status != .checking else { return }
        status = .checking

        do {
            let release = try await fetchLatestRelease()
            let latestVersion = Self.normalizedVersion(release.tagName)

            guard Self.isVersion(latestVersion, newerThan: currentVersion) else {
                status = .upToDate
                return
            }

            status = .available(version: latestVersion, downloadURL: release.htmlURL)

            // Background checks run daily; only notify once per new version.
            if userInitiated || Defaults[.lastNotifiedUpdateVersion] != latestVersion {
                Defaults[.lastNotifiedUpdateVersion] = latestVersion
                sendUpdateNotification(version: latestVersion, downloadURL: release.htmlURL)
            }
        } catch {
            logger.error("Update check failed: \(error)")
            status = .failed(message: error.localizedDescription)
        }
    }

    private struct Release: Decodable {
        let tagName: String
        let htmlURL: URL

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }

    private enum UpdateCheckError: LocalizedError {
        case invalidConfiguration
        case badResponse(statusCode: Int)

        var errorDescription: String? {
            switch self {
            case .invalidConfiguration:
                String(localized: "The update server address is invalid.")
            case .badResponse(let statusCode):
                String(localized: "GitHub returned an unexpected response (HTTP \(statusCode)).")
            }
        }
    }

    private func fetchLatestRelease() async throws -> Release {
        guard let url = Self.latestReleaseAPIURL else {
            throw UpdateCheckError.invalidConfiguration
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw UpdateCheckError.badResponse(statusCode: httpResponse.statusCode)
        }
        return try JSONDecoder().decode(Release.self, from: data)
    }

    private func sendUpdateNotification(version: String, downloadURL: URL) {
        guard !Defaults[.disableNotifications] else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Thorion \(version) is available")
        content.body = String(localized: "You are using version \(currentVersion). Click to download the update.")
        content.sound = .default
        content.userInfo = [Self.notificationURLKey: downloadURL.absoluteString]

        let request = UNNotificationRequest(
            identifier: "updateAvailable",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { [logger] error in
            if let error {
                logger.error("Failed to deliver update notification: \(error)")
            }
        }
    }

    static func normalizedVersion(_ tag: String) -> String {
        tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let candidateParts = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let currentParts = current.split(separator: ".").map { Int($0) ?? 0 }
        let length = max(candidateParts.count, currentParts.count)

        for index in 0..<length {
            let candidatePart = index < candidateParts.count ? candidateParts[index] : 0
            let currentPart = index < currentParts.count ? currentParts[index] : 0
            if candidatePart != currentPart {
                return candidatePart > currentPart
            }
        }
        return false
    }
}
