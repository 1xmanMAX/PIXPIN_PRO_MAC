// **La hoja del clip de la caja** (`ventana_chat/hoja_adjuntar.rs` de
// Windows, `Menus2.dc.html` b): una cuadricula con lo de todos los dias
// —foto, archivo, lienzo, nota, lista de tareas, tabla, conversacion y
// captura, con las teclas 1–8— y debajo, en chips, lo que se usa menos.
// Arriba un buscador: se escribe y se filtra («pdf» encuentra Archivo).
//
// Teclado, como alli: 1–8 eligen su baldosa (los numeros no se escriben),
// las flechas mueven lo elegido, Intro lo hace y Esc limpia el buscador o,
// vacio, cierra.
//
// Las entradas que el Mac aun no tiene (la pagina de un proyecto) salen
// apagadas y, pulsadas, lo dicen. Conversacion, Teleprónter y Pronunciar
// abren sus ventanitas de la voz (`VozVentanas/`, E5).

import AppKit
import PixPinCore
import SwiftUI
import UniformTypeIdentifiers

/// Lo que hace cada entrada de la hoja.
enum AccionAdjuntar: Hashable, Sendable {
    case foto, archivo, lienzo, nota, tabla, conversacion, captura
    case pagina, proyecto, telepronter, pronunciar, delMovil
    /// Una mini-app (`tareas`, `cronometro`...), por su nombre en el nucleo.
    case mini(String)

    /// Si el Mac ya la hace. Las que no, salen apagadas.
    var enElMac: Bool {
        switch self {
        case .pagina: false
        default: true
        }
    }
}

/// Una entrada de la hoja.
struct OpcionAdjuntar: Identifiable, Hashable, Sendable {
    let rotulo: String
    /// El rotulo y sus sinonimos, ya normalizados: donde mira el buscador.
    let buscable: String
    let accion: AccionAdjuntar
    /// El color de su cuadrado (solo las baldosas) y su simbolo.
    let color: UInt32
    let simbolo: String
    /// Del 1 al 8 en las baldosas; `nil` en los chips.
    let numero: Int?

    var id: String { rotulo }
    var esBaldosa: Bool { numero != nil }

    init(_ rotulo: String, _ palabras: String, _ accion: AccionAdjuntar,
         color: UInt32 = 0, simbolo: String = "", numero: Int? = nil) {
        self.rotulo = rotulo
        buscable = HojaAdjuntar.normalizar("\(rotulo) \(palabras)")
        self.accion = accion
        self.color = color
        self.simbolo = simbolo
        self.numero = numero
    }
}

enum HojaAdjuntar {
    /// Las columnas de baldosas.
    static let columnas = 4

    /// Las de Windows, en su orden, con sus colores y sus sinonimos.
    static let opciones: [OpcionAdjuntar] = [
        .init("Foto o vídeo", "imagen foto video photo image", .foto,
              color: 0x0A6CD6, simbolo: "photo", numero: 1),
        .init("Archivo", "pdf documento word excel fichero file", .archivo,
              color: 0x636366, simbolo: "doc.text.fill", numero: 2),
        .init("Lienzo", "dibujo pizarra canvas draw", .lienzo,
              color: 0xC77700, simbolo: "pencil.and.scribble", numero: 3),
        .init("Nota", "nota markdown texto note", .nota,
              color: 0x248A3D, simbolo: "list.bullet", numero: 4),
        .init("Lista de tareas", "tareas lista todo checklist", .mini("tareas"),
              color: 0x1E7A4A, simbolo: "checklist", numero: 5),
        .init("Tabla", "tabla hoja calculo excel table", .tabla,
              color: 0x4B49C8, simbolo: "tablecells.fill", numero: 6),
        .init("Conversación", "conversacion voz traducir conversation", .conversacion,
              color: 0x9A3FC4, simbolo: "person.wave.2.fill", numero: 7),
        .init("Captura", "captura pantalla recorte screenshot", .captura,
              color: 0xC93C35, simbolo: "crop", numero: 8),
        .init("Página de un proyecto", "pagina proyecto page", .pagina),
        .init("Proyecto entero", "proyecto entero project", .proyecto),
        .init("Teleprónter", "teleprompter leer", .telepronter),
        .init("Pronunciar", "pronunciar ingles pronounce", .pronunciar),
        .init("Cronómetro", "cronometro stopwatch mini-app", .mini("cronometro")),
        .init("Temporizador", "temporizador timer mini-app", .mini("temporizador")),
        .init("Contador", "contador counter mini-app", .mini("contador")),
        .init("Ruleta", "ruleta sorteo mini-app", .mini("ruleta")),
        .init("Gastos", "gastos dinero mini-app", .mini("gastos")),
        .init("Alarma", "alarma despertador mini-app", .mini("alarma")),
        .init("Traer del móvil", "movil telefono wifi phone", .delMovil),
    ]

