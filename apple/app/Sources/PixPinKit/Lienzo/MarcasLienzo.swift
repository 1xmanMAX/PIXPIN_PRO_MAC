// **Los marcadores del lienzo con su vista** (Windows,
// `ventana_editor/marcas.rs`, 25-oct-2026: como las vistas con nombre de
// AutoCAD). Las cuentas y los ficheros estan en Rust
// (`pixpin-nucleo/src/marcas_lienzo.rs`, `MarcasDelLienzo`): la linea
// `pins/draw/<d>.marcas` y el `pins/draw/<d>.vistas.json` del chat, los
// mismos que Windows y el movil. Aqui queda lo de la ventana:
//
// - **Poner**: el marcador del riel o ⌘M abren la tira de emoticonos; se
//   elige uno (o su cifra, 1-9 y 0) y el siguiente clic en el lienzo lo
//   planta, con lo que se ve en ese momento como su vista. ⎋ deja de ponerlo.
// - **Ir**: un clic en su punto del riel, ⌘1…9, o un clic en la marca misma
//   con cualquier herramienta menos la de elegir. Con vista, la camara viaja
//   hasta ella (encuadre y aumento); sin ella, hasta dejarla arriba.
// - **Su vista, la de ahora**: ⇧clic en la marca o en su punto (o ⌘⇧1…9).
// - **Mover**: con la herramienta de elegir. **Quitar**: clic derecho encima.

import AppKit
import PixPinCore
import SwiftUI

/// En que anda la puesta de una marca (`Poniendo` de Windows).
public enum PonerMarcaLienzo: Equatable {
    /// Nada: el riel en reposo.
    case no
    /// La tira abierta, esperando emoticono.
    case eligiendo
    /// Emoticono elegido: el siguiente clic en el lienzo la planta.
    case plantando(String)
}

/// Medidas de las marcas, las de Windows.
enum MedidasMarcasLienzo {
    /// El radio del redondel de una marca sobre el lienzo (`RADIO_MARCA`).
    static let radio: CGFloat = 18
    /// El fondo oscuro de los redondeles y de la tira, el `#14182B` del movil.
    static let oscuro = NSColor(red: 0x14 / 255.0, green: 0x18 / 255.0, blue: 0x2b / 255.0, alpha: 1)
    /// Lo que ocupa cada punto del riel a lo alto, y sus diametros en
    /// reposo, con el raton en el riel y el elegido (`riel_marcas`).
    static let paso: CGFloat = 30
    static let reposo: CGFloat = 20
    static let cerca: CGFloat = 26
    static let elegido: CGFloat = 44
    /// Cuanto se adelanta el elegido hacia dentro.
    static let salto: CGFloat = 40
    /// El borde de abajo de la barra de herramientas (una fila), o de la
    /// barra del pin si baja mas: ahi va la tira y ahi queda la marca a la
    /// que se va (`bajo_la_barra` de Windows).
    static var bajoLaBarra: CGFloat {
        max(MedidasBarraLienzo.distanciaBorde + MedidasBarraLienzo.lado + 2 * MedidasBarraLienzo.relleno,
            BarraFlotante.alto + 2 * BarraFlotante.separacion)
    }
    /// Cuanto se ve la pastilla de «vista guardada» (`AVISO_VISTA`).
    static let avisoVista: TimeInterval = 1.8
}

// MARK: - El modelo

extension ModeloEditorLienzo {
    /// Las marcas del dibujo que se abre en su ventana (las lee de disco).
    func cargarMarcas() {
        guard marcas == nil else { return }
        marcas = MarcasDelLienzo.juntoAlDibujo(ruta: editor.ruta())
        listaMarcas = marcas?.lista() ?? []
    }

    /// Lo que llego de otro aparato (la ventana vuelve al frente).
    public func releerMarcas() {
        guard let m = marcas, m.releer() else { return }
        refrescarMarcas()
    }

    /// La lista otra vez desde Rust, y el lienzo repintado.
    func refrescarMarcas() {
        listaMarcas = marcas?.lista() ?? []
        vista?.needsDisplay = true
    }

    /// El marcador del riel o ⌘M: abre la tira o deja de poner.
    public func alternarPonerMarca() {
        poniendoMarca = poniendoMarca == .no ? .eligiendo : .no
    }

