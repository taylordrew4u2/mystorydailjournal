import Foundation

/// Optional app-lock method, off by default (build spec §12). A user can
/// enable either or both; `biometric` falls back to the device passcode
/// automatically via `LAPolicy.deviceOwnerAuthenticationWithBiometrics`.
enum AppLockMethod: String, CaseIterable, Identifiable, Codable {
    case biometric
    case customCode
    case both

    var id: String { rawValue }

    var usesBiometric: Bool { self == .biometric || self == .both }
    var usesCustomCode: Bool { self == .customCode || self == .both }
}
