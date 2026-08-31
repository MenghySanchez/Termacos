import Foundation

enum SSHExitCode {
    static func description(for code: Int32) -> String? {
        guard code != 0 else { return nil }
        switch code {
        case 1:
            return "Error general en el shell remoto"
        case 2:
            return "Error de uso del cliente SSH"
        case 126:
            return "Permiso denegado — el shell remoto no es ejecutable"
        case 127:
            return "Shell remoto no encontrado"
        case 130:
            return "Sesión terminada por el usuario (Ctrl+C)"
        case 255:
            return "Fallo de conexión — verifica credenciales, host y red"
        default:
            if code >= 1 && code <= 2 {
                return "Error del cliente SSH (código \(code))"
            }
            if (64...78).contains(code) {
                return disconnectReason(for: code)
            }
            return "Sesión terminada con código \(code)"
        }
    }

    private static func disconnectReason(for code: Int32) -> String {
        switch code {
        case 64: return "El servidor no soporta la versión de protocolo SSH"
        case 65: return "Fallo al establecer conexión con el host"
        case 66: return "Problema con la clave del host"
        case 67: return "No se pudo verificar la identidad del servidor"
        case 68: return "La conexión fue rechazada por el servidor"
        case 69: return "Fallo en la autenticación — revisa usuario y contraseña"
        case 70: return "El servidor rechazó la conexión por error de protocolo"
        case 71: return "El servidor se desconectó — versión incompatible"
        case 72: return "Fallo al derivar la clave de cifrado"
        case 73: return "No se pudo abrir la conexión a la puerta del servidor"
        case 74: return "El servidor fue desconectado por otro usuario"
        case 75: return "La conexión fue cerrada por el servidor"
        case 76: return "El servidor fue desconectado por inactividad"
        case 77: return "El servidor fue desconectado — paquete demasiado grande"
        case 78: return "El servidor fue desconectado — error de cifrado"
        default:
            return "Desconexión SSH (código \(code))"
        }
    }
}
