// Lo que se le hace a una grabacion en el editor, sin nada de pantalla ni
// de AVFoundation: recortar el principio y el final, quitar tramos de en
// medio, la velocidad y el zoom, y de ahi las cuentas que necesitan la
// reproduccion (que saltar, cuando dar la vuelta) y la exportacion (que
// tramos van, cuanto dura, que fotograma toca, que parte se ve). Puro y
// probado (`EditorGrabacionD7Tests`).
//
// El reloj del editor de Windows (`reproductor.rs`) va por fotogramas en
// memoria; aqui la grabacion es un MP4 y todo va en SEGUNDOS del video
// original. Las velocidades y el GIF/MP4 son los de Windows.

import CoreGraphics
import Foundation

/// En que formato se guarda (`Formato` de Windows). De partida MP4: en el
/// Mac la grabacion ya es video (en Windows es GIF porque graba GIF).
public enum FormatoGrabacion: String, CaseIterable, Sendable {
    case mp4, gif

    public var ext: String { rawValue }
    /// En mayusculas y sin traducir, como en Windows.
    public var rotulo: String { rawValue.uppercased() }
    public var siguiente: FormatoGrabacion { self == .mp4 ? .gif : .mp4 }
}

/// Lo que el usuario decidio (`Salida` de Windows).
public enum DecisionEditor: Equatable, Sendable {
    /// Preguntar donde (dialogo de guardar).
    case guardar
    /// A `capturas/` sin preguntar (↩).
    case guardadoRapido
    /// Guardar y dejar el FICHERO en el portapapeles (se pega entero).
    case copiar
    /// Tirarla (Esc).
    case descartar
}

public struct EdicionGrabacion: Equatable, Sendable {
    /// Velocidades que se ofrecen (`VELOCIDADES` de Windows).
    public static let velocidades: [Double] = [0.25, 0.5, 1, 2, 4]
    /// Acercamientos que se ofrecen.
    public static let zooms: [Double] = [1, 1.5, 2, 3]
    /// Lo mas corto que queda un tramo (ni recortar ni dividir dejan
    /// migajas que no se ven).
    public static let tramoMinimo = 0.1

    /// Lo que dura el video original.
    public let duracion: Double
    /// Donde empieza y acaba lo que se guarda (recortar).
    public private(set) var inicio: Double
    public private(set) var fin: Double
    /// Los puntos donde se dividio (ordenados, sin repetir).
    public private(set) var divisiones: [Double] = []
    /// Los tramos quitados de en medio (cortar), ordenados y sin solaparse.
    public private(set) var quitados: [ClosedRange<Double>] = []
    /// Velocidad de lo guardado (y de la vista previa).
    public var velocidad: Double = 1
    /// Acercamiento (1 = todo) y su centro, de 0 a 1 con el origen ARRIBA
    /// a la izquierda.
    public var zoom: Double = 1
    public var centro = CGPoint(x: 0.5, y: 0.5)

    public init(duracion: Double) {
        self.duracion = max(duracion, 0)
        inicio = 0
        fin = self.duracion
    }

    /// Sin tocar: se puede guardar moviendo el fichero, sin recodificar.
    public var sinCambios: Bool {
        inicio <= 0 && fin >= duracion && quitados.isEmpty && velocidad == 1 && zoom == 1
    }

    // MARK: Recortar y cortar

    /// Pone el principio en `t` (I). No pasa del final menos un tramo.
    public mutating func ponerInicio(_ t: Double) {
        inicio = min(max(0, t), max(0, fin - EdicionGrabacion.tramoMinimo))
    }

    /// Pone el final en `t` (O).
    public mutating func ponerFin(_ t: Double) {
        fin = max(min(duracion, t), min(duracion, inicio + EdicionGrabacion.tramoMinimo))
    }

    /// Divide en `t` (S). No divide pegado a otra division ni a los bordes.
    @discardableResult
    public mutating func dividir(en t: Double) -> Bool {
        let m = EdicionGrabacion.tramoMinimo
        guard t > m, t < duracion - m,
              !divisiones.contains(where: { abs($0 - t) < m }) else { return false }
        divisiones.append(t)
        divisiones.sort()
        return true
    }

    /// Los tramos entre divisiones (y los extremos), en tiempo original.
    public var segmentos: [ClosedRange<Double>] {
        let bordes = [0] + divisiones + [duracion]
        return zip(bordes, bordes.dropFirst()).map { $0...$1 }
    }