    /// Un emoticono de la tira: el siguiente clic lo planta.
    public func elegirEmoji(_ emoji: String) {
        poniendoMarca = .plantando(emoji)
    }

    /// Ir a la marca `id` (su punto del riel): la vista hace el viaje.
    public func irAMarca(_ id: Int64) {
        vista?.irAMarca(id)
    }

    /// ⇧clic o ⌘⇧1…9: la vista de la marca `id`, la de ahora.
    public func fijarVistaDeMarca(_ id: Int64) {
        vista?.fijarVistaDeMarca(id)
    }

    /// Quitar la marca `id` (su vista se va con ella).
    public func quitarMarca(_ id: Int64) {
        guard let m = marcas, m.quitar(id: id) else { return }
        refrescarMarcas()
    }

    /// Saca la pastilla de «vista guardada» con el emoticono de `id` y la
    /// quita sola.
    func avisarVistaGuardada(_ id: Int64) {
        let emoji = listaMarcas.first { $0.id == id }?.emoji ?? ""
        vistaGuardada = emoji
        let turno = UUID()
        turnoVistaGuardada = turno
        DispatchQueue.main.asyncAfter(deadline: .now() + MedidasMarcasLienzo.avisoVista) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.turnoVistaGuardada == turno else { return }
                self.vistaGuardada = nil
            }
        }
    }
}

// MARK: - La vista: pintar, raton, teclado y el viaje

extension VistaEditorLienzoNS {
    /// La camara de ahora, como la entiende Rust.
    var camaraDeMarcas: CamaraDelLienzo {
        CamaraDelLienzo(x: Float(origen.x), y: Float(origen.y), zoom: Float(zoom))
    }

    /// Donde cae una marca en la vista: la que se arrastra, donde va el
    /// raton; las demas, donde dice su punto.
    private func enVista(_ m: MarcaDelLienzo) -> CGPoint {
        if let a = arrastreMarca, a.id == m.id { return a.punto }
        return CGPoint(x: (CGFloat(m.x) - origen.x) * zoom, y: (CGFloat(m.y) - origen.y) * zoom)
    }

    /// **Las marcas sobre el lienzo**, despues de todo lo dibujado: miden lo
    /// mismo a cualquier aumento, como el redondel del movil.
    func pintarMarcas(en ctx: CGContext) {
        guard modelo.marcas != nil, !modelo.listaMarcas.isEmpty else { return }
        let r = MedidasMarcasLienzo.radio
        for m in modelo.listaMarcas {
            let s = enVista(m)
            // Lo que no se ve no se pinta.
            if s.x < -2 * r || s.y < -2 * r || s.x > bounds.width + 2 * r || s.y > bounds.height + 2 * r { continue }
            VistaEditorLienzoNS.pintarRedondel(m.emoji, en: s, radio: r, alfa: 0.82, ctx: ctx)
        }
    }

