import Foundation

extension Notification.Name {
    static let vezSearchLocationsDidChange = Notification.Name(
        "com.spotalt.searchLocationsDidChange"
    )
}

final class SearchLocationStore {
    private struct AccessedLocation {
        let url: URL
        let didStartSecurityScope: Bool
    }

    private static let bookmarksKey = "searchLocationBookmarks"

    private let defaults: UserDefaults
    private var bookmarks: [Data]
    private var accessedLocations: [AccessedLocation] = []

    var locations: [URL] {
        accessedLocations.map(\.url)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        bookmarks = defaults.array(forKey: Self.bookmarksKey) as? [Data] ?? []
        restoreLocations()
    }

    deinit {
        for location in accessedLocations where location.didStartSecurityScope {
            location.url.stopAccessingSecurityScopedResource()
        }
    }

    func add(_ urls: [URL]) throws {
        var changed = false

        for selectedURL in urls {
            let url = selectedURL.standardizedFileURL
            guard !contains(url) else { continue }

            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            bookmarks.append(bookmark)
            accessedLocations.append(
                AccessedLocation(
                    url: url,
                    didStartSecurityScope: url.startAccessingSecurityScopedResource()
                )
            )
            changed = true
        }

        guard changed else { return }
        persistAndNotify()
    }

    func remove(_ url: URL) {
        let standardizedURL = url.standardizedFileURL
        guard let index = accessedLocations.firstIndex(where: {
            $0.url.standardizedFileURL == standardizedURL
        }) else { return }

        let removed = accessedLocations.remove(at: index)
        if removed.didStartSecurityScope {
            removed.url.stopAccessingSecurityScopedResource()
        }
        bookmarks.remove(at: index)
        persistAndNotify()
    }

    private func restoreLocations() {
        var restoredBookmarks: [Data] = []
        var restoredLocations: [AccessedLocation] = []

        for bookmark in bookmarks {
            var isStale = false

            guard let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                continue
            }

            let standardizedURL = url.standardizedFileURL
            guard !restoredLocations.contains(where: {
                $0.url.standardizedFileURL == standardizedURL
            }) else {
                continue
            }

            let refreshedBookmark: Data
            if isStale,
               let refreshed = try? standardizedURL.bookmarkData(
                   options: .withSecurityScope,
                   includingResourceValuesForKeys: nil,
                   relativeTo: nil
               ) {
                refreshedBookmark = refreshed
            } else {
                refreshedBookmark = bookmark
            }

            restoredBookmarks.append(refreshedBookmark)
            restoredLocations.append(
                AccessedLocation(
                    url: standardizedURL,
                    didStartSecurityScope: standardizedURL.startAccessingSecurityScopedResource()
                )
            )
        }

        bookmarks = restoredBookmarks
        accessedLocations = restoredLocations
        defaults.set(bookmarks, forKey: Self.bookmarksKey)
    }

    private func contains(_ url: URL) -> Bool {
        let standardizedURL = url.standardizedFileURL
        return accessedLocations.contains {
            $0.url.standardizedFileURL == standardizedURL
        }
    }

    private func persistAndNotify() {
        defaults.set(bookmarks, forKey: Self.bookmarksKey)
        NotificationCenter.default.post(name: .vezSearchLocationsDidChange, object: self)
    }
}
