// **Quien hace los pedidos** en el Mac: lo que en Windows es el bucle que
// atiende `WM_COPYDATA` (`pedidos.rs`). Llegan de los enlaces `pixpinmax://`
// (con su lista blanca y el cuadro de confirmar), del menu del Dock, de los
// Servicios del Finder y de Atajos (App Intents), y cada accion va a lo
// mismo que hace el boton de la app. Lo que el Mac aun no sabe hacer se
// dice en el aviso, no se calla.

import AppKit
import Foundation
import PixPinCore
import UniformTypeIdentifiers

@MainActor
public final class HacerPedidos {
    public static let compartidos = HacerPedidos()

    private weak var almacen: Almacen?
    private weak var sincro: Sincronizador?
    /// El asistente de los pedidos (sin ventana; la respuesta va al aviso).
    private var asistente: ModeloAsistente?
    /// Lo que llego antes de que la app registrara lo suyo (un enlace que
    /// abre PixPin): se hace al registrar.
    private var pendientes: [(LlamadaOrden)] = []
    private var registrado = false

    /// Preguntar antes de hacer (el cuadro de Windows). Las pruebas lo
    /// cambian.
    var confirmar: (String) -> Bool = HacerPedidos.cuadroConfirmar
    /// Decir algo (el globo de Windows). Las pruebas lo cambian.
    var avisar: (String) -> Void = HacerPedidos.aviso

    public init() {}

    /// La app dice con que trabaja (una vez, al arrancar).
    public func registrar(almacen: Almacen?, sincro: Sincronizador?) {
        self.almacen = almacen
        self.sincro = sincro
        registrado = true
        let ya = pendientes
        pendientes = []
        for l in ya { hacer(l) }
    }

    // MARK: Las puertas

    /// **Un enlace** `pixpinmax://…` (el `application(_:open:)` del Mac).
    /// `false` si no es nuestro.
    @discardableResult
    public func abrir(enlace url: URL) -> Bool {
        let texto = url.absoluteString
        guard Enlaces.esEnlace(texto) else { return false }
        do {
            hacer(try Enlaces.leer(texto))
        } catch {
            avisar(error.localizedDescription)
        }
        return true
    }

    /// Unos pedidos de la propia app (Dock, Servicios, Atajos): sin
    /// preguntar.
    public func hacer(_ pedidos: [Pedido]) {
        hacer(LlamadaOrden(orden: .pedidos(pedidos), origen: .consola))
    }

    public func hacer(_ pedido: Pedido) { hacer([pedido]) }

    /// **Hace una orden**: cambia los nombres de proyecto por su id, mira la
    /// seguridad si viene de un enlace y la hace.
    public func hacer(_ l: LlamadaOrden) {
        guard registrado else {
            pendientes.append(l)
            return
        }
        switch l.orden {
        case .ayuda:
            avisar("pixpinmax://<verbo>?campo=valor\n" + Verbos.tabla.filter(\.porEnlace).map(\.nombres[0]).joined(separator: ", "))
        case let .ocr(rutas, _):
            hacerUno(Pedido("ocr", ["ruta": .texto(rutas.first ?? ""), "rutas": .textos(Array(rutas.dropFirst()))]))
        case let .preguntar(rutas, proyecto):
            guard let pregunta = preguntarAlAsistente(rutas) else { return }
            hacerTodos([Verbos.pedidoAlAsistente(pregunta, ficheros: rutas, proyecto: proyecto)], origen: l.origen)
        case let .pedidos(v):
            hacerTodos(v, origen: l.origen)
        }
    }

    private func hacerTodos(_ pedidos: [Pedido], origen: OrigenOrden) {
        let pedidos = HacerPedidos.ponerIds(pedidos, proyectos: proyectos())
        if case let .enlace(firmado) = origen {
            // Lo peor de todos los pedidos del enlace manda.
            let peor = pedidos.map { firmado ? Enlaces.seguridadFirmado($0) : Enlaces.seguridad($0) }.max() ?? .directa
            switch peor {
            case .directa: break
            case let .prohibida(motivo):
                avisar(Enlaces.textoDelMotivo(motivo))
                return
            case let .confirmar(motivo):
                let cuerpo = "Un enlace le pide a PixPin Max:\n\n"
                    + pedidos.map(Enlaces.describir).joined(separator: "\n\n")
                    + "\n\n" + Enlaces.textoDelMotivo(motivo)
                guard confirmar(cuerpo) else { return }
            }
        }
        for p in pedidos { hacerUno(p) }
    }

    // MARK: Los proyectos por su nombre

    /// Los proyectos (id, nombre); «Mensajes guardados» va con `guardados`.
    private func proyectos() -> [(id: String, nombre: String, guardados: Bool)] {
        (almacen?.chats ?? []).map { ($0.id, $0.nombre, $0.esGuardados) }
    }

