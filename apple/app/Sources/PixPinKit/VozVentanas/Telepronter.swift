// **El telepronter: el texto baja solo y uno lo lee en voz alta, grabandose**
// (tanda E5). Es `teleprompter.rs` de Windows y `TelepronterActivity.kt` del
// movil, donde se llama «leer en voz alta». No hay voz sintetica: lee el
// usuario y el Mac graba.
//
// La nota que sale **ya trae su texto con minutos** sin pasar por ningun
// reconocedor: como el texto baja a una velocidad conocida, se sabe en que
// segundo cada parrafo cruzo la franja de lectura (`Desfile`, la cuenta de
// `pixpin_voz::telepronter`, copiada aqui con sus pruebas). Entra en el chat
// como `VOZ` con `transcripcion` y `estadoDelTexto = bien`.
//
// La ventana, como en Windows: **en la otra pantalla y a pantalla completa**
// (la del chat queda libre; con una sola, en esa). Arriba ← y el reloj de la
// grabacion; en medio el texto con su franja; abajo A−/A+, −/+ (la velocidad
// dicha con palabras), la raya de lo leido, «Ensayar», «Grabar» y, grabando,
// «Pausa» y «Tirar». Tres, dos, uno antes de grabar.
//
// Teclado: Esc cierra (tira lo grabado), Espacio pausa o ensaya, Intro graba
// o termina, ← → la velocidad, ↑ ↓ un renglon, + − la letra, RePag/AvPag
// media pantalla. La rueda es la velocidad.
//
// Rendimiento: el texto se mide una vez por letra y ancho, y solo se pintan
// los parrafos que se ven. El reloj (40 por segundo) solo corre mientras el
// texto se mueve o se cuenta; quieto, no hay temporizador.

import AppKit
import PixPinCore
import SwiftUI

// MARK: - La cuenta (pura)

/// Un parrafo ya medido: donde empieza en la columna sin desplazar y cuanto
/// ocupa.
struct MedidaParrafo: Equatable {
    var cima: CGFloat
    var alto: CGFloat
}

/// **El desfile** (`pixpin_voz::telepronter::Desfile`): por donde va el
/// texto y en que milisegundo cruzo cada parrafo la linea de lectura. No
/// sabe nada de letras: quien pinta mide y se lo da.
struct Desfile: Equatable {
    private(set) var medidas: [MedidaParrafo] = []
    /// En que milisegundo cruzo cada parrafo; -1 es «todavia no».
    private var tiempos: [Int64]
    /// Cuanto se ha desplazado el texto hacia arriba.
    var y: CGFloat = 0
    private var altoTotal: CGFloat = 0
    private var altoVisible: CGFloat = 0

    init(parrafos: Int) {
        tiempos = Array(repeating: -1, count: parrafos)
    }

    /// Lo que mide cada parrafo y cuanto se ve. Si cambio el numero de
    /// parrafos, los minutos de antes ya no son de nadie.
    mutating func medir(_ m: [MedidaParrafo], altoVisible: CGFloat) {
        altoTotal = max(m.last.map { $0.cima + $0.alto } ?? 0, 0)
        self.altoVisible = max(altoVisible, 0)
        if m.count != tiempos.count { tiempos = Array(repeating: -1, count: m.count) }
        medidas = m
        y = acotar(y)
    }

    /// Solo cambia cuanto se ve, sin volver a medir.
    mutating func ajustarVentana(_ alto: CGFloat) {
        altoVisible = max(alto, 0)
        y = acotar(y)
    }

    func medida(_ i: Int) -> MedidaParrafo? { medidas.indices.contains(i) ? medidas[i] : nil }

    /// Hasta donde se puede bajar: el final del texto se queda a la vista.
    var tope: CGFloat { max(altoTotal - altoVisible, 0) }

    private func acotar(_ y: CGFloat) -> CGFloat { min(max(y, 0), tope) }

    /// Donde cae la linea de lectura, desde arriba de lo que se ve.
    var lineaDeLectura: CGFloat { altoVisible * Telepronter.franja }

    /// Baja lo que toque en `segundos` a esa velocidad. `true` cuando ya no
    /// hay mas que bajar (lo que para el ensayo solo).
    @discardableResult
    mutating func avanzar(_ segundos: Double, velocidad: CGFloat) -> Bool {
        y = acotar(y + Telepronter.acotarVelocidad(velocidad) * CGFloat(max(segundos, 0)))
        return y >= tope
    }

