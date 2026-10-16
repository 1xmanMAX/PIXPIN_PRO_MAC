// **Presentar un PowerPoint como Windows** (tanda D9): es `diapositivas.rs`
// de alla con las piezas del Mac.
//
// - La presentacion va a pantalla completa, la diapositiva entera centrada
//   sobre negro, y abajo la pastilla del movil «← n / total → ✕». Pasar con
//   el raton como con el dedo: clic en el tercio derecho, siguiente; en el
//   izquierdo, anterior; en el medio, esconder o ensenar la pastilla. La
//   rueda y el boton derecho tambien pasan.
// - El teclado de PowerPoint, que es lo que mandan los mandos de presentar:
//   → ↓ AvPag ↩ Espacio siguiente; ← ↑ RePag ⌫ P y ⇧Espacio anterior;
//   Inicio/Fin; B o «.» pantalla negra; N las notas en una franja abajo; T
//   apaga o enciende las transiciones; ⎋ sale.
// - **Con dos pantallas**, la presentacion va a la otra (el proyector) y en
//   la principal sale la **vista del orador**: la de ahora, la siguiente,
//   las notas, el tiempo que lleva y la hora. El teclado se queda alli.
// - **Transiciones sencillas** (fundido, empuje, barrido, cubrir,
//   descubrir, corte) y el pase solo (`advTm`): cada diapositiva se pinta
//   una vez a la medida de la pantalla y la transicion solo mezcla las dos
//   imagenes con las capas que calcula Rust (`capasDeTransicion`), las
//   mismas que en Windows.
// - **Videos y audios**: su poster con el boton ya viene en la diapositiva;
//   un clic encima suena el audio en el reproductor de la app y abre el
//   video con el reproductor del sistema (PixPin no reproduce video).
//
// Las diapositivas las maqueta Rust (`DocumentoOffice`, como el lector) y
// las pinta `PintorOffice`, fuera del hilo principal. Solo se guardan las
// de alrededor de la que se ve.
//
// Windows no tiene puntero laser ni lapiz al presentar: aqui tampoco.

import AppKit
import PixPinCore
import QuartzCore

// MARK: - Las cuentas (sin ventanas: se prueban solas)

/// Lo que se le pide a la presentacion (una tecla, un clic, la rueda).
public enum MandoDiapositiva: Equatable, Sendable {
    case siguiente, anterior, primera, ultima
    /// Pantalla negra (B o «.»).
    case negro
    /// Esconder o ensenar la pastilla.
    case pastilla
    /// Las notas del orador en una franja abajo (N; con la vista del orador
    /// ya estan alli).
    case notas
    /// Encender o apagar las transiciones (T).
    case transiciones
    case salir
}

/// Por donde va el pase. `total` es 0 mientras no se sabe.
public struct PaseDiapositivas: Equatable, Sendable {
    public var actual = 0
    public var total = 0
    public var negro = false
    public var pastilla = true

    public init(actual: Int = 0, total: Int = 0) {
        self.actual = actual
        self.total = total
    }

    /// Aplica un mando. `false` si hay que salir.
    ///
    /// No da la vuelta: pasar de la ultima se queda en la ultima. Con la
    /// pantalla en negro, cualquier mando de pasar primero la enciende
    /// (PowerPoint).
    public mutating func aplicar(_ m: MandoDiapositiva) -> Bool {
        let ultima = max(total - 1, 0)
        if negro, ![.salir, .pastilla, .notas, .transiciones].contains(m) {
            negro = false
            if m == .negro { return true }
        }
        switch m {
        case .siguiente: actual = min(actual + 1, ultima)
        case .anterior: actual = max(actual - 1, 0)
        case .primera: actual = 0
        case .ultima: actual = ultima
        case .negro: negro = true
        case .pastilla: pastilla.toggle()
        // Las lleva la presentacion: no mueven el pase.
        case .notas, .transiciones: break
        case .salir: return false
        }
        return true
    }

    public var puedeAnterior: Bool { actual > 0 }
    public var puedeSiguiente: Bool { total == 0 || actual + 1 < total }
}

/// Lo que mide la vista del orador: la de ahora grande a la izquierda; a la
/// derecha, la siguiente arriba y las notas debajo; arriba, la cuenta, el
/// tiempo y la hora. Con la Y hacia abajo.
public struct ZonasOrador: Equatable, Sendable {
    public var actual: CGRect
    public var siguiente: CGRect
    public var notas: CGRect
    /// Donde empieza (en alto) la fila de arriba.
    public var cabecera: CGFloat
    /// Lo que mide un rotulo («Siguiente», «Notas») encima de su zona.
    public var rotulo: CGFloat
}

public enum CuentasDiapositivas {
    /// Lo que se ve la pastilla tras mover el raton.
    public static let segundosPastilla: CFTimeInterval = 3
    /// Lo que se ve un aviso («Transiciones desactivadas»).
    public static let segundosAviso: CFTimeInterval = 1.6

    /// Los formatos que maqueta PixPin (`pixpin-office`): los demas
    /// (`.ppt`, `.odp`, Keynote) no se presentan aqui.
    public static let extensiones: Set<String> = ["pptx", "pptm", "ppsx", "ppsm", "potx", "potm"]

    public static func sePresenta(_ url: URL) -> Bool {
        extensiones.contains(url.pathExtension.lowercased())
    }

