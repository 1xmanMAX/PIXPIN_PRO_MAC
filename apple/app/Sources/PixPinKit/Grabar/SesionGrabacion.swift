// La grabacion en dos fases (`grabador.rs` de Windows, P5b), sin nada de
// pantalla: en que punto esta la sesion, que hace cada tecla o boton, el
// reloj que no cuenta las pausas y la geometria del marco que se mueve y
// se estira con el raton. Todo puro: lo prueban las pruebas sin permiso de
// grabacion (la pantalla del Mac de pruebas esta bloqueada).
//
// Lanzar la grabacion NO empieza a grabar. Primero sale el marco azul
// alrededor de la zona (se puede mover y estirar) con su barra: el
// microfono, el sonido del sistema, «Grabar» y ✕. Solo al pulsar «Grabar»
// (tras la cuenta atras de `[gif] retardo_s`) el marco se pone rojo y
// empieza el video. Es la diferencia entre elegir la zona y elegir el
// momento.

import CoreGraphics
import CoreMedia
import Foundation

/// En que punto esta la sesion (`Fase` de Windows, mas `arrancando`: el
/// rato entre pulsar «Grabar» y que ScreenCaptureKit entregue).
public enum FaseGrabacion: Equatable, Sendable {
    /// Marco azul: eligiendo zona y sonido, sin grabar todavia.
    case esperando
    /// Marco azul y cuenta atras: ya se pulso «Grabar».
    case contando
    /// Pedido el flujo a ScreenCaptureKit, aun sin respuesta.
    case arrancando
    /// Marco rojo: grabando.
    case grabando
    /// Marco rojo y el reloj quieto: lo que llega no se escribe.
    case pausada

    /// Ya hay video (o se esta pidiendo): el marco no se mueve.
    public var conVideo: Bool {
        switch self {
        case .esperando, .contando: false
        case .arrancando, .grabando, .pausada: true
        }
    }
}

/// Lo que tiene que hacer quien graba tras un paso de la maquina.
public enum AccionSesion: Equatable, Sendable {
    case nada
    /// Ensenar la cuenta atras de estos segundos y, al acabar, arrancar.
    case contar(Int)
    /// Pedir el flujo ya (y quitar la cuenta atras si la habia).
    case arrancar
    case pausar
    case reanudar
    /// Cerrar el video y abrir el editor.
    case parar
    /// Cerrar la sesion sin haber grabado nada.
    case cerrar
}

/// La maquina de la sesion: cada boton, tecla o aviso es un metodo que
/// mueve la fase y dice que hacer. `fase == nil` es que no hay sesion.
public struct MaquinaGrabacion: Equatable, Sendable {
    public private(set) var fase: FaseGrabacion?

    public init() {}

    public var enSesion: Bool { fase != nil }

    /// Abre la sesion (marco azul). Con una ya abierta, no hace nada.
    @discardableResult
    public mutating func abrir() -> Bool {
        guard fase == nil else { return false }
        fase = .esperando
        return true
    }

    /// «Grabar» (el boton o ↩). Esperando: cuenta atras si hay retardo o
    /// arranca. Contando: se salta lo que quede de espera (como Windows:
    /// volver a pulsar «Grabar» no hace esperar dos veces).
    public mutating func grabar(retardo: Int) -> AccionSesion {
        switch fase {
        case .esperando:
            if retardo > 0 {
                fase = .contando
                return .contar(retardo)
            }
            fase = .arrancando
            return .arrancar
        case .contando:
            fase = .arrancando
            return .arrancar
        default:
            return .nada
        }
    }

    /// La cuenta atras llego a cero.
    public mutating func cuentaAcabada() -> AccionSesion {
        guard fase == .contando else { return .nada }
        fase = .arrancando
        return .arrancar
    }

    /// ScreenCaptureKit ya entrega.
    public mutating func arrancado() {
        if fase == .arrancando { fase = .grabando }
    }