    /// `proyecto: "Obra"` → el id de «Obra» (`poner_ids` de Windows). Un id
    /// que ya existe se deja; un nombre se busca sin mirar mayusculas;
    /// «Mensajes guardados» (o «guardados») es nulo. Lo que no se encuentra
    /// se deja: al hacerlo se dice que no existe.
    static func ponerIds(_ pedidos: [Pedido], proyectos: [(id: String, nombre: String, guardados: Bool)]) -> [Pedido] {
        func uno(_ v: ValorPedido?) -> ValorPedido? {
            guard let t = v?.texto?.trimmingCharacters(in: .whitespacesAndNewlines) else { return v }
            let bajo = t.lowercased()
            if bajo == "guardados" || bajo == "mensajes guardados" { return .nulo }
            if proyectos.contains(where: { $0.id == t }) { return .texto(t) }
            if let p = proyectos.first(where: { $0.nombre.trimmingCharacters(in: .whitespaces).lowercased() == bajo }) {
                return p.guardados ? .nulo : .texto(p.id)
            }
            return v
        }
        return pedidos.map { p in
            var p = p
            if p["proyecto"] != nil { p["proyecto"] = uno(p["proyecto"]) }
            if var que = p["que"]?.objeto, que["proyecto"] != nil {
                que["proyecto"] = uno(que["proyecto"])
                p["que"] = .objeto(que)
            }
            return p
        }
    }

    /// El id del chat de un pedido: el `proyecto` o, nulo, «Mensajes
    /// guardados». `nil` (y se dice) si no hay datos o no existe.
    private func chat(_ v: ValorPedido?) async -> String? {
        guard let almacen else {
            avisar("No se pudo abrir la carpeta de datos de PixPin.")
            return nil
        }
        if almacen.chats.isEmpty { await almacen.cargarChats() }
        if let id = v?.texto {
            guard almacen.chats.contains(where: { $0.id == id }) else {
                avisar("No existe el proyecto «\(id)».")
                return nil
            }
            return id
        }
        if let g = almacen.chats.first(where: \.esGuardados) { return g.id }
        let nucleo = almacen.nucleo
        return try? await Task.detached { try nucleo.chatGuardados().id }.value
    }

    /// Los chats de la app, en el orden de la lista (el menu del Dock).
    func fichas() -> [FichaChat] { almacen?.chats ?? [] }

    private func nombre(de chat: String) -> String {
        almacen?.chats.first { $0.id == chat }?.nombre ?? "Mensajes guardados"
    }

    // MARK: Cada accion

    /// **Hace un pedido** ya aceptado.
    func hacerUno(_ p: Pedido) {
        Task { await hacerYa(p) }
    }

    func hacerYa(_ p: Pedido) async {
        // Dentro de un paso «pedido al asistente» de una automatizacion, lo
        // que la haria saltar otra vez no se hace (E6, sin bucles).
        if let motivo = MotorAutomatizaciones.compartido.bloqueado(p.accion) {
            return avisar("No se hizo: \(motivo).")
        }
        switch p.accion {
        case "abrir": await abrir(p)
        case "ventana_principal":
            if p.texto("proyecto") != nil {
                guard let c = await chat(p["proyecto"]) else { return }
                abrirChat(c)
            } else {
                ventana(IdVentana.proyectos)
            }
        case "ventana": ventana(cual: p.texto("cual") ?? "")
        case "capturar": capturar(p.texto("modo"))
        case "chat": await escribir(p)
        case "nota_nueva": await notaNueva(p)
        case "lienzo_nuevo": await lienzoNuevo(p)
        case "lista_nueva": await listaNueva(p)
        case "anadir_tarea": await anadirTarea(p)
        case "marcar_tarea", "quitar_tarea", "corregir_tarea": await cambiarTarea(p)
        case "borrar_lista": await borrarLista(p)
        case "grabar":
            guard let almacen, let c = await chat(p["proyecto"]) else { return }
            MicrofonoFlotante.compartido.alternar(en: c, nombre: nombre(de: c), almacen: almacen)
        case "pinear": await pinear(p)
        case "pinear_ultima": await pinearUltima()
        case "conservar_captura": await conservar(p)
        case "copiar_imagen": copiarImagen(p)
        case "reproducir":
            guard let r = p.texto("ruta"), FileManager.default.fileExists(atPath: r) else {
                return avisar("No existe el audio «\(p.texto("ruta") ?? "")».")
            }
            let url = URL(fileURLWithPath: r)
            ReproductorFlotante.compartido.abrir([Pista(id: r, url: url,
                                                        titulo: p.texto("titulo") ?? url.lastPathComponent)])
        case "lecciones", "leccion_nueva":
            // La ventana de lecciones (ni la busqueda ni la ficha nueva se
            // pueden pedir aun desde fuera).
            ventana("lecciones")
            if p.accion == "leccion_nueva", p.texto("texto") != nil {
                avisar("La ficha de una lección nueva aún no se abre desde fuera en el Mac: escríbela en Lecciones.")
            }
        case "sincronizar": await sincronizar(p)
        case "enviar_al_movil": await alMovil(p)
        case "asistente": await preguntar(p)
        case "automatizacion": await automatizacion(p)
        case "pines": pines(p.texto("operacion") ?? "")
        case "timeline": await timeline(p)
        case "leer_en_voz": leer(p)
        case "ocr": await ocr(p)
        case "herramienta": await herramienta(p)
        case "carpeta_paginas": await carpetaPaginas(p)
        default:
            avisar("«\(p.accion)» aún no lo hace PixPin en el Mac.")
        }
    }

