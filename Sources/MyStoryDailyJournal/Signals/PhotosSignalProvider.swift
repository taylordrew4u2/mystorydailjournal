import Foundation
import Photos
import CoreLocation

/// Photos and screenshots taken that day. Stores `PHAsset` local
/// identifiers only — never copies image bytes into the journal store (§4,
/// §10). Works with limited-library access, since a fetch simply returns
/// whatever subset the user granted.
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
        var drafts: [(identifier: String, isScreenshot: Bool, location: CLLocation?, timestamp: Date)] = []
        assets.enumerateObjects { asset, _, _ in
            drafts.append((
                identifier: asset.localIdentifier,
                isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot),
                location: asset.location,
                timestamp: asset.creationDate ?? day.start
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

        return drafts.map { draft in
            let payload = PhotoPayload(
                assetLocalIdentifier: draft.identifier,
                isScreenshot: draft.isScreenshot,
                placeName: draft.location != nil ? placeName : nil,
                latitude: draft.location?.coordinate.latitude,
                longitude: draft.location?.coordinate.longitude
            )
            let signal = DaySignal(kind: .photo, timestamp: draft.timestamp)
            signal.setPayload(payload)
            return signal
        }
    }
}
