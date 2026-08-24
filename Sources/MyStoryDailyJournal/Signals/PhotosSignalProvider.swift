import Foundation
import Photos

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
        var signals: [DaySignal] = []
        assets.enumerateObjects { asset, _, _ in
            let payload = PhotoPayload(
                assetLocalIdentifier: asset.localIdentifier,
                isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot)
            )
            let signal = DaySignal(kind: .photo, timestamp: asset.creationDate ?? day.start)
            signal.setPayload(payload)
            signals.append(signal)
        }
        return signals
    }
}
