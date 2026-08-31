import Foundation

/// One thing found in a social archive, before it becomes a `DaySignal`.
/// Pure data, so the readers can be tested without a store or a file picker.
struct SocialArchiveEntry: Equatable {
    var network: String
    var form: String
    var text: String
    var timestamp: Date
    var placeName: String?
    var latitude: Double?
    var longitude: Double?
    var mediaCount: Int
    var externalID: String
}

/// Reads an Instagram "Download your information" export off disk.
///
/// The user asks Instagram for their data (Settings → Accounts Center →
/// Your information and permissions → Download your information), picks
/// **JSON** rather than HTML, and unzips what arrives. This walks that
/// folder and pulls out the things the writer themselves made: posts,
/// stories, reels and their captions, plus the comments they left.
///
/// Nothing else is read. Followers, likes, ad interests and other people's
/// messages are all in that archive and none of them are the writer's own
/// account of their day — see `ignoredFileNames` for the ones worth naming
/// out loud.
///
/// **Written to survive Meta moving things.** Export layouts change with no
/// notice: paths get reorganised, wrapper keys get renamed, files get split
/// and numbered differently. So this matches on file *names* wherever they
/// sit in the tree, takes whichever array a wrapper object holds rather
/// than a fixed key, and reads each item leniently — an item missing a
/// field is skipped, never fatal. A layout change should cost the user
/// posts, not a crash.
enum InstagramArchive {
    static let networkName = "Instagram"

    /// File name → what the network calls that thing. Matched
    /// case-insensitively, and `_1`/`_2` suffixes are tolerated, because
    /// Instagram splits large accounts across numbered files.
    private static let contentFiles: [(stem: String, form: String)] = [
        ("posts", "post"),
        ("archived_posts", "post"),
        ("recently_deleted_content", "post"),
        ("stories", "story"),
        ("reels", "reel"),
        ("post_comments", "comment"),
        ("reels_comments", "comment"),
    ]

    /// Deliberately not read, and why. Listed rather than merely omitted so
    /// the choice is reviewable: the first three are about other people or
    /// about advertising, and the last is other people's words as much as
    /// the writer's.
    static let ignoredFileNames = [
        "followers", "following", "liked_posts", "ads_interests", "messages",
    ]

    /// Every post, story, reel and comment in the archive, oldest first.
    static func entries(in directory: URL, fileManager: FileManager = .default) -> [SocialArchiveEntry] {
        var found: [SocialArchiveEntry] = []
        for url in jsonFiles(in: directory, fileManager: fileManager) {
            guard let form = form(forFileNamed: url.lastPathComponent) else { continue }
            guard let data = try? Data(contentsOf: url) else { continue }
            found.append(contentsOf: entries(inJSON: data, form: form))
        }
        found.sort { $0.timestamp < $1.timestamp }
        return found
    }