    /// Mueve el texto a mano: cuenta igual que el desfile.
    mutating func empujar(_ puntos: CGFloat) { y = acotar(y + puntos) }

    /// Arriba y sin minutos: lo que hace empezar a grabar.
    mutating func reiniciar() {
        y = 0
        tiempos = Array(repeating: -1, count: tiempos.count)
    }

    /// Apunta, en `ms`, los parrafos que ya cruzaron la linea y no tenian
    /// minuto. Solo la primera vez: volver a subir no se lo quita.
    mutating func apuntar(_ ms: Int64) {
        let linea = lineaDeLectura
        for (i, m) in medidas.enumerated() where tiempos[i] < 0 && m.cima - y <= linea {
            tiempos[i] = max(ms, 0)
        }
    }

    /// El minuto de un parrafo, o `nil` si todavia no cruzo.
    func tiempo(_ i: Int) -> Int64? {
        tiempos.indices.contains(i) && tiempos[i] >= 0 ? tiempos[i] : nil
    }

    /// Los parrafos que se ven ahora (solo esos se pintan).
    var visibles: Range<Int> {
        let arriba = y, abajo = y + altoVisible
        let primero = medidas.firstIndex { $0.cima + $0.alto > arriba } ?? medidas.count
        let ultimo = (medidas.lastIndex { $0.cima < abajo }).map { $0 + 1 } ?? primero
        return primero..<max(ultimo, primero)
    }

    /// El texto que se guarda: cada parrafo con su minuto, separados por un
    /// renglon en blanco. Lo que no llego a cruzar se queda con el final.
    func cuerpo(_ parrafos: [String], duracionMs: Int64) -> String {
        parrafos.enumerated().map { i, p in
            let ms = min(tiempo(i) ?? duracionMs, max(duracionMs, 0))
            return "[\(FormatoVoz.marca(ms: ms))] \(p)"
        }.joined(separator: "\n\n")
    }
}

/// Las constantes y lo puro del telepronter.
enum Telepronter {
    /// A que altura esta la linea de lectura (`FRANJA`).
    static let franja: CGFloat = 0.3
    static let cuentaAtras = 3
    /// Lo que dura cada numero de la cuenta: «un segundo escaso».
    static let msPorNumero = 900
    static let velocidadMinima: CGFloat = 10
    static let velocidadMaxima: CGFloat = 150
    static let velocidadPorDefecto: CGFloat = 45
    static let tamanoMinimo: CGFloat = 16
    static let tamanoMaximo: CGFloat = 48
    static let tamanoPorDefecto: CGFloat = 28

    static func acotarVelocidad(_ v: CGFloat) -> CGFloat { min(max(v, velocidadMinima), velocidadMaxima) }
    static func acotarTamano(_ t: CGFloat) -> CGFloat { min(max(t, tamanoMinimo), tamanoMaximo) }

    /// La velocidad dicha con palabras: un «45» no significa nada.
    static func palabra(deVelocidad v: CGFloat) -> String {
        switch v {
        case ..<30: "muy lenta"
        case ..<55: "lenta"
        case ..<85: "normal"
        case ..<115: "rápida"
        default: "muy rápida"
        }
    }

    /// **El texto en parrafos para leer** (`parrafos_de`): fuera las marcas
    /// de Markdown que no se leen (`#`, `**`, `>`, vinetas, imagenes) y
    /// partido por lineas en blanco; las lineas de un parrafo se juntan.
    static func parrafos(de texto: String) -> [String] {
        var bloques: [[Substring]] = []
        var actual: [Substring] = []
        for linea in texto.split(separator: "\n", omittingEmptySubsequences: false) {
            if linea.trimmingCharacters(in: .whitespaces).isEmpty {
                if !actual.isEmpty { bloques.append(actual); actual = [] }
            } else {
                actual.append(linea)
            }
        }
        if !actual.isEmpty { bloques.append(actual) }
        return bloques.compactMap { bloque in
            let limpio = bloque
                .filter { !$0.drop { $0 == " " || $0 == "\t" }.hasPrefix("![") }
                .map { l -> String in
                    let sin = l.drop { "# >-*".contains($0) }
                    return String(sin).replacingOccurrences(of: "**", with: "")
                        .replacingOccurrences(of: "__", with: "")
                        .replacingOccurrences(of: "`", with: "")
                        .trimmingCharacters(in: .whitespaces)
                }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            return limpio.isEmpty ? nil : limpio
        }
    }