    /// Pausar o seguir.
    public mutating func alternarPausa() -> AccionSesion {
        switch fase {
        case .grabando:
            fase = .pausada
            return .pausar
        case .pausada:
            fase = .grabando
            return .reanudar
        default:
            return .nada
        }
    }

    /// «Parar» (el boton o ↩ grabando).
    public mutating func parar() -> AccionSesion {
        guard fase == .grabando || fase == .pausada else { return .nada }
        return .parar
    }

    /// Esc: antes de grabar cierra sin nada; grabando (o en pausa) para y
    /// guarda, como Windows (`Fin::Escape` tambien abre el editor).
    public mutating func esc() -> AccionSesion {
        switch fase {
        case .esperando, .contando:
            fase = nil
            return .cerrar
        case .grabando, .pausada:
            return .parar
        case .arrancando, nil:
            return .nada
        }
    }

    /// El atajo de grabar (⌃⌥R) con la sesion abierta: la segunda vez
    /// empieza (o se salta la cuenta) y la tercera para.
    public mutating func atajo(retardo: Int) -> AccionSesion {
        switch fase {
        case .esperando, .contando: grabar(retardo: retardo)
        case .grabando, .pausada: parar()
        case .arrancando, nil: .nada
        }
    }

    /// La sesion se acabo (parada, cerrada o fallida).
    public mutating func cerrada() {
        fase = nil
    }
}

/// Las pausas de una grabacion en el reloj de las muestras (el del
/// sistema, el de ScreenCaptureKit): lo que llega en una pausa se tira y lo
/// de despues se adelanta lo que duraron, para que el video no tenga
/// huecos. Se guardan TODAS las pausas, no un desplazamiento suelto: una
/// muestra que llega tarde (de la cola) con un tiempo de dentro de una
/// pausa ya acabada tambien se tira.
public struct RelojPausas: Equatable, Sendable {
    public private(set) var pausas: [Tramo] = []

    public struct Tramo: Equatable, Sendable {
        public var desde: CMTime
        /// `nil` mientras dura.
        public var hasta: CMTime?
    }

    public init() {}

    public var enPausa: Bool { pausas.last.map { $0.hasta == nil } ?? false }
    /// Desde cuando dura la pausa en curso.
    public var pausadoDesde: CMTime? { enPausa ? pausas.last?.desde : nil }

    public mutating func pausar(_ t: CMTime) {
        guard !enPausa else { return }
        pausas.append(Tramo(desde: t, hasta: nil))
    }

    public mutating func reanudar(_ t: CMTime) {
        guard enPausa, let i = pausas.indices.last else { return }
        pausas[i].hasta = CMTimeMaximum(t, pausas[i].desde)
    }

    /// El tiempo de una muestra ya sin las pausas de antes; `nil` si cae
    /// dentro de una (se tira).
    public func ajustar(_ t: CMTime) -> CMTime? {
        var menos = CMTime.zero
        for p in pausas {
            guard t >= p.desde else { break }
            guard let hasta = p.hasta, t >= hasta else { return nil }
            menos = CMTimeAdd(menos, CMTimeSubtract(hasta, p.desde))
        }
        return CMTimeSubtract(t, menos)
    }

    /// Cuanto se grabo de verdad entre `a` y `b` (sin las pausas, ni la
    /// que siga abierta).
    public func activo(desde a: CMTime, hasta b: CMTime) -> CMTime {
        guard b > a else { return .zero }
        var total = CMTimeSubtract(b, a)
        for p in pausas {
            let fin = p.hasta ?? b
            let ini = CMTimeMaximum(p.desde, a)
            let hasta = CMTimeMinimum(fin, b)
            if hasta > ini { total = CMTimeSubtract(total, CMTimeSubtract(hasta, ini)) }
        }
        return CMTimeMaximum(total, .zero)
    }
}

/// Lo que se puede agarrar del marco (`Asa` de Windows).
public enum AsaMarco: Equatable, Sendable, CaseIterable {
    case mover, norte, sur, este, oeste, norEste, norOeste, surEste, surOeste
}

