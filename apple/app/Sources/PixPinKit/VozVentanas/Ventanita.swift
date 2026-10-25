// **Lo comun de las ventanitas de la voz** (tanda E5): el telepronter,
// Pronunciar, la conversacion por turnos y la llamada secreta. Es
// `ventanita.rs` de Windows: los colores de «papel oscuro», un boton plano,
// la ventana lisa centrada en la pantalla y el microfono que graba un
// `.m4a` suelto.
//
// - **La ventana** (`VentanaVoz`): lisa como las demas (`VentanaLisa`,
//   siempre oscura, como en Windows) y con su teclado: las teclas le llegan
//   antes que a los botones (Espacio no pulsa el boton que tenga el foco),
//   salvo cuando se esta escribiendo en una caja de texto.
// - **El microfono** (`MicrofonoSuelto`): lo de `GrabadoraVoz` sin el chat:
//   graba a un fichero con el nombre que le den (`lectura-<ms>.m4a`,
//   `toma-<ms>.m4a`...), cuenta lo llevado y al parar da la `NotaGrabada`.
//   Graba por la mezcla de Windows (`MicrofonoConMezcla`); el motor de
//   sonido solo existe mientras graba.

import AppKit
import AVFoundation
import PixPinCore
import SwiftUI

/// Los colores de las ventanitas (`ventanita.rs`): papel oscuro, no
/// interfaz, como el visor limpio.
enum ColoresVoz {
    static let fondo = Color(hex: 0x121316)
    static let texto = Color(hex: 0xE4E2E6)
    static let apagado = Color(hex: 0x9A9AA2)
    static let cristal = Color(hex: 0x26262C)
    static let rojo = Color(hex: 0xE05A4F)
    static let verde = Color(hex: 0x2FB344)
    static let azul = Color(hex: 0x1E88E5)
    static let dorado = Color(hex: 0xE8C06A)
    static let boton = Color(hex: 0x2C2C34)
    static let botonEncima = Color(hex: 0x36363E)
    /// La franja de lectura del telepronter.
    static let franja = Color(hex: 0x1D2733)

    static let fondoAppKit = NSColor(srgbRed: 0x12 / 255, green: 0x13 / 255, blue: 0x16 / 255, alpha: 1)
}

/// Un boton de las ventanitas: el rotulo centrado en una caja de radio 8;
/// `color` es el fondo si esta encendido (rojo de grabar, azul de empezar).
struct BotonVentanita: View {
    let rotulo: String
    var color: Color?
    var ancho: CGFloat?
    var alto: CGFloat = 36
    let accion: () -> Void
    @State private var encima = false

    init(_ rotulo: String, color: Color? = nil, ancho: CGFloat? = nil, alto: CGFloat = 36,
         accion: @escaping () -> Void) {
        self.rotulo = rotulo
        self.color = color
        self.ancho = ancho
        self.alto = alto
        self.accion = accion
    }

    var body: some View {
        Button(action: accion) {
            Text(rotulo)
                .font(.system(size: 15))
                .foregroundStyle(ColoresVoz.texto)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(minWidth: ancho ?? 44, maxWidth: ancho, minHeight: alto, maxHeight: alto)
                .background(color ?? (encima ? ColoresVoz.botonEncima : ColoresVoz.boton),
                            in: RoundedRectangle(cornerRadius: 8))
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { encima = $0 }
    }
}

/// Un aviso corto abajo (la nota salio demasiado corta, no hay micro), que
/// se va solo.
@MainActor
final class AvisoCorto: ObservableObject {
    @Published private(set) var texto: String?
    private var quitar: DispatchWorkItem?

    func decir(_ t: String, segundos: TimeInterval = 4) {
        texto = t
        quitar?.cancel()
        let q = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.texto = nil } }
        quitar = q
        DispatchQueue.main.asyncAfter(deadline: .now() + segundos, execute: q)
    }
}

// MARK: - La ventana

/// **La ventana de una ventanita**: lisa y oscura, con su teclado.
final class VentanaVoz: NSWindow {
    /// Una tecla bajada (`true`) o soltada (`false`). Devuelve si la uso.
    var alTeclear: ((NSEvent, Bool) -> Bool)?
    /// La rueda o el trackpad (el telepronter: la velocidad).
    var alRodar: ((NSEvent) -> Bool)?
    var alCerrar: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Escribiendo en una caja: las teclas son letras, no ordenes.
    private var escribiendo: Bool {
        firstResponder is NSTextView
    }

    override func sendEvent(_ e: NSEvent) {
        switch e.type {
        case .keyDown where !escribiendo || e.keyCode == 53:
            if alTeclear?(e, true) == true { return }
        case .keyUp where !escribiendo:
            if alTeclear?(e, false) == true { return }
        case .scrollWheel:
            if alRodar?(e) == true { return }
        default:
            break
        }
        super.sendEvent(e)
    }

    override func close() {
        let f = alCerrar
        alCerrar = nil
        super.close()
        f?()
    }

