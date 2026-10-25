// **La ventana de las figuras** (`ventana_editor/figuras/ventana.rs` de
// Windows, 22 al 25-oct-2026): el boton Figuras del lienzo abre una ventana
// aparte, grande, en vez del menu con submenus; la entrada «Figuras…» del
// menu de la barra abre la misma, para mirar (sin lienzo donde insertar).
//
// Con la barra comun (`Cabecera`) y los colores de las ventanas v2:
//
// - **a la izquierda**, las categorias con cuantas tiene cada una y, debajo,
//   lo demas que traia el menu (grafica, tablas, instrumentos);
// - **en medio**, las miniaturas grandes con su nombre, por categorias, y
//   el buscador arriba;
// - **a la derecha**, la elegida en grande: si es una plantilla con numeros,
//   con su intervalo («del 1 al 40, de 10 en 10») para insertarla ya
//   alargada; las propias, con renombrar; y quitar.
//
// Doble clic o «Insertar» (Intro) la pone en medio de lo que se ve del
// lienzo y la ventana se cierra. Lo que se busca, se filtra, se alarga y se
// guarda es de Rust (`galeria_figuras.rs`); las miniaturas son el bufer de
// siempre, pintado con `PintorLienzo` como la vista previa de un lienzo.
//
// **Elegir para adjuntar** (Windows 1d50a7c, el usuario: «adjuntar figura
// deberia abrir directamente la ventana de figuras, yo selecciono, aparece
// el boton de adjuntar y se adjunta al chat»): abierta desde «Figura» de la
// hoja del clip de un chat (`abrirParaAdjuntar`), la ventana sabe a que chat
// va. El panel lleva entonces, justo debajo del dibujo, el boton grande
// «Adjuntar a …»; doble clic en una figura o Intro hacen lo mismo. La figura
// entra en el chat como un lienzo con ella dentro y la ventana se queda
// abierta con «Adjuntada ✓», por si se quiere otra.
//
// Lo que falta respecto a Windows: mover lo elegido con las flechas.

import AppKit
import PixPinCore
import SwiftUI

/// Las medidas de Windows (pixeles logicos).
private enum MedidasFiguras {
    static let lateral: CGFloat = 236
    static let panel: CGFloat = 340
    static let celda: CGFloat = 184
    static let mini: CGFloat = 196
    static let filaLateral: CGFloat = 34
    /// El papel claro de las miniaturas: las plantillas son hojas blancas.
    static let papel = Color(hex: 0xF2F2F5)
    /// El fondo de los lados, un poco mas claro que la ventana.
    static let lado = Color(hex: 0x202022)
}

/// El chat al que se adjunta lo que se elija (la ventana abierta desde el
/// clip de uno); `adjuntar` mete la figura `id` en el.
struct ChatDeLaFigura {
    let chat: String
    /// Su nombre, para el boton («Adjuntar a «Casa Lima»»).
    let nombre: String
    let adjuntar: @MainActor (FichaDeFigura) -> Void
}

/// Un grupo de la rejilla: el titulo de su categoria y sus figuras.
struct GrupoVisibleFiguras: Identifiable {
    let nombre: String
    var fichas: [FichaDeFigura]
    var id: String { nombre }
}

/// El estado de la ventana.
@MainActor
final class ModeloFiguras: ObservableObject {
    let galeria: GaleriaFiguras
    /// El lienzo donde se inserta (el que abrio la ventana); sin el, solo se
    /// mira, se renombra y se quita.
    weak var destino: ModeloEditorLienzo? {
        didSet { objectWillChange.send() }
    }
    /// El chat al que se adjunta (abierta desde su clip); sin el, no se
    /// adjunta nada.
    @Published var paraElChat: ChatDeLaFigura?
    /// «Adjuntada a … ✓», mientras se ve.
    @Published private(set) var aviso: String?
    private var avisos = 0

    @Published var consulta = "" { didSet { if consulta != oldValue { rehacer() } } }
    /// `nil`: todas.
    @Published var categoria: String? { didSet { if categoria != oldValue { rehacer() } } }
    @Published private(set) var categorias: [CategoriaDeFiguras] = []
    @Published private(set) var lista: [FichaDeFigura] = []
    @Published private(set) var cuantas: UInt32 = 0
    @Published private(set) var elegida: FichaDeFigura?
    @Published private(set) var campos: [CampoDeIntervalo] = []
    @Published var valores: [String: String] = [:] { didSet { rehacerPrevia() } }
    @Published private(set) var previa: PreviaDeIntervalo?
    @Published private(set) var detalle: DetalleDeFigura?
    @Published var nombre = ""
    @Published var confirmarQuitar = false
    @Published private(set) var miniaturas: [String: LienzoLeido] = [:]
    private var pedidas: Set<String> = []

