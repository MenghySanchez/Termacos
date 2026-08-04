import SwiftUI

struct TermacosSSHApp: App {
    @StateObject private var store = ServerStore()
    @StateObject private var lockManager = AppLockManager()

    var body: some Scene {
        WindowGroup {
            Group {
                if lockManager.isUnlocked {
                    ContentView()
                        .environmentObject(store)
                        .environmentObject(lockManager)
                } else {
                    LockScreenView()
                        .environmentObject(lockManager)
                }
            }
            .frame(minWidth: 720, minHeight: 460)
            .tint(Theme.accent)
        }
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unified)

        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}