    /// Las teclas de PowerPoint en pase de diapositivas (`keyCode` del Mac).
    /// La N (que en PowerPoint tambien pasa) aqui ensena las notas, y la T
    /// apaga o enciende las transiciones.
    public static func mando(tecla: UInt16, caracteres: String, mayusculas: Bool) -> MandoDiapositiva? {
        switch tecla {
        case 124, 125, 121, 36, 76: return .siguiente // → ↓ AvPag ↩ Intro
        case 49: return mayusculas ? .anterior : .siguiente // Espacio
        case 123, 126, 116, 51: return .anterior // ← ↑ RePag ⌫
        case 115: return .primera // Inicio
        case 119: return .ultima // Fin
        case 53: return .salir // ⎋
        default: break
        }
        switch caracteres.lowercased() {
        case "p": return .anterior
        case "b", ".": return .negro
        case "n": return .notas
        case "t": return .transiciones
        default: return nil
        }
    }

    /// Un clic sin arrastrar: por tercios, como `ZonaDePasar` del movil.
    public static func mando(clicEn x: CGFloat, ancho: CGFloat) -> MandoDiapositiva {
        let tercio = ancho / 3
        if x < tercio { return .anterior }
        if x > tercio * 2 { return .siguiente }
        return .pastilla
    }

    /// La caja donde cabe entera una diapositiva de `pagina` en `pantalla`,
    /// centrada.
    public static func encajar(_ pagina: CGSize, en pantalla: CGSize) -> CGRect {
        let pw = max(pagina.width, 1), ph = max(pagina.height, 1)
        let s = min(pantalla.width / pw, pantalla.height / ph)
        let w = pw * s, h = ph * s
        return CGRect(x: (pantalla.width - w) / 2, y: (pantalla.height - h) / 2, width: w, height: h)
    }

    /// Como `encajar`, a puntos enteros (nitida al copiarla).
    public static func encajarEntera(_ pagina: CGSize, en pantalla: CGSize) -> CGRect {
        let c = encajar(pagina, en: pantalla)
        return CGRect(x: c.minX.rounded(), y: c.minY.rounded(),
                      width: max(c.width.rounded(), 1), height: max(c.height.rounded(), 1))
    }

    /// Que pantalla es de que: `(la de la presentacion, la del orador)`, por
    /// su indice. Con una sola, la presentacion va en ella y no hay orador;
    /// con dos o mas, el orador se queda la principal (la del portatil) y la
    /// presentacion va a otra (el proyector), como PowerPoint.
    public static func repartir(pantallas: Int, principal: Int) -> (presentacion: Int, orador: Int?)? {
        guard pantallas > 0 else { return nil }
        let p = (0..<pantallas).contains(principal) ? principal : 0
        guard let otra = (0..<pantallas).first(where: { $0 != p }) else { return (p, nil) }
        return (otra, p)
    }

    /// El tiempo que lleva: `05:07`, o `1:02:03` pasada la hora.
    public static func cronometro(segundos: Int) -> String {
        let s = max(segundos, 0)
        let (h, m, r) = (s / 3600, s / 60 % 60, s % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, r) : String(format: "%02d:%02d", m, r)
    }

    /// La hora del reloj (`14:05`).
    public static func hora(_ fecha: Date, calendario: Calendar = .current) -> String {
        let c = calendario.dateComponents([.hour, .minute], from: fecha)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    public static func zonasOrador(ancho: CGFloat, alto: CGFloat, pagina: CGSize) -> ZonasOrador {
        let m: CGFloat = 24, cab: CGFloat = 56, rotulo: CGFloat = 30
        let y0 = m + cab
        let h = max(alto - y0 - m, 1)
        let util = max(ancho - 3 * m, 2)
        let (wl, wr) = (util * 0.6, util * 0.4)
        let x1 = 2 * m + wl
        let a = encajar(pagina, en: CGSize(width: wl, height: h))
        let actual = a.offsetBy(dx: m, dy: y0)
        let s = encajar(pagina, en: CGSize(width: wr, height: max(h * 0.45 - rotulo, 1)))
        let siguiente = CGRect(x: x1 + s.minX, y: y0 + rotulo, width: s.width, height: s.height)
        let ny = siguiente.maxY + m + rotulo
        let notas = CGRect(x: x1, y: ny, width: wr, height: max(alto - m - ny, 0))
        return ZonasOrador(actual: actual, siguiente: siguiente, notas: notas, cabecera: m, rotulo: rotulo)
    }

    /// Si al pasar de `antes` a `ahora` toca transicion: solo hacia delante
    /// y de una en una (atras o saltando, de golpe, como PowerPoint), con
    /// las transiciones encendidas y si dura algo.
    public static func tocaTransicion(antes: Int, ahora: Int, encendidas: Bool, ms: UInt32?) -> Bool {
        encendidas && ahora == antes + 1 && (ms ?? 0) > 0
    }

    /// Por donde va una transicion que empezo hace `transcurrido` s y dura
    /// `ms`: de 0 a 1. Una de cero ms ya ha acabado.
    public static func progreso(transcurrido: CFTimeInterval, ms: UInt32) -> Float {
        guard ms > 0 else { return 1 }
        return Float(min(max(transcurrido * 1000 / Double(ms), 0), 1))
    }

    /// Un rectangulo en fracciones (izquierda, arriba, derecha, abajo) de
    /// `caja`.
    public static func trozo(_ f: [Float], de caja: CGRect) -> CGRect {
        guard f.count == 4 else { return caja }
        return CGRect(x: caja.minX + CGFloat(f[0]) * caja.width, y: caja.minY + CGFloat(f[1]) * caja.height,
                      width: CGFloat(f[2] - f[0]) * caja.width, height: CGFloat(f[3] - f[1]) * caja.height)
    }
}

// MARK: - La presentacion abierta (Rust)

/// **El PowerPoint abierto para presentarlo**: cada cosa se pide a Rust la
/// primera vez y se guarda (las notas, la transicion, los medios). Lo que
/// cruza el puente va por una cola propia, fuera del hilo principal.
final class ArchivoDiapositivas: @unchecked Sendable {
    let office: DocumentoOffice
    let total: Int
    /// Lo que mide una diapositiva, en puntos.
    let tamano: CGSize
    private let cerrojo = NSLock()
    private var notas: [Int: String?] = [:]
    private var transiciones: [Int: TransicionDiapositiva?] = [:]
    private var medios: [Int: [MedioDiapositiva]] = [:]