    /// Una ventana de `tam` centrada en la pantalla de la ventana activa (o
    /// la principal), con `vista` dentro.
    static func nueva<V: View>(_ titulo: String, tam: NSSize, vista: V) -> VentanaVoz {
        let v = VentanaVoz(contentRect: NSRect(origin: .zero, size: tam),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                           backing: .buffered, defer: false)
        v.title = titulo
        v.isReleasedWhenClosed = false
        v.appearance = NSAppearance(named: .darkAqua)
        v.backgroundColor = ColoresVoz.fondoAppKit
        v.contentView = NSHostingView(rootView: vista)
        VentanaLisa.vestir(v)
        v.setContentSize(tam)
        if let p = NSApp.keyWindow?.screen ?? NSScreen.main {
            v.setFrame(Ventanita.centrado(en: p.visibleFrame, tam: v.frame.size), display: false)
        } else {
            v.center()
        }
        return v
    }
}

enum Ventanita {
    /// Un marco de `tam` centrado en `area`, sin salirse (`centrado`).
    static func centrado(en area: CGRect, tam: CGSize) -> CGRect {
        let w = min(tam.width, area.width)
        let h = min(tam.height, area.height)
        return CGRect(x: area.minX + ((area.width - w) / 2).rounded(.down),
                      y: area.minY + ((area.height - h) / 2).rounded(.down), width: w, height: h)
    }

    /// La carpeta de lo que graban las ventanitas antes de pasar al chat.
    static func carpeta(_ nombre: String) -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("PixPinVoz", isDirectory: true)
            .appendingPathComponent(nombre, isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    /// Milisegundos de ahora (para los nombres `lectura-<ms>.m4a`).
    static var ahoraMs: Int64 { Int64((Date().timeIntervalSince1970 * 1000).rounded()) }
}

// MARK: - El microfono

/// **Un microfono que graba a un fichero** (`abrir_microfono` y
/// `cerrar_microfono` de Windows): para las ventanitas, que no graban al
/// chat sino a un `.m4a` suelto que luego entra con su nombre.
@MainActor
final class MicrofonoSuelto {
    private var microfono: MicrofonoConMezcla?
    private(set) var desde: Date?

    var grabando: Bool { microfono != nil }

    /// Lo llevado, contando muestras (lo que de verdad se grabo).
    var llevadoMs: Int64 { microfono?.llevadoMs ?? 0 }

    /// Pide el permiso (la primera vez sale el aviso del sistema) y empieza
    /// a grabar en `fichero`. Lanza si no hay permiso o microfono.
    func empezar(en fichero: URL) async throws {
        guard microfono == nil else { return }
        guard await GrabadoraVoz.permisoMicrofono() else { throw ErrorVoz.sinPermisoMicrofono }
        guard GrabadoraVoz.compartida.estado == .quieta else { throw ErrorVoz.sinMicrofono }
        let m = try MicrofonoConMezcla(url: fichero)
        do {
            try m.empezar()
        } catch {
            _ = m.terminar()
            try? FileManager.default.removeItem(at: fichero)
            throw error
        }
        microfono = m
        desde = Date()
    }

    /// Para y cierra el fichero (fuera del hilo principal: escribir el
    /// indice del MPEG-4 tarda). `nil` si no grababa.
    func parar() async -> NotaGrabada? {
        guard let microfono else { return nil }
        self.microfono = nil
        desde = nil
        return await Task.detached(priority: .userInitiated) { microfono.terminar() }.value
    }

    /// Para y tira lo grabado: no se guarda a escondidas.
    func cancelar() {
        guard let microfono else { return }
        self.microfono = nil
        desde = nil
        try? FileManager.default.removeItem(at: microfono.terminar().url)
    }

    /// Lo que se dice cuando no se puede grabar.
    static func explicar(_ error: Error) -> String {
        switch error as? ErrorVoz {
        case .sinPermisoMicrofono?:
            "PixPin no tiene permiso para el micrófono (Ajustes del Sistema > Privacidad y seguridad > Micrófono)"
        default:
            "No hay micrófono disponible"
        }
    }
}

// MARK: - Las teclas

/// Los codigos de tecla del Mac que usan las ventanitas.
enum TeclaVoz {
    static let escape: UInt16 = 53
    static let espacio: UInt16 = 49
    static let intro: UInt16 = 36
    static let introNumerico: UInt16 = 76
    static let tab: UInt16 = 48
    static let izquierda: UInt16 = 123
    static let derecha: UInt16 = 124
    static let abajo: UInt16 = 125
    static let arriba: UInt16 = 126
    static let rePag: UInt16 = 116
    static let avPag: UInt16 = 121

    static func esIntro(_ e: NSEvent) -> Bool { e.keyCode == intro || e.keyCode == introNumerico }

    /// La letra de la tecla sin modificadores («+», «-», «r», «1»).
    static func letra(_ e: NSEvent) -> Character? {
        e.charactersIgnoringModifiers?.lowercased().first
    }
}
