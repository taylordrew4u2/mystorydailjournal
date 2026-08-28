import Foundation
import Photos
import CoreLocation

/// Photos and screenshots taken that day, with what the asset's own
/// metadata says about them: when the shutter went, where it was
/// geotagged, whether it was favorited, how many faces are in the frame
/// and roughly what the shot is of. Stores `PHAsset` local identifiers and
/// those derived summaries only — never copies image bytes into the
/// journal store (§4, §10). Works with limited-library access, since a
/// fetch simply returns whatever subset the user granted.
struct PhotosSignalProvider: DaySignalProvider {
    let kind: DaySignalKind = .photo

    func isAuthorized() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized || status == .limited
    }

    func requestAuthorization() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status == .authorized || status == .limited
    }

    func collectSignals(for day: DateInterval) async throws -> [DaySignal] {
        guard await isAuthorized() else { return [] }

        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "creationDate >= %@ AND creationDate < %@",
            day.start as NSDate,
            day.end as NSDate
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

        let assets = PHAsset.fetchAssets(with: options)
        var drafts: [(identifier: String, isScreenshot: Bool, location: CLLocation?, timestamp: Date, isFavorite: Bool)] = []
        assets.enumerateObjects { asset, _, _ in
            drafts.append((
                identifier: asset.localIdentifier,
                isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot),
                location: asset.location,
                timestamp: asset.creationDate ?? day.start,
                isFavorite: asset.isFavorite
            ))
        }

        // One reverse-geocode per day, on the first geotagged shot: a place
        // name is a derived summary (§10), and a single lookup stays well
        // inside CLGeocoder's rate limit even when the 30-day backfill runs
        // this for a month of days in a row.
        var placeName: String?
        if let location = drafts.first(where: { $0.location != nil })?.location,
           let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first {
            placeName = placemark.name ?? placemark.locality
        }

        // What's actually *in* the shot, read on-device by Vision: faces
        // counted (never identified — §4) and a label or two for the
        // scene. Only the day's first few camera photos are analyzed, so a
        // 30-day backfill stays affordable; screenshots are skipped since
        // there's nothing to describe.
        var summaries: [String: PhotoContentSummary] = [:]
        for draft in drafts.filter({ !$0.isScreenshot }).prefix(PhotoContentAnalyzer.maximumPhotosPerDay) {
            if let summary = await PhotoContentAnalyzer.summarize(assetIdentifier: draft.identifier) {
                summaries[draft.identifier] = summary
            }
        }

        return drafts.map { draft in
            let summary = summaries[draft.identifier]
            let payload = PhotoPayload(
                assetLocalIdentifier: draft.identifier,
                isScreenshot: draft.isScreenshot,
                placeName: draft.location != nil ? placeName : nil,
                latitude: draft.location?.coordinate.latitude,
                longitude: draft.location?.coordinate.longitude,
                faceCount: summary?.faceCount ?? 0,
                sceneLabels: summary?.sceneLabels ?? [],
                isFavorite: draft.isFavorite
            )
            let signal = DaySignal(kind: .photo, timestamp: draft.timestamp)
            signal.setPayload(payload)
            return signal
        }
    }
}