    private init(office: DocumentoOffice, total: Int, tamano: CGSize) {
        self.office = office
        self.total = total
        self.tamano = tamano
    }

    /// Lo abre (bloquea: fuera del hilo principal). `nil` si no se deja.
    static func abrir(_ url: URL) -> ArchivoDiapositivas? {
        guard let office = try? DocumentoOffice.abrir(ruta: url.path, medidor: MedidorCoreText()),
              office.esPresentacion() else { return nil }
        let total = Int(office.total())
        guard total > 0, let p = office.pagina(n: 0) else { return nil }
        return ArchivoDiapositivas(office: office, total: total,
                                   tamano: CGSize(width: CGFloat(p.ancho), height: CGFloat(p.alto)))
    }

    /// Lo ya leido de la `i`, sin cruzar el puente (para pintar).
    func notasSiHay(_ i: Int) -> String?? {
        cerrojo.lock()
        defer { cerrojo.unlock() }
        return notas[i]
    }

    func notas(_ i: Int) -> String? {
        if let n = notasSiHay(i) { return n }
        let n = office.notas(n: UInt32(i))
        cerrojo.lock()
        notas[i] = .some(n)
        cerrojo.unlock()
        return n
    }

    func transicion(_ i: Int) -> TransicionDiapositiva? {
        cerrojo.lock()
        if let t = transiciones[i] {
            cerrojo.unlock()
            return t
        }
        cerrojo.unlock()
        let t = office.transicion(n: UInt32(i))
        cerrojo.lock()
        transiciones[i] = .some(t)
        cerrojo.unlock()
        return t
    }

    func medios(_ i: Int) -> [MedioDiapositiva] {
        cerrojo.lock()
        if let m = medios[i] {
            cerrojo.unlock()
            return m
        }
        cerrojo.unlock()
        let m = office.medios(n: UInt32(i))
        cerrojo.lock()
        medios[i] = m
        cerrojo.unlock()
        return m
    }

    /// **La diapositiva `i` pintada** a `pixeles` (sobre blanco, como el
    /// papel de PowerPoint). Bloquea.
    func foto(_ i: Int, pixeles: CGSize) -> CGImage? {
        let w = Int(pixeles.width.rounded()), h = Int(pixeles.height.rounded())
        guard w > 0, h > 0, let p = office.pagina(n: UInt32(i)), p.ancho > 0, p.alto > 0,
              let pintor = try? PintorOffice(pagina: p, imagen: { [office] in office.imagen(id: $0) }),
              let espacio = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: espacio, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.interpolationQuality = .high
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: CGFloat(w) / CGFloat(p.ancho), y: -CGFloat(h) / CGFloat(p.alto))
        pintor.pintar(en: ctx)
        return ctx.makeImage()
    }

    /// Saca un video o un audio a un fichero temporal (el mismo si ya
    /// estaba) para reproducirlo.
    func fichero(de m: MedioDiapositiva, origen: URL) -> URL? {
        guard let parte = m.parte else { return nil }
        let nombre = String((parte.split(separator: "/").last ?? "medio").map {
            $0.isLetter || $0.isNumber || ".-_".contains($0) ? $0 : "_"
        })
        let fecha = (try? origen.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        var h = Hasher()
        h.combine(origen.path)
        h.combine(fecha)
        h.combine(parte)
        let carpeta = FileManager.default.temporaryDirectory.appendingPathComponent("pixpin-medios", isDirectory: true)
        let ruta = carpeta.appendingPathComponent(String(format: "%016llx-", UInt64(bitPattern: Int64(h.finalize()))) + nombre)
        if FileManager.default.fileExists(atPath: ruta.path) { return ruta }
        guard let datos = office.bytesDeMedio(parte: parte) else { return nil }
        do {
            try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
            try datos.write(to: ruta, options: .atomic)
            return ruta
        } catch {
            return nil
        }
    }
}

// MARK: - Colores y textos (los del lector de Windows)

private enum TonoPase {
    static let cristal = NSColor(srgbRed: 0.16, green: 0.16, blue: 0.18, alpha: 1)
    static let apagado = NSColor(srgbRed: 0.62, green: 0.62, blue: 0.66, alpha: 1)
    static let texto = NSColor(srgbRed: 0.93, green: 0.93, blue: 0.95, alpha: 1)
    static let fondoOrador = NSColor(srgbRed: 0.09, green: 0.09, blue: 0.106, alpha: 1)
}

enum TextosPase {
    static let preparando = "Preparando la presentación…"
    static let noSePudo = "No se pudo preparar la presentación"
    static let siguiente = "Siguiente"
    static let notas = "Notas"
    static let sinNotas = "Esta diapositiva no tiene notas"
    static let fin = "Fin de la presentación"
    static let transicionesSi = "Transiciones activadas (T)"
    static let transicionesNo = "Transiciones desactivadas (T)"
}

/// Dibujar con la Y hacia abajo (las vistas de aqui son `isFlipped`).
private enum Dibujo {
    static func imagen(_ img: CGImage, en r: CGRect, recorte: CGRect? = nil, alfa: CGFloat = 1) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        var img = img
        if let recorte {
            let w = CGFloat(img.width), h = CGFloat(img.height)
            let px = CGRect(x: recorte.minX * w, y: recorte.minY * h, width: recorte.width * w, height: recorte.height * h)
                .integral.intersection(CGRect(x: 0, y: 0, width: w, height: h))
            guard !px.isEmpty, let c = img.cropping(to: px) else { return }
            img = c
        }
        ctx.saveGState()
        ctx.setAlpha(alfa)
        ctx.interpolationQuality = .high
        ctx.translateBy(x: r.minX, y: r.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(img, in: CGRect(origin: .zero, size: r.size))
        ctx.restoreGState()
    }