    /// Un emoticono sobre su redondel oscuro, centrado en `c`.
    static func pintarRedondel(_ emoji: String, en c: CGPoint, radio: CGFloat, alfa: CGFloat, ctx: CGContext) {
        ctx.setFillColor(MedidasMarcasLienzo.oscuro.withAlphaComponent(alfa).cgColor)
        ctx.fillEllipse(in: CGRect(x: c.x - radio, y: c.y - radio, width: 2 * radio, height: 2 * radio))
        let texto = emoji as NSString
        let atr: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: radio * 1.1)]
        let t = texto.size(withAttributes: atr)
        texto.draw(at: NSPoint(x: c.x - t.width / 2, y: c.y - t.height / 2), withAttributes: atr)
    }

    /// **Un clic, antes que el gesto**: plantar la marca elegida, o lo que
    /// pida la marca de debajo (⇧ su vista, con la de elegir arrastrarla, si
    /// no ir a ella). `true` si el clic era suyo.
    func marcaPulsada(_ evento: NSEvent) -> Bool {
        guard let m = modelo.marcas else { return false }
        // Un clic, en donde sea, para el viaje: la mano vuelve a mandar.
        pararVuelo()
        let p = convert(evento.locationInWindow, from: nil)
        if case let .plantando(emoji) = modelo.poniendoMarca {
            let w = CGPoint(x: origen.x + p.x / zoom, y: origen.y + p.y / zoom)
            let id = m.poner(x: Double(w.x), y: Double(w.y), emoji: emoji, camara: camaraDeMarcas,
                             anchoPx: Float(bounds.width), altoPx: Float(bounds.height))
            modelo.poniendoMarca = .no
            modelo.refrescarMarcas()
            // Y con ella lo que se ve ahora: es adonde se volvera.
            modelo.avisarVistaGuardada(id)
            return true
        }
        guard let id = m.marcaEn(camara: camaraDeMarcas, px: Float(p.x), py: Float(p.y),
                                 radio: Float(MedidasMarcasLienzo.radio)) else { return false }
        if evento.modifierFlags.contains(.shift) {
            fijarVistaDeMarca(id)
        } else if modelo.herramienta == "seleccion" {
            arrastreMarca = (id, p)
            NSCursor.closedHand.set()
        } else {
            irAMarca(id)
        }
        return true
    }

    /// Arrastrando una marca: va con el raton. `true` si es eso.
    func arrastrarMarca(_ evento: NSEvent) -> Bool {
        guard let a = arrastreMarca else { return false }
        arrastreMarca = (a.id, convert(evento.locationInWindow, from: nil))
        needsDisplay = true
        return true
    }

    /// Se suelta la marca: se queda donde cae.
    func soltarMarca(_ evento: NSEvent) -> Bool {
        guard let a = arrastreMarca else { return false }
        arrastreMarca = nil
        let p = convert(evento.locationInWindow, from: nil)
        modelo.marcas?.mover(id: a.id, x: Double(origen.x + p.x / zoom), y: Double(origen.y + p.y / zoom))
        modelo.refrescarMarcas()
        window?.invalidateCursorRects(for: self)
        return true
    }

    /// Clic derecho encima de una marca: se quita. `true` si habia una.
    func quitarMarcaBajo(_ evento: NSEvent) -> Bool {
        guard let m = modelo.marcas else { return false }
        let p = convert(evento.locationInWindow, from: nil)
        guard let id = m.marcaEn(camara: camaraDeMarcas, px: Float(p.x), py: Float(p.y),
                                 radio: Float(MedidasMarcasLienzo.radio)) else { return false }
        modelo.quitarMarca(id)
        return true
    }

    /// ⇧clic o ⌘⇧1…9: la vista de la marca, la de ahora, y la pastilla.
    func fijarVistaDeMarca(_ id: Int64) {
        guard let m = modelo.marcas,
              m.fijarVista(id: id, camara: camaraDeMarcas, anchoPx: Float(bounds.width), altoPx: Float(bounds.height))
        else { return }
        modelo.refrescarMarcas()
        modelo.avisarVistaGuardada(id)
    }

    /// **Echa a volar la camara** hacia la marca `id`.
    func irAMarca(_ id: Int64) {
        guard let m = modelo.marcas,
              m.irA(id: id, camara: camaraDeMarcas, anchoPx: Float(bounds.width), altoPx: Float(bounds.height),
                    bajoLaBarra: Float(MedidasMarcasLienzo.bajoLaBarra))
        else { return }
        relojVuelo?.invalidate()
        ultimoPasoVuelo = CACurrentMediaTime()
        relojVuelo = Timer.scheduledTimer(withTimeInterval: 1.0 / 120, repeats: true) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self, let m = self.modelo.marcas else { return t.invalidate() }
                let ahora = CACurrentMediaTime()
                let dt = Float(ahora - self.ultimoPasoVuelo)
                self.ultimoPasoVuelo = ahora
                if let c = m.avanzar(camara: self.camaraDeMarcas, dt: dt) {
                    self.ponerCamara(origen: CGPoint(x: CGFloat(c.x), y: CGFloat(c.y)), zoom: CGFloat(c.zoom))
                }
                if !m.volando() {
                    t.invalidate()
                    self.relojVuelo = nil
                }
            }
        }
    }

    /// Para el viaje (un clic, la rueda, pellizcar).
    func pararVuelo() {
        guard relojVuelo != nil else { return }
        relojVuelo?.invalidate()
        relojVuelo = nil
        modelo.marcas?.parar()
    }

    /// Las cifras de la fila de arriba y del teclado numerico, por su tecla:
    /// con ⇧ el caracter ya no es la cifra.
    private static let cifras: [UInt16: Int] = [
        18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9, 29: 0,
        83: 1, 84: 2, 85: 3, 86: 4, 87: 5, 88: 6, 89: 7, 91: 8, 92: 9, 82: 0,
    ]

    /// **Las teclas de las marcas** (las de Windows con ⌘ en vez de Ctrl):
    /// ⌘M la tira, con ella abierta 1-9 y 0 eligen emoticono, ⌘1…9 van a
    /// la marca, ⌘⇧1…9 le ponen la vista de ahora y ⎋ deja de poner.
    /// `true` si la tecla era suya.
    func teclaDeMarcas(_ evento: NSEvent) -> Bool {
        guard modelo.marcas != nil, !modelo.editor.escribiendo() else { return false }
        let teclas = evento.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        let cifra = VistaEditorLienzoNS.cifras[evento.keyCode]
        let lista = modelo.listaMarcas
        if teclas == .command, evento.charactersIgnoringModifiers?.lowercased() == "m" {
            modelo.alternarPonerMarca()
            return true
        }
        if teclas == .command, let c = cifra, c >= 1 {
            // Consumida aunque no haya tantas: un ⌘7 sin septima marca no
            // puede ir a parar a otra cosa.
            if c <= lista.count { irAMarca(lista[c - 1].id) }
            return true
        }
        if teclas == [.command, .shift], let c = cifra, c >= 1 {
            if c <= lista.count { fijarVistaDeMarca(lista[c - 1].id) }
            return true
        }
        if modelo.poniendoMarca == .eligiendo, teclas.isEmpty, let c = cifra {
            let todos = emojisDeMarcas()
            let i = min(c == 0 ? 9 : c - 1, todos.count - 1)
            if i >= 0 { modelo.elegirEmoji(todos[i]) }
            return true
        }
        if evento.keyCode == 53, modelo.poniendoMarca != .no {
            modelo.poniendoMarca = .no
            return true
        }
        return false
    }

    /// Las teclas con ⌘ llegan antes al menu (⌘M minimiza) que a
    /// `keyDown`: un vigia de la ventana las mira primero mientras el lienzo
    /// tiene el foco.
    func vigilarTeclasDeMarcas() {
        if let v = vigiaTeclasMarcas {
            NSEvent.removeMonitor(v)
            vigiaTeclasMarcas = nil
        }
        guard window != nil, modelo.marcas != nil else { return }
        vigiaTeclasMarcas = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            let suya = MainActor.assumeIsolated { () -> Bool in
                guard let self, let w = self.window, e.windowNumber == w.windowNumber,
                      w.firstResponder === self, e.modifierFlags.contains(.command) else { return false }
                return self.teclaDeMarcas(e)
            }
            return suya ? nil : e
        }
    }
}