    init(galeria: GaleriaFiguras, destino: ModeloEditorLienzo?) {
        self.galeria = galeria
        self.destino = destino
        rehacer()
    }

    /// Con titulos de categoria: sin filtrar ni buscar.
    var conTitulos: Bool {
        categoria == nil && consulta.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// La rejilla por categorias, en su orden.
    var grupos: [GrupoVisibleFiguras] {
        var v: [GrupoVisibleFiguras] = []
        for f in lista {
            if v.last?.nombre == f.categoria {
                v[v.count - 1].fichas.append(f)
            } else {
                v.append(GrupoVisibleFiguras(nombre: f.categoria, fichas: [f]))
            }
        }
        return v
    }

    /// Los campos del intervalo de dos en dos; el «de … en …», solo.
    var filasDeCampos: [[CampoDeIntervalo]] {
        var filas: [[CampoDeIntervalo]] = []
        var i = 0
        while i < campos.count {
            let par = i + 1 < campos.count && !campos[i].aLoAncho && !campos[i + 1].aLoAncho
            filas.append(par ? [campos[i], campos[i + 1]] : [campos[i]])
            i += par ? 2 : 1
        }
        return filas
    }

    var puedeInsertar: Bool { destino?.vista != nil }
    var puedeGuardarSeleccion: Bool { destino?.hayElegidos == true && destino?.nucleo != nil }

    /// **Adjunta la elegida** al chat de `paraElChat`, si lo hay, y deja el
    /// aviso un momento (1,8 s, `DURA_AVISO`). `false` sin chat: la ventana
    /// se abrio para mirar.
    @discardableResult
    func adjuntar() -> Bool {
        guard let d = paraElChat, let e = elegida else { return false }
        d.adjuntar(e)
        aviso = "Adjuntada a «\(d.nombre)» ✓"
        avisos += 1
        let mio = avisos
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1800))
            guard let self, self.avisos == mio else { return }
            self.aviso = nil
        }
        return true
    }

    /// Vuelve a leer la biblioteca (se guardo una desde el lienzo o el chat).
    func releer() {
        try? galeria.releer()
        miniaturas = [:]
        pedidas = []
        rehacer()
    }

    func rehacer() {
        categorias = galeria.categorias()
        if let c = categoria, !categorias.contains(where: { $0.nombre == c }) { categoria = nil }
        cuantas = galeria.cuantas()
        lista = galeria.visibles(categoria: categoria, consulta: consulta)
        if let e = elegida, let ahora = lista.first(where: { $0.id == e.id }) {
            elegida = ahora
        } else {
            elegir(lista.first)
        }
    }

    func elegir(_ f: FichaDeFigura?) {
        guard f?.id != elegida?.id else { return }
        elegida = f
        confirmarQuitar = false
        campos = f.map { galeria.campos(id: $0.id) } ?? []
        detalle = f.flatMap { galeria.detalle(id: $0.id) }
        nombre = f?.nombre ?? ""
        valores = [:]
        previa = nil
    }

    /// La miniatura de una figura: se pinta una vez, fuera del hilo
    /// principal, la primera vez que se ve.
    func pedirMiniatura(_ id: String) {
        guard miniaturas[id] == nil, !pedidas.contains(id) else { return }
        pedidas.insert(id)
        let galeria = self.galeria
        Task {
            let leido = await Task.detached(priority: .userInitiated) { () -> LienzoLeido? in
                guard let plano = galeria.plano(id: id) else { return nil }
                return try? leerLienzo(plano)
            }.value
            if let leido { miniaturas[id] = leido }
        }
    }

    private var valoresPedidos: [ValorDeCampo] {
        valores.map { ValorDeCampo(clave: $0.key, texto: $0.value) }
    }

    private func rehacerPrevia() {
        guard let e = elegida, e.alargable else { previa = nil; return }
        previa = galeria.previa(id: e.id, valores: valoresPedidos)
    }

    /// **Insertar** la elegida en medio de lo que se ve del lienzo (con su
    /// intervalo, alargada) y cerrar; si el intervalo no vale, lo dice.
    func insertar() {
        guard let e = elegida, let destino, let vista = destino.vista else { return }
        let c = vista.centroMundo
        do {
            if try galeria.insertar(id: e.id, valores: valoresPedidos, editor: destino.editor,
                                    centroX: Float(c.x), centroY: Float(c.y)) {
                vista.trasCambio()
                destino.refrescarBarra()
                VentanaFiguras.cerrar()
                vista.window?.makeKeyAndOrderFront(nil)
            }
        } catch {
            previa = galeria.previa(id: e.id, valores: valoresPedidos)
                ?? PreviaDeIntervalo(texto: "\(error)", error: true)
        }
    }

    func renombrar() {
        guard let e = elegida else { return }
        if (try? galeria.renombrar(id: e.id, nombre: nombre)) == true { rehacer() }
    }

    /// Quitar: el primer clic pide confirmarlo, el segundo la quita.
    func quitar() {
        guard let e = elegida else { return }
        guard confirmarQuitar else { confirmarQuitar = true; return }
        confirmarQuitar = false
        if (try? galeria.quitar(id: e.id)) == true {
            elegida = nil
            rehacer()
        }
    }

    /// Lo demas que traia el menu: se cierra la ventana y lo hace el lienzo
    /// (sus cajetines son hojas de su ventana).
    func herramienta(_ hacer: @escaping (ModeloEditorLienzo) -> Void) {
        guard let destino else { return }
        VentanaFiguras.cerrar()
        destino.vista?.window?.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { hacer(destino) }
    }
}

