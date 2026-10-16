// App Intents: lo que PixPin ofrece a Siri, Atajos y Spotlight (el
// sustituto de Flow Launcher en Windows, §3 del plan). Solo en la app que
// monta Xcode (`apple/xcode/project.yml`): el extractor de metadatos de App
// Intents es del sistema de compilacion de Xcode, no de SwiftPM.
//
// Cada intencion llama a `AccionesApp` o, las de los pedidos de Windows
// (tarea, lienzo, grabar, abrir proyecto, al movil), a `HacerPedidos`
// (PixPinKit), que trabajan con el mismo almacen y el mismo sincronizador
// que la app.

import AppIntents
import PixPinKit

// MARK: - Proyectos

/// Un proyecto (un chat), para elegirlo en Atajos.
struct ProyectoEntidad: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Proyecto"
    static let defaultQuery = ConsultaProyectos()

    var id: String
    var nombre: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(nombre)")
    }
}

struct ConsultaProyectos: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [ProyectoEntidad] {
        try await todos().filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [ProyectoEntidad] {
        let buscado = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !buscado.isEmpty else { return try await todos() }
        return try await todos().filter {
            $0.nombre.range(of: buscado, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    func suggestedEntities() async throws -> [ProyectoEntidad] {
        try await todos()
    }

    private func todos() async throws -> [ProyectoEntidad] {
        let lista = try await AccionesApp.compartidas.proyectos()
        return lista.map { ProyectoEntidad(id: $0.id, nombre: $0.nombre) }
    }
}

// MARK: - Intenciones

struct CapturarZona: AppIntent {
    static let title: LocalizedStringResource = "Capturar zona"
    static let description = IntentDescription(
        "Elige una zona de la pantalla para copiarla, dejarla flotando o mandarla a un proyecto.")
    /// La captura necesita la app abierta (pinta la seleccion encima).
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        try AccionesApp.compartidas.capturarZona()
        return .result()
    }
}

struct NuevaNotaEnProyecto: AppIntent {
    static let title: LocalizedStringResource = "Nueva nota en proyecto"
    static let description = IntentDescription("Escribe una nota al final de un proyecto de PixPin.")

    @Parameter(title: "Proyecto")
    var proyecto: ProyectoEntidad

    @Parameter(title: "Nota")
    var texto: String

    static var parameterSummary: some ParameterSummary {
        Summary("Escribir \(\.$texto) en \(\.$proyecto)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await AccionesApp.compartidas.escribirNota(texto, en: proyecto.id)
        let frase = "Nota guardada en «\(proyecto.nombre)»."
        return .result(dialog: "\(frase)")
    }
}

struct BuscarEnPixPin: AppIntent {
    static let title: LocalizedStringResource = "Buscar en PixPin"
    static let description = IntentDescription("Busca en todos los proyectos, notas, tareas y momentos.")

    @Parameter(title: "Buscar")
    var consulta: String

    static var parameterSummary: some ParameterSummary {
        Summary("Buscar \(\.$consulta) en PixPin")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let encontrados = try await AccionesApp.compartidas.buscar(consulta)
        let lineas = encontrados.map { $0.detalle.isEmpty ? $0.titulo : "\($0.titulo) — \($0.detalle)" }
        let texto = lineas.joined(separator: "\n")
        let frase = lineas.isEmpty
            ? "No encontré nada con «\(consulta)»."
            : "Encontré \(lineas.count) resultados con «\(consulta)»:\n\(texto)"
        return .result(value: texto, dialog: "\(frase)")
    }
}

struct SincronizarAhora: AppIntent {
    static let title: LocalizedStringResource = "Sincronizar ahora"
    static let description = IntentDescription("Sincroniza con los aparatos de tu grupo que estén en la Wi-Fi.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let resumen = try await AccionesApp.compartidas.sincronizarAhora()
        return .result(dialog: "\(resumen)")
    }
}

// MARK: - Los pedidos de Windows (C2)
//
// Lo que en Windows piden la linea de ordenes, Flow Launcher y los enlaces
// (`docs/integraciones.md`): cada intencion arma el mismo pedido y lo hace
// `HacerPedidos`, como un enlace `pixpinmax://` de la casa (sin preguntar:
// quien usa Atajos ya esta delante del Mac).

/// Hace un pedido con la app abierta.
@MainActor
private func hacerPedido(_ accion: String, _ campos: [String: ValorPedido]) {
    HacerPedidos.compartidos.hacer(Pedido(accion, campos))
}

struct NuevaTarea: AppIntent {
    static let title: LocalizedStringResource = "Nueva tarea"
    static let description = IntentDescription(
        "Apunta una tarea: sin proyecto, en el Inbox de Mensajes guardados; con proyecto, en su última lista.")
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Tarea")
    var texto: String

    @Parameter(title: "Proyecto")
    var proyecto: ProyectoEntidad?

    static var parameterSummary: some ParameterSummary {
        Summary("Apuntar \(\.$texto) en \(\.$proyecto)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        var campos: [String: ValorPedido] = ["texto": .texto(texto)]
        if let proyecto { campos["proyecto"] = .texto(proyecto.id) }
        hacerPedido("anadir_tarea", campos)
        return .result()
    }
}

struct NuevoLienzo: AppIntent {
    static let title: LocalizedStringResource = "Nuevo lienzo"
    static let description = IntentDescription("Crea un lienzo en un proyecto y lo abre.")
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Nombre")
    var nombre: String?

    @Parameter(title: "Proyecto")
    var proyecto: ProyectoEntidad?

    @MainActor
    func perform() async throws -> some IntentResult {
        hacerPedido("lienzo_nuevo", ["nombre": .t(nombre), "proyecto": .t(proyecto?.id)])
        return .result()
    }
}

struct GrabarNotaDeVoz: AppIntent {
    static let title: LocalizedStringResource = "Grabar nota de voz"
    static let description = IntentDescription(
        "Saca el micrófono flotante y graba una nota de voz para un proyecto (otro toque la guarda).")
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Proyecto")
    var proyecto: ProyectoEntidad?

    @MainActor
    func perform() async throws -> some IntentResult {
        hacerPedido("grabar", ["nombre": .texto("Nota de voz"), "proyecto": .t(proyecto?.id)])
        return .result()
    }
}

struct AbrirProyecto: AppIntent {
    static let title: LocalizedStringResource = "Abrir proyecto"
    static let description = IntentDescription("Abre el chat de un proyecto en PixPin.")
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Proyecto")
    var proyecto: ProyectoEntidad

    @MainActor
    func perform() async throws -> some IntentResult {
        hacerPedido("abrir", ["que": .objeto(["tipo": .texto("proyecto"), "proyecto": .texto(proyecto.id)])])
        return .result()
    }
}

struct MandarAlMovil: AppIntent {
    static let title: LocalizedStringResource = "Mandar al móvil"
    static let description = IntentDescription(
        "Manda ficheros a tus aparatos del grupo: las imágenes a su lienzo, lo demás a su chat.")
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Ficheros", supportedContentTypes: [.item])
    var ficheros: [IntentFile]

    @MainActor
    func perform() async throws -> some IntentResult {
        // Un fichero sin ruta (lo dio otra accion de Atajos) se escribe en
        // una carpeta temporal con su nombre.
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("pixpin-al-movil", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        var rutas: [String] = []
        for f in ficheros {
            if let url = f.fileURL {
                rutas.append(url.path)
            } else {
                let url = tmp.appendingPathComponent(f.filename)
                try f.data.write(to: url)
                rutas.append(url.path)
            }
        }
        hacerPedido("enviar_al_movil", ["aparato": .texto("todos"),
                                        "imagenes": .textos(rutas.filter(Verbos.esImagen)),
                                        "archivos": .textos(rutas.filter { !Verbos.esImagen($0) })])
        return .result()
    }
}

// MARK: - Frases para Siri y Spotlight

struct AtajosPixPin: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CapturarZona(),
            phrases: [
                "Capturar zona con \(.applicationName)",
                "Hacer una captura con \(.applicationName)",
            ],
            shortTitle: "Capturar zona",
            systemImageName: "camera.viewfinder")
        AppShortcut(
            intent: NuevaNotaEnProyecto(),
            phrases: [
                "Nueva nota en \(.applicationName)",
                "Apuntar una nota en \(.applicationName)",
            ],
            shortTitle: "Nueva nota",
            systemImageName: "square.and.pencil")
        AppShortcut(
            intent: BuscarEnPixPin(),
            phrases: [
                "Buscar en \(.applicationName)",
            ],
            shortTitle: "Buscar",
            systemImageName: "magnifyingglass")
        AppShortcut(
            intent: SincronizarAhora(),
            phrases: [
                "Sincronizar \(.applicationName)",
                "Sincronizar \(.applicationName) ahora",
            ],
            shortTitle: "Sincronizar ahora",
            systemImageName: "arrow.triangle.2.circlepath")
        AppShortcut(
            intent: NuevaTarea(),
            phrases: [
                "Nueva tarea en \(.applicationName)",
                "Apuntar una tarea en \(.applicationName)",
            ],
            shortTitle: "Nueva tarea",
            systemImageName: "checklist")
        AppShortcut(
            intent: NuevoLienzo(),
            phrases: ["Nuevo lienzo en \(.applicationName)"],
            shortTitle: "Nuevo lienzo",
            systemImageName: "scribble.variable")
        AppShortcut(
            intent: GrabarNotaDeVoz(),
            phrases: ["Grabar una nota de voz con \(.applicationName)"],
            shortTitle: "Grabar nota de voz",
            systemImageName: "mic")
        AppShortcut(
            intent: AbrirProyecto(),
            phrases: ["Abrir un proyecto de \(.applicationName)"],
            shortTitle: "Abrir proyecto",
            systemImageName: "folder")
        AppShortcut(
            intent: MandarAlMovil(),
            phrases: ["Mandar al móvil con \(.applicationName)"],
            shortTitle: "Mandar al móvil",
            systemImageName: "iphone.and.arrow.forward")
    }
}
