// El asistente del Mac: un chat con el motor que dicen los ajustes
// `[asistente]` (los mismos que Windows, Ajustes → Asistente). Como Windows
// desde el 27-oct-2026 (`f86732c`) y Android, **contesta la nube**: Claude
// Haiku 5.5 o DeepSeek V4.1 Flash con la clave del Llavero, por el HTTPS de
// URLSession (`TransporteHttps`). El modelo local (llama.cpp con Qwen3.5 y
// Gemma, su descarga y sus ajustes) ya no esta; lo que quedo bajado se
// ofrece borrar una vez (`ModelosViejos.swift`).
//
// **Apple Intelligence** (Foundation Models, macOS 26: `MotorApple.swift`)
// es solo del Mac y sigue como la opcion **sin la nube**: contesta cuando
// no hay clave de Claude ni de DeepSeek. Es del sistema (no se baja nada ni
// hay ajustes que tocar) y no sale del Mac. Con la clave guardada contesta
// siempre la nube; si la nube falla, se dice, como en Windows.
//
// Las ordenes simples del camino rapido («apunta pan», «¿que tengo
// pendiente?») se hacen sin modelo y sin clave (`iaEsOrdenRapida`).
//
// Lo que no es Foundation Models va entero por el nucleo de Rust
// (`iaTurno`): el bucle del agente de Windows con pensar (`pensar`: en
// automatico solo las tareas complejas), el plan, la hoja de trabajo de la
// conversacion, el camino rapido y todas las herramientas y acciones (las
// de la app son pedidos del protocolo, `ManosDelAsistente`). En vivo: el
// texto y lo pensado llegan por tandas a un `OyenteIa` y se puede parar
// (`CorteIa`).
//
// Cada turno va en un hilo de GCD (no de Swift Concurrency: puede esperar
// un «Sí»/«No» del usuario sin quitarle hilos al resto de la app).

import AppKit
import Foundation
import ImageIO
import PixPinCore
import UniformTypeIdentifiers

@MainActor
public final class ModeloAsistente: ObservableObject {
    /// Que motor contesta.
    public enum Motor: Equatable, Sendable {
        /// Apple Intelligence: solo sin clave de la nube (lo del Mac).
        case apple
        /// Claude o DeepSeek (su nombre); `conClave` si hay clave guardada.
        case nube(String, conClave: Bool)

        public var nombre: String {
            switch self {
            case .apple: return "Apple Intelligence (en este Mac)"
            case let .nube(n, conClave): return conClave ? n : n + " · falta la clave"
            }
        }

        var esNube: Bool {
            if case .nube = self { return true }
            return false
        }
    }

    /// Una herramienta que se uso (guardable).
    public struct Hecha: Codable, Equatable, Sendable {
        public var nombre: String
        public var ok: Bool
        public var resumen: String
    }

    /// Lo citado de los documentos del usuario (abre el documento).
    public struct Cita: Codable, Equatable, Sendable {
        public var numero: Int
        public var titulo: String
        /// El pedido `abrir` del protocolo (JSON).
        public var pedido: String
    }

    /// Un fichero adjunto a la conversacion.
    public struct Adjunto: Codable, Hashable, Identifiable, Sendable {
        public var id = UUID()
        public var nombre: String
        public var ruta: String

        public var esImagen: Bool {
            ["png", "jpg", "jpeg", "gif", "webp", "heic", "tif", "tiff", "bmp"]
                .contains(URL(fileURLWithPath: ruta).pathExtension.lowercased())
        }
    }

    /// Una burbuja del chat.
    public struct Burbuja: Identifiable, Equatable, Codable, Sendable {
        public var id = UUID()
        public var delUsuario: Bool
        public var texto: String
        public var herramientas: [Hecha] = []
        /// Lo dibujado, como `.excalidraw` (se puede guardar y abrir).
        public var lienzo: String?
        /// Un aviso de la app (no lo dijo el modelo): no vuelve al modelo.
        public var esAviso = false
        /// Lo que penso (plegable) y cuanto tardo.
        public var pensamiento = ""
        public var segundosPensando: Double?
        /// Quien contesto.
        public var motor = ""
        /// Lo que adjunto el usuario con este mensaje.
        public var adjuntos: [Adjunto] = []
        /// Lo citado de sus documentos (`buscar_en_mis_cosas`).
        public var citas: [Cita] = []
        /// «dibujando…» mientras el modelo pide una herramienta (no se guarda).
        public var llamando: String?

