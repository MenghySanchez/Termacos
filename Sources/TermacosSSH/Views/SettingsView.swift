import SwiftUI

struct SettingsView: View {
    @AppStorage("appLockEnabled") private var appLockEnabled = true

    var body: some View {
        Form {
            Section {
                Toggle("Requerir Touch ID o contraseña para abrir la app", isOn: $appLockEnabled)
                Text("Usa Touch ID si tu Mac lo tiene; si no, te pide la contraseña de tu cuenta de macOS. Sin esto, cualquiera con acceso a tu sesión desbloqueada puede ver tus servidores, claves y conectarse por SSH.\n\nNota: macOS no admite llaves de seguridad físicas (FIDO2/YubiKey) para desbloquear apps locales — eso solo aplica a inicios de sesión web.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Seguridad")
            }

            ExportImportSection()
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .padding(.vertical, Theme.Spacing.sm)
    }
}