    private func ventana(_ id: String) {
        guard let abrir = ComandosApp.abrirVentana else { return NSSound.beep() }
        abrir(id)
        NSApp.activate()
    }

    /// `ventana {cual}`: las de la bandeja de Windows.
    private func ventana(cual: String) {
        switch cual {
        case "tareas": ventana(IdVentana.tareas)
        case "galeria": ventana(IdVentana.galeria)
        case "lecciones": ventana("lecciones")
        case "sincronizar": ventana("sincronizar")
        case "timeline": ventana(IdVentana.timeline)
        case "buscar": ventana(IdVentana.buscar)
        // 26-oct (Flow, `p clase`): «Grabar clase o reunión…», como la bandeja.
        case "clase": GrabarClase.compartida.abrir()
        // El horario semanal es la vista Horario de Tareas (Windows 5139e5d).
        case "horario": VentanaTareas.abrir(vista: .horario)
        case "ajustes":
            guard let abrir = ComandosApp.abrirAjustes else { return NSSound.beep() }
            abrir()
            NSApp.activate()
        default: avisar("No hay ventana «\(cual)».")
        }
    }

    /// **`carpeta_paginas`** (Flow, `p carpeta`, Windows 22c3ce2): abrir una
    /// carpeta de paginas, crearla o su pagina siguiente, sin abrir el chat.
    private func carpetaPaginas(_ p: Pedido) async {
        guard let almacen, let c = await chat(p["proyecto"]) else { return }
        let hacer = p.texto("hacer") ?? ""
        guard ["abrir", "nueva", "pagina"].contains(hacer) else {
            return avisar("«carpeta_paginas» no sabe «\(hacer)»: abrir, nueva o pagina.")
        }
        if let aviso = await CarpetasSinChat.pedido(hacer: hacer, proyecto: c, carpeta: p.texto("carpeta"),
                                                    nombre: p.texto("nombre") ?? "", almacen: almacen) {
            avisar(aviso)
        }
    }

    private func abrirChat(_ chat: String) {
        PeticionDeChat.compartida.salto = nil
        PeticionDeChat.compartida.chat = chat
        ventana(IdVentana.proyectos)
    }

    /// `capturar {modo}`, un poco despues (como Windows, 300 ms) para que lo
    /// que lo pidio ya no salga en la foto.
    private func capturar(_ modo: String?) {
        guard let c = Capturador.principal else { return NSSound.beep() }
        let hacer: () -> Void
        switch modo ?? "zona" {
        case "zona": hacer = { c.capturar() }
        case "copiar": hacer = { c.capturar(.copiar) }
        case "pin": hacer = { c.capturar(.pinear) }
        case "en_vivo": hacer = { c.capturar(.enVivo) }
        case "anotar": hacer = { c.capturar(.anotar) }
        case "texto": hacer = { c.capturar(.texto) }
        case "scroll": hacer = { c.capturar(.scroll) }
        case "gif": hacer = { c.capturar(.gif) }
        case "repetir": hacer = { c.capturarUltimaZona() }
        case "retardo": hacer = { CuentaAtras.empezar { c.capturar() } }
        case let otro: return avisar("No hay captura «\(otro)».")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { hacer() }
    }

    // MARK: Abrir

    private func abrir(_ p: Pedido) async {
        guard let que = p["que"]?.objeto, let tipo = que["tipo"]?.texto else {
            return avisar("«abrir» sin «que».")
        }
        switch tipo {
        case "proyecto":
            guard let c = await chat(que["proyecto"]) else { return }
            abrirChat(c)
        case "mensaje":
            guard let almacen, let c = await chat(que["proyecto"]), let codigo = que["codigo"]?.texto else { return }
            Recordatorios.abrir(chat: c, mensaje: codigo, nucleo: almacen.nucleo)
        case "hoja":
            guard let almacen, let c = await chat(que["proyecto"]), let r = que["referencia"]?.texto else { return }
            VentanasDeLienzo.compartidas.abrir(referencia: r, en: c, titulo: r, almacen: almacen)
        case "nota":
            guard let almacen, let c = await chat(que["proyecto"]), let codigo = que["codigo"]?.texto,
                  let m = await mensaje(codigo, en: c) else { return }
            EditoresDeNotas.compartidos.abrir(m, en: c, almacen: almacen)
        case "fichero":
            guard let r = que["ruta"]?.texto else { return }
            abrir(fichero: URL(fileURLWithPath: r))
        default:
            avisar("«abrir» no conoce «\(tipo)».")
        }
    }

    /// Como «Abrir con PixPin» del Finder: planos y modelos a su visor,
    /// documentos al lector o al editor, imagenes y videos a un pin, audios
    /// al reproductor flotante.
    @discardableResult
    func abrir(fichero url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            avisar("No existe «\(url.path)».")
            return false
        }
        if VentanasDePlano.compartidas.abrirSiEsSuyo(url) { return true }
        if let tipo = UTType(filenameExtension: url.pathExtension.lowercased()), tipo.conforms(to: .audio) {
            ReproductorFlotante.compartido.abrir([Pista(id: url.path, url: url, titulo: url.lastPathComponent)])
            return true
        }
        if let almacen, AbrirDocumento.abrir(url, nucleo: almacen.nucleo) { return true }
        if GestorPines.compartido.pinear(fichero: url) { return true }
        avisar("PixPin no sabe abrir «\(url.lastPathComponent)».")
        return false
    }