    /// **En que pantalla se lee** (`monitor_para_leer`): una que no sea la
    /// del chat, prefiriendo la principal (suele tener la camara encima);
    /// con una sola, esa. `nil` si no se sabe donde esta el chat.
    static func pantallaParaLeer(_ areas: [CGRect], principal: Int, juntoA: CGRect?) -> Int? {
        guard let juntoA else { return nil }
        let otras = areas.indices.filter { areas[$0] != juntoA }
        if otras.contains(principal) { return principal }
        return otras.first ?? areas.firstIndex(of: juntoA)
    }
}

/// Lo que sale de una lectura: lo que va al mensaje de voz.
struct LecturaTelepronter {
    var nota: NotaGrabada
    /// `[m:ss] parrafo`, para `transcripcion`.
    var cuerpo: String
}

// MARK: - El modelo

@MainActor
final class ModeloTelepronter: ObservableObject {
    enum Fase: Equatable { case parado, ensayando, contando, grabando }

    let parrafos: [String]
    /// El desfile no se publica: cambia 40 veces por segundo y lo pinta su
    /// vista; se publica el fotograma.
    var desfile: Desfile
    @Published var velocidad = Telepronter.velocidadPorDefecto
    @Published var tamano = Telepronter.tamanoPorDefecto
    @Published private(set) var fase = Fase.parado
    @Published private(set) var pausado = false
    @Published private(set) var cuenta = 0
    @Published private(set) var fotograma = 0
    let aviso = AvisoCorto()

    private let mic = MicrofonoSuelto()
    private var abriendo: Task<Void, Never>?
    private var falloAlAbrir: String?
    private var cuentaHasta = Date()
    private var reloj: Timer?
    private var ultimo = Date()
    private(set) var inicio = Date()
    /// Con que letra y que ancho se midio lo que hay en el desfile.
    private var medidoCon: (CGFloat, CGFloat) = (0, 0)
    /// Lo que se acumula de la rueda del trackpad hasta un paso.
    private var rueda: CGFloat = 0
    var alTerminar: ((LecturaTelepronter) -> Void)?
    var cerrar: (() -> Void)?

    init(parrafos: [String]) {
        self.parrafos = parrafos
        desfile = Desfile(parrafos: parrafos.count)
    }

    // MARK: Medir