    static func texto(_ s: String, _ tam: CGFloat, _ color: NSColor, peso: NSFont.Weight = .regular) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [
            .font: NSFont.systemFont(ofSize: tam, weight: peso),
            .foregroundColor: color,
        ])
    }

    /// Un texto que se parte en lineas para caber en `ancho`.
    static func parrafo(_ s: String, _ tam: CGFloat, _ color: NSColor) -> NSAttributedString {
        let p = NSMutableParagraphStyle()
        p.lineBreakMode = .byWordWrapping
        p.paragraphSpacing = tam * 0.4
        return NSAttributedString(string: s, attributes: [
            .font: NSFont.systemFont(ofSize: tam), .foregroundColor: color, .paragraphStyle: p,
        ])
    }

    static func alto(_ t: NSAttributedString, ancho: CGFloat) -> CGFloat {
        ceil(t.boundingRect(with: CGSize(width: ancho, height: .greatestFiniteMagnitude),
                            options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
    }

    static func icono(_ nombre: String, en r: CGRect, color: NSColor) {
        let conf = NSImage.SymbolConfiguration(pointSize: r.height * 0.8, weight: .semibold)
            .applying(.init(paletteColors: [color]))
        guard let img = NSImage(systemSymbolName: nombre, accessibilityDescription: nil)?
            .withSymbolConfiguration(conf) else { return }
        let s = img.size
        let d = CGRect(x: r.midX - s.width / 2, y: r.midY - s.height / 2, width: s.width, height: s.height)
        img.draw(in: d, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}

// MARK: - La vista de la presentacion

/// La pantalla del pase: negro, la diapositiva (o el fotograma de su
/// transicion), las notas abajo, el aviso y la pastilla.
final class VistaPase: NSView {
    weak var pase: PresentacionDiapositivas?
    /// Donde estan los botones de la pastilla (para el clic).
    private var botones: [(CGRect, MandoDiapositiva)] = []
    private var raton: CGPoint?
    private var rueda: CGFloat = 0

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        // Mover el raton ensena la pastilla un rato, como en cualquier
        // reproductor.
        if let r = raton, abs(p.x - r.x) + abs(p.y - r.y) > 4 { pase?.ensenarPastilla() }
        raton = p
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        raton = p
        if let b = botones.first(where: { $0.0.contains(p) }) {
            pase?.mandar(b.1)
        } else if pase?.reproducirMedio(en: p, caja: bounds.size) != true {
            pase?.mandar(CuentasDiapositivas.mando(clicEn: p.x, ancho: bounds.width))
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        pase?.mandar(.anterior)
    }

    /// La rueda pasa de una en una: un golpe de raton, o un gesto del
    /// trackpad que recorre un trecho.
    override func scrollWheel(with event: NSEvent) {
        if event.phase == .began { rueda = 0 }
        let d = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 10
        guard event.momentumPhase.isEmpty else { return }
        rueda += d
        if rueda <= -30 {
            rueda = event.hasPreciseScrollingDeltas ? -.greatestFiniteMagnitude : 0
            pase?.mandar(.siguiente)
        } else if rueda >= 30 {
            rueda = event.hasPreciseScrollingDeltas ? .greatestFiniteMagnitude : 0
            pase?.mandar(.anterior)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()
        botones = []
        guard let p = pase else { return }
        let (ancho, alto) = (bounds.width, bounds.height)
        let centrado = { (t: String, c: NSColor) in
            let s = Dibujo.texto(t, 18, c)
            let w = s.size().width
            s.draw(at: CGPoint(x: (ancho - w) / 2, y: alto / 2))
        }
        if p.fallo {
            centrado(TextosPase.noSePudo, TonoPase.texto)
            return
        }
        guard let archivo = p.archivo else {
            centrado(TextosPase.preparando, TonoPase.apagado)
            return
        }
        if p.estado.negro { return }
        let caja = CuentasDiapositivas.encajarEntera(archivo.tamano, en: bounds.size)
        let nueva = p.fotos[p.estado.actual]
        if let (vieja, capas) = p.fotograma() {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: caja).addClip()
            for c in capas {
                let destino = CuentasDiapositivas.trozo(c.destino, de: caja)
                let origen = CuentasDiapositivas.trozo(c.origen, de: CGRect(x: 0, y: 0, width: 1, height: 1))
                switch c.fuente {
                case .vieja: Dibujo.imagen(vieja, en: destino, recorte: origen, alfa: CGFloat(c.alfa))
                case .nueva:
                    if let nueva { Dibujo.imagen(nueva, en: destino, recorte: origen, alfa: CGFloat(c.alfa)) }
                case .negro:
                    NSColor.black.withAlphaComponent(CGFloat(c.alfa)).setFill()
                    destino.fill(using: .sourceOver)
                }
            }
            NSGraphicsContext.restoreGraphicsState()
        } else if let nueva {
            Dibujo.imagen(nueva, en: caja)
        }
        // Las notas abajo (una pantalla, tecla N).
        var suelo = alto
        if p.notasAbajo {
            let margen: CGFloat = 24
            let notas = archivo.notasSiHay(p.estado.actual) ?? nil
            let t = Dibujo.parrafo(notas ?? TextosPase.sinNotas, 20, notas == nil ? TonoPase.apagado : .white)
            let h = Dibujo.alto(t, ancho: ancho - 2 * margen)
            let fh = min(h + 2 * margen, alto * 0.33)
            let franja = CGRect(x: 0, y: alto - fh, width: ancho, height: fh)
            TonoPase.cristal.withAlphaComponent(0.92).setFill()
            franja.fill(using: .sourceOver)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: franja).addClip()
            t.draw(with: CGRect(x: margen, y: franja.minY + margen, width: ancho - 2 * margen, height: fh),
                   options: [.usesLineFragmentOrigin, .usesFontLeading])
            NSGraphicsContext.restoreGraphicsState()
            suelo = franja.minY
        }
        if let aviso = p.avisoVisible {
            let s = Dibujo.texto(aviso, 16, .white)
            let tam = s.size()
            let c = CGRect(x: (ancho - tam.width) / 2 - 16, y: 32, width: tam.width + 32, height: tam.height + 16)
            TonoPase.cristal.withAlphaComponent(0.9).setFill()
            NSBezierPath(roundedRect: c, xRadius: c.height / 2, yRadius: c.height / 2).fill()
            s.draw(at: CGPoint(x: c.minX + 16, y: c.minY + 8))
        }
        guard p.pastillaVisible else { return }
        // La pastilla del movil: anterior, «n / total», siguiente y salir.
        let lado: CGFloat = 44
        let cuenta = Dibujo.texto("\(p.estado.actual + 1) / \(p.estado.total)", 15, .white)
        let tc = cuenta.size()
        let total = lado * 3 + tc.width + 30
        let c = CGRect(x: (ancho - total) / 2, y: suelo - lado - 28, width: total, height: lado)
        TonoPase.cristal.withAlphaComponent(0.86).setFill()
        NSBezierPath(roundedRect: c, xRadius: lado / 2, yRadius: lado / 2).fill()
        var x = c.minX + 6
        let boton = { (icono: String, activo: Bool, mando: MandoDiapositiva, x: CGFloat) in
            let zona = CGRect(x: x, y: c.minY, width: lado, height: lado)
            Dibujo.icono(icono, en: zona.insetBy(dx: 13, dy: 13), color: activo ? .white : NSColor.white.withAlphaComponent(0.35))
            self.botones.append((zona, mando))
        }
        boton("arrow.left", p.estado.puedeAnterior, .anterior, x)
        x += lado
        cuenta.draw(at: CGPoint(x: x + 4, y: c.minY + (lado - tc.height) / 2))
        x += tc.width + 8
        boton("arrow.right", p.estado.puedeSiguiente, .siguiente, x)
        x += lado + 10
        boton("xmark", true, .salir, x)
    }
}

/// **La vista del orador**: la de ahora, la siguiente, las notas, el tiempo
/// que lleva y la hora. Sin botones: se maneja con el teclado (o el mando).
final class VistaOrador: NSView {
    weak var pase: PresentacionDiapositivas?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        TonoPase.fondoOrador.setFill()
        bounds.fill()
        guard let p = pase, let archivo = p.archivo else { return }
        let (ancho, _) = (bounds.width, bounds.height)
        let z = CuentasDiapositivas.zonasOrador(ancho: bounds.width, alto: bounds.height, pagina: archivo.tamano)
        let m: CGFloat = 24
        // Arriba: «3 / 12», el tiempo (grande, en medio) y la hora.
        Dibujo.texto("\(p.estado.actual + 1) / \(max(p.estado.total, 1))", 18, TonoPase.apagado)
            .draw(at: CGPoint(x: m, y: z.cabecera + 8))
        let tiempo = Dibujo.texto(CuentasDiapositivas.cronometro(segundos: p.segundos), 30, .white, peso: .medium)
        tiempo.draw(at: CGPoint(x: (ancho - tiempo.size().width) / 2, y: z.cabecera))
        let reloj = Dibujo.texto(CuentasDiapositivas.hora(Date()), 18, TonoPase.apagado)
        reloj.draw(at: CGPoint(x: ancho - m - reloj.size().width, y: z.cabecera + 8))
        if !p.transiciones {
            let t = Dibujo.texto(TextosPase.transicionesNo, 13, TonoPase.apagado)
            t.draw(at: CGPoint(x: ancho - m - t.size().width, y: z.cabecera + 34))
        }
        // La de ahora.
        if p.estado.negro {
            NSColor.black.setFill()
            z.actual.fill()
        } else if let f = p.fotos[p.estado.actual] {
            Dibujo.imagen(f, en: z.actual)
        } else {
            TonoPase.cristal.setFill()
            z.actual.fill()
        }
        // La siguiente (la misma imagen ya pintada, en pequeno).
        Dibujo.texto(TextosPase.siguiente, 15, TonoPase.apagado)
            .draw(at: CGPoint(x: z.siguiente.minX, y: z.siguiente.minY - z.rotulo + 4))
        if p.estado.actual + 1 < p.estado.total, let f = p.fotos[p.estado.actual + 1] {
            Dibujo.imagen(f, en: z.siguiente)
        } else {
            TonoPase.cristal.setFill()
            z.siguiente.fill()
            if p.estado.actual + 1 >= p.estado.total {
                let t = Dibujo.texto(TextosPase.fin, 15, TonoPase.apagado)
                let s = t.size()
                t.draw(at: CGPoint(x: z.siguiente.midX - s.width / 2, y: z.siguiente.midY - s.height / 2))
            }
        }
        // Las notas.
        Dibujo.texto(TextosPase.notas, 15, TonoPase.apagado)
            .draw(at: CGPoint(x: z.notas.minX, y: z.notas.minY - z.rotulo + 4))
        if z.notas.height > 0 {
            let n = archivo.notasSiHay(p.estado.actual) ?? nil
            let t = Dibujo.parrafo(n ?? TextosPase.sinNotas, 22, n == nil ? TonoPase.apagado : TonoPase.texto)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: z.notas).addClip()
            t.draw(with: z.notas, options: [.usesLineFragmentOrigin, .usesFontLeading])
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}

/// Una ventana sin marco que si recibe el teclado y se lo pasa al pase.
final class VentanaPase: NSWindow {
    weak var pase: PresentacionDiapositivas?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if pase?.tecla(event) == true { return }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // ⌘W y ⌘. salen, como ⎋.
        let m = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if m == .command, ["w", "."].contains(event.charactersIgnoringModifiers ?? "") {
            pase?.mandar(.salir)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        pase?.mandar(.salir)
    }
}

// MARK: - La presentacion

/// **Una presentacion en marcha**: sus ventanas, por donde va y lo pintado.
@MainActor
final class PresentacionDiapositivas: NSObject {
    let url: URL
    private(set) var archivo: ArchivoDiapositivas?
    private(set) var fallo = false
    private(set) var estado = PaseDiapositivas()
    /// Las diapositivas ya pintadas: la que se ve y las de al lado.
    private(set) var fotos: [Int: CGImage] = [:]
    private(set) var transiciones = true
    private(set) var notasAbajo = false
    private var pidiendo: Set<Int> = []
    private var vista = 0
    private var visibleDesde = CACurrentMediaTime()
    private var empezo = CACurrentMediaTime()
    private var enCurso: (vieja: CGImage, efecto: EfectoDiapositiva, ms: UInt32, empezo: CFTimeInterval)?
    private var aviso: (texto: String, hasta: CFTimeInterval)?
    private var pastillaHasta = CACurrentMediaTime() + CuentasDiapositivas.segundosPastilla

    private let ventana: VentanaPase
    let lienzo = VistaPase()
    private var orador: (ventana: VentanaPase, vista: VistaOrador)?
    private let cola = DispatchQueue(label: "pixpin.diapositivas", qos: .userInteractive)
    private var enlace: CADisplayLink?
    private var reloj: Timer?
    private var avance: Timer?
    private var esconder: Timer?
    private var vigias: [NSObjectProtocol] = []
    private var cerrada = false
    var alSalir: ((Int) -> Void)?

    var segundos: Int { Int(CACurrentMediaTime() - empezo) }
    var pastillaVisible: Bool { estado.pastilla && pastillaHasta > CACurrentMediaTime() }
    var avisoVisible: String? {
        guard let a = aviso, a.hasta > CACurrentMediaTime() else { return nil }
        return a.texto
    }

    init(url: URL, desde: Int) {
        self.url = url
        let pantallas = NSScreen.screens
        let reparto = CuentasDiapositivas.repartir(pantallas: pantallas.count, principal: 0)
        let pantalla = reparto.map { pantallas[$0.presentacion] } ?? NSScreen.main
        let marco = pantalla?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        ventana = VentanaPase(contentRect: marco, styleMask: [.borderless], backing: .buffered, defer: false)
        super.init()
        estado.actual = max(desde, 0)
        vista = estado.actual
        ventana.setFrame(marco, display: false)
        montar(ventana, lienzo)
        lienzo.pase = self
        // Encima de la barra de menus y del Dock mientras PixPin esta
        // delante; al irse a otra app, a su sitio (que no tape lo demas).
        ventana.level = PresentacionDiapositivas.nivel
        ventana.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        ventana.backgroundColor = .black
        ventana.title = url.deletingPathExtension().lastPathComponent
        if let o = reparto?.orador {
            // La vista del orador, en la pantalla del portatil (sin tapar la
            // barra de menus ni el Dock: es una ventana normal).
            let v = VentanaPase(contentRect: pantallas[o].visibleFrame, styleMask: [.borderless],
                                backing: .buffered, defer: false)
            v.setFrame(pantallas[o].visibleFrame, display: false)
            let vo = VistaOrador()
            montar(v, vo)
            vo.pase = self
            v.backgroundColor = TonoPase.fondoOrador
            v.title = ventana.title
            orador = (v, vo)
        }
    }

    private static let nivel = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)

    private func montar(_ v: VentanaPase, _ contenido: NSView) {
        v.pase = self
        v.isReleasedWhenClosed = false
        v.hasShadow = false
        v.isOpaque = true
        v.acceptsMouseMovedEvents = true
        v.contentView = contenido
    }

    /// Sale a pantalla y abre el documento detras.
    func empezar() {
        NSApp.activate()
        ventana.makeKeyAndOrderFront(nil)
        if let o = orador {
            o.ventana.makeKeyAndOrderFront(nil)
            o.ventana.makeFirstResponder(o.vista)
        } else {
            ventana.makeFirstResponder(lienzo)
        }
        let centro = NotificationCenter.default
        vigias.append(centro.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.ventana.level = .normal }
        })
        vigias.append(centro.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.ventana.level = PresentacionDiapositivas.nivel }
        })
        vigias.append(centro.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.ajustarAPantallas() }
        })
        // El reloj del orador (cada segundo) y lo que se va solo.
        let r = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.orador?.vista.needsDisplay = true }
        }
        RunLoop.main.add(r, forMode: .common)
        reloj = r
        programarEsconder()
        let url = self.url
        cola.async { [weak self] in
            let a = ArchivoDiapositivas.abrir(url)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.abierto(a) }
            }
        }
    }

    func abierto(_ a: ArchivoDiapositivas?) {
        guard !cerrada else { return }
        guard let a else {
            fallo = true
            redibujar()
            return
        }
        archivo = a
        estado.total = a.total
        estado.actual = min(estado.actual, a.total - 1)
        vista = estado.actual
        visibleDesde = CACurrentMediaTime()
        empezo = visibleDesde
        pedirFotos()
        programarAvance()
        redibujar()
    }

    /// Si se conecta o se quita una pantalla: la presentacion ocupa la suya.
    private func ajustarAPantallas() {
        guard let s = ventana.screen ?? NSScreen.main else { return }
        ventana.setFrame(s.frame, display: true)
        fotos.removeAll()
        pedirFotos()
    }

    // MARK: Mandos

    func tecla(_ e: NSEvent) -> Bool {
        let m = e.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function, .shift])
        guard m.isEmpty, let mando = CuentasDiapositivas.mando(
            tecla: e.keyCode, caracteres: e.charactersIgnoringModifiers ?? "",
            mayusculas: e.modifierFlags.contains(.shift)) else { return false }
        NSCursor.setHiddenUntilMouseMoves(true)
        mandar(mando)
        return true
    }

    func mandar(_ m: MandoDiapositiva) {
        switch m {
        case .pastilla:
            // En el medio: esconder o ensenar ya, sin esperar.
            estado.pastilla = !pastillaVisible
            pastillaHasta = estado.pastilla ? .infinity : 0
            redibujar()
            return
        case .notas:
            // Con la vista del orador las notas ya estan alli.
            if orador == nil { notasAbajo.toggle() }
            redibujar()
            return
        case .transiciones:
            transiciones.toggle()
            aviso = (transiciones ? TextosPase.transicionesSi : TextosPase.transicionesNo,
                     CACurrentMediaTime() + CuentasDiapositivas.segundosAviso)
            programarEsconder()
            redibujar()
            return
        default: break
        }
        if !estado.aplicar(m) {
            terminar()
            return
        }
        alCambiar()
        redibujar()
    }

    func ensenarPastilla() {
        guard estado.pastilla else { return }
        pastillaHasta = CACurrentMediaTime() + CuentasDiapositivas.segundosPastilla
        programarEsconder()
        lienzo.needsDisplay = true
    }

    /// Un clic en un video o un audio lo reproduce. `true` si habia uno.
    func reproducirMedio(en p: CGPoint, caja tam: CGSize) -> Bool {
        guard let a = archivo, !estado.negro, estado.total > 0 else { return false }
        let caja = CuentasDiapositivas.encajarEntera(a.tamano, en: tam)
        let k = caja.width / max(a.tamano.width, 1)
        let (px, py) = (Float((p.x - caja.minX) / k), Float((p.y - caja.minY) / k))
        guard let m = a.medios(estado.actual).first(where: {
            px >= $0.x && px <= $0.x + $0.ancho && py >= $0.y && py <= $0.y + $0.alto
        }) else { return false }
        let url = self.url
        cola.async {
            let f = a.fichero(de: m, origen: url)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let f else { return NSSound.beep() }
                    if m.audio {
                        ReproductorVoz.compartido.alternar(f.path, url: f, titulo: f.lastPathComponent)
                    } else {
                        NSWorkspace.shared.open(f)
                    }
                }
            }
        }
        return true
    }

    // MARK: Pasar

    /// La diapositiva cambio: con transicion si toca, la siguiente pintada
    /// y el pase solo programado.
    private func alCambiar() {
        guard estado.actual != vista else { return }
        let antes = vista
        vista = estado.actual
        let ahora = CACurrentMediaTime()
        visibleDesde = ahora
        enCurso = nil
        if let a = archivo, !estado.negro {
            let t = a.transicion(estado.actual)
            if CuentasDiapositivas.tocaTransicion(antes: antes, ahora: estado.actual, encendidas: transiciones, ms: t?.ms),
               let t, let vieja = fotos[antes] {
                enCurso = (vieja, t.efecto, t.ms, ahora)
                visibleDesde = ahora + Double(t.ms) / 1000
                arrancarEnlace()
            }
        }
        pedirFotos()
        programarAvance()
    }

    /// El fotograma de la transicion en curso: la de antes y sus capas.
    func fotograma() -> (CGImage, [CapaDiapositiva])? {
        guard let c = enCurso else { return nil }
        let t = CuentasDiapositivas.progreso(transcurrido: CACurrentMediaTime() - c.empezo, ms: c.ms)
        if t >= 1 { return nil }
        return (c.vieja, capasDeTransicion(efecto: c.efecto, t: t))
    }

    private func arrancarEnlace() {
        guard enlace == nil else { return }
        let e = lienzo.displayLink(target: self, selector: #selector(PresentacionDiapositivas.fotogramaSiguiente))
        e.add(to: .main, forMode: .common)
        enlace = e
    }

    @objc private func fotogramaSiguiente() {
        lienzo.needsDisplay = true
        if let c = enCurso, CACurrentMediaTime() - c.empezo >= Double(c.ms) / 1000 {
            enCurso = nil
        }
        if enCurso == nil {
            enlace?.invalidate()
            enlace = nil
        }
    }

    /// Paso sola si la diapositiva lo pide (`advTm`), contando desde que
    /// acabo de entrar.
    private func programarAvance() {
        avance?.invalidate()
        avance = nil
        guard let a = archivo, estado.total > 0, estado.puedeSiguiente,
              let ms = a.transicion(estado.actual)?.avanceMs else { return }
        let espera = max(visibleDesde + Double(ms) / 1000 - CACurrentMediaTime(), 0)
        let i = estado.actual
        let r = Timer(timeInterval: espera, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.estado.actual == i, !self.estado.negro else { return }
                self.mandar(.siguiente)
            }
        }
        RunLoop.main.add(r, forMode: .common)
        avance = r
    }

    /// Repinta cuando la pastilla o el aviso se van solos.
    private func programarEsconder() {
        esconder?.invalidate()
        let ahora = CACurrentMediaTime()
        let cuando = [pastillaHasta, aviso?.hasta ?? 0].filter { $0 > ahora && $0.isFinite }.min()
        guard let cuando else { return }
        let r = Timer(timeInterval: cuando - ahora + 0.02, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.lienzo.needsDisplay = true
                self?.programarEsconder()
            }
        }
        RunLoop.main.add(r, forMode: .common)
        esconder = r
    }

    // MARK: Pintar

    /// Pide la que se ve y las de al lado (para que pasar sea al momento y
    /// el orador vea la siguiente); suelta las lejanas.
    private func pedirFotos() {
        guard let a = archivo, estado.total > 0 else { return }
        let i = estado.actual
        fotos = fotos.filter { abs($0.key - i) <= 1 }
        let escala = ventana.backingScaleFactor
        let caja = CuentasDiapositivas.encajarEntera(a.tamano, en: lienzo.bounds.size)
        let pixeles = CGSize(width: caja.width * escala, height: caja.height * escala)
        for j in [i, i + 1, i - 1] where j >= 0 && j < estado.total && fotos[j] == nil && !pidiendo.contains(j) {
            pidiendo.insert(j)
            cola.async { [weak self] in
                let f = a.foto(j, pixeles: pixeles)
                // Las notas y la transicion de la siguiente, de paso.
                _ = a.notas(j)
                _ = a.transicion(j)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self, !self.cerrada else { return }
                        self.pidiendo.remove(j)
                        if let f, abs(j - self.estado.actual) <= 1 { self.fotos[j] = f }
                        self.redibujar()
                    }
                }
            }
        }
    }

    private func redibujar() {
        lienzo.needsDisplay = true
        orador?.vista.needsDisplay = true
    }

    // MARK: Salir

    func terminar() {
        guard !cerrada else { return }
        cerrada = true
        for t in [reloj, avance, esconder] { t?.invalidate() }
        enlace?.invalidate()
        enlace = nil
        vigias.forEach(NotificationCenter.default.removeObserver)
        vigias = []
        ventana.orderOut(nil)
        orador?.ventana.orderOut(nil)
        ventana.close()
        orador?.ventana.close()
        alSalir?(vista)
        Diapositivas.soltar(self)
    }
}

// MARK: - La entrada

/// **Presentar un PowerPoint**: lo que piden el boton y F5 del lector, el
/// pin de Office y el menu de la burbuja.
@MainActor
public enum Diapositivas {
    private static var actual: PresentacionDiapositivas?

    /// Si este fichero se presenta aqui.
    public static func sePresenta(_ url: URL) -> Bool {
        CuentasDiapositivas.sePresenta(url)
    }

    /// Presenta `url` desde la diapositiva `desde` (desde 0). Al salir,
    /// `alSalir` recibe la ultima que se vio. Si ya habia una, se cierra.
    public static func presentar(_ url: URL, desde: Int = 0, alSalir: ((Int) -> Void)? = nil) {
        actual?.terminar()
        guard FileManager.default.fileExists(atPath: url.path) else {
            NSSound.beep()
            return
        }
        let p = PresentacionDiapositivas(url: url, desde: desde)
        p.alSalir = alSalir
        actual = p
        p.empezar()
    }

    fileprivate static func soltar(_ p: PresentacionDiapositivas) {
        if actual === p { actual = nil }
    }
}
