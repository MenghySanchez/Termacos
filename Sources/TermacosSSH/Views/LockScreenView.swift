import SwiftUI

struct LockScreenView: View {
    @EnvironmentObject private var lockManager: AppLockManager

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.15))
                    .frame(width: 72, height: 72)
                Image(systemName: "lock.fill")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }

            VStack(spacing: 6) {
                Text("Termacos SSH está bloqueado")
                    .font(.title2.bold())
                Text("Tus servidores, claves y contraseñas guardadas quedan ocultos hasta que te autentiques.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }

            Button {
                lockManager.authenticate()
            } label: {
                Label(
                    lockManager.isAuthenticating ? "Autenticando…" : "Desbloquear",
                    systemImage: "touchid"
                )
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, 2)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(lockManager.isAuthenticating)

            if let error = lockManager.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .onAppear { lockManager.authenticate() }
    }
}