        public init(delUsuario: Bool, texto: String, herramientas: [Hecha] = [], lienzo: String? = nil,
                    esAviso: Bool = false) {
            self.delUsuario = delUsuario
            self.texto = texto
            self.herramientas = herramientas
            self.lienzo = lienzo
            self.esAviso = esAviso
        }

        enum CodingKeys: String, CodingKey {
            case id, delUsuario, texto, herramientas, lienzo, esAviso, pensamiento, segundosPensando, motor, adjuntos, citas
        }

        public init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            delUsuario = try c.decode(Bool.self, forKey: .delUsuario)
            texto = try c.decode(String.self, forKey: .texto)
            herramientas = try c.decodeIfPresent([Hecha].self, forKey: .herramientas) ?? []
            lienzo = try c.decodeIfPresent(String.self, forKey: .lienzo)
            esAviso = try c.decodeIfPresent(Bool.self, forKey: .esAviso) ?? false
            pensamiento = try c.decodeIfPresent(String.self, forKey: .pensamiento) ?? ""
            segundosPensando = try c.decodeIfPresent(Double.self, forKey: .segundosPensando)
            motor = try c.decodeIfPresent(String.self, forKey: .motor) ?? ""
            adjuntos = try c.decodeIfPresent([Adjunto].self, forKey: .adjuntos) ?? []
            citas = try c.decodeIfPresent([Cita].self, forKey: .citas) ?? []
        }
    }

    /// Una pregunta de «¿seguro?» que espera en la burbuja.
    public struct Pregunta: Identifiable {
        public let id = UUID()
        public let texto: String
        let responder: @MainActor (Bool) -> Void
    }

    public static let textoSinMotor = """
    No hay quien conteste en este Mac. Opciones:
    • Claude o DeepSeek con tu clave: Ajustes → Asistente.
    • macOS 26 con Apple Intelligence activado (Ajustes del Sistema > Apple Intelligence y Siri).
    """

    /// Donde se saca la clave de quien contesta («Claude Haiku 5.5»).
    static func paginaDeClaves(_ nombre: String) -> String {
        nombre.localizedCaseInsensitiveContains("deepseek") ? ProveedorNube.deepseek.consola
            : ProveedorNube.claude.consola
    }

    /// El aviso de que falta la clave (Windows, `nube::falta_la_clave`), en
    /// la burbuja o en la barra del chat.
    public static func faltaLaClave(_ nombre: String) -> String {
        "Falta la clave de \(nombre): pégala en Ajustes → Asistente (se saca en \(paginaDeClaves(nombre)))."
    }

    /// Lo de la tarjeta «Falta la clave de la nube» (`asistente-nube-explica`
    /// de Windows).
    public static func explicaLaClave(_ nombre: String) -> String {
        "El asistente contesta con \(nombre): pega su clave en Ajustes → Asistente (se saca en \(paginaDeClaves(nombre))). "
            + "Las órdenes simples («apunta pan», «abre la galería») funcionan sin clave."
    }

    @Published public private(set) var burbujas: [Burbuja] = []
    @Published public private(set) var ocupado = false
    @Published public private(set) var motor: Motor?
    /// La conversacion abierta y las guardadas (la lista de la izquierda).
    @Published public private(set) var conversacion = Conversacion()
    @Published public private(set) var guardadas: [Conversacion] = []
    /// Lo adjuntado para el mensaje que se esta escribiendo.
    @Published public var pendientes: [Adjunto] = []
    @Published public private(set) var pregunta: Pregunta?

    private let usarApple: Bool
    private weak var almacen: Almacen?
    private let historial: HistorialAsistente?
    /// Lo que se manda a Foundation Models como historial, como mucho.
    static let historialMaximo = 8

    public init(almacen: Almacen?, usarApple: Bool = true, historial: HistorialAsistente? = nil) {
        self.almacen = almacen
        self.usarApple = usarApple
        self.historial = historial
        TransporteHttps.instalar()
        if let historial {
            guardadas = historial.todas()
        }
    }

    // MARK: Ajustes y motor

    /// Los ajustes `[asistente]` de la carpeta de datos (sin ella, los de
    /// fabrica).
    func ajustes() -> AjustesIa {
        let a = almacen.flatMap { try? $0.nucleo.ajustes() }
        return AjustesIa(motor: a?.asistenteMotor ?? "",
                         pensar: a?.asistentePensar,
                         documentosALaNube: a?.asistenteDocumentosALaNube ?? "")
    }

    public var revisarLoDicho: Bool { almacen.flatMap { try? $0.nucleo.ajustes().asistenteRevisarLoDicho } ?? false }

    /// Mira quien contesta ahora segun los ajustes: la nube elegida y, sin
    /// su clave, Apple Intelligence si esta. Barato: el TOML, el Llavero y
    /// una consulta al sistema.
    @discardableResult
    public func comprobarMotor() async -> Motor {
        let a = ajustes()
        let visto = await Task.detached(priority: .utility) { iaQueMotor(ajustes: a) }.value
        let elegido: Motor = !visto.conClave && usarApple && motorAppleDisponible()
            ? .apple : .nube(visto.nombre, conClave: visto.conClave)
        motor = elegido
        return elegido
    }

    // MARK: Conversaciones

    /// Empieza otra conversacion (la de antes queda guardada).
    public func nuevaConversacion() {
        guardar()
        conversacion = Conversacion()
        burbujas = []
        pendientes = []
    }

    public func abrir(_ c: Conversacion) {
        guard !ocupado else { return }
        guardar()
        conversacion = c
        burbujas = c.burbujas
        pendientes = []
    }

    public func borrar(_ c: Conversacion) {
        historial?.borrar(c.id)
        guardadas.removeAll { $0.id == c.id }
        if c.id == conversacion.id {
            conversacion = Conversacion()
            burbujas = []
        }
    }

    private func guardar() {
        guard let historial, !burbujas.isEmpty else { return }
        conversacion.burbujas = burbujas
        conversacion.cambiada = Date()
        historial.guardar(conversacion)
        guardadas.removeAll { $0.id == conversacion.id }
        guardadas.insert(conversacion, at: 0)
    }

    // MARK: Adjuntos

    /// Adjunta ficheros al mensaje que se escribe.
    public func adjuntar(_ urls: [URL]) {
        for u in urls where u.isFileURL {
            pendientes.append(Adjunto(nombre: u.lastPathComponent, ruta: u.path))
        }
    }

    /// Adjunta una imagen pegada (la guarda junto a las conversaciones).
    public func adjuntar(imagen: NSImage) {
        guard let tiff = imagen.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return }
        let carpeta = (historial?.carpeta.deletingLastPathComponent() ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("adjuntos", isDirectory: true)
        try? FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        let f = carpeta.appendingPathComponent("pegada-\(Int(Date().timeIntervalSince1970 * 1000)).png")
        if (try? png.write(to: f)) != nil { adjuntar([f]) }
    }

    /// La foto que mira el modelo, reducida a ~768 px (JPEG).
    nonisolated static func foto(_ ruta: String, lado: Int = 768) -> FotoIa? {
        let opciones: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: lado,
        ]
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: ruta) as CFURL, nil),
              let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opciones as CFDictionary)
        else { return nil }
        let datos = NSMutableData()
        guard let dst = CGImageDestinationCreateWithData(datos, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dst, img, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(dst) else { return nil }
        return FotoIa(bytes: datos as Data, mime: "image/jpeg")
    }

    // MARK: Enviar

    /// Manda un pedido y espera la respuesta entera.
    public func enviar(_ texto: String) async {
        let pedido = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pedido.isEmpty, !ocupado else { return }
        let historialTexto = burbujas.filter { !$0.esAviso && !$0.texto.isEmpty }
            .map { MensajeIa(delUsuario: $0.delUsuario, texto: $0.texto) }
        var mia = Burbuja(delUsuario: true, texto: pedido)
        mia.adjuntos = pendientes
        conversacion.adjuntos += pendientes
        let nuevos = pendientes
        pendientes = []
        burbujas.append(mia)
        ocupado = true
        defer {
            ocupado = false
            guardar()
        }
        let motor = await comprobarMotor()
        // Las ordenes simples las hace el nucleo sin modelo (ni clave).
        let orden = iaEsOrdenRapida(pedido: pedido)
        switch motor {
        case .apple where !orden:
            await conApple(pedido, historial: Array(historialTexto.suffix(ModeloAsistente.historialMaximo)))
        case let .nube(nombre, conClave) where !conClave && !orden:
            burbujas.append(Burbuja(delUsuario: false, texto: ModeloAsistente.faltaLaClave(nombre), esAviso: true))
        default:
            let foto = nuevos.first(where: \.esImagen).map(\.ruta)
            await turno(pedido, historial: historialTexto, foto: foto)
        }
    }

    /// Un turno con Foundation Models.
    private func conApple(_ pedido: String, historial: [MensajeIa]) async {
        do {
            guard let r = try await preguntarAApple(pedido, historial: historial) else {
                burbujas.append(Burbuja(delUsuario: false, texto: ModeloAsistente.textoSinMotor, esAviso: true))
                return
            }
            var b = Burbuja(delUsuario: false, texto: r.texto,
                            herramientas: r.herramientas.map(ModeloAsistente.hecha), lienzo: r.lienzo)
            b.motor = Motor.apple.nombre
            burbujas.append(b)
        } catch {
            burbujas.append(Burbuja(delUsuario: false, texto: ModeloAjustes.texto(de: error), esAviso: true))
        }
    }

    static func hecha(_ u: HerramientaUsada) -> Hecha {
        Hecha(nombre: u.nombre, ok: u.ok, resumen: u.resumen)
    }

    // MARK: En vivo (el nucleo)

    /// El corte del turno en vivo que esta en marcha.
    private var corte: CorteIa?
    /// Las burbujas en vivo que ya tienen su texto final: lo que llegue
    /// tarde por el oyente no se pega dos veces.
    private var cerradas: Set<UUID> = []

    /// Si hay un turno en vivo que se puede parar.
    public var sePuedeParar: Bool { corte != nil }

    /// «Parar»: el modelo deja de escribir y queda lo que llevaba (y una
    /// pregunta pendiente cuenta como «no»).
    public func parar() {
        corte?.cancelar()
        responder(false)
    }

    /// Contesta la pregunta de la burbuja.
    public func responder(_ si: Bool) {
        guard let p = pregunta else { return }
        pregunta = nil
        p.responder(si)
    }

    /// Un turno por el nucleo: la burbuja del asistente aparece vacia y se
    /// va llenando con las tandas (cada ~60 ms como mucho, nunca una llamada
    /// por palabra); al acabar se pone la respuesta entera, con lo pensado,
    /// sus herramientas y lo dibujado.
    func turno(_ pedido: String, historial: [MensajeIa], foto: String?) async {
        let corte = CorteIa.nuevo()
        self.corte = corte
        defer {
            self.corte = nil
            pregunta = nil
        }
        let burbuja = Burbuja(delUsuario: false, texto: "")
        let id = burbuja.id
        burbujas.append(burbuja)
        let principal: @Sendable (@escaping @MainActor (ModeloAsistente) -> Void) -> Void = { [weak self] hacer in
            DispatchQueue.main.async { MainActor.assumeIsolated { if let self { hacer(self) } } }
        }
        let oyente = OyenteDelAsistente(
            alTexto: { t in principal { $0.cambiar(id) { b in b.texto += t; b.llamando = nil } } },
            alHerramienta: { u in principal { $0.cambiar(id) { b in b.herramientas.append(ModeloAsistente.hecha(u)); b.llamando = nil } } },
            alPensar: { t in principal { $0.cambiar(id) { b in b.pensamiento += t } } },
            alLlamar: { n in principal { $0.cambiar(id) { b in b.llamando = ModeloAsistente.rotuloDe(n) } } })
        let manos = ManosDelAsistente(nucleo: almacen?.nucleo, corte: corte) { [weak self] texto, responder in
            guard let self else { return responder(false) }
            self.pregunta = Pregunta(texto: texto, responder: responder)
        }
        let peticion = PeticionIa(historial: historial, pedido: pedido,
                                  foto: foto.flatMap { ModeloAsistente.foto($0) },
                                  adjuntos: conversacion.adjuntos.map { AdjuntoIa(nombre: $0.nombre, ruta: $0.ruta) },
                                  hoja: conversacion.hoja,
                                  desfaseMs: Int64(TimeZone.current.secondsFromGMT()) * 1000)
        let a = ajustes()
        let nucleo = almacen?.nucleo
        let r: Result<RespuestaIa, Error> = await withCheckedContinuation { c in
            DispatchQueue.global(qos: .utility).async {
                c.resume(returning: Result {
                    try iaTurno(ajustes: a, peticion: peticion, nucleo: nucleo, app: manos, oyente: oyente, corte: corte)
                })
            }
        }
        switch r {
        case let .success(r):
            conversacion.hoja = r.hoja.isEmpty ? conversacion.hoja : r.hoja
            cerrar(id) { b in
                b.texto = r.texto.isEmpty && corte.cortado() ? "(parado)" : r.texto
                b.herramientas = r.herramientas.map(ModeloAsistente.hecha)
                b.lienzo = r.lienzo
                b.pensamiento = r.pensamiento
                b.segundosPensando = r.segundosPensando.map(Double.init)
                b.motor = r.motor
                b.citas = r.citas.map { Cita(numero: Int($0.numero), titulo: $0.titulo, pedido: $0.pedido) }
                b.llamando = nil
            }
        case let .failure(e):
            let texto = ModeloAjustes.texto(de: e)
            cerrar(id) { b in
                b.texto = texto
                b.esAviso = true
                b.llamando = nil
            }
        }
    }

    /// Lo que se ve mientras el modelo pide una herramienta.
    static func rotuloDe(_ herramienta: String) -> String {
        switch herramienta {
        case "dibujar_en_lienzo", "grafica", "funciones", "ecuacion", "svg", "cronograma", "fisica",
             "problema_en_limpio": return "Dibujando…"
        case "calcar_imagen": return "Calcando la imagen…"
        case "ocr_pdf", "leer_documento": return "Leyendo…"
        default: return "Haciendo «\(herramienta)»…"
        }
    }

    private func cambiar(_ id: UUID, _ cambio: (inout Burbuja) -> Void) {
        guard !cerradas.contains(id), let i = burbujas.firstIndex(where: { $0.id == id }) else { return }
        cambio(&burbujas[i])
    }

    func pegar(_ trozo: String, en id: UUID) {
        cambiar(id) { $0.texto += trozo }
    }

    func anadir(_ usada: HerramientaUsada, en id: UUID) {
        cambiar(id) { $0.herramientas.append(ModeloAsistente.hecha(usada)) }
    }

    private func cerrar(_ id: UUID, _ cambio: (inout Burbuja) -> Void) {
        cerradas.insert(id)
        guard let i = burbujas.firstIndex(where: { $0.id == id }) else { return }
        cambio(&burbujas[i])
    }

    // MARK: Documentos

    /// Abre lo citado (el lector en su pagina, o el chat en su mensaje).
    public func abrir(_ c: Cita) {
        if let error = ManosDelAsistente.aLaApp(c.pedido) {
            burbujas.append(Burbuja(delUsuario: false, texto: error, esAviso: true))
        }
    }

    private static var indexando = false

    /// Pone al dia el indice de los documentos en segundo plano (al abrir la
    /// ventana), para que la primera busqueda no espere. Solo si hay quien
    /// conteste: quien no usa el asistente no paga nada.
    public func prepararDocumentos() {
        guard let nucleo = almacen?.nucleo, !ModeloAsistente.indexando, motor != nil else { return }
        ModeloAsistente.indexando = true
        let manos = ManosDelAsistente(nucleo: nucleo, corte: CorteIa.nuevo()) { _, responder in responder(false) }
        DispatchQueue.global(qos: .background).async {
            _ = iaDocumentosAlDia(nucleo: nucleo, app: manos)
            DispatchQueue.main.async { MainActor.assumeIsolated { ModeloAsistente.indexando = false } }
        }
    }

    // MARK: Voz

    /// Lee la burbuja en voz alta (la voz de la app, con su barra).
    public func leerEnVoz(_ b: Burbuja) {
        let parrafos = b.texto.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !parrafos.isEmpty else { return }
        let voz = LeerEnVoz.compartida
        if voz.arrancar(.init(clave: "asistente-\(b.id.uuidString)", titulo: "Asistente", parrafos: parrafos,
                              idioma: VozAlta.idiomaDeLaApp), lector: nil) {
            voz.leer(desde: 0)
        }
    }

    // MARK: Lo dibujado

    /// Guarda lo dibujado en «Mensajes guardados» como un **lienzo del
    /// chat** (un `DIBUJO` con su `lienzos/<d>.excalidraw`, lo que viaja con
    /// Windows y Android; no un `.excalidraw` suelto adjunto) y, con
    /// `abrir`, lo abre en el lienzo.
    @discardableResult
    public func guardarDibujo(_ b: Burbuja, abrir: Bool = false) async -> Bool {
        guard let lienzo = b.lienzo, let almacen else { return false }
        let nucleo = almacen.nucleo
        let titulo = "Lienzo del asistente"
        do {
            let (guardados, m) = try await Task.detached(priority: .utility) { () -> (String, MensajeChat) in
                let g = try nucleo.chatGuardados()
                return (g.id, try nucleo.crearLienzoConDibujo(chat: g.id, nombre: titulo, json: lienzo))
            }.value
            almacen.anadir([m], en: guardados)
            if abrir, let ref = m.referencia {
                VentanasDeLienzo.compartidas.abrir(referencia: ref, en: guardados, titulo: titulo, almacen: almacen)
            }
            return true
        } catch {
            return false
        }
    }
}
