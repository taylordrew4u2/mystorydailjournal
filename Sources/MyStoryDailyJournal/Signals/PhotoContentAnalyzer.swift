import Foundation
import Photos
import UIKit
#if canImport(Vision)
import Vision
#endif

/// What the phone can tell about a photo without anyone describing it:
/// how many faces are in the frame and what the shot is roughly of.
struct PhotoContentSummary: Sendable, Equatable {
    var faceCount: Int = 0
    var sceneLabels: [String] = []
    var isEmpty: Bool { faceCount == 0 && sceneLabels.isEmpty }
}

/// Reads a day's photos with Vision, entirely on-device, and keeps only
/// the summary (§10: derived summaries, never content — no pixels are
/// copied into the journal store, and nothing is uploaded anywhere).
///
/// Faces are **counted, never identified**: the count is enough to
/// describe who was in frame ("two people in the shot") and to ask the
/// writer who they were, which is the only way a name is ever attached to
/// a day (§4).
///
/// **Version-sensitive** (§18): `VNClassifyImageRequest`'s label
/// vocabulary and confidence scale shift between releases, and iOS 18
/// introduced a newer async Vision API that eventually supersedes these
/// request classes — worth revisiting the confidence threshold and the
/// API surface against the SDK this ships on. Any failure here is
/// silent: a photo simply contributes no summary.
enum PhotoContentAnalyzer {
    /// A day's worth of analysis has to stay cheap enough to run during a
    /// 30-day backfill, so only this many photos per day are examined.
    static let maximumPhotosPerDay = 12

    /// Vision reports every label it knows; only reasonably confident ones
    /// are worth putting in someone's diary.
    private static let minimumSceneConfidence: Float = 0.6

    /// Labels that are true of almost any photo and say nothing about the
    /// day.
    private static let uselessSceneLabels: Set<String> = [
        "adult", "people", "person", "material", "structure", "object",
        "indoor", "outdoor", "day", "night", "color", "texture",
    ]

    static func summarize(assetIdentifier: String) async -> PhotoContentSummary? {
        #if canImport(Vision)
        guard let data = await imageData(forAssetIdentifier: assetIdentifier) else { return nil }
        // Vision is heavy enough that it must not run on whichever actor
        // asked for the digest — the entry view calls this path directly.
        let summary = await Task.detached(priority: .utility) { analyze(imageData: data) }.value
        return summary.isEmpty ? nil : summary
        #else
        return nil
        #endif
    }

    #if canImport(Vision)
    private static func analyze(imageData: Data) -> PhotoContentSummary {
        var summary = PhotoContentSummary()

        let faceRequest = VNDetectFaceRectanglesRequest()
        let sceneRequest = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(data: imageData, options: [:])
        try? handler.perform([faceRequest, sceneRequest])

        summary.faceCount = faceRequest.results?.count ?? 0
        summary.sceneLabels = (sceneRequest.results ?? [])
            .filter { $0.confidence >= minimumSceneConfidence }
            .sorted { $0.confidence > $1.confidence }
            .map { humanized($0.identifier) }
            .filter { !uselessSceneLabels.contains($0) }
            .reduce(into: [String]()) { unique, label in
                if !unique.contains(label) { unique.append(label) }
            }
            .prefix(2)
            .map { $0 }

        return summary
    }
    #endif

    /// Vision's identifiers are underscored and occasionally hierarchical
    /// ("fast_food"); a diary wants "fast food".
    static func humanized(_ identifier: String) -> String {
        identifier
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    #if canImport(Vision)
    /// A small, fast render of the asset — never the original file, and
    /// never written anywhere: it lives just long enough for Vision to
    /// look at it.
    private static func imageData(forAssetIdentifier identifier: String) async -> Data? {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = assets.firstObject else { return nil }

        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false
        options.isSynchronous = false
        options.resizeMode = .fast
        // `.fastFormat` guarantees the handler runs exactly once, which
        // `.opportunistic` does not — a second call would resume an
        // already-resumed continuation and trap.
        options.deliveryMode = .fastFormat

        // A downscaled render rather than the original file: enough pixels
        // for Vision, a fraction of the memory during a 30-day backfill.
        // Re-encoding inside the handler also keeps only `Data` — which is
        // `Sendable` — crossing the continuation.
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 512, height: 512),
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: image?.jpegData(compressionQuality: 0.8))
            }
        }
    }
    #endif
}
