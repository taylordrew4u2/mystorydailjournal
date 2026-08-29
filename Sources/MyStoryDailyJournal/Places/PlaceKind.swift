import Foundation

/// What a place *was*, in the writer's own terms — the options offered
/// with every place question so a location can be defined with one tap
/// instead of typed out.
///
/// A kind is what the diary says when Maps has no venue to offer, or when
/// the writer would rather not name it: "spent time at home" reads better
/// than any address, and "a friend's place" is exactly as specific as most
/// people want their journal to be about someone else's address.
enum PlaceKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case home
    case work
    case friendsPlace
    case familysPlace
    case restaurant
    case bar
    case cafe
    case comedyClub
    case venue
    case gym
    case store
    case outdoors
    case appointment
    case travel
    /// Not a destination at all — the phone noticed a stop the writer never
    /// really made. See `PlaceChoice.passingThrough`.
    case walkingPast

    var id: String { rawValue }

    /// The chip label.
    var displayName: String {
        switch self {
        case .home: "Home"
        case .work: "Work"
        case .friendsPlace: "A friend's place"
        case .familysPlace: "Family's place"
        case .restaurant: "Restaurant"
        case .bar: "Bar"
        case .cafe: "Café"
        case .comedyClub: "Comedy club"
        case .venue: "Venue / show"
        case .gym: "Gym"
        case .store: "Store / errand"
        case .outdoors: "Outdoors"
        case .appointment: "Appointment"
        case .travel: "Travelling"
        case .walkingPast: "Just walking past"
        }
    }

    /// How the entry names the place. Lower-case and article-carrying, so
    /// it drops into the composer's existing sentences ("Spent time at the
    /// comedy club.") without reading like a label.
    var entryPhrase: String {
        switch self {
        case .home: "home"
        case .work: "work"
        case .friendsPlace: "a friend's place"
        case .familysPlace: "family's place"
        case .restaurant: "the restaurant"
        case .bar: "the bar"
        case .cafe: "the café"
        case .comedyClub: "the comedy club"
        case .venue: "the venue"
        case .gym: "the gym"
        case .store: "the store"
        case .outdoors: "outside"
        case .appointment: "an appointment"
        case .travel: "travelling"
        // Never written as a place — a passing stop leaves the entry
        // entirely rather than being named.
        case .walkingPast: ""
        }
    }

    /// The kinds offered as chips under a place question, in the order they
    /// appear. "Just walking past" is deliberately last: it's the way out
    /// for a stop that wasn't a visit, not a description of one.
    static var options: [PlaceKind] {
        allCases
    }

    /// Whether an answer of this kind means "there's nothing here worth
    /// keeping."
    var isPassingThrough: Bool { self == .walkingPast }
}
