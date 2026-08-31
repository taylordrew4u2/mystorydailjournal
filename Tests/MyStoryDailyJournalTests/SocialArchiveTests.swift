import XCTest
import SwiftData
@testable import MyStoryDailyJournal

/// Fixtures here mirror the shapes Instagram actually ships in a JSON
/// export, mojibake and all — the parser's whole job is surviving them.
final class SocialArchiveTests: XCTestCase {
    private func makeContext() -> ModelContext {
        ModelContext(PersistenceController.makeContainer(inMemory: true))
    }

    private func json(_ text: String) -> Data {
        Data(text.utf8)
    }

    // MARK: - Which files get read

    func testItReadsContentFilesAndIgnoresTheRest() {
        XCTAssertEqual(InstagramArchive.form(forFileNamed: "posts_1.json"), "post")
        XCTAssertEqual(InstagramArchive.form(forFileNamed: "posts_12.json"), "post")
        XCTAssertEqual(InstagramArchive.form(forFileNamed: "stories.json"), "story")
        XCTAssertEqual(InstagramArchive.form(forFileNamed: "reels.json"), "reel")
        XCTAssertEqual(InstagramArchive.form(forFileNamed: "post_comments_1.json"), "comment")

        for ignored in InstagramArchive.ignoredFileNames {
            XCTAssertNil(
                InstagramArchive.form(forFileNamed: "\(ignored).json"),
                "\(ignored) is other people's data or advertising, not the writer's day."
            )
        }
        XCTAssertNil(InstagramArchive.form(forFileNamed: "posts_1.html"), "HTML exports can't be read.")
    }

    // MARK: - Post shapes