/// La ventana, una sola a la vez.
@MainActor
public enum VentanaFiguras {
    private static var ventana: NSWindow?
    private static var modelo: ModeloFiguras?

    /// **Abre la ventana**, o la trae delante: con `destino`, lo elegido se
    /// inserta en ese lienzo.
    static func abrir(nucleo: Nucleo, destino: ModeloEditorLienzo?) {
        abrir(nucleo: nucleo, destino: destino, paraElChat: nil)
    }

    /// **Abre la ventana para adjuntar una figura al chat** (el clip →
    /// «Figura»). Si ya estaba abierta, cambia a ese chat y se trae delante.
    static func abrirParaAdjuntar(nucleo: Nucleo, chat: ChatDeLaFigura) {
        abrir(nucleo: nucleo, destino: nil, paraElChat: chat)
    }

    private static func abrir(nucleo: Nucleo, destino: ModeloEditorLienzo?, paraElChat: ChatDeLaFigura?) {
        if let v = ventana, let m = modelo {
            m.destino = destino
            m.paraElChat = paraElChat
            m.releer()
            v.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        guard let galeria = try? nucleo.galeriaDeFiguras() else { return NSSound.beep() }
        let m = ModeloFiguras(galeria: galeria, destino: destino)
        m.paraElChat = paraElChat
        // Grande: casi toda la pantalla de trabajo, hasta 1440 x 900.
        let area = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1600, height: 900)
        let marco = NSRect(x: 0, y: 0, width: min(1440, area.width * 0.9), height: min(900, area.height * 0.9))
        let v = NSWindow(contentRect: marco, styleMask: [.titled, .closable, .miniaturizable, .resizable],
                         backing: .buffered, defer: false)
        v.title = "Figuras"
        v.isReleasedWhenClosed = false
        v.contentView = NSHostingView(rootView: VistaFiguras(modelo: m).ventanaConCabecera())
        v.center()
        _ = v.setFrameAutosaveName("PixPinFiguras")
        ventana = v
        modelo = m
        v.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    static func cerrar() {
        ventana?.close()
    }

    /// Tras guardar una figura desde otro sitio, o cuando la sincronizacion
    /// trae `figuras.json` de otro aparato: si esta abierta, se ve ya.
    public static func releer() {
        guard ventana?.isVisible == true else { return }
        modelo?.releer()
    }
}

// MARK: - Las vistas

struct VistaFiguras: View {
    @ObservedObject var modelo: ModeloFiguras
    @Environment(\.ventanaDeLaVista) private var ventana