    /// Minusculas y sin tildes, para buscar sin pensar en acentos.
    static func normalizar(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
    }

    /// Las que se ven con lo escrito: cada palabra en algun sitio de su
    /// rotulo o sus sinonimos. Primero las baldosas, luego los chips.
    static func visibles(_ busqueda: String, en opciones: [OpcionAdjuntar] = opciones) -> [OpcionAdjuntar] {
        let palabras = normalizar(busqueda).split(whereSeparator: \.isWhitespace)
        guard !palabras.isEmpty else { return opciones }
        return opciones.filter { o in palabras.allSatisfy { o.buscable.contains($0) } }
    }

    /// Mover lo elegido con las flechas (`mover_eleccion` de Windows):
    /// izquierda y derecha de uno en uno; arriba y abajo saltan una fila
    /// entre las baldosas, y de la ultima fila se baja a los chips.
    static func mover(_ actual: Int?, _ flecha: Flecha, cuantas: Int, baldosas: Int) -> Int? {
        guard cuantas > 0 else { return nil }
        guard let n = actual else { return 0 }
        let col = columnas
        let nuevo: Int
        switch flecha {
        case .derecha: nuevo = n + 1
        case .izquierda: nuevo = max(n - 1, 0)
        case .abajo:
            if n + col < baldosas { nuevo = n + col }
            else if n < baldosas { nuevo = baldosas }
            else { nuevo = n + 1 }
        case .arriba:
            if n >= baldosas, n > 0, baldosas > 0 { nuevo = min(n - 1, baldosas - 1) }
            else { nuevo = max(n - col, 0) }
        }
        return min(nuevo, cuantas - 1)
    }

    enum Flecha { case arriba, abajo, izquierda, derecha }
}

// MARK: - La vista

/// La hoja, en el globo que sale del clip.
struct VistaHojaAdjuntar: View {
    let elegir: (AccionAdjuntar) -> Void
    let cerrar: () -> Void
    @State private var busqueda = ""
    /// Lo elegido con las flechas (indice en `visibles`).
    @State private var elegido: Int?
    @State private var encima: String?

    private var visibles: [OpcionAdjuntar] { HojaAdjuntar.visibles(busqueda) }