    /// Mide los parrafos si cambio la letra o el ancho (lo llama quien
    /// pinta, con su caja).
    func medir(ancho: CGFloat, alto: CGFloat) {
        let columna = max(ancho - Self.margen(ancho) * 2, 40)
        guard medidoCon != (tamano, columna) else {
            desfile.ajustarVentana(alto)
            return
        }
        let atributos = Self.atributos(tamano, color: .white)
        var y: CGFloat = 0
        let medidas = parrafos.map { p -> MedidaParrafo in
            let alto = (p as NSString).boundingRect(
                with: CGSize(width: columna, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: atributos
            ).height.rounded(.up)
            defer { y += alto + tamano * 0.9 }
            return MedidaParrafo(cima: y, alto: alto)
        }
        desfile.medir(medidas, altoVisible: alto)
        medidoCon = (tamano, columna)
    }

    /// Una columna estrecha se lee de un vistazo.
    static func margen(_ ancho: CGFloat) -> CGFloat { max(ancho * 0.16, 24) }

    static func atributos(_ tamano: CGFloat, color: NSColor) -> [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: tamano, weight: .regular), .foregroundColor: color]
    }

    // MARK: Hacer

    func ensayar() {
        switch fase {
        case .ensayando: fase = .parado
        case .parado: fase = .ensayando
        case .grabando, .contando: break
        }
        armar()
    }

    /// Espacio: grabando, para el texto y deja correr la grabacion.
    func pausa() {
        if fase == .grabando { pausado.toggle() } else { ensayar() }
        armar()
    }

    func grabar() {
        pausado = false
        guard fase != .grabando, fase != .contando else { return }
        fase = .contando
        cuenta = Telepronter.cuentaAtras
        cuentaHasta = Date().addingTimeInterval(Double(Telepronter.msPorNumero) / 1000)
        // El microfono se abre ya: tarda y asi esta listo al llegar a cero.
        falloAlAbrir = nil
        let fichero = Ventanita.carpeta("telepronter").appendingPathComponent("lectura-\(Ventanita.ahoraMs).m4a")
        abriendo = Task { [weak self] in
            guard let self else { return }
            do { try await self.mic.empezar(en: fichero) } catch { self.falloAlAbrir = MicrofonoSuelto.explicar(error) }
            self.abriendo = nil
        }
        armar()
    }

    func tirar() {
        mic.cancelar()
        fase = .parado
        pausado = false
        desfile.reiniciar()
        armar()
    }

    func terminar() {
        guard fase == .grabando else { return }
        fase = .parado
        armar()
        Task {
            guard let nota = await mic.parar() else { return }
            guard nota.duracionMs >= FormatoVoz.minimoMs else {
                try? FileManager.default.removeItem(at: nota.url)
                aviso.decir("La lectura salió demasiado corta")
                return
            }
            alTerminar?(LecturaTelepronter(nota: nota, cuerpo: desfile.cuerpo(parrafos, duracionMs: nota.duracionMs)))
            cerrar?()
        }
    }

    func cambiarVelocidad(_ paso: CGFloat) {
        velocidad = Telepronter.acotarVelocidad(velocidad + paso)
    }

    func cambiarLetra(_ paso: CGFloat) {
        tamano = Telepronter.acotarTamano(tamano + paso)
        fotograma &+= 1
    }

    func empujar(_ puntos: CGFloat) {
        desfile.empujar(puntos)
        if fase == .grabando { desfile.apuntar(mic.llevadoMs) }
        fotograma &+= 1
    }

    /// Al cerrar: lo grabado se tira y el reloj se para.
    func soltar() {
        reloj?.invalidate()
        reloj = nil
        abriendo?.cancel()
        mic.cancelar()
    }

    // MARK: El reloj

    /// Pone o quita el reloj segun la fase: quieto, nada corre.
    private func armar() {
        let corre = fase != .parado
        if corre, reloj == nil {
            ultimo = Date()
            let t = Timer(timeInterval: 1.0 / 40, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.latir() }
            }
            RunLoop.main.add(t, forMode: .common)
            reloj = t
        } else if !corre {
            reloj?.invalidate()
            reloj = nil
        }
        fotograma &+= 1
    }

    private func latir() {
        let ahora = Date()
        let segundos = ahora.timeIntervalSince(ultimo)
        ultimo = ahora
        if fase == .contando, ahora >= cuentaHasta {
            if cuenta > 1 {
                cuenta -= 1
                cuentaHasta = ahora.addingTimeInterval(Double(Telepronter.msPorNumero) / 1000)
            } else {
                cuenta = 0
                grabarYa(ahora)
            }
        }
        let baja = fase == .ensayando || (fase == .grabando && !pausado)
        if baja, desfile.avanzar(segundos, velocidad: velocidad), fase == .ensayando {
            fase = .parado
            armar()
        }
        // El minuto es el del audio (lo grabado de verdad), no el del reloj.
        if fase == .grabando { desfile.apuntar(mic.llevadoMs) }
        fotograma &+= 1
    }

    /// Al llegar a cero: graba si el microfono ya esta; si aun se abre, se
    /// vuelve a mirar en el siguiente latido.
    private func grabarYa(_ ahora: Date) {
        if mic.grabando {
            inicio = ahora
            desfile.reiniciar()
            fase = .grabando
        } else if let falloAlAbrir {
            // Que no se pueda grabar es normal (otra app tiene el
            // microfono, el permiso esta quitado): se dice en el acto.
            fase = .parado
            aviso.decir(falloAlAbrir)
            armar()
        }
    }

    /// La rueda es la velocidad: lo que se toca sin mirar mientras se lee.
    func rodar(_ e: NSEvent) {
        let d = e.hasPreciseScrollingDeltas ? e.scrollingDeltaY / 12 : e.scrollingDeltaY
        rueda += d
        while abs(rueda) >= 1 {
            let paso: CGFloat = rueda > 0 ? 1 : -1
            cambiarVelocidad(paso * 5)
            rueda -= paso
        }
    }

    // MARK: Teclado

    func tecla(_ e: NSEvent, abajo: Bool, altoPantalla: CGFloat) -> Bool {
        guard abajo else { return false }
        switch e.keyCode {
        case TeclaVoz.escape: cerrar?()
        case TeclaVoz.espacio: if !e.isARepeat { pausa() }
        case TeclaVoz.intro, TeclaVoz.introNumerico: if !e.isARepeat { fase == .grabando ? terminar() : grabar() }
        case TeclaVoz.derecha: cambiarVelocidad(5)
        case TeclaVoz.izquierda: cambiarVelocidad(-5)
        case TeclaVoz.abajo: empujar(tamano * 1.45)
        case TeclaVoz.arriba: empujar(-tamano * 1.45)
        case TeclaVoz.avPag: empujar(altoPantalla * 0.5)
        case TeclaVoz.rePag: empujar(-altoPantalla * 0.5)
        default:
            switch TeclaVoz.letra(e) {
            case "+", "=": cambiarLetra(2)
            case "-": cambiarLetra(-2)
            default: return false
            }
        }
        return true
    }
}