// MARK: - El riel y la tira

/// **Los puntos del riel**, uno por marca en el orden del dibujo, debajo de
/// la isla (`pintar_riel` de Windows): en reposo pequenos y medio
/// transparentes; con el raton en el riel crecen y el de debajo se adelanta
/// con su atajo al lado.
struct PuntosMarcasLienzo: View {
    @ObservedObject var modelo: ModeloEditorLienzo
    /// El alto que tienen: si no caben al paso de siempre, se aprietan.
    let alto: CGFloat
    @State private var encima: Int64?

    var body: some View {
        let lista = modelo.listaMarcas
        let paso = lista.isEmpty ? MedidasMarcasLienzo.paso
            : max(1, min(MedidasMarcasLienzo.paso, alto / CGFloat(lista.count)))
        VStack(spacing: 0) {
            ForEach(Array(lista.enumerated()), id: \.element.id) { i, m in
                punto(i, m)
                    // Tan ancha como la isla: los puntos, centrados bajo ella.
                    .frame(width: 34, height: paso)
            }
        }
    }

    private func punto(_ i: Int, _ m: MarcaDelLienzo) -> some View {
        let elegido = encima == m.id
        let lado = elegido ? MedidasMarcasLienzo.elegido
            : (encima != nil ? MedidasMarcasLienzo.cerca : MedidasMarcasLienzo.reposo)
        return Button {
            // ⇧clic: su vista, la de ahora (lo de Windows).
            if NSEvent.modifierFlags.contains(.shift) {
                modelo.fijarVistaDeMarca(m.id)
            } else {
                modelo.irAMarca(m.id)
            }
        } label: {
            ZStack {
                Circle().fill(Color(nsColor: MedidasMarcasLienzo.oscuro).opacity(elegido ? 0.9 : 0.4))
                Text(m.emoji).font(.system(size: lado * 0.55))
            }
            .frame(width: lado, height: lado)
            .overlay(alignment: .trailing) {
                if elegido, i < 9 {
                    Text("⌘\(i + 1)")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(nsColor: MedidasMarcasLienzo.oscuro).opacity(0.7))
                        .fixedSize()
                        .offset(x: -lado - 6)
                }
            }
            .offset(x: elegido ? -MedidasMarcasLienzo.salto : 0)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(m.conVista ? "\(m.emoji) Ir a su vista · ⇧clic guarda aquí la de ahora"
              : "\(m.emoji) Ir a la marca · ⇧clic guarda aquí la vista de ahora")
        .onHover { dentro in
            if dentro { encima = m.id } else if encima == m.id { encima = nil }
        }
        .contextMenu {
            Button("Guardar aquí la vista de ahora") { modelo.fijarVistaDeMarca(m.id) }
            Button("Quitar", role: .destructive) { modelo.quitarMarca(m.id) }
        }
        .animation(.easeOut(duration: 0.12), value: encima)
    }
}

