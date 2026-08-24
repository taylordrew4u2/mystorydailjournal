import SwiftUI

/// Shown only when iCloud is signed out or otherwise unreachable — the app
/// stays fully usable either way (§11: "offline-first ... sync is
/// additive, never blocking"), this is purely informational.
struct CloudStatusBanner: View {
    @EnvironmentObject private var cloudStatus: CloudAccountStatus

    var body: some View {
        if !cloudStatus.isAvailable, cloudStatus.status != .couldNotDetermine {
            HStack(spacing: 8) {
                Image(systemName: "icloud.slash")
                Text(message)
                    .font(.footnote)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08))
        }
    }

    private var message: String {
        switch cloudStatus.status {
        case .noAccount:
            "Not signed in to iCloud — everything still saves on this device."
        case .restricted:
            "iCloud is restricted on this device — everything still saves locally."
        default:
            "iCloud is unavailable right now — everything still saves on this device."
        }
    }
}
