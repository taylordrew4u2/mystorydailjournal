import Foundation
import SwiftData

/// A freeform, user-entered name tagged onto a day. Deliberately lightweight:
/// no matching against the system Contacts database happens automatically
/// (see build spec §12) — a user can only link a real contact by explicitly
/// picking one via `CNContactPickerViewController` in a later milestone.
@Model
final class Person {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date.distantPast
    var dayRecords: [DayRecord]? = []

    init(name: String, createdAt: Date = .now) {
        self.id = UUID()
        self.name = name
        self.createdAt = createdAt
    }
}
