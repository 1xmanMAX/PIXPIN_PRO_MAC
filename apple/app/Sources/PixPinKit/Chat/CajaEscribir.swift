// **La caja de escribir del chat**: la «isla» flotante de Windows (y del
// movil), `pintar_redaccion` de `ventana_chat.rs` con las medidas de
// `pixpin-ui/src/chat.rs`:
//
// - la isla: radio 22 y un filete de 1 que la despega del papel;
// - dentro, el campo en pastilla, con el clip a su derecha y apoyado abajo
//   (se retira al escribir, como en el movil); el clip abre la hoja de
//   adjuntar (`HojaAdjuntar.swift`);
// - fuera del campo, a la derecha, un sitio con dos caras: el microfono, o
//   enviar si hay algo escrito. Grabando, el campo deja su sitio al
//   cronometro.
//
// Teclado, como Windows: Intro envia, ⇧Intro (o ⌥Intro) salta de linea y
// Esc suelta lo seleccionado o, si no lo hay, limpia lo escrito; con la
// caja vacia, Esc deja de responder.

import AppKit
import PixPinCore
import SwiftUI

// MARK: - Colores

extension Paleta {
    /// `CLARO` y `OSCURO` de `ventana_chat.rs`: lo de la caja de escribir y
    /// las hojas que salen del chat.
    public enum chat {
        /// El fondo de la cabecera y de las hojas (`cabecera`).
        public static let cabecera = Color(claro: 0xFFFFFF, oscuro: 0x17212B)
        public static let isla = Color(claro: 0xFFFFFF, oscuro: 0x14192D)
        /// El filete de la isla: tinta al 10 % de dia; de noche, opaco.
        public static let islaBorde = Color(nsColor: NSColor(name: nil) { a in
            a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0x3A / 255, green: 0x40 / 255, blue: 0x60 / 255, alpha: 1)
                : NSColor(srgbRed: 0x10 / 255, green: 0x1B / 255, blue: 0x24 / 255, alpha: 0.10)
        })
        /// La pastilla donde se escribe y lo apagado de dentro.
        public static let campo = Color(claro: 0xECEEF8, oscuro: 0x242B55)
        public static let campoApagado = Color(claro: 0x5D5F71, oscuro: 0xB4B9D7)
        /// Enviar y lo que se pulsa en el chat.
        public static let enviar = Color(claro: 0x40A7E3, oscuro: 0x5288C1)
        /// Lo elegido con el teclado (`AZUL_ELEGIDO`).
        public static let azulElegido = Color(hex: 0x0060DF)
        /// Grabando (`#E5534B`).
        public static let grabando = Color(hex: 0xE5534B)
    }
}

// MARK: - Medidas (las de `pixpin-ui/src/chat.rs`, al 100 %)

enum MedidasIsla {
    static let margenX: CGFloat = 7
    static let arriba: CGFloat = 6
    static let abajo: CGFloat = 9
    static let rellenoX: CGFloat = 6
    static let rellenoY: CGFloat = 4
    static let radio: CGFloat = 22
    /// Lo alto del campo con una linea, y el lado del clip.
    static let fila: CGFloat = 44
    /// El lado del boton de la voz (o enviar).
    static let boton: CGFloat = fila + 4
    static let textoX: CGFloat = 14
    static let textoArriba: CGFloat = 9
    static let textoAbajo: CGFloat = 10
    /// La letra de lo que se escribe.
    static let letra: CGFloat = 15
    /// Lo mas que crece la caja antes de desplazarse, en lineas.
    static let lineas = 8
}

// MARK: - La isla

struct IslaDeEscribir: View {
    @Binding var borrador: String
    let chat: String
    let almacen: Almacen
    /// Sube para pedir el foco (al abrir el chat, tras enviar...).
    var foco: Int
    let enviar: () -> Void
    /// Esc con la caja vacia: `true` si alguien lo uso.
    let escaparVacio: () -> Bool
    let adjuntar: (AccionAdjuntar) -> Void
    @Environment(\.escalaChat) private var f
    @ObservedObject private var grabadora = GrabadoraVoz.compartida
    @State private var hoja = false

