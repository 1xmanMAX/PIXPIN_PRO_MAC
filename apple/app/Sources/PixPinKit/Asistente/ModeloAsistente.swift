// El asistente del Mac: un chat con el motor que dicen los ajustes
// `[asistente]` (los mismos que Windows, Ajustes → Asistente):
//
// - `motor = claude | deepseek`: la nube (Claude Haiku 5.5 o DeepSeek V4.1
//   Flash, con la clave del Llavero) por el HTTPS de URLSession
//   (`TransporteHttps`); si falla y `respaldo_local`, el local (el modelo
//   bajado, o Apple Intelligence).
// - local (vacio): el modelo bajado (Qwen3.5 2B u 0.8B, `modelo`; Gemma 4
//   E2B para mirar fotos con `mejor_vista`) con su `llama-server`; si no
//   esta, **Foundation Models** (macOS 26 con Apple Intelligence,
//   `MotorApple.swift`); si tampoco, un `llama-server` del usuario en
//   127.0.0.1:8080; y si no hay nada, se dice como tener uno (y la ventana
//   ofrece bajar el modelo).
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
        case apple
        case llamaLocal(UInt16)
        /// El modelo bajado, con su `llama-server` (su nombre).
        case descargado(String)
        /// Claude o DeepSeek (su nombre); `conClave` si hay clave guardada.
        case nube(String, conClave: Bool)
        case ninguno

        public var nombre: String {
            switch self {
            case .apple: return "Apple Intelligence (en este Mac)"
            case let .llamaLocal(p): return "llama-server local (127.0.0.1:\(p))"
            case let .descargado(n): return n + " · en este Mac"
            case let .nube(n, conClave): return conClave ? n : n + " · falta la clave"
            case .ninguno: return "Sin motor"
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
    No hay motor para el asistente en este Mac. Opciones:
    • Baja el modelo local (Qwen3.5) desde esta ventana: gratis y sin red.
    • macOS 26 con Apple Intelligence activado (Ajustes del Sistema > Apple Intelligence y Siri).
    • Claude o DeepSeek con tu clave: Ajustes → Asistente.
    • O un llama-server propio escuchando en 127.0.0.1:8080 (por ejemplo: llama-server -m modelo.gguf --port 8080).
    """

    @Published public private(set) var burbujas: [Burbuja] = []
    @Published public private(set) var ocupado = false
    @Published public private(set) var motor: Motor?
    /// La conversacion abierta y las guardadas (la lista de la izquierda).
    @Published public private(set) var conversacion = Conversacion()
    @Published public private(set) var guardadas: [Conversacion] = []
    /// Lo adjuntado para el mensaje que se esta escribiendo.
    @Published public var pendientes: [Adjunto] = []
    @Published public private(set) var pregunta: Pregunta?

    public let puertoLlama: UInt16
    private let usarApple: Bool
    private weak var almacen: Almacen?
    private let historial: HistorialAsistente?
    /// Lo que se manda a Foundation Models como historial, como mucho.
    static let historialMaximo = 8

    public init(almacen: Almacen?, puertoLlama: UInt16 = 8080, usarApple: Bool = true,
                historial: HistorialAsistente? = nil) {
        self.almacen = almacen
        self.puertoLlama = puertoLlama
        self.usarApple = usarApple
        self.historial = historial
        TransporteHttps.instalar()
        ModeloAsistente.alArrancar()
        if let historial {
            guardadas = historial.todas()
        }
    }

    /// Una vez por proceso: matar el `llama-server` que dejo una PixPin que
    /// murio de golpe, y soltar los modelos al salir de la app.
    private static var arrancado = false
    private static func alArrancar() {
        guard !arrancado else { return }
        arrancado = true
        let carpeta = carpetaDeModelos().path
        Task.detached(priority: .utility) { _ = iaLimpiarHuerfanos(carpeta: carpeta) }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil,
                                               queue: nil) { _ in iaSoltarMotores() }
    }

    // MARK: Ajustes y motor

    /// Los ajustes `[asistente]` de la carpeta de datos (sin ella, los de
    /// fabrica y sin modelos bajados).
    func ajustes() -> AjustesIa {
        let a = almacen.flatMap { try? $0.nucleo.ajustes() }
        return AjustesIa(motor: a?.asistenteMotor ?? "",
                         modelo: a?.asistenteModelo ?? "",
                         pensar: a?.asistentePensar,
                         respaldoLocal: a?.asistenteRespaldoLocal ?? true,
                         mejorVista: a?.asistenteMejorVista ?? false,
                         documentosALaNube: a?.asistenteDocumentosALaNube ?? "",
                         carpetaModelos: almacen == nil ? "" : carpetaDeModelos().path,
                         puertoUsuario: puertoLlama)
    }

    public var revisarLoDicho: Bool { almacen.flatMap { try? $0.nucleo.ajustes().asistenteRevisarLoDicho } ?? false }

    /// Mira que motor hay ahora segun los ajustes. Barato: el disco, una
    /// consulta al sistema y, si hace falta, un `GET /health` local.
    @discardableResult
    public func comprobarMotor() async -> Motor {
        let a = ajustes()
        let visto = await Task.detached(priority: .utility) { iaQueMotor(ajustes: a) }.value
        let apple = usarApple && motorAppleDisponible()
        let elegido: Motor
        switch visto {
        case let .nube(_, nombre, _, conClave): elegido = .nube(nombre, conClave: conClave)
        case let .descargado(_, nombre): elegido = .descargado(nombre)
        case let .usuario(puerto): elegido = apple ? .apple : .llamaLocal(puerto)
        case .ninguno: elegido = apple ? .apple : .ninguno
        }
        motor = elegido
        return elegido
    }

    /// Si falta bajar el modelo local de los ajustes (para la tarjeta).
    public var modeloLocalPorBajar: String? {
        let a = ajustes()
        guard a.motor.isEmpty || a.motor == "local" else { return nil }
        return a.modelo.isEmpty ? "qwen3.5-2b" : a.modelo
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
        switch motor {
        case .apple:
            await conApple(pedido, historial: Array(historialTexto.suffix(ModeloAsistente.historialMaximo)), aviso: nil)
        case .ninguno:
            burbujas.append(Burbuja(delUsuario: false, texto: ModeloAsistente.textoSinMotor, esAviso: true))
        case .llamaLocal, .descargado, .nube:
            let foto = nuevos.first(where: \.esImagen).map(\.ruta)
            await turno(pedido, historial: historialTexto, foto: foto, motor: motor)
        }
    }

    /// Un turno con Foundation Models. `aviso`: lo que va delante (la nube
    /// fallo y sigue Apple).
    private func conApple(_ pedido: String, historial: [MensajeIa], aviso: String?) async {
        do {
            guard let r = try await preguntarAApple(pedido, historial: historial) else {
                burbujas.append(Burbuja(delUsuario: false, texto: ModeloAsistente.textoSinMotor, esAviso: true))
                return
            }
            var b = Burbuja(delUsuario: false, texto: (aviso ?? "") + r.texto,
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
    func turno(_ pedido: String, historial: [MensajeIa], foto: String?, motor: Motor) async {
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
            // La nube fallo antes de decir nada y no hay local bajado: si
            // el usuario quiere respaldo, sigue Apple Intelligence.
            let vacia = burbujas.first { $0.id == id }?.texto.isEmpty ?? true
            if motor.esNube, vacia, a.respaldoLocal, usarApple, motorAppleDisponible(), !corte.cortado() {
                cerradas.insert(id)
                burbujas.removeAll { $0.id == id }
                await conApple(pedido, historial: Array(historial.suffix(ModeloAsistente.historialMaximo)),
                               aviso: "⚠️ \(texto)\nSigo con Apple Intelligence.\n\n")
                return
            }
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

    /// Compatibilidad: un turno con el `llama-server` del usuario.
    func preguntarEnVivo(puerto: UInt16, historial: [MensajeIa], pedido: String) async {
        await turno(pedido, historial: historial, foto: nil, motor: .llamaLocal(puerto))
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
        guard let nucleo = almacen?.nucleo, !ModeloAsistente.indexando, motor != nil, motor != .ninguno else { return }
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

    /// Guarda lo dibujado en «Mensajes guardados» como un `.excalidraw`
    /// (el formato del lienzo de Windows y Android) y, con `abrir`, lo abre
    /// en el lienzo.
    @discardableResult
    public func guardarDibujo(_ b: Burbuja, abrir: Bool = false) async -> Bool {
        guard let lienzo = b.lienzo, let almacen else { return false }
        let carpeta = FileManager.default.temporaryDirectory
            .appendingPathComponent("pixpin-asistente-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: carpeta) }
        do {
            try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
            let ms = Int64(Date().timeIntervalSince1970 * 1000)
            let fichero = carpeta.appendingPathComponent("asistente-\(ms).excalidraw")
            try Data(lienzo.utf8).write(to: fichero)
            let nucleo = almacen.nucleo
            let guardados = try await Task.detached(priority: .utility) { try nucleo.chatGuardados() }.value
            let hechos = await almacen.adjuntar(urls: [fichero], en: guardados.id)
            if abrir, let ref = hechos.first?.referencia {
                VentanasDeLienzo.compartidas.abrir(referencia: ref, en: guardados.id, titulo: "Lienzo del asistente",
                                                  almacen: almacen)
            }
            return !hechos.isEmpty
        } catch {
            return false
        }
    }
}