/// La geometria del marco que se mueve y se estira antes de grabar
/// (`marco_de`, `asa_en` y `aplicar_asa` de Windows). Todo en PUNTOS de la
/// pantalla con el origen ARRIBA a la izquierda, como `ZonaDeGrabacion`.
public enum MarcoAjustable {
    /// Grosor del borde que se ve, pintado por fuera de la zona.
    public static let grosor: CGFloat = 3
    /// Margen de agarre alrededor de la zona (`MARGEN`): lo que hay que
    /// acertar con el raton, mas que el borde que se ve.
    public static let margen: CGFloat = 8
    /// Lado minimo de la zona (`LADO_MINIMO`).
    public static let ladoMinimo: CGFloat = 32

    /// La ventana del marco: la zona con su margen de agarre.
    public static func marco(de zona: CGRect) -> CGRect {
        zona.standardized.insetBy(dx: -margen, dy: -margen)
    }

    /// Que parte del marco cae bajo `p`. `nil` dentro de la zona (ahi el
    /// raton atraviesa a la app de debajo) o fuera del marco.
    public static func asa(en p: CGPoint, zona: CGRect) -> AsaMarco? {
        let z = zona.standardized
        guard marco(de: z).contains(p), !z.contains(p) else { return nil }
        // Las esquinas mandan, en un cuadrado de 3 margenes.
        let esquina = 3 * margen
        let oeste = p.x < z.minX + esquina
        let este = p.x > z.maxX - esquina
        let norte = p.y < z.minY + esquina
        let sur = p.y > z.maxY - esquina
        switch (norte, sur, oeste, este) {
        case (true, _, true, _): return .norOeste
        case (true, _, _, true): return .norEste
        case (_, true, true, _): return .surOeste
        case (_, true, _, true): return .surEste
        case (true, _, _, _): return .norte
        case (_, true, _, _): return .sur
        case (_, _, true, _): return .oeste
        case (_, _, _, true): return .este
        default: return .mover
        }
    }

    /// La zona tras arrastrar `asa` un `(dx, dy)` (y hacia ABAJO). Nunca
    /// menor que `ladoMinimo`: el lado deja de seguir al raton en vez de
    /// darse la vuelta.
    public static func aplicar(_ asa: AsaMarco, a zona: CGRect, dx: CGFloat, dy: CGFloat) -> CGRect {
        let z = zona.standardized
        if asa == .mover { return z.offsetBy(dx: dx, dy: dy) }
        var (i, a, d, b) = (z.minX, z.minY, z.maxX, z.maxY)
        if [.oeste, .norOeste, .surOeste].contains(asa) { i = min(i + dx, d - ladoMinimo) }
        if [.este, .norEste, .surEste].contains(asa) { d = max(d + dx, i + ladoMinimo) }
        if [.norte, .norEste, .norOeste].contains(asa) { a = min(a + dy, b - ladoMinimo) }
        if [.sur, .surEste, .surOeste].contains(asa) { b = max(b + dy, a + ladoMinimo) }
        return CGRect(x: i, y: a, width: d - i, height: b - a)
    }

    /// La zona dentro de la pantalla (`limites`, en los mismos puntos):
    /// moverla la empuja de vuelta sin cambiar su tamano; si es mas grande
    /// que la pantalla, se recorta.
    public static func limitar(_ zona: CGRect, a limites: CGRect) -> CGRect {
        var z = zona.standardized
        z.size.width = min(z.width, limites.width)
        z.size.height = min(z.height, limites.height)
        z.origin.x = min(max(z.minX, limites.minX), limites.maxX - z.width)
        z.origin.y = min(max(z.minY, limites.minY), limites.maxY - z.height)
        return z
    }

    /// Un tiempo en `m:ss` (`reloj` de Windows); con horas, `h:mm:ss`.
    public static func reloj(_ segundos: Double) -> String {
        let s = max(0, Int(segundos))
        if s >= 3600 {
            return "\(s / 3600):" + String(format: "%02d:%02d", (s / 60) % 60, s % 60)
        }
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }
}