    /// Split out so the parsing can be tested against a literal export
    /// fragment, with no file system involved.
    static func entries(inJSON data: Data, form: String) -> [SocialArchiveEntry] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var results: [SocialArchiveEntry] = []
        for item in itemArray(from: root) {
            if let entry = entry(from: item, form: form) {
                results.append(entry)
            }
        }
        return results
    }

    // MARK: - Finding the files

    private static func jsonFiles(in directory: URL, fileManager: FileManager) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var urls: [URL] = []
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "json" {
            urls.append(url)
        }
        return urls.sorted { $0.path < $1.path }
    }

    /// "posts_1.json" -> "post". Nil for anything this importer doesn't read.
    static func form(forFileNamed name: String) -> String? {
        var stem = name.lowercased()
        guard stem.hasSuffix(".json") else { return nil }
        stem.removeLast(5)

        // Instagram numbers split files: posts_1, posts_2, ...
        while let last = stem.last, last.isNumber {
            stem.removeLast()
        }
        if stem.hasSuffix("_") { stem.removeLast() }

        return contentFiles.first { $0.stem == stem }?.form
    }

    // MARK: - Finding the items inside a file

    /// A content file is either a bare array of items, or one object
    /// wrapping a single array under a key that has been renamed more than
    /// once ("ig_stories", "ig_reels_media", "comments"). Taking whichever
    /// array is in there beats guessing the key of the week.
    private static func itemArray(from root: Any) -> [[String: Any]] {
        if let array = root as? [Any] {
            return array.compactMap { $0 as? [String: Any] }
        }
        guard let object = root as? [String: Any] else { return [] }
        for value in object.values {
            if let array = value as? [Any] {
                let items = array.compactMap { $0 as? [String: Any] }
                if !items.isEmpty { return items }
            }
        }
        return []
    }

    // MARK: - Reading one item

    private static func entry(from item: [String: Any], form: String) -> SocialArchiveEntry? {
        // A post carries its photos in a `media` array. A story or a reel is
        // one piece of media written flat, with the uri on the item itself —
        // so treat such an item as its own single media rather than reading
        // it as having none.
        var media = (item["media"] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
        if media.isEmpty, item["uri"] != nil {
            media = [item]
        }

        // A post's caption sits on the post for multi-photo posts and on the
        // single media item for one-photo posts; a comment keeps its text in
        // the string_map_data shape instead.
        let text = firstNonEmpty([
            string(item["title"]),
            media.compactMap { string($0["title"]) }.first,
            mappedValue(item, key: "Comment"),
        ])

        // Likewise the timestamp: on the post, else on its first media, else
        // in the comment's map.
        let seconds = firstTimestamp([
            item["creation_timestamp"], item["taken_at"], item["timestamp"],
            media.first?["creation_timestamp"],
            mappedTimestamp(item, key: "Time"),
        ])
        guard let seconds else { return nil }

        // A post with neither words nor pictures is not a day worth recording.
        guard !text.isEmpty || !media.isEmpty else { return nil }

        let coordinate = exifCoordinate(in: media)
        let uri = media.compactMap { string($0["uri"]) }.first

        return SocialArchiveEntry(
            network: networkName,
            form: form,
            text: text,
            timestamp: Date(timeIntervalSince1970: seconds),
            placeName: nil,
            latitude: coordinate?.latitude,
            longitude: coordinate?.longitude,
            mediaCount: media.count,
            // The media path is unique per post and stable across exports;
            // a caption-only comment has no path, so its own time and words
            // identify it. Deliberately not a hashValue: Swift seeds string
            // hashing per process, so an ID built from one would differ on
            // every launch and re-importing would duplicate everything.
            externalID: "\(networkName)/\(form)/\(uri ?? "\(Int(seconds))-\(text.prefix(64))")"
        )
    }

    private static func exifCoordinate(in media: [[String: Any]]) -> (latitude: Double, longitude: Double)? {
        for item in media {
            guard let metadata = item["media_metadata"] as? [String: Any] else { continue }
            for value in metadata.values {
                guard let photo = value as? [String: Any],
                      let exif = photo["exif_data"] as? [Any] else { continue }
                for case let field as [String: Any] in exif {
                    guard let latitude = double(field["latitude"]),
                          let longitude = double(field["longitude"]),
                          latitude != 0 || longitude != 0 else { continue }
                    return (latitude, longitude)
                }
            }
        }
        return nil
    }

    // MARK: - The string_map_data shape

    /// Comments (and several other exports) store their fields as
    /// `{"string_map_data": {"Comment": {"value": "..."}}}`.
    private static func mappedValue(_ item: [String: Any], key: String) -> String? {
        guard let map = item["string_map_data"] as? [String: Any],
              let field = map[key] as? [String: Any] else { return nil }
        return string(field["value"])
    }

    private static func mappedTimestamp(_ item: [String: Any], key: String) -> Any? {
        guard let map = item["string_map_data"] as? [String: Any],
              let field = map[key] as? [String: Any] else { return nil }
        return field["timestamp"]
    }

    // MARK: - Small readers

    private static func firstNonEmpty(_ candidates: [String?]) -> String {
        for candidate in candidates {
            if let candidate, !candidate.isEmpty { return candidate }
        }
        return ""
    }

    private static func firstTimestamp(_ candidates: [Any?]) -> TimeInterval? {
        for candidate in candidates {
            if let seconds = double(candidate), seconds > 0 { return seconds }
        }
        return nil
    }

    private static func double(_ value: Any?) -> Double? {
        if let number = value as? Double { return number }
        if let number = value as? Int { return Double(number) }
        if let text = value as? String { return Double(text) }
        return nil
    }

    private static func string(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let repaired = repairingMojibake(text).trimmingCharacters(in: .whitespacesAndNewlines)
        return repaired.isEmpty ? nil : repaired
    }

    /// Instagram writes UTF-8 bytes into its JSON as if they were Latin-1,
    /// so "café" arrives as "cafÃ©" and every emoji arrives as mojibake.
    /// Reading the scalars back as raw bytes and decoding those as UTF-8
    /// undoes it.
    ///
    /// Only attempted when every scalar fits in a byte, which is exactly
    /// the damaged case — and only kept if the result decodes, so text that
    /// was never damaged is returned untouched.
    static func repairingMojibake(_ text: String) -> String {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(text.unicodeScalars.count)
        for scalar in text.unicodeScalars {
            guard scalar.value < 256 else { return text }
            bytes.append(UInt8(scalar.value))
        }
        guard let repaired = String(bytes: bytes, encoding: .utf8) else { return text }
        return repaired
    }
}
