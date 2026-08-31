import Foundation

enum SSHExitCode {
    static func description(for code: Int32) -> String? {
        let normalizedCode = normalized(code)
        guard normalizedCode != 0 else { return nil }
        switch normalizedCode {
        case 1:
            return "La sesión terminó por un error general del servidor remoto. Revisa el comando o shell de inicio configurado para el usuario."
        case 2:
            return "SSH recibió una opción inválida o incompleta. Revisa la configuración de esta conexión."
        case 126:
            return "El servidor permitió la conexión, pero negó ejecutar el shell o comando inicial. Revisa permisos del usuario remoto."
        case 127:
            return "El servidor permitió la conexión, pero no encontró el shell o comando inicial del usuario."
        case 130:
            return "Sesión terminada por el usuario."
        case 143:
            return "Sesión cerrada desde la aplicación."
        case 255:
            return "No se pudo establecer la conexión SSH. Revisa contraseña, llave privada, usuario, host, puerto, VPN/firewall o si el servidor rechazó el acceso."
        default:
            if (64...78).contains(normalizedCode) {
                return disconnectReason(for: normalizedCode)
            }
            if normalizedCode > 128 {
                return "La sesión fue interrumpida por el sistema o por el servidor remoto. Revisa si hubo cierre forzado, reinicio, timeout o pérdida de red."
            }
            return "La sesión terminó de forma inesperada. Revisa la salida de la terminal para ver el detalle del servidor."
        }
    }

    private static func normalized(_ code: Int32) -> Int32 {
        if code > 255 && code % 256 == 0 {
            return code / 256
        }
        return code
    }

    private static func disconnectReason(for code: Int32) -> String {
        switch code {
        case 64: return "El servidor no soporta la versión de protocolo SSH usada por la app."
        case 65: return "No se pudo establecer conexión con el host. Revisa dirección, puerto, red o VPN."
        case 66: return "Hay un problema con la clave de identidad del servidor."
        case 67: return "No se pudo verificar la identidad del servidor. Revisa known_hosts o la clave del host."
        case 68: return "El servidor rechazó la conexión. Revisa firewall, puerto SSH o permisos de acceso."
        case 69: return "Autenticación rechazada. Revisa usuario, contraseña y llave privada."
        case 70: return "El servidor rechazó la conexión por un error de protocolo SSH."
        case 71: return "El servidor se desconectó por incompatibilidad de versión."
        case 72: return "Falló el intercambio de claves de cifrado con el servidor."
        case 73: return "No se pudo abrir el canal SSH hacia el servidor."
        case 74: return "La sesión fue cerrada por otra aplicación o por el administrador del servidor."
        case 75: return "El servidor cerró la conexión. Puede ser reinicio, política de seguridad o pérdida de red."
        case 76: return "El servidor cerró la sesión por inactividad."
        case 77: return "El servidor cerró la conexión porque recibió un paquete demasiado grande."
        case 78: return "El servidor cerró la conexión por un error de cifrado."
        default:
            return "La conexión SSH fue cerrada por el servidor."
        }
    }
}
