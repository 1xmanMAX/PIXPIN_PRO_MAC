// Las capturas caducadas, a la Papelera del Mac: lo que hace en Windows
// `caducidad_capturas.rs` (barre al arrancar y luego cada hora, y lo
// caducado va a la papelera de reciclaje, de donde se puede restaurar).
//
// Lo que se va lo decide el nucleo de Rust con las reglas de siempre
// (`Nucleo.capturasCaducadas`: conservadas, fecha acordada con el grupo,
// el plazo del ajuste y «7 dias mas»); Swift solo las mueve con
// `FileManager.trashItem` y luego le pide al nucleo que olvide las
// conservadas y prorrogadas que ya no estan (`olvidarCapturasAusentes`).
//
// **El aviso «se van en 24 h»** (C4, `caducidad_capturas::vigilar_avisos`
// de Windows): tras cada barrido, las que se van en las proximas 24 h
// (`Nucleo.capturasPorAvisar`) salen en una notificacion con «Conservar» y
// «Abrir» (una) o «Ver la galeria» (varias), por `CentroAvisos`; sin
// permiso, en su ventanita. Cada captura se avisa una vez por sesion.
//
// Rendimiento (§4bis.6 del plan): nada de temporizadores propios. Un solo
// `NSBackgroundActivityScheduler` con mucha tolerancia: el sistema elige
// el momento (con el Mac despierto, sin bateria baja, junto a otros
// trabajos) y lo corre con prioridad `.utility`. Cada barrido es una
// lectura de `capturas/` (de la cache si no cambio) y del registro.

import AppKit
import Foundation
import os
import PixPinCore

public final class BarrenderoCapturas: @unchecked Sendable {
    /// El id de la actividad para el sistema (uno por app).
    public static let identificador = "io.github.1xmanmax.pixpin.caducidad-capturas"
    /// Cada cuanto, como mucho (Windows: `CADA`, una hora).
    public static let cada: TimeInterval = 60 * 60
    /// Cuanto puede retrasarlo el sistema para juntarlo con otros trabajos.
    public static let tolerancia: TimeInterval = 20 * 60
    /// La espera tras arrancar, para no competir con el arranque.
    public static let esperaAlArrancar: TimeInterval = 15

    /// Lo que hizo un barrido.
    public struct Barrido: Equatable, Sendable {
        /// Los nombres de las que se fueron a la Papelera.
        public var idas: [String] = []
        /// Las que no se pudieron mover (con el motivo).
        public var fallos: [String] = []
        /// Cuantos nombres se olvidaron del registro.
        public var olvidadas: UInt32 = 0
        /// Las que se avisaron porque se van en las proximas 24 h.
        public var avisadas: [String] = []
    }

