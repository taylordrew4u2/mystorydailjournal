import Foundation
import CloudKit

/// Watches `CKContainer.accountStatus()` so the app can degrade to a clear
/// local-only banner rather than failing silently when iCloud is signed
/// out or unreachable (§11: "detect accountStatus() and degrade to
/// local-only with a clear banner if signed out, rather than failing
/// silently").
@MainActor
final class CloudAccountStatus: ObservableObject {
    static let shared = CloudAccountStatus()

    @Published private(set) var status: CKAccountStatus = .couldNotDetermine

    var isAvailable: Bool { status == .available }

    func refresh() {
        Task {
            let container = CKContainer(identifier: PersistenceController.cloudKitContainerIdentifier)
            let current = (try? await container.accountStatus()) ?? .couldNotDetermine
            self.status = current
        }
    }
}