    private var hayTexto: Bool { !borrador.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var grabandoAqui: Bool { grabadora.grabando(en: chat) }

    var body: some View {
        HStack(alignment: .bottom, spacing: MedidasIsla.rellenoX * f) {
            campo
            botonDeVoz
        }
        .padding(.horizontal, MedidasIsla.rellenoX * f)
        .padding(.vertical, MedidasIsla.rellenoY * f)
        .background {
            RoundedRectangle(cornerRadius: MedidasIsla.radio * f)
                .fill(Paleta.chat.isla)
                .overlay(RoundedRectangle(cornerRadius: MedidasIsla.radio * f)
                    .strokeBorder(Paleta.chat.islaBorde, lineWidth: 1))
        }
        .padding(.horizontal, MedidasIsla.margenX * f)
        .padding(.top, MedidasIsla.arriba * f)
        .padding(.bottom, MedidasIsla.abajo * f)
    }

    /// La pastilla: lo escrito (o el cronometro, grabando) y el clip.
    private var campo: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if grabandoAqui, case let .grabando(_, desde) = grabadora.estado {
                TimelineView(.periodic(from: desde, by: 1)) { contexto in
                    HStack(spacing: 8) {
                        Circle().fill(Paleta.chat.grabando).frame(width: 8 * f, height: 8 * f)
                        Text(FormatoVoz.marca(ms: Int64(contexto.date.timeIntervalSince(desde) * 1000)))
                            .font(.system(size: MedidasIsla.letra * f).monospacedDigit())
                            .foregroundStyle(Paleta.chat.grabando)
                        Text("Grabando… pulsa ■ para mandarla")
                            .font(.system(size: 13 * f))
                            .foregroundStyle(Paleta.chat.campoApagado)
                            .lineLimit(1)
                    }
                }
                .padding(.leading, MedidasIsla.textoX * f)
                .frame(maxWidth: .infinity, minHeight: MedidasIsla.fila * f, alignment: .leading)
            } else {
                CampoDeEscribir(texto: $borrador, tamano: MedidasIsla.letra * f,
                                lineas: MedidasIsla.lineas, foco: foco,
                                enviar: enviar, escaparVacio: escaparVacio)
                    .overlay(alignment: .topLeading) {
                        if borrador.isEmpty {
                            Text("Escribe algo…")
                                .font(.system(size: MedidasIsla.letra * f))
                                .foregroundStyle(Paleta.chat.campoApagado)
                                .allowsHitTesting(false)
                        }
                    }
                    .padding(.leading, MedidasIsla.textoX * f)
                    .padding(.trailing, hayTexto ? MedidasIsla.textoX * f : 0)
                    .padding(.top, MedidasIsla.textoArriba * f)
                    .padding(.bottom, MedidasIsla.textoAbajo * f)
                    .frame(minHeight: MedidasIsla.fila * f)
                if !hayTexto { clip }
            }
        }
        .background(Paleta.chat.campo,
                    in: RoundedRectangle(cornerRadius: min(MedidasIsla.radio * f, MedidasIsla.fila * f / 2)))
    }

    private var clip: some View {
        Button { hoja.toggle() } label: {
            Image(systemName: "paperclip")
                .font(.system(size: 19 * f, weight: .medium))
                .foregroundStyle(Paleta.chat.campoApagado)
                .frame(width: MedidasIsla.fila * f, height: MedidasIsla.fila * f)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Adjuntar: foto, archivo, lienzo, nota, tareas, tabla, captura…")
        .popover(isPresented: $hoja, arrowEdge: .top) {
            VistaHojaAdjuntar(elegir: { accion in
                hoja = false
                adjuntar(accion)
            }, cerrar: { hoja = false })
        }
    }

    /// El microfono, enviar o parar: el mismo sitio con tres caras.
    private var botonDeVoz: some View {
        Button(action: pulsarVoz) {
            Image(systemName: grabandoAqui ? "stop.fill" : (hayTexto ? "paperplane.fill" : "mic"))
                .font(.system(size: 20 * f, weight: .medium))
                .foregroundStyle(grabandoAqui ? Paleta.chat.grabando
                                 : (hayTexto ? Paleta.chat.enviar : Paleta.chat.campoApagado))
                .frame(width: MedidasIsla.boton * f, height: MedidasIsla.boton * f)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!hayTexto && vozOcupadaEnOtro)
        .help(grabandoAqui ? "Parar y mandar la nota de voz"
              : (hayTexto ? "Enviar (Intro)" : "Grabar una nota de voz"))
    }

    private func pulsarVoz() {
        if hayTexto, !grabandoAqui {
            enviar()
        } else {
            grabadora.alternar(en: chat, almacen: almacen)
        }
    }

    /// Grabando en otro chat, o guardando: el microfono espera.
    private var vozOcupadaEnOtro: Bool {
        switch grabadora.estado {
        case .quieta: false
        case let .grabando(c, _): c != chat
        case .guardando, .transcribiendo: true
        }
    }
}