    let nucleo: Nucleo
    /// Los dias del ajuste (`[capturas] dias_caducidad` de `pixpinmax.toml`,
    /// el que cambia Ajustes y vale tambien en Windows). Si el fichero no se
    /// entiende, cero: mejor no borrar nada que borrar con un plazo inventado.
    var dias: @Sendable () -> Int64
    /// Llevar un fichero a la Papelera (las pruebas lo cambian).
    var tirar: @Sendable (URL) throws -> Void = { url in
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    /// Lo que se hace con el aviso de las que se van (las pruebas lo
    /// cambian): por defecto, a `CentroAvisos`.
    var avisar: @Sendable (Aviso) -> Void = { aviso in
        Task { @MainActor in CentroAvisos.compartido.avisar(aviso) }
    }
    /// Las ya avisadas en esta sesion (por nombre).
    private var avisadas: Set<String> = []

    private let cerrojo = NSLock()
    private var programador: NSBackgroundActivityScheduler?
    private static let registro = Logger(subsystem: "io.github.1xmanmax.pixpin", category: "caducidad")

    public init(nucleo: Nucleo) {
        self.nucleo = nucleo
        dias = { Int64((try? nucleo.ajustes().diasCaducidad) ?? 0) }
    }

    deinit {
        programador?.invalidate()
    }

    /// **Barre una vez**: lo caducado a la Papelera. Bloqueante (lee el
    /// disco y mueve ficheros): fuera del hilo principal. Dos barridos a la
    /// vez no se pisan.
    @discardableResult
    public func barrer() -> Barrido {
        cerrojo.lock()
        defer { cerrojo.unlock() }
        var hecho = Barrido()
        let plazo = dias()
        if plazo > 0 {
            for c in nucleo.capturasCaducadas(dias: plazo) {
                do {
                    try tirar(URL(fileURLWithPath: c.ruta))
                    hecho.idas.append(c.nombre)
                } catch {
                    hecho.fallos.append("\(c.nombre): \(error.localizedDescription)")
                }
            }
        }
        do {
            hecho.olvidadas = try nucleo.olvidarCapturasAusentes()
        } catch {
            BarrenderoCapturas.registro.error("no se pudo limpiar el registro de caducidad: \(String(describing: error), privacy: .public)")
        }
        if !hecho.idas.isEmpty {
            BarrenderoCapturas.registro.info("capturas caducadas a la Papelera: \(hecho.idas.count)")
        }
        for f in hecho.fallos {
            BarrenderoCapturas.registro.error("no se pudo llevar a la Papelera: \(f, privacy: .public)")
        }
        if plazo > 0 {
            let seVan = nucleo.capturasPorAvisar(dias: plazo).filter { !avisadas.contains($0.nombre) }
            avisadas.formUnion(seVan.map(\.nombre))
            hecho.avisadas = seVan.map(\.nombre)
            if let aviso = AvisoCaducidad.aviso(de: seVan, ahora: Date()) {
                avisar(aviso)
            }
        }
        return hecho
    }

    /// **Empieza**: un barrido poco despues de arrancar y luego como mucho
    /// cada hora, cuando el sistema vea bien. Llamarlo otra vez no hace nada.
    public func arrancar() {
        guard programador == nil else { return }
        let nucleo = self.nucleo
        Task { @MainActor in
            CentroAvisos.compartido.alResponder([.captura, .capturas]) { accion, datos in
                AvisoCaducidad.responder(accion, datos, nucleo: nucleo)
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + BarrenderoCapturas.esperaAlArrancar) { [weak self] in
            self?.barrer()
        }
        let p = NSBackgroundActivityScheduler(identifier: BarrenderoCapturas.identificador)
        p.repeats = true
        p.interval = BarrenderoCapturas.cada
        p.tolerance = BarrenderoCapturas.tolerancia
        p.qualityOfService = .utility
        p.schedule { [weak self, weak p] completar in
            guard let self else {
                completar(.finished)
                return
            }
            if p?.shouldDefer == true {
                completar(.deferred)
                return
            }
            self.barrer()
            completar(.finished)
        }
        programador = p
    }

    /// Deja de barrer (al salir).
    public func parar() {
        programador?.invalidate()
        programador = nil
    }
}

/// El aviso de las capturas que se van (`notificaciones::de_capturas` de
/// Windows) y lo que hacen sus botones.
enum AvisoCaducidad {
    static let id = "pixpin.capturas-se-van"
    static let claveNombre = "nombre"
    static let claveRuta = "ruta"

    /// Una: con su imagen, «Conservar» y «Abrir» (como pin). Varias:
    /// cuantas y la galeria. Ninguna: nada.
    static func aviso(de seVan: [CapturaCaducada], ahora: Date, calendario: Calendar = .current) -> Aviso? {
        switch seVan.count {
        case 0:
            return nil
        case 1:
            let c = seVan[0]
            let cuando = AtajosDeHora.legible(fechaDe(ms: c.seVa), ahora: ahora, calendario: calendario)
            return Aviso(id: id, categoria: .captura, titulo: "Capturas que caducan",
                         texto: "Esta captura se va a la Papelera: \(cuando)",
                         imagen: URL(fileURLWithPath: c.ruta),
                         datos: [claveNombre: c.nombre, claveRuta: c.ruta])
        default:
            return Aviso(id: id, categoria: .capturas, titulo: "Capturas que caducan",
                         texto: "\(seVan.count) capturas se van a la Papelera en las próximas 24 h")
        }
    }

    /// «Conservar» la manda a «Mensajes guardados» (y ya no caduca);
    /// «Abrir», como pin; pulsar o «Ver la galeria», la galeria.
    @MainActor
    static func responder(_ accion: AccionAviso, _ datos: [String: String], nucleo: Nucleo) {
        switch accion {
        case .conservar:
            guard let nombre = datos[claveNombre] else { return }
            Task.detached(priority: .userInitiated) {
                if (try? nucleo.conservarCaptura(nombre: nombre)) != nil {
                    await MainActor.run {
                        NotificationCenter.default.post(name: .pixpinCambioLocal, object: nil)
                    }
                }
            }
        case .abrir:
            guard let ruta = datos[claveRuta] else { return }
            if !GestorPines.compartido.pinear(fichero: URL(fileURLWithPath: ruta)) { NSSound.beep() }
        case .galeria:
            ComandosApp.abrirVentana?(IdVentana.galeria)
            NSApp.activate()
        case .hecha, .posponer, .cerrar:
            break
        }
    }
}
