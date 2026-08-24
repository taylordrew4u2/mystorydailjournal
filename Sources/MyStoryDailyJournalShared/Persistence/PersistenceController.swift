import Foundation
import SwiftData

/// Owns the shared `ModelContainer`, backed by the app-group container so
/// the host app, the widget extension, and any future extension all read
/// and write the same on-disk store (§2).
///
/// CloudKit sync (build spec §11) is a later milestone (M6): enabling it is
/// a one-line change to `cloudKitDatabase:` below once an iCloud container
/// identifier is provisioned, because every model in `Models/` was already
/// written with CloudKit's schema constraints in mind (optional/defaulted
/// fields, no unique-constraint reliance beyond what SwiftData enforces
/// locally).
enum PersistenceController {
    static let schema = Schema([
        DayRecord.self,
        DaySignal.self,
        Person.self,
        Tag.self,
    ])

    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let configuration = inMemory
            ? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            : ModelConfiguration(schema: schema, url: AppGroup.storeURL)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
}