/// **La tira de emoticonos** bajo la barra, mientras se pone una marca, o
/// la pastilla de lo que falta (plantarla) o de la vista guardada.
struct TiraMarcasLienzo: View {
    @ObservedObject var modelo: ModeloEditorLienzo

    var body: some View {
        VStack(spacing: 8) {
            switch modelo.poniendoMarca {
            case .eligiendo:
                HStack(spacing: 0) {
                    ForEach(Array(emojisDeMarcas().enumerated()), id: \.offset) { _, e in
                        CeldaTiraMarcas(texto: e) { modelo.elegirEmoji(e) }
                    }
                    CeldaTiraMarcas(simbolo: "xmark") { modelo.poniendoMarca = .no }
                }
                .padding(4)
                .background(Capsule().fill(Color(nsColor: MedidasMarcasLienzo.oscuro).opacity(0.85)))
                PastillaMarcas(texto: "¿Con qué lo marcas? (1-9, 0) · Esc para dejarlo")
            case let .plantando(emoji):
                PastillaMarcas(texto: "Pulsa en el lienzo donde va la marca · Esc cancela", emoji: emoji)
            case .no:
                if let emoji = modelo.vistaGuardada {
                    PastillaMarcas(texto: "Vista guardada en la marca · Mayús+clic en ella la actualiza",
                                   emoji: emoji.isEmpty ? nil : emoji)
                }
            }
        }
        .fixedSize()
    }
}

/// Una celda de la tira: un emoticono (o la ✕), 40 x 40.
private struct CeldaTiraMarcas: View {
    var texto: String?
    var simbolo: String?
    let accion: () -> Void
    @State private var encima = false

    init(texto: String, accion: @escaping () -> Void) {
        self.texto = texto
        self.accion = accion
    }

    init(simbolo: String, accion: @escaping () -> Void) {
        self.simbolo = simbolo
        self.accion = accion
    }

    var body: some View {
        Button(action: accion) {
            ZStack {
                if encima { Circle().fill(Color.white.opacity(0.18)) }
                if let texto {
                    Text(texto).font(.system(size: 22))
                } else if let simbolo {
                    Simbolo(nombre: simbolo, lado: 16).foregroundStyle(.white)
                }
            }
            .frame(width: 40, height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { encima = $0 }
    }
}

/// Una pastilla oscura con una linea de texto (`aviso` de Windows).
private struct PastillaMarcas: View {
    let texto: String
    var emoji: String?

    var body: some View {
        HStack(spacing: 6) {
            if let emoji { Text(emoji).font(.system(size: 17)) }
            Text(texto).font(.system(size: 13)).foregroundStyle(.white)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Capsule().fill(Color(nsColor: MedidasMarcasLienzo.oscuro).opacity(0.85)))
        .allowsHitTesting(false)
    }
}