    var body: some View {
        VStack(spacing: 0) {
            // Eligiendo para un chat, el subtitulo dice para cual.
            Cabecera("Figuras", subtitulo: modelo.paraElChat.map { "Elige una figura para «\($0.nombre)»" }
                         ?? "\(modelo.cuantas) figuras y plantillas",
                     buscador: BuscadorCabecera($modelo.consulta, pista: "Buscar figuras", enfocar: true)) {
                if modelo.puedeGuardarSeleccion {
                    BotonCabecera(icono: "rectangle.stack.badge.plus", rotulo: "Guardar lo elegido") {
                        modelo.herramienta { $0.guardarComoFigura() }
                    }
                }
            }
            HStack(spacing: 0) {
                LateralFiguras(modelo: modelo)
                    .frame(width: MedidasFiguras.lateral)
                RejillaFiguras(modelo: modelo)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .bottom) {
                        // «Adjuntada a … ✓», una pastilla abajo en el centro.
                        if let aviso = modelo.aviso {
                            Text(aviso)
                                .font(.system(size: 14))
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 9)
                                .background(Color(hex: 0x248A3D), in: Capsule())
                                .padding(.bottom, 40)
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeOut(duration: 0.15), value: modelo.aviso)
                PanelFiguras(modelo: modelo)
                    .frame(width: MedidasFiguras.panel)
            }
        }
        .frame(minWidth: 960, minHeight: 600)
        .background(Paleta.v2.fondo)
        .environment(\.colorScheme, .dark)
        .background {
            // Esc: primero lo buscado; sin nada buscado, cierra.
            Button("") {
                if modelo.consulta.isEmpty { VentanaLisa.cerrar(ventana?.ventana) } else { modelo.consulta = "" }
            }
            .keyboardShortcut(.cancelAction)
            .hidden()
        }
    }
}

/// Una fila de la barra de la izquierda: el rotulo, su cuenta a la derecha
/// y, elegida, el fondo de tarjeta con la raya azul.
private struct FilaLateralFiguras: View {
    let rotulo: String
    var cuenta: UInt32?
    var elegida = false
    let accion: () -> Void
    @State private var encima = false

    var body: some View {
        Button(action: accion) {
            HStack(spacing: 6) {
                Text(rotulo)
                    .font(.system(size: 13.5))
                    .foregroundStyle(elegida ? Paleta.v2.texto : Paleta.v2.cuerpo)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let cuenta {
                    Text("\(cuenta)")
                        .font(.system(size: 12))
                        .foregroundStyle(Paleta.v2.gris)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: MedidasFiguras.filaLateral)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(elegida ? Paleta.v2.tarjetaEncima : encima ? Paleta.v2.tarjeta : .clear)
            }
            .overlay(alignment: .leading) {
                if elegida {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Paleta.v2.acento)
                        .frame(width: 3)
                        .padding(.vertical, 9)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { encima = $0 }
    }
}

private struct LateralFiguras: View {
    @ObservedObject var modelo: ModeloFiguras

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                FilaLateralFiguras(rotulo: "Todas", cuenta: modelo.cuantas,
                                   elegida: modelo.categoria == nil) { modelo.categoria = nil }
                ForEach(modelo.categorias, id: \.nombre) { c in
                    FilaLateralFiguras(rotulo: c.nombre, cuenta: c.cuenta,
                                       elegida: modelo.categoria == c.nombre) { modelo.categoria = c.nombre }
                }
                // Lo demas que traia el menu.
                if modelo.destino != nil {
                    Paleta.v2.linea.frame(height: 1).padding(.vertical, 12)
                    Text("INSERTAR")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Paleta.v2.gris)
                        .padding(.leading, 14)
                        .padding(.bottom, 6)
                    FilaLateralFiguras(rotulo: "Gráfica de una función…") { modelo.herramienta { $0.pedirGrafica() } }
                    FilaLateralFiguras(rotulo: "Tabla en blanco") { modelo.herramienta { $0.pedirTablaEnBlanco() } }
                    FilaLateralFiguras(rotulo: "Pegar tabla (de Excel)") { modelo.herramienta { $0.pegarTabla() } }
                    FilaLateralFiguras(rotulo: "Plano de funciones") { modelo.herramienta { $0.estamparInstrumentoEnMedio(2) } }
                    FilaLateralFiguras(rotulo: "Recta de funciones") { modelo.herramienta { $0.estamparInstrumentoEnMedio(1) } }
                    FilaLateralFiguras(rotulo: "Espacio xyz") { modelo.herramienta { $0.estamparInstrumentoEnMedio(3) } }
                }
            }
            .padding(12)
        }
        .background(MedidasFiguras.lado)
    }
}

