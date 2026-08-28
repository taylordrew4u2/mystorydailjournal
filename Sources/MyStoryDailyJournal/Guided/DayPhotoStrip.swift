import SwiftUI
import Photos

/// The day's actual photos, shown with the question that's asking about
/// them. Answering "what was happening here?" is a different question when
/// you're looking at the shot.
///
/// Loads thumbnails straight from the photo library by local identifier —
/// nothing is copied into the app's own storage (§10). A photo that can't
/// be loaded (revoked access, an asset since deleted, a limited-library
/// selection that excludes it) simply doesn't appear.
struct DayPhotoStrip: View {
    let assetIdentifiers: [String]
    var height: CGFloat = 108

    @State private var thumbnails: [String: Data] = [:]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(assetIdentifiers, id: \.self) { identifier in
                    thumbnail(for: identifier)
                }
            }
        }
        .frame(height: height)
        .task(id: assetIdentifiers) {
            await loadThumbnails()
        }
    }

    @ViewBuilder
    private func thumbnail(for identifier: String) -> some View {
        if let data = thumbnails[identifier], let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: height, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.12))
                .frame(width: height, height: height)
        }
    }

    private func loadThumbnails() async {
        for identifier in assetIdentifiers where thumbnails[identifier] == nil {
            if let data = await DayPhotoThumbnailLoader.thumbnailData(for: identifier) {
                thumbnails[identifier] = data
            }
        }
    }
}

/// The day's camera roll, straight from the photo library rather than from
/// what a digest happened to record — so a guided question can show the
/// photos from the day being written about even when the day has no photo
/// signals on it (Photos left off at the time, an entry started from
/// scratch, a day generated before the library was granted).
enum DayPhotoLibrary {
    static func assetIdentifiers(for date: Date, timeZoneIdentifier: String, limit: Int = 6) async -> [String] {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return [] }

        let day = DateUtilities.dayInterval(containing: date, timeZoneIdentifier: timeZoneIdentifier)
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "creationDate >= %@ AND creationDate < %@",
            day.start as NSDate,
            day.end as NSDate
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

        // Screenshots are filtered here rather than in the predicate —
        // a bitmask over `mediaSubtypes` isn't reliably supported by the
        // Photos query language, and a day rarely holds enough assets for
        // the difference to matter.
        var identifiers: [String] = []
        PHAsset.fetchAssets(with: options).enumerateObjects { asset, _, stop in
            guard !asset.mediaSubtypes.contains(.photoScreenshot) else { return }
            identifiers.append(asset.localIdentifier)
            if identifiers.count >= limit { stop.pointee = true }
        }
        return identifiers
    }
}

/// Small, throwaway renders of library assets for display only.
enum DayPhotoThumbnailLoader {
    static func thumbnailData(
        for assetIdentifier: String,
        targetSize: CGSize = CGSize(width: 320, height: 320)
    ) async -> Data? {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
        guard let asset = assets.firstObject else { return nil }

        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false
        options.isSynchronous = false
        options.resizeMode = .fast
        // `.fastFormat` calls the handler exactly once — `.opportunistic`
        // would call it again with a better image and trap on the
        // already-resumed continuation.
        options.deliveryMode = .fastFormat

        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image?.jpegData(compressionQuality: 0.8))
            }
        }
    }
}
