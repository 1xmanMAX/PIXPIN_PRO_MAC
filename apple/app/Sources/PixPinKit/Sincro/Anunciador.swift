// Anunciar este Mac en la Wi-Fi como un aparato de PinDesk, igual que Windows
// (`anunciarse` + `mdns::anunciar`) y Android (`NsdManager`): la instancia
// `PinDesk <nombre>` del tipo `_pindesk._tcp` con el TXT `g`/`id`/`l`/`n`, en
// el puerto donde escucha el nucleo de Rust. Y lo mismo con el tipo de antes
// (`_pixpin._tcp`, `tipoDeAntes`), para que lo vean los aparatos sin
// actualizar; si ese falla, se sigue con el nuevo solo (docs/formato-pindesk.md).
//
// Por que `DNSServiceRegister` (la API C de `dns_sd.h`) y no otra cosa:
//
// - `NWListener.service` solo anuncia el puerto de ese mismo `NWListener`,
//   y el socket que escucha es el de Rust (`Nucleo.escuchar`): con
//   `NWListener` habria que mover el protocolo entero a Swift.
// - `NetService` hace lo mismo pero esta obsoleto desde macOS 12.
// - `DNSServiceRegister` anuncia cualquier puerto, no esta obsoleto, es lo
//   que hay debajo de los otros dos (mDNSResponder) y es una llamada.
//
// Se registra con una funcion de respuesta y la cola propia
// (`DNSServiceSetDispatchQueue`): asi mDNSResponder puede contestar (nombre
// final si hubo choque, errores) sin que nadie lea a mano su socket. Todo lo
// que toca el `DNSServiceRef` va en esa cola, como pide `dns_sd.h`.
//
// Si un SDK no trajera el modulo `dnssd`, se compila con `NetService`
// (mismo anuncio, obsoleto pero vigente): ver el `#else` del final.

import Foundation
import PixPinCore
#if canImport(dnssd)
import dnssd
#endif

#if canImport(dnssd)
public final class Anunciador: @unchecked Sendable {
    private let cola = DispatchQueue(label: "pixpin.sincro.anuncio", qos: .utility)
    /// Solo se toca en `cola`: el del tipo de ahora y, si salio, el de antes.
    private var registros: [DNSServiceRef] = []
    /// Lo anunciado ahora (en `cola`), para no rehacerlo si no cambia.
    private var actual: (AnuncioBonjour, UInt16)?

    public init() {}

    deinit {
        for r in registros { DNSServiceRefDeallocate(r) }
    }

    /// Anuncia `anuncio` en `puerto`, sustituyendo lo anunciado antes. Si ya
    /// estaba igual, no hace nada (rehacerlo obliga a los demas a olvidarlo
    /// y volver a verlo, que en algunas Wi-Fi tarda minutos).
    public func anunciar(_ anuncio: AnuncioBonjour, puerto: UInt16) {
        cola.async { [self] in
            if let actual, actual.0 == anuncio, actual.1 == puerto { return }
            soltar()
            let txt = codificarTXT(anuncio.txt.map { ($0.clave, $0.valor) })
            var tipos = [anuncio.tipo]
            if let antes = tipoDeAntes(tipo: anuncio.tipo) { tipos.append(antes) }
            var hechos: [DNSServiceRef] = []
            for (i, tipo) in tipos.enumerated() {
                var nuevo: DNSServiceRef?
                let resultado: DNSServiceErrorType = txt.withUnsafeBytes { bytes in
                    DNSServiceRegister(&nuevo, 0, 0, anuncio.instancia, tipo, nil, nil,
                                       puerto.bigEndian, UInt16(bytes.count), bytes.baseAddress,
                                       Anunciador.alResponder, nil)
                }
                // 0 es kDNSServiceErr_NoError.
                guard resultado == 0, let nuevo else {
                    NSLog("PinDesk: no se pudo anunciar %@ en la red (DNSServiceRegister %d)", tipo, resultado)
                    // Sin el de ahora no hay anuncio (se reintenta la proxima
                    // vez); sin el de antes, se sigue con el de ahora.
                    if i == 0 { return }
                    continue
                }
                if DNSServiceSetDispatchQueue(nuevo, cola) != 0 {
                    NSLog("PinDesk: el anuncio no tiene cola para sus respuestas")
                }
                hechos.append(nuevo)
            }
            registros = hechos
            actual = (anuncio, puerto)
        }
    }

    /// Deja de anunciar (al salir del grupo o cerrar la app).
    public func retirar() {
        cola.async { [self] in soltar() }
    }

    /// En `cola`.
    private func soltar() {
        for r in registros { DNSServiceRefDeallocate(r) }
        registros = []
        actual = nil
    }

    /// La respuesta de mDNSResponder: solo se apunta si fue mal (un choque de
    /// nombre lo resuelve el solo anadiendo « (2)»).
    private static let alResponder: DNSServiceRegisterReply = { _, _, error, _, _, _, _ in
        if error != 0 {
            NSLog("PixPin: el anuncio fallo (%d)", error)
        }
    }
}

#else

public final class Anunciador: NSObject, @unchecked Sendable {
    /// Solo se toca en el hilo principal (`NetService` necesita su bucle):
    /// el del tipo de ahora y el de antes.
    private var servicios: [NetService] = []
    private var actual: (AnuncioBonjour, UInt16)?

    override public init() {}

    public func anunciar(_ anuncio: AnuncioBonjour, puerto: UInt16) {
        DispatchQueue.main.async { [self] in
            if let actual, actual.0 == anuncio, actual.1 == puerto { return }
            for s in servicios { s.stop() }
            var txt: [String: Data] = [:]
            for par in anuncio.txt { txt[par.clave] = Data(par.valor.utf8) }
            var tipos = [anuncio.tipo]
            if let antes = tipoDeAntes(tipo: anuncio.tipo) { tipos.append(antes) }
            servicios = tipos.map { tipo in
                let s = NetService(domain: "", type: tipo + ".", name: anuncio.instancia, port: Int32(puerto))
                s.setTXTRecord(NetService.data(fromTXTRecord: txt))
                s.publish()
                return s
            }
            actual = (anuncio, puerto)
        }
    }

    public func retirar() {
        DispatchQueue.main.async { [self] in
            for s in servicios { s.stop() }
            servicios = []
            actual = nil
        }
    }
}

#endif