private struct RejillaFiguras: View {
    @ObservedObject var modelo: ModeloFiguras

    private let columnas = [GridItem(.adaptive(minimum: MedidasFiguras.celda, maximum: 260), spacing: 22)]

    var body: some View {
        if modelo.lista.isEmpty {
            Text("No hay ninguna figura que lo tenga")
                .font(.system(size: 13.5))
                .foregroundStyle(Paleta.v2.gris)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if modelo.conTitulos {
                        ForEach(modelo.grupos) { g in
                            Text(g.nombre)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Paleta.v2.texto)
                                .padding(.top, 10)
                            celdas(g.fichas)
                        }
                    } else {
                        celdas(modelo.lista)
                    }
                }
                .padding(22)
            }
        }
    }

    private func celdas(_ fichas: [FichaDeFigura]) -> some View {
        LazyVGrid(columns: columnas, alignment: .leading, spacing: 22) {
            ForEach(fichas, id: \.id) { f in
                CeldaFigura(ficha: f, mini: modelo.miniaturas[f.id], elegida: modelo.elegida?.id == f.id)
                    .onAppear { modelo.pedirMiniatura(f.id) }
                    .onTapGesture(count: 2) {
                        modelo.elegir(f)
                        // Eligiendo para un chat, el doble clic la adjunta.
                        if !modelo.adjuntar() { modelo.insertar() }
                    }
                    .onTapGesture { modelo.elegir(f) }
            }
        }
    }
}

/// La miniatura de una figura sobre su papel claro.
private struct MiniaturaFigura: View {
    let mini: LienzoLeido?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(MedidasFiguras.papel)
            if let mini {
                // Sin raton: los clics son de la celda.
                VistaLienzo(lienzo: mini)
                    .allowsHitTesting(false)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(8)
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }
}

private struct CeldaFigura: View {
    let ficha: FichaDeFigura
    let mini: LienzoLeido?
    let elegida: Bool
    @State private var encima = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MiniaturaFigura(mini: mini)
                .frame(height: MedidasFiguras.mini - 20)
                .padding(10)
            Text(ficha.corto)
                .font(.system(size: 12.5))
                .foregroundStyle(elegida ? Paleta.v2.texto : Paleta.v2.cuerpo)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
        }
        .background(encima ? Paleta.v2.tarjetaEncima : Paleta.v2.tarjeta, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            if elegida {
                RoundedRectangle(cornerRadius: 14).strokeBorder(Paleta.v2.acento, lineWidth: 2).padding(-3)
            }
        }
        .contentShape(Rectangle())
        .onHover { encima = $0 }
        .help(ficha.nombre)
    }
}

/// La elegida en grande, con su intervalo, su nombre y sus botones.
private struct PanelFiguras: View {
    @ObservedObject var modelo: ModeloFiguras
    /// Con el foco en el nombre, Intro renombra (y no inserta).
    @FocusState private var enNombre: Bool