// MARK: - La vista

struct VistaTelepronter: View {
    @ObservedObject var m: ModeloTelepronter
    @ObservedObject private var aviso: AvisoCorto

    init(m: ModeloTelepronter) {
        self.m = m
        aviso = m.aviso
    }

    var body: some View {
        VStack(spacing: 0) {
            barra
            LienzoDesfile(m: m, fotograma: m.fotograma, tamano: m.tamano)
                .overlay(alignment: .bottomLeading) {
                    if let t = aviso.texto {
                        Text(t).font(.system(size: 15)).foregroundStyle(ColoresVoz.dorado)
                            .padding(.leading, 40).padding(.bottom, 12)
                    }
                }
            pie
        }
        .background(ColoresVoz.fondo)
        .overlay { if m.fase == .contando, m.cuenta > 0 { cuenta } }
    }

    private var barra: some View {
        HStack(spacing: 12) {
            BotonVentanita("←", ancho: 44) { m.cerrar?() }
            if m.fase == .grabando {
                TimelineView(.periodic(from: m.inicio, by: 1)) { c in
                    Text("● \(FormatoVoz.marca(ms: Int64(c.date.timeIntervalSince(m.inicio) * 1000)))")
                        .foregroundStyle(ColoresVoz.rojo)
                }
                .font(.system(size: 17).monospacedDigit())
            } else {
                Text("Leer en voz alta").font(.system(size: 17)).foregroundStyle(ColoresVoz.texto)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 56)
        .background(ColoresVoz.cristal)
    }

    private var pie: some View {
        let tope = m.desfile.tope
        let leido = tope > 0 ? min(max(m.desfile.y / tope, 0), 1) : 0
        return HStack(spacing: 6) {
            BotonVentanita("A-", ancho: 44) { m.cambiarLetra(-2) }
            BotonVentanita("A+", ancho: 44) { m.cambiarLetra(2) }
            BotonVentanita("−", ancho: 44) { m.cambiarVelocidad(-5) }
            BotonVentanita("+", ancho: 44) { m.cambiarVelocidad(5) }
            Text("velocidad y letra · \(Telepronter.palabra(deVelocidad: m.velocidad))")
                .font(.system(size: 14)).foregroundStyle(ColoresVoz.apagado).padding(.leading, 8)
            Spacer()
            if m.fase == .grabando {
                BotonVentanita(m.pausado ? "Seguir" : "Pausa", ancho: 150) { m.pausa() }
                BotonVentanita("Tirar", ancho: 150) { m.tirar() }
                BotonVentanita("Terminar", color: ColoresVoz.rojo, ancho: 150) { m.terminar() }
            } else {
                BotonVentanita(m.fase == .ensayando ? "Parar" : "Ensayar", ancho: 150) { m.ensayar() }
                BotonVentanita("Grabar", color: ColoresVoz.rojo, ancho: 150) { m.grabar() }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 76)
        .background(ColoresVoz.cristal)
        // Cuanto texto queda, en una raya fina encima de los mandos.
        .overlay(alignment: .topLeading) {
            GeometryReader { g in
                Rectangle().fill(ColoresVoz.dorado).frame(width: g.size.width * leido, height: 3)
            }
        }
    }

    private var cuenta: some View {
        ZStack {
            Color(hex: 0x0C0C10)
            VStack(spacing: 20) {
                Text("\(m.cuenta)").font(.system(size: 96, weight: .regular).monospacedDigit())
                    .foregroundStyle(ColoresVoz.texto)
                Text("Prepárate").font(.system(size: 20)).foregroundStyle(ColoresVoz.apagado)
            }
        }
    }
}

/// El texto que baja, pintado con AppKit: se mide y se pinta con lo mismo
/// (`NSAttributedString`), asi la franja cae donde cae el texto.
struct LienzoDesfile: NSViewRepresentable {
    let m: ModeloTelepronter
    /// Solo para que SwiftUI lo vuelva a pintar.
    let fotograma: Int
    let tamano: CGFloat

    func makeNSView(context: Context) -> VistaDesfile {
        let v = VistaDesfile()
        v.m = m
        return v
    }

    func updateNSView(_ v: VistaDesfile, context: Context) {
        v.needsDisplay = true
    }
}

final class VistaDesfile: NSView {
    weak var m: ModeloTelepronter?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        ColoresVoz.fondoAppKit.setFill()
        bounds.fill()
        guard let m else { return }
        MainActor.assumeIsolated {
            m.medir(ancho: bounds.width, alto: bounds.height)
            let tam = m.tamano
            let d = m.desfile
            // La franja de lectura: donde hay que tener los ojos.
            NSColor(srgbRed: 0x1D / 255, green: 0x27 / 255, blue: 0x33 / 255, alpha: 1).setFill()
            NSRect(x: 0, y: d.lineaDeLectura - tam * 0.35, width: bounds.width, height: tam * 1.5).fill()
            let izquierda = ModeloTelepronter.margen(bounds.width)
            let columna = max(bounds.width - izquierda * 2, 40)
            let claro = NSColor(srgbRed: 0xE4 / 255, green: 0xE2 / 255, blue: 0xE6 / 255, alpha: 1)
            let apagado = NSColor(srgbRed: 0x9A / 255, green: 0x9A / 255, blue: 0xA2 / 255, alpha: 1)
            for i in d.visibles {
                guard let medida = d.medida(i) else { continue }
                let color = d.tiempo(i) == nil ? claro : apagado
                (m.parrafos[i] as NSString).draw(
                    with: NSRect(x: izquierda, y: medida.cima - d.y, width: columna, height: medida.alto),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: ModeloTelepronter.atributos(tam, color: color))
            }
        }
    }
}

// MARK: - Abrir

extension Telepronter {
    /// La ventana abierta (una a la vez, como en Windows).
    @MainActor private static var abierta: VentanaVoz?

