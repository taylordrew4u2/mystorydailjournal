import XCTest
@testable import MyStoryDailyJournal

final class PlaceNamingTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "PlaceNamingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    // MARK: - Spotting an address

    func testStreetAddressesAndUnknownPlacesAreWorthAskingAbout() {
        XCTAssertTrue(PlaceNameResolver.looksLikeAddress("480 Larkin Street"))
        XCTAssertTrue(PlaceNameResolver.looksLikeAddress("Unknown place"))
        XCTAssertFalse(PlaceNameResolver.looksLikeAddress("Golden Gate Park"))
        XCTAssertFalse(PlaceNameResolver.looksLikeAddress(""))
    }

    // MARK: - Reading a venue name out of an answer

    func testVenueNameTakesTheNameOutOfAConversationalAnswer() {
        XCTAssertEqual(PlaceNameResolver.venueName(fromAnswer: "Blue Bottle Coffee"), "Blue Bottle Coffee")
        XCTAssertEqual(PlaceNameResolver.venueName(fromAnswer: "That's Blue Bottle, we got breakfast"), "Blue Bottle")
        XCTAssertEqual(PlaceNameResolver.venueName(fromAnswer: "we were at Blue Bottle"), "Blue Bottle")
        XCTAssertEqual(PlaceNameResolver.venueName(fromAnswer: "the dentist"), "dentist")
    }

    func testVenueNameIgnoresShrugsAndStories() {
        XCTAssertNil(PlaceNameResolver.venueName(fromAnswer: "no idea"))
        XCTAssertNil(PlaceNameResolver.venueName(fromAnswer: "   "))
        XCTAssertNil(PlaceNameResolver.venueName(fromAnswer: "480"))
        XCTAssertNil(PlaceNameResolver.venueName(fromAnswer: "the place at 480 Larkin"), "That's the address again, not a name.")
        XCTAssertNil(PlaceNameResolver.venueName(
            fromAnswer: "a really long winding explanation that goes on for far more words than a name ever would"
        ))
    }

    // MARK: - Rewriting text

    func testRenameSwapsAddressesForNamesCaseInsensitively() {
        let text = "Spent time at 480 Larkin Street. Back at 480 larkin street later."
        let renamed = PlaceNameResolver.rename(text, replacements: ["480 Larkin Street": "Blue Bottle"])
        XCTAssertEqual(renamed, "Spent time at Blue Bottle. Back at Blue Bottle later.")
    }

    func testRenameLeavesTextAloneWithoutReplacements() {
        XCTAssertEqual(PlaceNameResolver.rename("Spent time at Blue Bottle.", replacements: [:]), "Spent time at Blue Bottle.")
    }

    // MARK: - Remembering the answer

    func testRecordedNameIsFoundAgainByNameAndByCoordinate() {
        let defaults = makeDefaults()
        PlaceAliasStore.record(
            name: "Blue Bottle",
            for: "480 Larkin Street",
            latitude: 37.7811,
            longitude: -122.4162,
            defaults: defaults
        )

        XCTAssertEqual(PlaceAliasStore.name(for: "480 larkin  street", defaults: defaults), "Blue Bottle")
        // A different geocode string at the same corner still resolves.
        XCTAssertEqual(
            PlaceAliasStore.name(for: "482 Larkin St", latitude: 37.78112, longitude: -122.41615, defaults: defaults),
            "Blue Bottle"
        )
        XCTAssertNil(PlaceAliasStore.name(for: "Somewhere else", defaults: defaults))
    }

    func testCoordinatesFarApartDoNotShareAName() {
        let defaults = makeDefaults()
        PlaceAliasStore.record(name: "Blue Bottle", for: "480 Larkin Street", latitude: 37.781, longitude: -122.416, defaults: defaults)
        XCTAssertNil(PlaceAliasStore.name(for: "12 Other Road", latitude: 40.7, longitude: -74.0, defaults: defaults))
    }

    // MARK: - Composing with confirmed names

    func testDigestWritesTheConfirmedNameInsteadOfTheAddress() {
        let visit = DaySignal(kind: .visit, timestamp: Date())
        visit.setPayload(VisitPayload(placeName: "480 Larkin Street", latitude: 37.781, longitude: -122.416, isFullAccuracy: true))

        let aliases = [PlaceAliasStore.nameKey("480 Larkin Street"): "Blue Bottle"]
        let text = DigestComposer.compose(date: Date(), signals: [visit], placeAliases: aliases)

        XCTAssertTrue(text.contains("The day had time at Blue Bottle."))
        XCTAssertFalse(text.contains("480 Larkin Street"))
    }
}
