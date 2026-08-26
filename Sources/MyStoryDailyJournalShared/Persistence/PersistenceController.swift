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
/// entitlement) before shipping.
enum PersistenceController {
    static let cloudKitContainerIdentifier = "iCloud.com.mystorydailyjournal.app"

    static let schema = Schema([
        DayRecord.self,
        DaySignal.self,
        Person.self,
        Tag.self,
    ])

    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        if inMemory {
            return createContainer(
                configuration: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            )
        }

        let storeURL = AppGroup.storeURL
        let cloudConfiguration = ModelConfiguration(
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .private(cloudKitContainerIdentifier)
        )

        do {
            return try ModelContainer(for: schema, configurations: [cloudConfiguration])
        } catch {
            print("Failed to create CloudKit-backed ModelContainer, falling back to local store: \(error)")
            return createPersistentLocalContainer(storeURL: storeURL)
        }
    }

    private static func createPersistentLocalContainer(storeURL: URL) -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            print("Failed to create local ModelContainer, moving aside store and retrying: \(error)")
            moveAsideStoreFiles(at: storeURL)
            return createContainer(
                configuration: ModelConfiguration(schema: schema, url: storeURL)
            )
        }
    }

    private static func createContainer(configuration: ModelConfiguration) -> ModelContainer {
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    private static func moveAsideStoreFiles(at storeURL: URL) {
        let fileManager = FileManager.default
        let suffix = ".failed-\(Int(Date().timeIntervalSince1970))"
        let paths = [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-shm"),
            URL(fileURLWithPath: storeURL.path + "-wal"),
        ]

        for url in paths where fileManager.fileExists(atPath: url.path) {
            let destinationURL = URL(fileURLWithPath: url.path + suffix)
            try? fileManager.moveItem(at: url, to: destinationURL)
        }
    }
}