    /// Si ya hay uno abierto.
    @MainActor static var abierto: Bool { abierta != nil }

    /// **Abre el telepronter con ese texto** en la otra pantalla, a pantalla
    /// completa. `false` si el texto no tiene nada que leer. La lectura
    /// llega por `alTerminar`; cerrar sin terminar no manda nada.
    @MainActor @discardableResult
    static func abrir(texto: String, alTerminar: @escaping (LecturaTelepronter) -> Void) -> Bool {
        if let abierta {
            abierta.makeKeyAndOrderFront(nil)
            return true
        }
        let parrafos = parrafos(de: texto)
        guard !parrafos.isEmpty else { return false }
        let m = ModeloTelepronter(parrafos: parrafos)
        m.alTerminar = alTerminar
        let pantallas = NSScreen.screens
        let delChat = NSApp.keyWindow?.screen ?? NSScreen.main
        let i = pantallaParaLeer(pantallas.map(\.frame), principal: 0, juntoA: delChat?.frame)
        let pantalla = i.map { pantallas[$0] } ?? NSScreen.main
        let v = VentanaVoz.nueva("Leer en voz alta", tam: NSSize(width: 1280, height: 720),
                                 vista: VistaTelepronter(m: m))
        if let pantalla { v.setFrame(pantalla.frame, display: false) }
        v.collectionBehavior.insert(.fullScreenPrimary)
        v.alTeclear = { [weak v] e, abajo in
            MainActor.assumeIsolated { m.tecla(e, abajo: abajo, altoPantalla: v?.frame.height ?? 800) }
        }
        v.alRodar = { e in MainActor.assumeIsolated { m.rodar(e) }; return true }
        m.cerrar = { [weak v] in v?.close() }
        v.alCerrar = {
            MainActor.assumeIsolated {
                m.soltar()
                abierta = nil
            }
        }
        abierta = v
        v.makeKeyAndOrderFront(nil)
        NSApp.activate()
        v.toggleFullScreen(nil)
        return true
    }
}
