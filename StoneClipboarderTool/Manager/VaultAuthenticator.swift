//
//  VaultAuthenticator.swift
//  StoneClipboarderTool
//
//  The Touch ID / password check in front of the Passwords vault.
//

import Foundation
import LocalAuthentication

@MainActor
protocol VaultAuthenticator: AnyObject {
    /// Asks the owner to confirm; false when cancelled or failed.
    func authenticate(reason: String) async -> Bool
}

/// Touch ID, falling back to the login password (Macs without a sensor, a
/// closed lid, too many failed touches).
@MainActor
final class LocalAuthenticationAuthenticator: VaultAuthenticator {
    func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "Use Password"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            ErrorLogger.shared.log("Owner authentication unavailable", category: "Vault", error: error)
            return false
        }
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
                if let error, (error as? LAError)?.code != .userCancel {
                    ErrorLogger.shared.debug(
                        "Vault authentication failed: \(error.localizedDescription)", category: "Vault")
                }
                continuation.resume(returning: success)
            }
        }
    }
}