    /// El tramo (entre divisiones) que contiene `t`.
    public func segmento(en t: Double) -> ClosedRange<Double>? {
        segmentos.first { $0.contains(min(max(t, 0), duracion)) }
    }

    /// Si `t` cae en un tramo quitado.
    public func quitado(_ t: Double) -> Bool {
        quitados.contains { $0.contains(t) && t < $0.upperBound }
    }

    /// Quita (⌫) el tramo entre divisiones que contiene `t`. No deja la
    /// grabacion sin nada: si es lo unico que queda, no se quita.
    @discardableResult
    public mutating func quitarSegmento(en t: Double) -> Bool {
        guard let s = segmento(en: t) else { return false }
        var prueba = self
        prueba.quitados = EdicionGrabacion.unir(quitados + [s])
        guard !prueba.tramos.isEmpty else { return false }
        quitados = prueba.quitados
        return true
    }

    /// Devuelve el tramo quitado que contiene `t` (deshace ese corte).
    @discardableResult
    public mutating func restaurar(en t: Double) -> Bool {
        guard let i = quitados.firstIndex(where: { $0.contains(t) }) else { return false }
        quitados.remove(at: i)
        return true
    }

    /// Junta los tramos que se tocan o se pisan.
    static func unir(_ rangos: [ClosedRange<Double>]) -> [ClosedRange<Double>] {
        var salida: [ClosedRange<Double>] = []
        for r in rangos.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let u = salida.last, r.lowerBound <= u.upperBound + 1e-9 {
                salida[salida.count - 1] = u.lowerBound...max(u.upperBound, r.upperBound)
            } else {
                salida.append(r)
            }
        }
        return salida
    }

    // MARK: Lo que se guarda

    /// Los tramos que se guardan, en tiempo original y en orden: de
    /// `inicio` a `fin` menos lo quitado. Sin migajas.
    public var tramos: [ClosedRange<Double>] {
        var salida: [ClosedRange<Double>] = []
        var desde = inicio
        for q in quitados where q.upperBound > inicio && q.lowerBound < fin {
            if q.lowerBound > desde { salida.append(desde...q.lowerBound) }
            desde = max(desde, q.upperBound)
        }
        if fin > desde { salida.append(desde...fin) }
        return salida.filter { $0.upperBound - $0.lowerBound >= 1e-3 }
    }

    /// Lo que dura lo guardado, ya con la velocidad.
    public var duracionFinal: Double {
        tramos.reduce(0) { $0 + ($1.upperBound - $1.lowerBound) } / max(velocidad, 0.01)
    }

    /// El momento del original que sale en el segundo `s` de lo guardado.
    public func original(enSalida s: Double) -> Double {
        var resta = max(0, s) * velocidad
        for t in tramos {
            let largo = t.upperBound - t.lowerBound
            if resta < largo { return t.lowerBound + resta }
            resta -= largo
        }
        return tramos.last?.upperBound ?? 0
    }

    /// La reproduccion: desde `t` (tiempo original), a donde hay que
    /// saltar si cae fuera de lo que se guarda. Delante del principio o en
    /// un tramo quitado, al siguiente que se guarda; pasado el final, da la
    /// vuelta al primero (`avanzar` de Windows da la vuelta: se entiende
    /// mejor viendola repetir). `nil` si `t` ya se guarda.
    public func salto(desde t: Double) -> Double? {
        let ts = tramos
        guard let primero = ts.first else { return nil }
        if ts.contains(where: { t >= $0.lowerBound && t < $0.upperBound }) { return nil }
        return ts.first { $0.lowerBound > t }?.lowerBound ?? primero.lowerBound
    }

    /// Un fotograma adelante o atras (a 30 por segundo), dando la vuelta
    /// por los dos lados como `paso` de Windows y saltando lo quitado.
    public func paso(desde t: Double, adelante: Bool, fotograma: Double = 1.0 / 30) -> Double {
        let ts = tramos
        guard let primero = ts.first, let ultimo = ts.last else { return t }
        var n = t + (adelante ? fotograma : -fotograma)
        if adelante {
            if let s = salto(desde: n) { n = s }
        } else if n < primero.lowerBound {
            n = max(ultimo.upperBound - fotograma, ultimo.lowerBound)
        } else if !ts.contains(where: { n >= $0.lowerBound && n < $0.upperBound }) {
            // Hacia atras, al final del tramo anterior.
            if let ant = ts.last(where: { $0.upperBound <= n + 1e-9 }) {
                n = max(ant.upperBound - fotograma, ant.lowerBound)
            }
        }
        return n
    }

    // MARK: Velocidad y zoom

    /// La velocidad siguiente de la lista, dando la vuelta.
    public mutating func siguienteVelocidad() {
        let v = EdicionGrabacion.velocidades
        let i = v.firstIndex(of: velocidad) ?? 2
        velocidad = v[(i + 1) % v.count]
    }

    /// El zoom siguiente, dando la vuelta.
    public mutating func siguienteZoom() {
        let z = EdicionGrabacion.zooms
        let i = z.firstIndex(of: zoom) ?? 0
        zoom = z[(i + 1) % z.count]
    }

    /// La parte del video que se ve con el zoom, en pixeles del video
    /// (origen arriba): centrada en `centro` y empujada para no salirse.
    public func zonaVisible(en tam: CGSize) -> CGRect {
        let z = max(zoom, 1)
        let w = tam.width / z, h = tam.height / z
        let x = min(max(centro.x * tam.width - w / 2, 0), tam.width - w)
        let y = min(max(centro.y * tam.height - h / 2, 0), tam.height - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// La transformacion que lleva la zona visible a ocupar todo el video
    /// (la de `AVMutableVideoCompositionLayerInstruction`, origen arriba).
    public func transformacion(en tam: CGSize) -> CGAffineTransform {
        let z = max(zoom, 1)
        let v = zonaVisible(en: tam)
        return CGAffineTransform(a: z, b: 0, c: 0, d: z, tx: -v.minX * z, ty: -v.minY * z)
    }

    /// Un clic en la vista previa (ya acercada) en la fraccion `f` de lo
    /// que se ve: ese punto del video pasa a ser el centro del zoom.
    public mutating func centrar(enVista f: CGPoint, tam: CGSize) {
        guard tam.width > 0, tam.height > 0 else { return }
        let v = zonaVisible(en: tam)
        centro = CGPoint(x: min(max((v.minX + f.x * v.width) / tam.width, 0), 1),
                         y: min(max((v.minY + f.y * v.height) / tam.height, 0), 1))
    }

    /// Un punto de la vista previa (origen arriba) a la fraccion del video,
    /// con el video ajustado (sin deformar) y centrado en la vista.
    public static func fraccion(de p: CGPoint, vista: CGSize, video: CGSize) -> CGPoint? {
        guard video.width > 0, video.height > 0, vista.width > 0, vista.height > 0 else { return nil }
        let e = min(vista.width / video.width, vista.height / video.height)
        let w = video.width * e, h = video.height * e
        let x = (p.x - (vista.width - w) / 2) / w
        let y = (p.y - (vista.height - h) / 2) / h
        guard (0...1).contains(x), (0...1).contains(y) else { return nil }
        return CGPoint(x: x, y: y)
    }

    // MARK: GIF

    /// Fotogramas por segundo del GIF guardado (el de partida de Windows).
    public static let gifPorSegundo = 10

    /// Los momentos del original de cada fotograma del GIF, a
    /// `porSegundo` de lo guardado (ya con la velocidad).
    public func momentosGif(porSegundo: Int = EdicionGrabacion.gifPorSegundo) -> [Double] {
        let n = Int((duracionFinal * Double(porSegundo)).rounded(.up))
        return (0 ..< max(n, tramos.isEmpty ? 0 : 1)).map { original(enSalida: Double($0) / Double(porSegundo)) }
    }
}

/// El deshacer del editor: cada cambio guarda la edicion de antes.
public struct HistorialEdicion: Sendable {
    public private(set) var actual: EdicionGrabacion
    private var antes: [EdicionGrabacion] = []

    public init(_ e: EdicionGrabacion) { actual = e }

    public var puedeDeshacer: Bool { !antes.isEmpty }

    /// Aplica `cambio`; si cambio algo, se puede deshacer.
    public mutating func cambiar(_ cambio: (inout EdicionGrabacion) -> Void) {
        var nueva = actual
        cambio(&nueva)
        guard nueva != actual else { return }
        antes.append(actual)
        if antes.count > 100 { antes.removeFirst() }
        actual = nueva
    }

    /// Cambia sin guardar otro paso de deshacer: arrastrando un asa, todo
    /// el arrastre es un solo paso (el primero lo guardo `cambiar`).
    public mutating func retocar(_ cambio: (inout EdicionGrabacion) -> Void) {
        cambio(&actual)
    }

    public mutating func deshacer() {
        if let e = antes.popLast() { actual = e }
    }
}
