import Foundation
import SwiftData

/// Owns the shared `ModelContainer`, backed by the app-group container so
/// the host app, the widget extension, and any future extension all read
/// and write the same on-disk store (§2), and by the user's own CloudKit
/// private database so it syncs across their devices (§11). Every model in
/// `Models/` was written with CloudKit's schema constraints in mind from
/// the start (optional/defaulted fields, no unique-constraint reliance) so
/// enabling this needed no model changes.
///
/// Version-sensitive per build spec §18: SwiftData's CloudKit integration
/// is the area most likely to have moved by the time this is built against
/// a real SDK — confirm current constraint/relationship support, and
/// whether a single on-disk store safely serves both a CloudKit-configured
/// process (the app) and a plain one (an extension without the iCloud
/// entitlement) before shipping. This implementation gives every target
/// the same `cloudKitDatabase` configuration to avoid that ambiguity.
enum PersistenceController {
    static let cloudKitContainerIdentifier = "iCloud.com.mystorydailyjournal.app"

    static let schema = Schema([
        DayRecord.self,
        DaySignal.self,
        Person.self,
        Tag.self,
    ])

    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let configuration = inMemory
            ? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            : ModelConfiguration(
                schema: schema,
                url: AppGroup.storeURL,
                cloudKitDatabase: .private(cloudKitContainerIdentifier)
            )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
}
