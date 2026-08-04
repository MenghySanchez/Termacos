import Foundation
import LocalAuthentication

/// Gates access to the server list behind macOS's native device-owner
/// authentication: Touch ID where available, automatically falling back to
/// the Mac's account password otherwise. There is no separate app password
/// to manage or leak — it defers entirely to the system.
@MainActor
final class AppLockManager: ObservableObject {
    @Published var isUnlocked: Bool
    @Published var lastError: String?
    @Published private(set) var isAuthenticating = false

    /// Starts unlocked unless "appLockEnabled" is on (default), so the
    /// launch-time gate respects the Settings toggle while the manual Lock
    /// button below always works regardless of that toggle.
    init() {
        let defaults = UserDefaults.standard
        let lockOnLaunch = defaults.object(forKey: "appLockEnabled") == nil
            ? true
            : defaults.bool(forKey: "appLockEnabled")
        isUnlocked = !lockOnLaunch
    }

    func authenticate() {
        guard !isAuthenticating else { return }
        lastError = nil
        isAuthenticating = true

        let context = LAContext()
        context.localizedCancelTitle = "Cancelar"
        var evalError: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &evalError) else {
            lastError = evalError?.localizedDescription ?? "Este Mac no admite autenticación local."
            isAuthenticating = false
            return
        }

        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Desbloqueá Termacos SSH para ver tus servidores y claves."
        ) { [weak self] success, error in
            Task { @MainActor in
                guard let self else { return }
                self.isAuthenticating = false
                if success {
                    self.isUnlocked = true
                } else if let laError = error as? LAError, laError.code != .userCancel {
                    self.lastError = laError.localizedDescription
                }
            }
        }
    }

    func lock() {
        isUnlocked = false
    }
}