    func testAPostBecomesAnEntryWithItsCaptionAndTime() {
        let entries = InstagramArchive.entries(inJSON: json("""
        [{
          "media": [{"uri": "media/posts/202401/a.jpg", "creation_timestamp": 1704067200, "title": ""}],
          "creation_timestamp": 1704067200,
          "title": "Long walk, good coffee."
        }]
        """), form: "post")

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.text, "Long walk, good coffee.")
        XCTAssertEqual(entries.first?.mediaCount, 1)
        XCTAssertEqual(entries.first?.timestamp, Date(timeIntervalSince1970: 1704067200))
    }

    func testASinglePhotoPostKeepsItsCaptionFromTheMedia() {
        // Instagram puts a one-photo post's caption on the media, not the post.
        let entries = InstagramArchive.entries(inJSON: json("""
        [{
          "media": [{"uri": "media/posts/b.jpg", "creation_timestamp": 1704067200, "title": "On the caption's real home."}],
          "title": ""
        }]
        """), form: "post")

        XCTAssertEqual(entries.first?.text, "On the caption's real home.")
    }

    func testStoriesArriveWrappedInTheirOwnKey() {
        let entries = InstagramArchive.entries(inJSON: json("""
        {"ig_stories": [{"uri": "media/stories/c.jpg", "creation_timestamp": 1704153600, "title": "Late one."}]}
        """), form: "story")

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.form, "story")
    }

    func testAWrapperKeyThisAppHasNeverSeenStillParses() {
        // The point of taking whichever array is present: Meta renames these.
        let entries = InstagramArchive.entries(inJSON: json("""
        {"ig_some_future_name": [{"creation_timestamp": 1704153600, "title": "Still mine."}]}
        """), form: "post")

        XCTAssertEqual(entries.first?.text, "Still mine.")
    }

    func testACommentIsReadOutOfItsStringMap() {
        let entries = InstagramArchive.entries(inJSON: json("""
        {"comments": [{"string_map_data": {
          "Comment": {"value": "Congratulations!"},
          "Time": {"timestamp": 1704240000}
        }}]}
        """), form: "comment")

        XCTAssertEqual(entries.first?.text, "Congratulations!")
        XCTAssertEqual(entries.first?.timestamp, Date(timeIntervalSince1970: 1704240000))
    }

    func testExifLocationComesAcrossWhenTheArchiveHasIt() {
        let entries = InstagramArchive.entries(inJSON: json("""
        [{
          "creation_timestamp": 1704067200,
          "title": "Up top.",
          "media": [{"uri": "media/posts/d.jpg", "media_metadata": {"photo_metadata": {"exif_data": [
            {"latitude": 37.8199, "longitude": -122.4783}
          ]}}}]
        }]
        """), form: "post")

        XCTAssertEqual(entries.first?.latitude ?? 0, 37.8199, accuracy: 0.0001)
        XCTAssertEqual(entries.first?.longitude ?? 0, -122.4783, accuracy: 0.0001)
    }

    func testAZeroCoordinateIsNotALocation() {
        let entries = InstagramArchive.entries(inJSON: json("""
        [{
          "creation_timestamp": 1704067200,
          "title": "No location on this one.",
          "media": [{"uri": "e.jpg", "media_metadata": {"photo_metadata": {"exif_data": [
            {"latitude": 0, "longitude": 0}
          ]}}}]
        }]
        """), form: "post")

        XCTAssertNil(entries.first?.latitude, "0,0 is Instagram's empty, not the Gulf of Guinea.")
    }

    func testAnItemWithNoTimestampIsSkippedRatherThanDated() {
        let entries = InstagramArchive.entries(inJSON: json("""
        [{"title": "When was this?"}]
        """), form: "post")

        XCTAssertTrue(entries.isEmpty, "A post with no time can't be filed under a day.")
    }

    func testMalformedJSONYieldsNothingRatherThanThrowing() {
        XCTAssertTrue(InstagramArchive.entries(inJSON: json("{ not json"), form: "post").isEmpty)
    }

    // MARK: - Walking a real archive folder

    /// Builds a miniature export on disk: nested the way Instagram nests it,
    /// split across numbered files, with a file this importer must ignore.
    private func makeArchive() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ig-\(UUID().uuidString)")
        let content = root.appendingPathComponent("your_instagram_activity/content")
        let connections = root.appendingPathComponent("connections/followers_and_following")
        try FileManager.default.createDirectory(at: content, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: connections, withIntermediateDirectories: true)

        try json("""
        [{"creation_timestamp": 1704240000, "title": "Later."}]
        """).write(to: content.appendingPathComponent("posts_1.json"))
        try json("""
        [{"creation_timestamp": 1704067200, "title": "Earlier."}]
        """).write(to: content.appendingPathComponent("posts_2.json"))
        try json("""
        {"ig_stories": [{"creation_timestamp": 1704153600, "title": "Middle."}]}
        """).write(to: content.appendingPathComponent("stories.json"))
        try json("""
        [{"title": "someone_else", "string_list_data": []}]
        """).write(to: connections.appendingPathComponent("followers_1.json"))

        return root
    }

    func testItWalksTheWholeArchiveAndReturnsPostsOldestFirst() throws {
        let root = try makeArchive()
        defer { try? FileManager.default.removeItem(at: root) }

        let entries = InstagramArchive.entries(in: root)

        XCTAssertEqual(
            entries.map(\.text),
            ["Earlier.", "Middle.", "Later."],
            "Files are found wherever they sit, and the archive is ordered as a life is."
        )
    }

    func testWalkingTheArchiveSkipsFilesAboutOtherPeople() throws {
        let root = try makeArchive()
        defer { try? FileManager.default.removeItem(at: root) }

        let entries = InstagramArchive.entries(in: root)
        XCTAssertFalse(
            entries.contains { $0.text == "someone_else" },
            "followers_1.json is a list of other people, not the writer's day."
        )
    }

    func testAnEmptyFolderIsNotAnError() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ig-empty-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertTrue(InstagramArchive.entries(in: root).isEmpty)
    }

    func testAStoryCountsItsOwnMedia() {
        // stories.json writes one flat item with the uri on the item itself,
        // not a media array.
        let entries = InstagramArchive.entries(inJSON: json("""
        {"ig_stories": [{"uri": "media/stories/f.jpg", "creation_timestamp": 1704153600, "title": "One frame."}]}
        """), form: "story")

        XCTAssertEqual(entries.first?.mediaCount, 1, "A story is one piece of media, not none.")
    }

    func testTheSameArchiveParsedTwiceProducesTheSameIDs() {
        // Guards the identity against Swift's per-process string hash seed:
        // an ID that changed per launch would re-import the whole archive.
        let source = json("""
        [{"creation_timestamp": 1704240000, "title": "A caption with no media at all."}]
        """)

        let first = InstagramArchive.entries(inJSON: source, form: "post")
        let second = InstagramArchive.entries(inJSON: source, form: "post")

        XCTAssertEqual(first.first?.externalID, second.first?.externalID)
        XCTAssertFalse(first.first?.externalID.isEmpty ?? true)
    }

    func testTwoPostsAtTheSameSecondAreTwoPosts() {
        let entries = InstagramArchive.entries(inJSON: json("""
        [{"creation_timestamp": 1704240000, "title": "One thing."},
         {"creation_timestamp": 1704240000, "title": "A different thing."}]
        """), form: "post")

        XCTAssertEqual(entries.count, 2)
        XCTAssertNotEqual(
            entries.first?.externalID, entries.last?.externalID,
            "Posting twice in the same second must not collapse into one post."
        )
    }

    // MARK: - The encoding bug

    func testItRepairsInstagramsMangledUTF8() {
        // Instagram writes UTF-8 bytes as if they were Latin-1.
        XCTAssertEqual(InstagramArchive.repairingMojibake("cafÃ©"), "café")
        XCTAssertEqual(InstagramArchive.repairingMojibake("ð\u{9F}\u{98}\u{80}"), "😀")
    }

    func testTextThatWasNeverMangledIsLeftAlone() {
        XCTAssertEqual(InstagramArchive.repairingMojibake("café"), "café")
        XCTAssertEqual(InstagramArchive.repairingMojibake("plain"), "plain")
    }

    func testACaptionIsRepairedOnTheWayIn() {
        let entries = InstagramArchive.entries(inJSON: json("""
        [{"creation_timestamp": 1704067200, "title": "CafÃ© morning"}]
        """), form: "post")

        XCTAssertEqual(entries.first?.text, "Café morning")
    }

    // MARK: - Importing

    private func entry(_ id: String, at seconds: TimeInterval, text: String = "Something.") -> SocialArchiveEntry {
        SocialArchiveEntry(
            network: InstagramArchive.networkName,
            form: "post",
            text: text,
            timestamp: Date(timeIntervalSince1970: seconds),
            placeName: nil,
            latitude: nil,
            longitude: nil,
            mediaCount: 1,
            externalID: id
        )
    }

    func testImportingPutsEachPostOnItsOwnDay() {
        let context = makeContext()
        let summary = SocialArchiveImporter.ingest(
            [entry("a", at: 1704067200), entry("b", at: 1704240000)],
            in: context
        )

        XCTAssertEqual(summary.imported, 2)
        XCTAssertEqual(summary.daysCreated, 2)

        let record = DayRecordRepository.existingRecord(for: Date(timeIntervalSince1970: 1704067200), in: context)
        XCTAssertEqual(record?.signals?.first?.kind, .socialPost)
    }

    func testImportingTheSameArchiveTwiceAddsNothingTheSecondTime() {
        let context = makeContext()
        let entries = [entry("a", at: 1704067200), entry("b", at: 1704240000)]

        SocialArchiveImporter.ingest(entries, in: context)
        let second = SocialArchiveImporter.ingest(entries, in: context)

        XCTAssertEqual(second.imported, 0, "Re-importing an export must not duplicate it.")
        XCTAssertEqual(second.skipped, 2)
    }

    func testALaterExportOverlappingTheLastOnlyAddsWhatIsNew() {
        let context = makeContext()
        SocialArchiveImporter.ingest([entry("a", at: 1704067200)], in: context)

        let summary = SocialArchiveImporter.ingest(
            [entry("a", at: 1704067200), entry("b", at: 1704240000)],
            in: context
        )

        XCTAssertEqual(summary.imported, 1)
        XCTAssertEqual(summary.skipped, 1)
    }

    func testImportingNeverOverwritesADayTheWriterWrote() {
        let context = makeContext()
        let date = Date(timeIntervalSince1970: 1704067200)
        let record = DayRecordRepository.record(for: date, in: context)
        record.bodyText = "What I actually wrote."
        record.source = .userWritten

        SocialArchiveImporter.ingest([entry("a", at: 1704067200)], in: context)

        let after = DayRecordRepository.existingRecord(for: date, in: context)
        XCTAssertEqual(after?.bodyText, "What I actually wrote.")
        XCTAssertEqual(after?.signals?.count, 1, "The post is evidence on the day, not the day.")
    }

    func testForgettingRemovesThePostsAndLeavesTheEntries() {
        let context = makeContext()
        let date = Date(timeIntervalSince1970: 1704067200)
        SocialArchiveImporter.ingest([entry("a", at: 1704067200)], in: context)
        let record = DayRecordRepository.record(for: date, in: context)
        record.bodyText = "Written since."

        let removed = SocialArchiveImporter.forget(network: InstagramArchive.networkName, in: context)

        XCTAssertEqual(removed, 1)
        let after = DayRecordRepository.existingRecord(for: date, in: context)
        XCTAssertEqual(after?.bodyText, "Written since.")
        XCTAssertEqual(after?.signals?.count ?? 0, 0)
    }

    // MARK: - Reaching the entry

    func testAnImportedPostIsWrittenIntoTheDay() {
        let signal = DaySignal(kind: .socialPost, timestamp: Date(timeIntervalSince1970: 1704067200))
        signal.setPayload(SocialPostPayload(
            network: "Instagram",
            form: "post",
            text: "Long walk, good coffee.",
            mediaCount: 1,
            externalID: "a"
        ))

        let text = DigestComposer.compose(date: Date(timeIntervalSince1970: 1704067200), signals: [signal])
        XCTAssertTrue(text.contains("Long walk, good coffee."), "Got: \(text)")
    }

    func testACaptionlessPostStillSaysSomethingHappened() {
        let signal = DaySignal(kind: .socialPost, timestamp: Date(timeIntervalSince1970: 1704067200))
        signal.setPayload(SocialPostPayload(
            network: "Instagram",
            form: "post",
            text: "",
            mediaCount: 3,
            externalID: "a"
        ))

        let text = DigestComposer.compose(date: Date(timeIntervalSince1970: 1704067200), signals: [signal])
        XCTAssertTrue(text.contains("3 photos"), "Got: \(text)")
    }
}
