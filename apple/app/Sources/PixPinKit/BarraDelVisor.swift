// **La barra de los visores como pin**, la misma para todos (`lector_pin.rs`
// de Windows, `PinLector`): el asa, el recuadro del tipo de archivo con el
// nombre, los botones propios de cada visor, la luna/sol, pantalla
// completa, el pin y la ✕. La usan el PDF, el Word, el libro, la hoja de
// calculo, el HTML, la nota, el pin de Office, los planos y el lienzo; cada
// uno pone solo sus botones (`propios`).
//
// Como en Windows, cada visor abre **para ver** y el lapiz (`material::EDIT`)
// entre sus botones lo pasa a editar; editando, el ojo vuelve a ver.

import AppKit
import SwiftUI

/// **El color del tipo de archivo** (`pixpin_ui::color_de_extension`, el
/// mismo de los iconos del chat del movil).
public enum ColorDeExtension {
    struct Familia {
        let color: UInt32
        let textoOscuro: Bool
    }

    private static let tabla: [(UInt32, Bool, [String])] = [
        (0xE5484D, false, ["pdf"]),
        (0x2F7BF5, false, ["doc", "docx", "docm", "dot", "dotx", "odt", "rtf", "pages", "wps"]),
        (0x2E9E4F, false, ["xls", "xlsx", "xlsm", "xlsb", "csv", "tsv", "ods", "numbers"]),
        (0xF2711C, false, ["ppt", "pptx", "pptm", "pps", "ppsx", "pot", "potx", "odp", "key"]),
        (0xF5B800, true, ["dwg", "dxf", "dwf", "dwfx", "dgn", "dwt", "plt", "rvt", "rfa", "ifc", "nwd", "nwc"]),
        (0x0FA3A3, false, ["obj", "stl", "fbx", "3ds", "blend", "skp", "gltf", "glb", "dae", "ply", "step", "stp",
                           "iges", "igs", "3dm", "usdz"]),
        (0xD6336C, false, ["jpg", "jpeg", "png", "webp", "gif", "heic", "heif", "bmp", "tif", "tiff", "svg",
                           "psd", "ai", "raw", "dng", "avif", "ico"]),
        (0x8E44AD, false, ["mp3", "m4a", "aac", "wav", "ogg", "oga", "opus", "flac", "amr", "wma", "mid", "midi"]),
        (0x5B3CC4, false, ["mp4", "mov", "avi", "mkv", "webm", "3gp", "m4v", "wmv", "flv"]),
        (0x8D6E63, false, ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "zst"]),
        (0x1098AD, false, ["html", "htm", "css", "js", "ts", "json", "xml", "kt", "kts", "java", "py", "c", "h",
                           "cpp", "hpp", "cs", "rs", "go", "sh", "sql", "yml", "yaml", "tex", "m", "ipynb"]),
        (0x607D8B, false, ["txt", "md", "log", "ini", "cfg", "srt", "vtt"]),
        (0x3B5BDB, false, ["epub", "mobi", "azw", "azw3", "fb2", "djvu", "cbz", "cbr"]),
        (0x6CBF5B, false, ["apk", "aab", "xapk", "apks", "exe", "msi", "dmg", "deb", "appimage"]),
        (0x7048E8, false, ["pixpin", "excalidraw"]),
    ]
    private static let resto: [UInt32] = [0x5C7CFA, 0x20C997, 0xFF6B6B, 0xFAB005, 0x845EF7, 0x15AABF, 0xE64980, 0x82C91E]

    /// La extension en minusculas (mas de diez letras no es extension).
    static func extension_(_ ext: String) -> String? {
        let e = ext.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        return e.isEmpty || e.utf16.count > 10 ? nil : e
    }

    static func de(_ ext: String) -> Familia {
        guard let e = extension_(ext) else { return Familia(color: 0x868E96, textoOscuro: false) }
        if let f = tabla.first(where: { $0.2.contains(e) }) { return Familia(color: f.0, textoOscuro: f.1) }
        let suma = e.utf16.reduce(0) { $0 + Int($1) }
        let c = resto[suma % resto.count]
        return Familia(color: c, textoOscuro: c == 0xFAB005)
    }

    /// Lo que va escrito: la extension cortada a 4 letras.
    static func rotulo(_ ext: String) -> String { String((extension_(ext) ?? "").prefix(4)) }

    static func color(_ f: Familia) -> Color {
        Color(red: Double((f.color >> 16) & 0xFF) / 255, green: Double((f.color >> 8) & 0xFF) / 255,
              blue: Double(f.color & 0xFF) / 255)
    }
}

