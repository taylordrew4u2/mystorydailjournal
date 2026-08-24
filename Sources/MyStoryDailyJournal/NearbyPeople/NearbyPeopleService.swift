import Foundation
import MultipeerConnectivity

/// The optional, deferred bonus from §3/§13 M10: two installs of this app
/// trading a local Bluetooth/Wi-Fi handshake to auto-suggest each other.
/// Off by default and does nothing until explicitly turned on (§12). Never
/// connects a session — discovery alone (the browser side's
/// `foundPeer(_:withDiscoveryInfo:)`, which fires with no session
/// established) is enough to surface a name suggestion, so this never asks
/// for anything beyond the Local Network prompt Bonjour discovery itself
/// requires.
///
/// **Version-sensitive** (§18): both `NSLocalNetworkUsageDescription`'s
/// current App Review expectations and whether `MCNearbyServiceBrowser`
/// discovery still runs without triggering the Local Network prompt any
/// differently than in past releases need confirming against the current
/// SDK — this entire feature must stay privacy-inert (discovery only, no
/// session, no data sent) regardless of how the OS-level prompts evolve.
@MainActor
final class NearbyPeopleService: NSObject, ObservableObject {
    static let shared = NearbyPeopleService()

    @Published private(set) var nearbySuggestions: [String] = []

    /// Bonjour service type — lowercase letters/digits/hyphens, <= 15 chars.
    private static let serviceType = "mystory-nb"

    private var peerID: MCPeerID?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    func start(displayName: String) {
        stop()
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let peerID = MCPeerID(displayName: UUID().uuidString)
        self.peerID = peerID

        let advertiser = MCNearbyServiceAdvertiser(
            peer: peerID,
            discoveryInfo: ["name": trimmed],
            serviceType: Self.serviceType
        )
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser

        let browser = MCNearbyServiceBrowser(peer: peerID, serviceType: Self.serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        advertiser = nil
        browser = nil
        peerID = nil
        nearbySuggestions = []
    }

    func dismissSuggestion(_ name: String) {
        nearbySuggestions.removeAll { $0 == name }
    }
}

extension NearbyPeopleService: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        // Discovery alone is the whole feature — never accept a session.
        invitationHandler(false, nil)
    }
}

extension NearbyPeopleService: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(
        _ browser: MCNearbyServiceBrowser,
        foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        guard let name = info?["name"], !name.isEmpty else { return }
        Task { @MainActor in
            guard !self.nearbySuggestions.contains(name) else { return }
            self.nearbySuggestions.append(name)
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        // Suggestions already surfaced this session stay put rather than
        // disappearing the instant someone steps out of range — simplicity
        // over perfect accuracy for what's explicitly a bonus feature.
    }
}