    /// Un mensaje por su id: la pagina donde esta, cargada.
    private func mensaje(_ id: String, en chat: String) async -> MensajeChat? {
        guard let almacen else { return nil }
        if let m = almacen.mensajes[chat]?.first(where: { $0.id == id }) { return m }
        let nucleo = almacen.nucleo
        let posicion = await Task.detached { try? nucleo.posicionDeMensaje(chat: chat, mensaje: id) }.value
        guard let posicion = posicion.flatMap({ $0 }) else {
            avisar("No existe ese mensaje en «\(nombre(de: chat))».")
            return nil
        }
        await almacen.abrir(chat: chat, en: posicion)
        return almacen.mensajes[chat]?.first { $0.id == id }
    }

    // MARK: Escribir

    /// Las rutas de un campo (`imagenes`, `archivos`), las que existen; si
    /// falta alguna, nada (y se dice), como Windows.
    private func ficheros(_ p: Pedido, _ campos: [String]) -> [URL]? {
        let rutas = campos.flatMap { p[$0]?.lista?.compactMap(\.texto) ?? [] }
        var urls: [URL] = []
        for r in rutas {
            var dir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: r, isDirectory: &dir), !dir.boolValue else {
                avisar("No existe «\(r)».")
                return nil
            }
            urls.append(URL(fileURLWithPath: r))
        }
        return urls
    }

    /// `chat`: el texto (sin sus fichas `[img 01]`) y despues las fotos y
    /// los ficheros, como al soltarlos en el chat.
    private func escribir(_ p: Pedido) async {
        guard let almacen, let c = await chat(p["proyecto"]),
              let urls = ficheros(p, ["imagenes", "archivos"]) else { return }
        let texto = HacerPedidos.sinFichas(p.texto("texto") ?? "")
        if !texto.isEmpty { _ = await almacen.escribir(nota: texto, en: c) }
        if !urls.isEmpty { _ = await almacen.adjuntar(urls: urls, en: c) }
        avisar("Escrito en «\(nombre(de: c))».")
    }

    /// Quita las fichas `[img 01]` y `[archivo 01]` del texto.
    static func sinFichas(_ t: String) -> String {
        let sin = t.replacingOccurrences(of: #"\[(img|archivo) \d+\]"#, with: "", options: .regularExpression)
        return sin.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func notaNueva(_ p: Pedido) async {
        guard let almacen, let c = await chat(p["proyecto"]), let urls = ficheros(p, ["imagenes"]) else { return }
        let texto = HacerPedidos.sinFichas(p.texto("texto") ?? "")
        guard let m = await almacen.escribir(nota: texto.isEmpty ? "# Nota nueva" : texto, en: c) else { return }
        // Las imagenes van al chat, detras de la nota.
        if !urls.isEmpty { _ = await almacen.adjuntar(urls: urls, en: c) }
        EditoresDeNotas.compartidos.abrir(m, en: c, almacen: almacen)
    }

    private func lienzoNuevo(_ p: Pedido) async {
        guard let almacen, let c = await chat(p["proyecto"]) else { return }
        let nucleo = almacen.nucleo
        let nombre = p.texto("nombre")
        do {
            let m = try await Task.detached { try nucleo.crearLienzo(chat: c, nombre: nombre) }.value
            await almacen.alFinal(m, en: c)
            guard let r = m.referencia else { return }
            VentanasDeLienzo.compartidas.abrir(referencia: r, en: c, titulo: nombre ?? "Lienzo nuevo", almacen: almacen)
        } catch {
            avisar("No se pudo crear el lienzo: \(error)")
        }
    }

    /// Una lista de tareas nueva, pineada (como «Lista de tareas» del clip).
    @discardableResult
    private func listaNueva(_ p: Pedido) async -> MensajeChat? {
        guard let c = await chat(p["proyecto"]) else { return nil }
        return await crearLista(p.texto("titulo") ?? "Tareas", en: c, pinear: true)
    }

    private func crearLista(_ titulo: String, en c: String, pinear: Bool) async -> MensajeChat? {
        guard let almacen else { return nil }
        let nucleo = almacen.nucleo
        let moneda = monedaDelAparato()
        do {
            let m = try await Task.detached {
                try nucleo.crearMiniapp(chat: c, miniapp: "tareas", titulo: titulo, moneda: moneda)
            }.value
            await almacen.alFinal(m, en: c)
            if pinear {
                GestorPines.compartido.pinearMiniapp(chat: c, mensaje: m.id, miniapp: "tareas", documento: m.texto)
            }
            return m
        } catch {
            avisar("No se pudo crear la lista: \(error)")
            return nil
        }
    }

    /// `anadir_tarea`: sin proyecto ni lista, al Inbox; con lista, a esa;
    /// con proyecto, a su ultima lista (o a una nueva «Tareas»).
    private func anadirTarea(_ p: Pedido) async {
        guard let almacen else { return avisar("No se pudo abrir la carpeta de datos de PixPin.") }
        let texto = HacerPedidos.sinFichas(p.texto("texto") ?? "")
        if p["imagenes"]?.lista?.isEmpty == false {
            avisar("Las tareas con imágenes aún no se apuntan desde fuera en el Mac: va solo el texto.")
        }
        guard !texto.isEmpty else { return }
        let nucleo = almacen.nucleo
        let desfase = desfaseLocalMs()
        let codigo = p.texto("codigo")
        if codigo == nil, p["proyecto"] == nil {
            do {
                let lista = try await Task.detached { try nucleo.apuntarTarea(texto: texto, desfaseMs: desfase) }.value
                avisoDeTareas(lista.chat)
                avisar("Apuntado en el Inbox: «\(texto)».")
            } catch {
                avisar("No se pudo apuntar la tarea: \(error)")
            }
            return
        }
        guard let c = await chat(p["proyecto"]) else { return }
        var lista = codigo
        if lista == nil {
            let todas = (try? await Task.detached { try nucleo.tareas(desfaseMs: desfase) }.value) ?? []
            lista = todas.filter { $0.chat == c }.max { $0.cuando < $1.cuando }?.mensaje
        }
        if lista == nil { lista = await crearLista("Tareas", en: c, pinear: false)?.id }
        guard let lista else { return }
        let hecho = await Task.detached { () -> Bool in
            guard let doc = try? nucleo.documentoMiniapp(chat: c, mensaje: lista) else { return false }
            let nuevo = miniTareasAnadir(documento: doc, texto: texto, desfaseMs: desfase)
            return (try? nucleo.guardarMiniapp(chat: c, mensaje: lista, anterior: doc, documento: nuevo)) ?? false
        }.value
        if hecho {
            avisoDeTareas(c)
            avisar("Apuntado en «\(nombre(de: c))»: «\(texto)».")
        } else {
            avisar("No se pudo apuntar: esa lista no está o cambió entre medias.")
        }
    }

    /// `marcar_tarea`, `quitar_tarea` y `corregir_tarea`: la tarea numero
    /// `indice` (desde 0, en el orden del documento) de la lista `codigo`,
    /// como la ventana de tareas. Si la lista cambio entre medias, nada.
    private func cambiarTarea(_ p: Pedido) async {
        guard let nucleo = almacen?.nucleo, let codigo = p.texto("codigo"),
              let indice = p["indice"]?.entero, indice >= 0, let c = await chat(p["proyecto"]) else {
            return avisar("«\(p.accion)» necesita la lista (codigo) y la tarea (indice).")
        }
        let accion = p.accion
        let hecha = p["hecha"]?.booleano ?? true
        let texto = p.texto("texto")
        if accion == "corregir_tarea", texto == nil { return avisar("Una tarea no se queda sin texto: eso es quitarla.") }
        let desfase = desfaseLocalMs()
        let hecho = await Task.detached { () -> Bool in
            guard let doc = try? nucleo.documentoMiniapp(chat: c, mensaje: codigo) else { return false }
            let tareas = miniTareasLeer(documento: doc, desfaseMs: desfase)
            guard let t = tareas.first(where: { $0.indice == UInt32(indice) }) else { return false }
            let nuevo: String
            switch accion {
            case "marcar_tarea":
                if t.hecha == hecha { return true }
                nuevo = miniTareasAlternar(documento: doc, indice: t.indice)
            case "quitar_tarea": nuevo = miniTareasQuitar(documento: doc, indice: t.indice)
            default: nuevo = miniTareasRenombrar(documento: doc, indice: t.indice, texto: texto ?? t.texto)
            }
            return (try? nucleo.guardarMiniapp(chat: c, mensaje: codigo, anterior: doc, documento: nuevo)) ?? false
        }.value
        if hecho { avisoDeTareas(c) } else { avisar("No hay esa tarea en esa lista (o cambió entre medias).") }
    }

    /// `borrar_lista`: la lista entera, como «Borrar» en el chat (quien lo
    /// pide ya pregunto).
    private func borrarLista(_ p: Pedido) async {
        guard let nucleo = almacen?.nucleo, let codigo = p.texto("codigo"), let c = await chat(p["proyecto"]) else { return }
        let desfase = desfaseLocalMs()
        let borrada = await Task.detached { () -> Bool in
            let listas = (try? nucleo.tareas(desfaseMs: desfase)) ?? []
            guard listas.contains(where: { $0.chat == c && $0.mensaje == codigo }) else { return false }
            return ((try? nucleo.borrarMensajes(chat: c, ids: [codigo])) ?? 0) > 0
        }.value
        if borrada {
            avisoDeTareas(c)
            await almacen?.abrir(chat: c)
        } else {
            avisar("Eso no es una lista de tareas.")
        }
    }

    private func avisoDeTareas(_ chat: String) {
        NotificationCenter.default.post(name: .pixpinCambioLocal, object: nil)
        NotificationCenter.default.post(name: .pixpinTareasCambiadas, object: chat)
    }

    // MARK: Pines y capturas

    private func pinear(_ p: Pedido) async {
        if let r = p.texto("ruta") {
            if !GestorPines.compartido.pinear(fichero: URL(fileURLWithPath: r)) { avisar("No se pudo pinear «\(r)».") }
            return
        }
        guard let almacen, let codigo = p.texto("codigo"), let c = await chat(p["proyecto"]),
              let m = await mensaje(codigo, en: c) else { return }
        guard let ruta = m.ruta, let url = await almacen.url(deRuta: ruta, en: c),
              GestorPines.compartido.pinear(fichero: url) else {
            return avisar("Ese mensaje no tiene un fichero que pinear.")
        }
    }

    /// La captura mas reciente de la galeria.
    private func ultimaCaptura() async -> URL? {
        guard let nucleo = almacen?.nucleo else { return nil }
        let dias = AjusteCaducidad.dias
        let desfase = desfaseLocalMs()
        let r = try? await Task.detached {
            try nucleo.galeria(desde: 0, cuantos: 1, dias: dias, desfaseMs: desfase).capturas.first?.ruta
        }.value
        return r.flatMap { $0 }.map { URL(fileURLWithPath: $0) }
    }

    private func pinearUltima() async {
        guard let url = await ultimaCaptura(), GestorPines.compartido.pinear(fichero: url) else {
            return avisar("No hay capturas.")
        }
    }

    /// Solo una captura de la carpeta de capturas (como Windows).
    private func conservar(_ p: Pedido) async {
        guard let nucleo = almacen?.nucleo, let r = p.texto("ruta") else { return }
        let carpeta = URL(fileURLWithPath: nucleo.carpetaCapturas()).standardizedFileURL.path
        let url = URL(fileURLWithPath: r).standardizedFileURL
        guard url.deletingLastPathComponent().path == carpeta else {
            return avisar("Solo se conservan capturas de la carpeta de capturas.")
        }
        let nombre = url.lastPathComponent
        do {
            _ = try await Task.detached { try nucleo.conservarCaptura(nombre: nombre) }.value
            NotificationCenter.default.post(name: .pixpinCambioLocal, object: nil)
            avisar("Conservada en «Mensajes guardados».")
        } catch {
            avisar("No se pudo conservar: \(error)")
        }
    }

    private func copiarImagen(_ p: Pedido) {
        guard let r = p.texto("ruta"), Verbos.esImagen(r), !r.lowercased().hasSuffix(".gif"),
              let imagen = NSImage(contentsOfFile: r) else {
            return avisar("Eso no es una imagen que copiar.")
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([imagen])
    }

    private func pines(_ operacion: String) {
        let g = GestorPines.compartido
        switch operacion {
        case "cerrar": g.cerrarTodos()
        case "ocultar_mostrar": g.alternarTodos()
        case "devolver_ultimo": if !g.restaurarUltimoCerrado() { NSSound.beep() }
        case "paso_de_clics": _ = g.alternarPasoDeClics()
        default: avisar("Los pines no saben «\(operacion)».")
        }
    }

    // MARK: Otros aparatos

    private func sincronizar(_ p: Pedido) async {
        guard let sincro else { return avisar("La sincronización no está lista.") }
        let aparato = p.texto("aparato") ?? "todos"
        if aparato != "todos", !sincro.filas.contains(where: { $0.id == aparato || $0.nombre == aparato }) {
            return avisar("No hay ningún aparato «\(aparato)» en tu grupo.")
        }
        let id = aparato == "todos" ? nil : sincro.filas.first { $0.id == aparato || $0.nombre == aparato }?.id
        avisar("Sincronizando…")
        await sincro.sincronizarAhora(id: id)
    }

    private func alMovil(_ p: Pedido) async {
        guard let sincro else { return avisar("La sincronización no está lista.") }
        guard let urls = ficheros(p, ["imagenes", "archivos"]), !urls.isEmpty else {
            return avisar("No hay nada que mandar al móvil.")
        }
        let aparato = p.texto("aparato") ?? "todos"
        let filas = aparato == "todos" ? sincro.filas : sincro.filas.filter { $0.id == aparato || $0.nombre == aparato }
        guard !filas.isEmpty else { return avisar("No hay ningún aparato «\(aparato)» en tu grupo.") }
        for f in filas { await sincro.enviar(urls, a: f.id) }
    }

    // MARK: Asistente, voz, timeline y texto

    private func preguntar(_ p: Pedido) async {
        if let id = p.texto("automatizacion") {
            return await automatizacion(Pedido("automatizacion", ["operacion": .texto("ejecutar"), "id": .texto(id)]))
        }
        let texto = p.texto("texto") ?? ""
        guard !texto.isEmpty else { return ventana("asistente") }
        let modelo = asistente ?? ModeloAsistente(almacen: almacen)
        asistente = modelo
        modelo.nuevaConversacion()
        avisar("El asistente está en ello: «\(texto.prefix(80))».")
        await modelo.enviar(texto)
        let respuesta = modelo.burbujas.last { !$0.delUsuario }?.texto ?? ""
        avisar(respuesta.isEmpty ? "El asistente no contestó." : String(respuesta.prefix(400)))
    }

    /// `automatizacion` (E6): crear (la receta que manda el asistente tras
    /// preguntar), encender, apagar, borrar (sin preguntar: quien lo manda
    /// ya pregunto) o correr una ya. Lo hecho, en el globo, con los textos
    /// de Windows.
    private func automatizacion(_ p: Pedido) async {
        guard let nucleo = almacen?.nucleo else { return avisar("No se pudo abrir la carpeta de datos de PixPin.") }
        let operacion = p.texto("operacion") ?? ""
        if operacion == "crear" {
            guard let receta = p["receta"], !receta.esNulo else {
                return avisar("No se pudo guardar la automatización: falta la receta")
            }
            let texto = receta.texto ?? receta.json
            do {
                let nombre = try await Task.detached { try nucleo.automatizacionDeReceta(recetaJson: texto) }.value
                NotificationCenter.default.post(name: .pixpinCambioLocal, object: nil)
                avisar("Automatización «\(nombre)» creada.")
            } catch {
                avisar("No se pudo guardar la automatización: \(ModeloAjustes.texto(de: error))")
            }
            return
        }
        guard ["activar", "desactivar", "borrar", "ejecutar"].contains(operacion) else {
            return avisar("Las automatizaciones no saben «\(operacion)».")
        }
        guard let id = p.texto("id") else { return avisar("Falta el id de la automatización.") }
        do {
            let nombre: String? = try await Task.detached { () throws -> String? in
                switch operacion {
                case "activar", "desactivar":
                    return try nucleo.automatizacionActivar(id: id, activa: operacion == "activar")
                case "borrar":
                    return try nucleo.automatizacionBorrar(id: id)
                default:
                    return try nucleo.automatizaciones().first { $0.id == id && $0.rota == nil }?.nombre
                }
            }.value
            guard let nombre else { return avisar("No hay ninguna automatización «\(id)».") }
            switch operacion {
            case "activar": avisar("Automatización «\(nombre)» encendida.")
            case "desactivar": avisar("Automatización «\(nombre)» apagada.")
            case "borrar": avisar("Automatización «\(nombre)» borrada.")
            default:
                MotorAutomatizaciones.compartido.aMano(id)
                avisar("Corriendo «\(nombre)»…")
            }
            if operacion != "ejecutar" { NotificationCenter.default.post(name: .pixpinCambioLocal, object: nil) }
        } catch {
            avisar("No se pudo guardar la automatización: \(ModeloAjustes.texto(de: error))")
        }
    }

    private func leer(_ p: Pedido) {
        if p["parar"]?.booleano == true {
            LeerEnVoz.compartida.soltar()
            return
        }
        var texto = p.texto("texto")
        var titulo = p.texto("titulo") ?? "PixPin Max"
        if texto == nil, let r = p.texto("ruta") {
            let url = URL(fileURLWithPath: r)
            if ["txt", "md", "markdown"].contains(url.pathExtension.lowercased()) {
                texto = try? String(contentsOf: url, encoding: .utf8)
                titulo = p.texto("titulo") ?? url.lastPathComponent
            } else {
                // Un PDF o un Word: su lector, que tiene su voz (L).
                if abrir(fichero: url) { avisar("Pulsa L en el lector para escucharlo.") }
                return
            }
        }
        guard let texto, !texto.isEmpty,
              VozDeLaNota.escuchar(texto: texto, desde: 0, clave: "pedido", titulo: titulo) else {
            return avisar("No hay nada que leer.")
        }
    }

    private func timeline(_ p: Pedido) async {
        guard let texto = p.texto("texto") else { return ventana(IdVentana.timeline) }
        guard let nucleo = almacen?.nucleo else { return }
        let desfase = desfaseLocalMs()
        do {
            _ = try await Task.detached {
                try nucleo.timelineApuntar(texto: texto, fotos: [], audio: nil, duracionMs: 0,
                                           dicho: nil, cuando: nil, desfaseMs: desfase)
            }.value
            NotificationCenter.default.post(name: .pixpinCambioLocal, object: nil)
            avisar("Apuntado en el timeline: «\(texto.prefix(80))».")
        } catch {
            avisar("No se pudo apuntar en el timeline: \(error)")
        }
    }

    /// `ocr`: el texto de una o varias imagenes, al portapapeles.
    /// **Una herramienta del asistente pedida desde fuera** (el MCP:
    /// Claude Desktop o Claude Code; el pedido `herramienta` de Windows). Se
    /// hace por el mismo camino que el asistente (lo que borra pregunta) y
    /// la respuesta va al fichero `respuesta` de una vez (`{"ok","texto"}`),
    /// que es donde la espera `pixpin-mcp`.
    private func herramienta(_ p: Pedido) async {
        let respuesta = p.texto("respuesta")
        func contestar(_ ok: Bool, _ texto: String) {
            guard let respuesta else { return avisar(texto) }
            HacerPedidos.escribirRespuesta(respuesta, ok: ok, texto: texto)
        }
        guard let nombre = p.texto("nombre"), let nucleo = almacen?.nucleo else {
            return contestar(false, "falta el nombre de la herramienta, o PixPin aun no ha abierto sus datos")
        }
        if let q = p.texto("preguntar"), !HacerPedidos.preguntar(q) {
            return contestar(false, "El usuario dijo que no.")
        }
        let args = p["args"]?.json ?? "{}"
        let manos = ManosDelAsistente(nucleo: nucleo, corte: CorteIa.nuevo()) { pregunta, responder in
            responder(HacerPedidos.preguntar(pregunta))
        }
        let desfase = desfaseLocalMs()
        let r = await Task.detached(priority: .userInitiated) {
            Result { try iaHacerHerramienta(nucleo: nucleo, nombre: nombre, argsJson: args, desfaseMs: desfase, app: manos) }
        }.value
        switch r {
        case let .success(t): contestar(true, t)
        case let .failure(e): contestar(false, (e as? ErrorNucleo).map { "\($0)" } ?? e.localizedDescription)
        }
    }

    /// Pregunta al usuario con un aviso del Mac («Claude pide…»).
    static func preguntar(_ pregunta: String) -> Bool {
        let a = NSAlert()
        a.messageText = "PixPin"
        a.informativeText = pregunta
        a.addButton(withTitle: "Sí")
        a.addButton(withTitle: "No")
        NSApp.activate()
        return a.runModal() == .alertFirstButtonReturn
    }

    /// Escribe la respuesta de una vez (aparte y renombrando): quien espera
    /// nunca lee un fichero a medias.
    nonisolated static func escribirRespuesta(_ ruta: String, ok: Bool, texto: String) {
        let destino = URL(fileURLWithPath: ruta)
        let tmp = destino.appendingPathExtension("parte")
        guard let datos = try? JSONSerialization.data(withJSONObject: ["ok": ok, "texto": texto]) else { return }
        try? datos.write(to: tmp)
        try? FileManager.default.moveItem(at: tmp, to: destino)
    }

    private func ocr(_ p: Pedido) async {
        let rutas = ([p.texto("ruta")].compactMap { $0 }) + (p["rutas"]?.lista?.compactMap(\.texto) ?? [])
        var trozos: [String] = []
        for r in rutas {
            guard Verbos.esImagen(r) || ["heic", "tiff"].contains((r as NSString).pathExtension.lowercased()),
                  let fuente = CGImageSourceCreateWithURL(URL(fileURLWithPath: r) as CFURL, nil),
                  let imagen = CGImageSourceCreateImageAtIndex(fuente, 0, nil) else {
                return avisar("«\(r)» no es una imagen.")
            }
            if let t = try? await sacarTexto(de: imagen), !t.isEmpty { trozos.append(t) }
        }
        let texto = trozos.joined(separator: "\n\n")
        guard !texto.isEmpty else { return avisar("No se ve texto en la imagen.") }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(texto, forType: .string)
        avisar("Texto copiado (\(texto.count) caracteres): «\(texto.prefix(60))…»")
    }

    // MARK: Los cuadros

    /// Los ficheros sin pregunta (Servicios → «Preguntar al asistente»): la
    /// caja de Windows para escribir que hacer con ellos.
    private func preguntarAlAsistente(_ rutas: [String]) -> String? {
        let alerta = NSAlert()
        alerta.messageText = rutas.count == 1
            ? "Preguntar al asistente sobre \((rutas[0] as NSString).lastPathComponent)"
            : "Preguntar al asistente sobre \(rutas.count) archivos"
        let caja = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        caja.placeholderString = "¿Qué hago con esto?"
        alerta.accessoryView = caja
        alerta.addButton(withTitle: "Preguntar")
        alerta.addButton(withTitle: "Cancelar")
        alerta.window.initialFirstResponder = caja
        NSApp.activate()
        guard alerta.runModal() == .alertFirstButtonReturn else { return nil }
        let t = caja.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// El cuadro de confirmar: por encima de todo y con «No» por defecto.
    static func cuadroConfirmar(_ cuerpo: String) -> Bool {
        let alerta = NSAlert()
        alerta.messageText = "PixPin Max"
        alerta.informativeText = cuerpo + "\n\n¿Hacerlo?"
        alerta.alertStyle = .warning
        let no = alerta.addButton(withTitle: "No")
        no.keyEquivalent = "\r"
        let si = alerta.addButton(withTitle: "Sí")
        si.keyEquivalent = ""
        alerta.window.level = .modalPanel
        NSApp.activate()
        return alerta.runModal() == .alertSecondButtonReturn
    }

    /// El globo: el aviso de la app (sin botones).
    static func aviso(_ texto: String) {
        CentroAvisos.compartido.avisar(Aviso(id: "pixpin.pedido.\(UUID().uuidString)", categoria: .mini,
                                             titulo: "PixPin Max", texto: texto))
    }
}