// MARK: - El campo de varias lineas

/// Lo escrito en la isla: un `NSTextView` (un `TextField` de SwiftUI no deja
/// distinguir Intro de ⇧Intro). Crece con lo escrito hasta `lineas` y
/// despues se desplaza.
struct CampoDeEscribir: NSViewRepresentable {
    @Binding var texto: String
    var tamano: CGFloat
    var lineas: Int
    var foco: Int
    let enviar: () -> Void
    let escaparVacio: () -> Bool

    func makeCoordinator() -> Coordinador { Coordinador(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        let tv = TextoDeLaIsla(frame: NSRect(x: 0, y: 0, width: 200, height: tamano * 1.3))
        tv.minSize = .zero
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = true
        // Alto sin tope: si no, se deja de colocar texto en la primera linea.
        tv.textContainer?.containerSize = NSSize(width: 200, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.font = .systemFont(ofSize: tamano)
        tv.textColor = .labelColor
        tv.string = texto
        tv.delegate = context.coordinator
        scroll.documentView = tv
        context.coordinator.vista = tv
        context.coordinator.focoVisto = foco
        DispatchQueue.main.async {
            tv.window?.makeFirstResponder(tv)
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        c.padre = self
        guard let tv = c.vista else { return }
        var medir = false
        if tv.string != texto {
            tv.string = texto
            medir = true
        }
        if tv.font?.pointSize != tamano {
            tv.font = .systemFont(ofSize: tamano)
            medir = true
        }
        if c.focoVisto != foco {
            c.focoVisto = foco
            DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        }
        if medir { scroll.invalidateIntrinsicContentSize() }
    }

    /// Crece con lo escrito: lo alto de sus lineas con el ancho que le dan.
    func sizeThatFits(_ propuesta: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        let ancho = propuesta.width ?? 200
        return CGSize(width: ancho, height: context.coordinator.alto(ancho: ancho))
    }

    @MainActor
    final class Coordinador: NSObject, NSTextViewDelegate {
        var padre: CampoDeEscribir
        weak var vista: NSTextView?
        var focoVisto = 0

        init(_ padre: CampoDeEscribir) { self.padre = padre }

        func textDidChange(_ notification: Notification) {
            guard let tv = vista else { return }
            padre.texto = tv.string
        }

        /// Lo alto de lo escrito con `ancho`, hasta `lineas` lineas.
        func alto(ancho: CGFloat) -> CGFloat {
            let letra = NSFont.systemFont(ofSize: padre.tamano)
            guard let tv = vista, let lm = tv.layoutManager, let tc = tv.textContainer else {
                return ceil(letra.ascender - letra.descender + letra.leading)
            }
            tc.containerSize = NSSize(width: max(ancho, 1), height: CGFloat.greatestFiniteMagnitude)
            lm.ensureLayout(for: tc)
            let usado = lm.usedRect(for: tc).height
            let linea = lm.defaultLineHeight(for: tv.font ?? letra)
            return ceil(min(max(usado, linea), linea * CGFloat(padre.lineas)))
        }

        func textView(_ tv: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                if tv.hasMarkedText() { return false }
                let teclas = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
                if teclas.contains(.shift) || teclas.contains(.option) {
                    tv.insertNewlineIgnoringFieldEditor(nil)
                } else {
                    padre.enviar()
                }
                return true
            case #selector(NSResponder.cancelOperation(_:)), #selector(NSTextView.complete(_:)):
                if tv.hasMarkedText() { return false }
                // Con algo seleccionado, Esc solo lo suelta; con algo
                // escrito, lo limpia (y se puede deshacer); vacia, se lo
                // queda quien este detras (la respuesta).
                let r = tv.selectedRange()
                if r.length > 0 {
                    tv.setSelectedRange(NSRange(location: r.upperBound, length: 0))
                } else if !tv.string.isEmpty {
                    let todo = NSRange(location: 0, length: (tv.string as NSString).length)
                    if tv.shouldChangeText(in: todo, replacementString: "") {
                        tv.replaceCharacters(in: todo, with: "")
                        tv.didChangeText()
                    }
                } else {
                    _ = padre.escaparVacio()
                }
                return true
            default:
                return false
            }
        }
    }
}

/// El texto de la isla: lo soltado encima que no sea texto lo coge el chat
/// (se adjunta), no se escribe su ruta aqui.
final class TextoDeLaIsla: NSTextView {
    override var acceptableDragTypes: [NSPasteboard.PasteboardType] { [.string] }
}

// MARK: - Una caja de una linea (buscadores)

/// Las teclas de una caja de una linea que puede querer quien la usa.
enum TeclaDeCampo: Equatable {
    case flecha(HojaAdjuntar.Flecha)
    case intro, introConMayusculas, escape
}

/// Una caja de una linea sin marco (los buscadores del chat y de la hoja):
/// da a quien la usa las flechas, Intro y Esc antes que a ella misma, y le
/// deja retocar lo escrito al cambiar (la hoja se come los numeros).
struct CampoDeUnaLinea: NSViewRepresentable {
    @Binding var texto: String
    var invitacion: String
    var tamano: CGFloat = 13
    /// Sube para pedir el foco; al montarse lo pide siempre.
    var foco: Int = 0
    /// `true` si la tecla era suya (y la caja no la ve).
    var tecla: (TeclaDeCampo) -> Bool = { _ in false }
    var alCambiar: (String) -> String = { $0 }

    init(texto: Binding<String>, invitacion: String, tamano: CGFloat = 13, foco: Bool = true,
         tecla: @escaping (TeclaDeCampo) -> Bool = { _ in false },
         alCambiar: @escaping (String) -> String = { $0 }) {
        _texto = texto
        self.invitacion = invitacion
        self.tamano = tamano
        self.foco = foco ? 0 : -1
        self.tecla = tecla
        self.alCambiar = alCambiar
    }

    init(texto: Binding<String>, invitacion: String, tamano: CGFloat = 13, pedirFoco: Int,
         tecla: @escaping (TeclaDeCampo) -> Bool = { _ in false }) {
        _texto = texto
        self.invitacion = invitacion
        self.tamano = tamano
        foco = pedirFoco
        self.tecla = tecla
    }

    func makeCoordinator() -> Coordinador { Coordinador(self) }

    func makeNSView(context: Context) -> NSTextField {
        let campo = NSTextField()
        campo.isBordered = false
        campo.drawsBackground = false
        campo.focusRingType = .none
        campo.font = .systemFont(ofSize: tamano)
        campo.placeholderString = invitacion
        campo.stringValue = texto
        campo.cell?.isScrollable = true
        campo.cell?.wraps = false
        campo.cell?.usesSingleLineMode = true
        campo.lineBreakMode = .byClipping
        campo.delegate = context.coordinator
        campo.setContentHuggingPriority(.defaultLow, for: .horizontal)
        context.coordinator.focoVisto = foco
        if foco >= 0 {
            DispatchQueue.main.async { campo.window?.makeFirstResponder(campo) }
        }
        return campo
    }

    func updateNSView(_ campo: NSTextField, context: Context) {
        context.coordinator.padre = self
        if campo.stringValue != texto { campo.stringValue = texto }
        if campo.font?.pointSize != tamano { campo.font = .systemFont(ofSize: tamano) }
        if context.coordinator.focoVisto != foco {
            context.coordinator.focoVisto = foco
            DispatchQueue.main.async { campo.window?.makeFirstResponder(campo) }
        }
    }

    @MainActor
    final class Coordinador: NSObject, NSTextFieldDelegate {
        var padre: CampoDeUnaLinea
        var focoVisto = 0

        init(_ padre: CampoDeUnaLinea) { self.padre = padre }

        func controlTextDidChange(_ obj: Notification) {
            guard let campo = obj.object as? NSTextField else { return }
            let retocado = padre.alCambiar(campo.stringValue)
            if retocado != campo.stringValue { campo.stringValue = retocado }
            padre.texto = retocado
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            let t: TeclaDeCampo
            switch selector {
            case #selector(NSResponder.moveUp(_:)): t = .flecha(.arriba)
            case #selector(NSResponder.moveDown(_:)): t = .flecha(.abajo)
            case #selector(NSResponder.moveLeft(_:)): t = .flecha(.izquierda)
            case #selector(NSResponder.moveRight(_:)): t = .flecha(.derecha)
            case #selector(NSResponder.insertNewline(_:)):
                let teclas = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
                t = teclas.contains(.shift) ? .introConMayusculas : .intro
            case #selector(NSResponder.cancelOperation(_:)): t = .escape
            default: return false
            }
            return padre.tecla(t)
        }
    }
}
