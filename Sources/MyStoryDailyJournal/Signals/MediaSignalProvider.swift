import Foundation
import MediaPlayer

/// Music listened to that day, via `MPMediaLibrary`'s local-library
/// "last played" metadata (§4: "coverage is inconsistent across streaming
/// apps — low priority"). Only items with a `lastPlayedDate` inside the
/// day are surfaced; a track merely downloaded or synced, never played,
/// never appears.
struct MediaSignalProvider: DaySignalProvider {
    let kind: DaySignalKind = .media

    func isAuthorized() async -> Bool {
        MPMediaLibrary.authorizationStatus() == .authorized
    }

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            MPMediaLibrary.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func collectSignals(for day: DateInterval) async throws -> [DaySignal] {
        guard await isAuthorized() else { return [] }

        let query = MPMediaQuery.songs()
        let items = query.items ?? []
        let titles = items
            .filter { item in
                guard let played = item.lastPlayedDate else { return false }
                return played >= day.start && played < day.end
            }
            .compactMap(\.title)

        guard !titles.isEmpty else { return [] }

        let signal = DaySignal(kind: .media, timestamp: day.start)
        signal.setPayload(MediaPayload(titles: Array(Set(titles)).sorted()))
        return [signal]
    }
}