    var body: some View {
        let visibles = self.visibles
        let baldosas = visibles.filter(\.esBaldosa)
        let chips = visibles.filter { !$0.esBaldosa }
        VStack(alignment: .leading, spacing: 10) {
            buscador
            if visibles.isEmpty {
                Text("Nada coincide con lo buscado")
                    .font(.system(size: 13))
                    .foregroundStyle(Paleta.proyectos.apagado)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            if !baldosas.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4),
                                         count: HojaAdjuntar.columnas), spacing: 4) {
                    ForEach(baldosas) { o in
                        baldosa(o, elegida: visibles.firstIndex(of: o) == elegido)
                    }
                }
            }
            if !chips.isEmpty {
                HStack(spacing: 8) {
                    Text("MÁS").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Paleta.proyectos.apagado)
                    Paleta.proyectos.separador.frame(height: 1)
                }
                .padding(.top, 2)
                FilasDeChips(espacio: 6) {
                    ForEach(chips) { o in
                        chip(o, elegido: visibles.firstIndex(of: o) == elegido)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 460)
        .background(Paleta.chat.cabecera)
    }

    private var buscador: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Paleta.proyectos.apagado)
            CampoDeUnaLinea(texto: $busqueda, invitacion: "Buscar: tabla, cronómetro, PDF…",
                            tamano: 14, foco: true) { t in
                self.tecla(t)
            } alCambiar: { escrito in
                // Los numeros son teclas, no texto: ninguna opcion se busca
                // por uno. El primero que llegue elige su baldosa.
                guard let d = escrito.first(where: \.isNumber) else { return escrito }
                if let n = d.wholeNumberValue, let o = visibles.first(where: { $0.numero == n }) {
                    DispatchQueue.main.async { elegir(o.accion) }
                }
                return escrito.filter { !$0.isNumber }
            }
            Text("Esc")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Paleta.proyectos.apagado)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Paleta.proyectos.apagado.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(Paleta.chat.campo, in: RoundedRectangle(cornerRadius: 10))
        .onChange(of: busqueda) { _, _ in elegido = nil }
    }

    /// Las teclas del buscador que son de la hoja.
    private func tecla(_ t: TeclaDeCampo) -> Bool {
        let visibles = self.visibles
        let baldosas = visibles.filter(\.esBaldosa).count
        switch t {
        case let .flecha(f):
            elegido = HojaAdjuntar.mover(elegido, f, cuantas: visibles.count, baldosas: baldosas)
            return true
        case .intro:
            if let o = visibles[safe: elegido ?? 0] { elegir(o.accion) }
            return true
        case .escape:
            if busqueda.isEmpty { cerrar() } else { busqueda = "" }
            return true
        case .introConMayusculas:
            return false
        }
    }

    private func baldosa(_ o: OpcionAdjuntar, elegida: Bool) -> some View {
        Button { elegir(o.accion) } label: {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(hex: o.color))
                    .frame(width: 48, height: 48)
                    .overlay {
                        Image(systemName: o.simbolo)
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                Text(o.rotulo)
                    .font(.system(size: 13))
                    .foregroundStyle(Paleta.proyectos.texto)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 96)
            .overlay(alignment: .topTrailing) {
                if let n = o.numero {
                    Text("\(n)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Paleta.proyectos.apagado)
                        .frame(width: 16, height: 16)
                        .background(Paleta.proyectos.apagado.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
                        .padding(8)
                }
            }
            .background(fondo(o, elegida: elegida), in: RoundedRectangle(cornerRadius: 14))
            .opacity(o.accion.enElMac ? 1 : 0.45)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { encima = $0 ? o.id : (encima == o.id ? nil : encima) }
        .help(o.accion.enElMac ? "\(o.rotulo) (\(o.numero ?? 0))" : "Aún no está en el Mac")
    }

    private func chip(_ o: OpcionAdjuntar, elegido: Bool) -> some View {
        Button { elegir(o.accion) } label: {
            Text(o.rotulo)
                .font(.system(size: 13))
                .foregroundStyle(elegido ? .white : Paleta.proyectos.texto)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(elegido ? Paleta.chat.azulElegido
                                    : Paleta.proyectos.texto.opacity(encima == o.id ? 0.16 : 0.08),
                            in: Capsule())
                .opacity(o.accion.enElMac ? 1 : 0.45)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { encima = $0 ? o.id : (encima == o.id ? nil : encima) }
        .help(o.accion.enElMac ? o.rotulo : "Aún no está en el Mac")
    }

    private func fondo(_ o: OpcionAdjuntar, elegida: Bool) -> Color {
        if elegida { return Paleta.chat.azulElegido.opacity(0.35) }
        return encima == o.id ? Paleta.proyectos.texto.opacity(0.08) : .clear
    }
}

/// Los chips en filas: los que caben en una, y el resto debajo.
struct FilasDeChips: Layout {
    var espacio: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let filas = colocar(ancho: proposal.width ?? .infinity, subviews)
        return CGSize(width: proposal.width ?? filas.ancho, height: filas.alto)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let filas = colocar(ancho: bounds.width, subviews)
        for (i, p) in filas.sitios.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified)
        }
    }

    private func colocar(ancho: CGFloat, _ subviews: Subviews) -> (sitios: [CGPoint], ancho: CGFloat, alto: CGFloat) {
        var sitios: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, altoFila: CGFloat = 0, mayor: CGFloat = 0
        for s in subviews {
            let t = s.sizeThatFits(.unspecified)
            if x > 0, x + t.width > ancho {
                x = 0
                y += altoFila + espacio
                altoFila = 0
            }
            sitios.append(CGPoint(x: x, y: y))
            x += t.width + espacio
            mayor = max(mayor, x - espacio)
            altoFila = max(altoFila, t.height)
        }
        return (sitios, mayor, y + altoFila)
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

// MARK: - Lo que hace cada entrada

/// Hace una entrada de la hoja en un chat. Cada una hace lo mismo que su
/// `Accion` de Windows con lo que el Mac ya tiene.
@MainActor
enum AdjuntarEnChat {
    static func hacer(_ accion: AccionAdjuntar, chat: String, almacen: Almacen,
                      avisar: @escaping (String) -> Void, abrirVentana: @escaping (String) -> Void) {
        switch accion {
        case .foto:
            elegirFicheros(tipos: [.image, .movie], chat: chat, almacen: almacen)
        case .archivo:
            elegirFicheros(tipos: [], chat: chat, almacen: almacen)
        case .lienzo:
            Task {
                guard let m = await almacen.crearLienzo(en: chat), let referencia = m.referencia else { return }
                VentanasDeLienzo.compartidas.abrir(referencia: referencia, en: chat,
                                                   titulo: "Lienzo nuevo", almacen: almacen)
            }
        case .nota:
            // Windows abre el editor con una nota por nacer; aqui la nota
            // nace ya, con su titulo, y se abre en el editor de notas.
            Task {
                guard let m = await almacen.escribir(nota: "# Nota nueva", en: chat) else { return }
                EditoresDeNotas.compartidos.abrir(m, en: chat, almacen: almacen)
            }
        case let .mini(cual):
            crearMini(cual, chat: chat, almacen: almacen)
        case .tabla:
            crearTabla(chat: chat, almacen: almacen)
        case .captura:
            // Como Windows: la captura de siempre (un poco despues, para que
            // el globo ya no salga en la foto). Su «Al chat» propone este
            // proyecto el primero.
            guard let capturador = Capturador.principal else { return NSSound.beep() }
            UserDefaults.standard.set(chat, forKey: ListaDeProyectos.clave)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { capturador.capturar() }
        case .delMovil:
            abrirVentana("envio")
        case .conversacion:
            VozEnElChat.conversacion(chat: chat, almacen: almacen, avisar: avisar)
        case .telepronter:
            VozEnElChat.telepronter(chat: chat, almacen: almacen, avisar: avisar)
        case .pronunciar:
            VozEnElChat.pronunciar(chat: chat, almacen: almacen, avisar: avisar)
        case .proyecto:
            elegirProyecto(chat: chat, almacen: almacen, avisar: avisar)
        case .pagina:
            let rotulo = HojaAdjuntar.opciones.first { $0.accion == accion }?.rotulo ?? ""
            avisar("«\(rotulo)» aún no está en el Mac")
        }
    }

    /// «Proyecto entero» (Windows): un menu con los otros chats; el elegido
    /// entra como su puerta (no se copia).
    private static func elegirProyecto(chat: String, almacen: Almacen, avisar: @escaping (String) -> Void) {
        let otros = almacen.chats.filter { $0.id != chat && !$0.esAsistente }
        guard !otros.isEmpty else { return avisar("No hay otros proyectos") }
        let menu = NSMenu()
        for f in otros {
            menu.addItem(ItemConAccion.nuevo(f.nombre) {
                let nucleo = almacen.nucleo
                Task {
                    guard let m = try? await Task.detached(operation: {
                        try nucleo.adjuntarProyecto(chat: chat, proyecto: f.id)
                    }).value else { return avisar("No se pudo adjuntar «\(f.nombre)»") }
                    almacen.anadir([m], en: chat)
                    NotificationCenter.default.post(name: .pixpinCambioLocal, object: nil)
                }
            })
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    /// El panel de abrir del sistema; lo elegido se copia al chat.
    private static func elegirFicheros(tipos: [UTType], chat: String, almacen: Almacen) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if !tipos.isEmpty { panel.allowedContentTypes = tipos }
        panel.begin { respuesta in
            guard respuesta == .OK else { return }
            let urls = panel.urls
            Task { @MainActor in await almacen.adjuntar(urls: urls, en: chat) }
        }
    }

    /// El nombre con el que nace una mini-app (el de su entrada, como
    /// `clave_del_nombre` de Windows).
    static func nombre(deMini cual: String) -> String {
        HojaAdjuntar.opciones.first { $0.accion == .mini(cual) }?.rotulo ?? ""
    }

    private static func crearMini(_ cual: String, chat: String, almacen: Almacen) {
        let nucleo = almacen.nucleo
        let titulo = nombre(deMini: cual)
        let moneda = monedaDelAparato()
        Task {
            let r = await Task.detached(priority: .userInitiated) { () -> Result<MensajeChat, Error> in
                Result { try nucleo.crearMiniapp(chat: chat, miniapp: cual, titulo: titulo, moneda: moneda) }
            }.value
            switch r {
            case let .success(m):
                await almacen.alFinal(m, en: chat)
                GestorPines.compartido.pinearMiniapp(chat: chat, mensaje: m.id, miniapp: cual, documento: m.texto)
            case let .failure(e):
                almacen.ponerError("\(e)")
            }
        }
    }

    private static func crearTabla(chat: String, almacen: Almacen) {
        let nucleo = almacen.nucleo
        Task {
            let r = await Task.detached(priority: .userInitiated) { () -> Result<MensajeChat, Error> in
                Result { try nucleo.crearTabla(chat: chat, nombre: "Tabla") }
            }.value
            switch r {
            case let .success(m):
                await almacen.alFinal(m, en: chat)
                HojasDeCalculo.compartidas.abrir(m, en: chat, almacen: almacen)
            case let .failure(e):
                almacen.ponerError("\(e)")
            }
        }
    }
}

extension Almacen {
    /// Un mensaje recien creado, al final de lo cargado (o, si se veia una
    /// pagina del medio, el chat otra vez desde el final).
    func alFinal(_ m: MensajeChat, en chat: String) async {
        if quedanPosteriores(chat: chat) {
            await abrir(chat: chat)
            NotificationCenter.default.post(name: .pixpinCambioLocal, object: nil)
        } else {
            anadir([m], en: chat)
        }
    }
}