    var body: some View {
        Group {
            if let f = modelo.elegida {
                VStack(alignment: .leading, spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) { cuerpo(f) }
                    }
                    botones(f)
                }
                .padding(20)
            } else {
                Text("Elige una figura para verla en grande")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Paleta.v2.gris)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(MedidasFiguras.lado)
    }

    @ViewBuilder
    private func cuerpo(_ f: FichaDeFigura) -> some View {
        MiniaturaFigura(mini: modelo.miniaturas[f.id])
            .frame(height: modelo.campos.isEmpty ? 300 : 230)
            .onAppear { modelo.pedirMiniatura(f.id) }
            .padding(.bottom, 16)
        // Eligiendo para un chat, el boton grande va justo debajo del
        // dibujo: es lo primero que se busca al elegir una.
        if let d = modelo.paraElChat {
            Button { _ = modelo.adjuntar() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "paperclip")
                    Text("Adjuntar a «\(d.nombre)»")
                        .font(.system(size: 15, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color(hex: 0x0A6CD6), in: RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(enNombre ? nil : KeyboardShortcut.defaultAction)
            Text("O doble clic en la figura, o Intro.")
                .font(.system(size: 11.5))
                .foregroundStyle(Paleta.v2.gris)
                .padding(.top, 6)
                .padding(.bottom, 18)
        }
        Text(f.corto)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(Paleta.v2.texto)
            .lineLimit(2)
        Text("\(f.categoria)  ·  \(f.piezas) piezas")
            .font(.system(size: 12.5))
            .foregroundStyle(Paleta.v2.gris)
            .lineLimit(1)
            .padding(.top, 4)
            .padding(.bottom, 18)
        if !modelo.campos.isEmpty {
            rotulo("Intervalo")
            ForEach(Array(modelo.filasDeCampos.enumerated()), id: \.offset) { _, fila in
                HStack(spacing: 8) {
                    ForEach(fila, id: \.clave) { c in campo(c) }
                }
                .padding(.bottom, 8)
            }
            if let p = modelo.previa {
                Text(p.error ? p.texto : "→ \(p.texto)")
                    .font(.system(size: 12.5))
                    .foregroundStyle(p.error ? Paleta.v2.rojo : Paleta.v2.acento)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 12)
            }
        }
        if !f.deSerie {
            rotulo("Nombre")
            HStack(spacing: 8) {
                TextField("", text: $modelo.nombre)
                    .textFieldStyle(.roundedBorder)
                    .focused($enNombre)
                    .onSubmit { modelo.renombrar() }
                Button("Renombrar") { modelo.renombrar() }
                    .disabled(modelo.nombre.trimmingCharacters(in: .whitespaces).isEmpty || modelo.nombre == f.nombre)
            }
            .padding(.bottom, 16)
        }
        // Sin lienzo donde insertar, lo que el previsualizador del chat
        // cuenta de ella.
        if modelo.destino == nil, let d = modelo.detalle {
            rotulo("Mide")
            Text("\(Int(f.ancho.rounded())) × \(Int(f.alto.rounded()))")
                .font(.system(size: 12.5)).foregroundStyle(Paleta.v2.cuerpo).padding(.bottom, 12)
            rotulo("Piezas")
            Text(Self.resumen(d))
                .font(.system(size: 12.5)).foregroundStyle(Paleta.v2.cuerpo).padding(.bottom, 12)
            if !d.letras.isEmpty {
                rotulo("Textos que lleva")
                Text(d.letras.prefix(12).joined(separator: " · "))
                    .font(.system(size: 12.5)).foregroundStyle(Paleta.v2.cuerpo)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func botones(_ f: FichaDeFigura) -> some View {
        VStack(spacing: 8) {
            if modelo.destino != nil {
                Button { modelo.insertar() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                        Text("Insertar").font(.system(size: 13.5, weight: .medium))
                        Chapa(texto: "Intro")
                    }
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Paleta.v2.azulLleno, in: RoundedRectangle(cornerRadius: 10))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(enNombre ? nil : KeyboardShortcut.defaultAction)
                .disabled(!modelo.puedeInsertar)
            }
            Button { modelo.quitar() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "trash")
                    Text(modelo.confirmarQuitar ? "Pulsa otra vez para quitarla" : "Quitar")
                        .font(.system(size: 13.5, weight: .medium))
                }
                .foregroundStyle(modelo.confirmarQuitar ? Color.white : Paleta.v2.rojo)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(modelo.confirmarQuitar ? Paleta.v2.rojo : Paleta.v2.caja,
                            in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 12)
    }

    private func rotulo(_ s: String) -> some View {
        Text(s.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Paleta.v2.gris)
            .padding(.bottom, 6)
    }

    /// Un campo del intervalo: su rotulo encima y la caja con la pista de
    /// lo que trae la de serie.
    private func campo(_ c: CampoDeIntervalo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(c.rotulo)
                .font(.system(size: 12))
                .foregroundStyle(Paleta.v2.cuerpo)
                .lineLimit(1)
            TextField("", text: Binding(get: { modelo.valores[c.clave] ?? "" },
                                        set: { modelo.valores[c.clave] = $0 }),
                      prompt: Text(c.pista).foregroundStyle(Paleta.v2.gris))
                .textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// «3 líneas · 2 formas · 4 textos» (`resumen_de_piezas` de Windows).
    static func resumen(_ d: DetalleDeFigura) -> String {
        var v: [String] = []
        if d.lineas > 0 { v.append("\(d.lineas) líneas") }
        if d.formas > 0 { v.append("\(d.formas) formas") }
        if d.textos > 0 { v.append("\(d.textos) textos") }
        if d.trazos > 0 { v.append("\(d.trazos) trazos a mano") }
        if d.otras > 0 { v.append("\(d.otras) otras") }
        return v.isEmpty ? "\(d.total)" : v.joined(separator: " · ")
    }
}