/// El recuadro de 24 del tipo de archivo, con la extension dentro.
struct CuadroDeTipo: View {
    let ext: String
    /// 19 en la barra de un visor; mas grande en la burbuja del chat.
    var lado: CGFloat = 19

    var body: some View {
        let f = ColorDeExtension.de(ext)
        RoundedRectangle(cornerRadius: lado * 0.26)
            .fill(ColorDeExtension.color(f))
            .frame(width: lado, height: lado)
            .overlay {
                Text(ColorDeExtension.rotulo(ext))
                    .font(.system(size: lado * 0.42, weight: .semibold))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(.horizontal, 2)
                    .foregroundStyle(f.textoOscuro ? Color(red: 0x3a / 255, green: 0x2b / 255, blue: 0) : .white)
            }
    }
}

/// **La barra del pin**: asa, tipo y nombre, `propios`, luna/sol (si el
/// visor sabe pintarse en oscuro), pantalla completa, el pin y la ✕. Lo que
/// es de la ventana (moverla, pantalla completa, fijarla, cerrarla) lo hace
/// la barra; lo demas, el visor.
public struct BarraVisor<Propios: View>: View {
    @Environment(\.ventanaDeLaBarra) private var ref
    let nombre: String
    let ext: String
    var renombrar: (() -> Void)?
    /// `nil`: sin luna/sol.
    var oscuro: Bool?
    var alternarOscuro: (() -> Void)?
    /// Lo que pasa al pulsar el pin (el visor lo recuerda); sin el, la barra
    /// sube o baja la ventana.
    var fijar: ((Bool) -> Void)?
    var cerrar: (() -> Void)?
    let propios: Propios
    @State private var fijado = false
    @State private var completa = false

    public init(nombre: String, ext: String, renombrar: (() -> Void)? = nil,
                oscuro: Bool? = nil, alternarOscuro: (() -> Void)? = nil,
                fijar: ((Bool) -> Void)? = nil, cerrar: (() -> Void)? = nil,
                @ViewBuilder propios: () -> Propios) {
        self.nombre = nombre
        self.ext = ext
        self.renombrar = renombrar
        self.oscuro = oscuro
        self.alternarOscuro = alternarOscuro
        self.fijar = fijar
        self.cerrar = cerrar
        self.propios = propios()
    }

    public var body: some View {
        HStack(spacing: 2) {
            AsaBarra()
            Button { renombrar?() } label: {
                HStack(spacing: 7) {
                    if !ext.isEmpty { CuadroDeTipo(ext: ext) }
                    Text(nombre)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(red: 0.96, green: 0.96, blue: 0.97))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 220, alignment: .leading)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.horizontal, 8)
                .frame(height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(renombrar == nil)
            .help(renombrar == nil ? nombre : "Cambiar el nombre (F2)")
            propios
            if let oscuro {
                BotonFlotante(simbolo: oscuro ? "sun.max" : "moon", ayuda: oscuro ? "Modo claro" : "Modo oscuro") {
                    alternarOscuro?()
                }
            }
            BotonFlotante(simbolo: completa ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                          ayuda: completa ? "Volver a pin (⎋)" : "Pantalla completa (⌃⌘F)") {
                ref?.ventana?.toggleFullScreen(nil)
            }
            BotonFlotante(simbolo: fijado ? "pin.fill" : "pin", ayuda: "Siempre encima, como un pin", encendido: fijado) {
                let si = !fijado
                if let fijar { fijar(si) } else { ref?.ventana?.level = si ? .floating : .normal }
                fijado = si
            }
            BotonFlotante(simbolo: "xmark", ayuda: "Cerrar (⎋)") {
                if let cerrar { cerrar() } else { VentanaLisa.cerrar(ref?.ventana) }
            }
        }
        .fixedSize()
        .buttonStyle(.borderless)
        .onAppear { leerVentana() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in leerVentana() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in leerVentana() }
    }

    private func leerVentana() {
        guard let v = ref?.ventana else { return }
        fijado = v.level != .normal
        completa = v.styleMask.contains(.fullScreen)
    }
}

/// **Ver o editar**: el lapiz pasa a editar y, editando, el ojo vuelve a ver
/// (`EDIT` y `VISIBILITY` de Windows).
public struct BotonVerEditar: View {
    let editando: Bool
    let accion: () -> Void

    public init(editando: Bool, accion: @escaping () -> Void) {
        self.editando = editando
        self.accion = accion
    }

    public var body: some View {
        BotonFlotante(simbolo: editando ? "eye" : "pencil",
                      ayuda: editando ? "Volver a ver" : "Editar (lápiz)", accion: accion)
    }
}
