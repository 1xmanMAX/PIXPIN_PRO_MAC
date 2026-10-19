// **El editor de hojas de calculo** del chat: una tabla del PC (mensaje
// `MINIAPP` tabla), una del movil (`TABLA`, `tablas/<ref>.json`) o un libro
// del chat (Excel, OpenDocument, CSV) con todas sus hojas en pestanas,
// guardado donde lo guarda Windows (`HojaDeCalculo` de Rust, el `hoja_pin`
// de Windows): cada hoja de un libro pasa a ser una tabla del chat y el
// archivo no cambia. Las formulas las calcula el motor de `pixpin-proyecto`
// (el mismo `=SUMA(...)` que Windows).
//
// Lo de Windows (D5): elegir un rango (⇧ + flechas o ⇧ + clic), formato de
// todo lo elegido como un paso de deshacer (negrita, cursiva, subrayado,
// tachado, ajustar, resaltar, color de letra, alinear, formato de numero,
// borrar formato), deshacer y rehacer, copiar, cortar y pegar (con Excel y
// Sheets: texto con tabuladores y tabla HTML), y sus teclas con ⌘
// (`AccionHoja.de`): ⌘B, ⌘I, ⌘U, ⌘5, ⇧⌘L/E/R, F2, ⌘Z/⇧⌘Z/⌘Y, ⌘C/X/V, ⌫.
// ⌘N, ⌘K y ⌘S (los otros de Windows) son de macOS y no se usan.
//
// Rendimiento (§4bis): la rejilla es un `NSTableView` (solo existen las
// filas que se ven) y las celdas se piden a Rust por bloques de 100 filas,
// ya calculadas; un cambio vacia los bloques (una formula puede depender de
// cualquier celda) y se piden otra vez solo los que se ven. Guardar va 1 s
// despues del ultimo cambio, fuera del hilo principal.

import AppKit
import PixPinCore
import SwiftUI

/// El texto de una celda con su formato de numero (`nf`: numero, moneda,
/// porcentaje, fecha), como lo ensena el pin de hoja de Windows.
public func textoDeCelda(_ c: CeldaHoja, locale: Locale = .current) -> String {
    guard let n = c.numero, let nf = c.estilo?.formatoNumero, !c.error else { return c.mostrado }
    let f = NumberFormatter()
    f.locale = locale
    switch nf {
    case "numero":
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.usesGroupingSeparator = true
    case "moneda":
        f.numberStyle = .currency
    case "porcentaje":
        f.numberStyle = .percent
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
    case "fecha":
        // El numero es el serial de Excel: dias desde el 30-12-1899.
        let base = DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(identifier: "UTC"),
                                  year: 1899, month: 12, day: 30).date ?? Date(timeIntervalSince1970: 0)
        let d = base.addingTimeInterval(n * 86_400)
        let df = DateFormatter()
        df.locale = locale
        df.timeZone = TimeZone(identifier: "UTC")
        df.dateStyle = .short
        df.timeStyle = .none
        return df.string(from: d)
    default:
        return c.mostrado
    }
    return f.string(from: NSNumber(value: n)) ?? c.mostrado
}

/// El nombre de una columna (`A`, `Z`, `AA`...), como `tabla::ref_a`.
public func letrasDeColumna(_ i: Int) -> String {
    var n = i + 1
    var s = ""
    while n > 0 {
        let r = (n - 1) % 26
        s = String(UnicodeScalar(UInt8(65 + r))) + s
        n = (n - 1) / 26
    }
    return s
}

/// Un color `#rrggbb` (el de los estilos de celda).
func colorDeHex(_ hex: String?) -> NSColor? {
    guard var h = hex?.trimmingCharacters(in: .whitespaces), h.hasPrefix("#") else { return nil }
    h.removeFirst()
    guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                   blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}

/// **Lo que hace una tecla en la hoja** (`hoja_pin::accion_de_tecla` de
/// Windows, con ⌘ donde Windows pone Ctrl). Pura: se prueba sin ventanas.
public enum AccionHoja: Equatable {
    case deshacer, rehacer, copiar, cortar, pegar, elegirTodo
    case formato(FormatoHoja)
    /// F2: escribir en la celda con lo que tiene.
    case empezar
    /// Suprimir o ⌫ sin escribir: vaciar lo elegido.
    case borrar
    /// Escribiendo, Esc deja la celda como estaba.
    case cancelar
    /// La hoja de al lado (⌃⇟ / ⌃⇞ y ⌥⌘→ / ⌥⌘←).
    case hojaSiguiente, hojaAnterior
    /// ⌘ + flecha: al borde de lo escrito.
    case borde(dx: Int, dy: Int)

    /// Las teclas de Mac (`keyCode`) que usa.
    public enum Tecla {
        public static let izquierda: UInt16 = 123, derecha: UInt16 = 124, abajo: UInt16 = 125, arriba: UInt16 = 126
        public static let retroceso: UInt16 = 51, suprimir: UInt16 = 117, escape: UInt16 = 53, f2: UInt16 = 120
        public static let rePag: UInt16 = 116, avPag: UInt16 = 121
    }

    /// `letra`: lo que da la tecla sin modificadores (`charactersIgnoringModifiers`).
    public static func de(tecla: UInt16, letra: String, mayus: Bool, comando: Bool, opcion: Bool, control: Bool,
                          escribiendo: Bool) -> AccionHoja? {
        let l = letra.lowercased()
        if control, !comando {
            switch tecla {
            case Tecla.avPag: return .hojaSiguiente
            case Tecla.rePag: return .hojaAnterior
            default: return nil
            }
        }
        if comando {
            if opcion {
                switch tecla {
                case Tecla.derecha: return .hojaSiguiente
                case Tecla.izquierda: return .hojaAnterior
                default: return nil
                }
            }
            // Escribiendo, deshacer, copiar y pegar son del texto de la barra.
            if !escribiendo {
                switch (l, mayus) {
                case ("z", true): return .rehacer
                case ("z", false): return .deshacer
                case ("y", _): return .rehacer
                case ("c", false): return .copiar
                case ("x", false): return .cortar
                case ("v", false): return .pegar
                case ("a", false): return .elegirTodo
                default: break
                }
                switch tecla {
                case Tecla.arriba: return .borde(dx: 0, dy: -1)
                case Tecla.abajo: return .borde(dx: 0, dy: 1)
                case Tecla.izquierda: return .borde(dx: -1, dy: 0)
                case Tecla.derecha: return .borde(dx: 1, dy: 0)
                default: break
                }
            }
            if mayus {
                switch l {
                case "l": return .formato(.alinear(alineacion: "i"))
                case "e": return .formato(.alinear(alineacion: "c"))
                case "r": return .formato(.alinear(alineacion: "d"))
                case "x": return .formato(.tachado)
                default: return nil
                }
            }
            switch l {
            case "b": return .formato(.negrita)
            case "i": return .formato(.cursiva)
            case "u": return .formato(.subrayado)
            case "5": return .formato(.tachado)
            default: return nil
            }
        }
        if opcion { return nil }
        switch tecla {
        case Tecla.escape where escribiendo: return .cancelar
        case Tecla.f2: return .empezar
        case Tecla.retroceso, Tecla.suprimir: return escribiendo ? nil : .borrar
        default: return nil
        }
    }
}

/// La rejilla: las flechas mueven la celda elegida (con ⇧, alargan lo
/// elegido), escribir empieza a editarla en la barra de formulas,
/// Suprimir la vacia; las teclas con ⌘ van antes que los menus del Mac.
final class RejillaHoja: NSTableView {
    weak var controlador: ControladorHoja?

    override func keyDown(with event: NSEvent) {
        if let c = controlador, c.tecla(event) { return }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let c = controlador, c.atajo(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    // Los del menu Edicion, por si llegan por el.
    @objc func copy(_ sender: Any?) { controlador?.hacer(.copiar) }
    @objc func cut(_ sender: Any?) { controlador?.hacer(.cortar) }
    @objc func paste(_ sender: Any?) { controlador?.hacer(.pegar) }
    @objc func undo(_ sender: Any?) { controlador?.hacer(.deshacer) }
    @objc func redo(_ sender: Any?) { controlador?.hacer(.rehacer) }
    override func selectAll(_ sender: Any?) { controlador?.hacer(.elegirTodo) }
    @objc func delete(_ sender: Any?) { controlador?.hacer(.borrar) }
}

@MainActor
final class ControladorHoja: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate,
    NSTextFieldDelegate {
    let hoja: HojaDeCalculo
    let ventana: NSWindow
    private let rejilla = RejillaHoja()
    private let barra = NSTextField()
    private let referencia = NSTextField(labelWithString: "A1")
    private let aviso = NSTextField(labelWithString: "")
    private let pestanas = NSStackView()
    private var columnas = 26
    private var filas = 200
    private var bloques: [Int: [Int: [Int: CeldaHoja]]] = [:]
    private static let filasPorBloque = 100
    /// La celda activa y el ancla de lo elegido.
    private var fila = 0
    private var columna = 0
    private var anclaFila = 0
    private var anclaColumna = 0
    private let colaGuardar = DispatchQueue(label: "pixpin.hoja.guardar", qos: .utility)
    private var guardado: DispatchWorkItem?
    var alCerrar: (@MainActor (ControladorHoja) -> Void)?
    /// **Ver o editar** (`visor_hoja.rs` de Windows): abre para ver; el lapiz
    /// de la barra del pin trae la barra de formulas y el formato.
    let modelo = ModeloHojaPin()
    private var arriba: NSStackView?
    private var arribaCerrada: NSLayoutConstraint?
    private var barraPin: BarraFlotante?

    init(hoja: HojaDeCalculo, titulo: String) {
        self.hoja = hoja
        ventana = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 660),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable],
                           backing: .buffered, defer: false)
        super.init()
        ventana.title = titulo
        // Como un pin: sin encabezado; ⎋ sale de pantalla completa y cierra.
        VentanaLisa.vestirEntera(ventana)
        ventana.collectionBehavior.insert(.fullScreenPrimary)
        ventana.isReleasedWhenClosed = false
        ventana.delegate = self
        montar()
        recalcularTamano()
        let s = hoja.seleccion()
        elegir(Int(s.fila), Int(s.columna))
    }

    private func boton(_ simbolo: String, _ ayuda: String, _ accion: Selector) -> NSButton {
        let b = NSButton(image: NSImage(systemSymbolName: simbolo, accessibilityDescription: ayuda) ?? NSImage(),
                         target: self, action: accion)
        b.bezelStyle = .rounded
        b.toolTip = ayuda
        return b
    }

    private func menuDeColores(_ titulo: String, _ colores: [ColorHoja], sinColor: String, _ accion: Selector) -> NSPopUpButton {
        let p = NSPopUpButton(frame: .zero, pullsDown: true)
        p.addItem(withTitle: titulo)
        p.addItem(withTitle: sinColor)
        for c in colores {
            p.addItem(withTitle: c.nombre)
            if let color = colorDeHex(c.hex) {
                let img = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { r in
                    color.setFill()
                    NSBezierPath(roundedRect: r, xRadius: 2, yRadius: 2).fill()
                    return true
                }
                p.lastItem?.image = img
            }
        }
        p.target = self
        p.action = accion
        p.toolTip = titulo
        return p
    }

    private func montar() {
        referencia.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        referencia.setContentHuggingPriority(.required, for: .horizontal)
        barra.placeholderString = "Valor o =fórmula"
        barra.delegate = self
        barra.target = self
        barra.action = #selector(confirmar)
        let formato = NSPopUpButton(frame: .zero, pullsDown: false)
        formato.addItems(withTitles: ["General", "Número", "Moneda", "Porcentaje", "Fecha"])
        formato.target = self
        formato.action = #selector(elegirFormato(_:))
        formato.toolTip = "Formato del número"
        let fondo = menuDeColores("Resaltar", hojaFondos(), sinColor: "Sin color", #selector(elegirFondo(_:)))
        let letra = menuDeColores("Color de letra", hojaColoresDeLetra(), sinColor: "Automático", #selector(elegirLetra(_:)))
        let arriba = NSStackView(views: [
            referencia, barra,
            boton("arrow.uturn.backward", "Deshacer (⌘Z)", #selector(deshacer)),
            boton("arrow.uturn.forward", "Rehacer (⇧⌘Z)", #selector(rehacer)),
            boton("bold", "Negrita (⌘B)", #selector(negrita)),
            boton("italic", "Cursiva (⌘I)", #selector(cursiva)),
            boton("underline", "Subrayado (⌘U)", #selector(subrayado)),
            boton("strikethrough", "Tachado (⌘5)", #selector(tachado)),
            boton("text.alignleft", "Izquierda (⇧⌘L)", #selector(alinearIzquierda)),
            boton("text.aligncenter", "Centro (⇧⌘E)", #selector(alinearCentro)),
            boton("text.alignright", "Derecha (⇧⌘R)", #selector(alinearDerecha)),
            boton("text.word.spacing", "Ajustar texto", #selector(ajustar)),
            formato, fondo, letra,
            boton("eraser", "Borrar formato", #selector(borrarFormato)),
        ])
        arriba.orientation = .horizontal
        arriba.spacing = 6
        arriba.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        arriba.translatesAutoresizingMaskIntoConstraints = false
        barra.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        self.arriba = arriba

        aviso.textColor = .secondaryLabelColor
        aviso.font = .systemFont(ofSize: 11)
        aviso.isHidden = true
        aviso.translatesAutoresizingMaskIntoConstraints = false

        rejilla.controlador = self
        rejilla.dataSource = self
        rejilla.delegate = self
        rejilla.usesAlternatingRowBackgroundColors = false
        rejilla.gridStyleMask = [.solidHorizontalGridLineMask, .solidVerticalGridLineMask]
        rejilla.selectionHighlightStyle = .none
        rejilla.allowsColumnReordering = false
        rejilla.allowsColumnResizing = true
        rejilla.rowHeight = 22
        rejilla.intercellSpacing = NSSize(width: 0, height: 0)
        rejilla.target = self
        rejilla.action = #selector(clic)
        rejilla.doubleAction = #selector(dobleClic)
        let scroll = NSScrollView()
        scroll.documentView = rejilla
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        // Las pestanas de las hojas, abajo como en Excel.
        pestanas.orientation = .horizontal
        pestanas.spacing = 2
        pestanas.edgeInsets = NSEdgeInsets(top: 3, left: 8, bottom: 3, right: 8)
        pestanas.translatesAutoresizingMaskIntoConstraints = false

        let raiz = NSView()
        raiz.addSubview(arriba)
        raiz.addSubview(aviso)
        raiz.addSubview(scroll)
        raiz.addSubview(pestanas)
        NSLayoutConstraint.activate([
            arriba.topAnchor.constraint(equalTo: raiz.topAnchor),
            arriba.leadingAnchor.constraint(equalTo: raiz.leadingAnchor),
            arriba.trailingAnchor.constraint(lessThanOrEqualTo: raiz.trailingAnchor),
            barra.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
            aviso.topAnchor.constraint(equalTo: arriba.bottomAnchor),
            aviso.leadingAnchor.constraint(equalTo: raiz.leadingAnchor, constant: 10),
            aviso.trailingAnchor.constraint(lessThanOrEqualTo: raiz.trailingAnchor, constant: -10),
            scroll.topAnchor.constraint(equalTo: aviso.bottomAnchor, constant: 2),
            scroll.leadingAnchor.constraint(equalTo: raiz.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: raiz.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: pestanas.topAnchor),
            pestanas.leadingAnchor.constraint(equalTo: raiz.leadingAnchor),
            pestanas.trailingAnchor.constraint(lessThanOrEqualTo: raiz.trailingAnchor),
            pestanas.bottomAnchor.constraint(equalTo: raiz.bottomAnchor),
        ])
        ventana.contentView = raiz
        ventana.setContentSize(NSSize(width: 980, height: 660))
        ventana.center()
        _ = ventana.setFrameAutosaveName("PixPinHoja")
        NotificationCenter.default.addObserver(self, selector: #selector(columnaCambiada(_:)),
                                               name: NSTableView.columnDidResizeNotification, object: rejilla)
        ponerPestanas()
        arribaCerrada = arriba.heightAnchor.constraint(equalToConstant: 0)
        modelo.nombre = ventana.title
        modelo.controlador = self
        ponerEditando(false)
        let modelo = self.modelo
        let barraPin = BarraFlotante(ventana: ventana) { BarraHojaPin(modelo: modelo) }
        barraPin.empezar()
        self.barraPin = barraPin
    }

    /// El lapiz y el ojo de la barra del pin.
    func ponerEditando(_ si: Bool) {
        modelo.editando = si
        arriba?.isHidden = !si
        arribaCerrada?.isActive = !si
        if !si, ventana.firstResponder === barra.currentEditor() { ventana.makeFirstResponder(rejilla) }
    }

    /// Las pestanas de un libro (con una sola hoja no hacen falta).
    private func ponerPestanas() {
        for v in pestanas.arrangedSubviews { pestanas.removeArrangedSubview(v); v.removeFromSuperview() }
        let nombres = hoja.hojas()
        pestanas.isHidden = nombres.count < 2
        let activa = Int(hoja.activa())
        for (i, n) in nombres.enumerated() {
            let b = NSButton(title: n, target: self, action: #selector(elegirPestana(_:)))
            b.tag = i
            b.bezelStyle = .recessed
            b.setButtonType(.pushOnPushOff)
            b.state = i == activa ? .on : .off
            b.toolTip = "⌃⇟ / ⌃⇞ o ⌥⌘→ / ⌥⌘← cambian de hoja"
            pestanas.addArrangedSubview(b)
        }
    }

    @objc private func elegirPestana(_ b: NSButton) { irAHoja(b.tag) }

    private func irAHoja(_ i: Int) {
        let n = hoja.hojas().count
        guard n > 0 else { return }
        let destino = (i % n + n) % n
        if ventana.firstResponder === barra.currentEditor() { confirmar() }
        hoja.cambiarHoja(hoja: UInt32(destino))
        trasCambioDeHoja()
    }

    /// Otra hoja (o deshacer llevo a otra): todo lo que se ve es nuevo.
    private func trasCambioDeHoja() {
        bloques = [:]
        rejilla.tableColumns.forEach { rejilla.removeTableColumn($0) }
        recalcularTamano()
        ponerPestanas()
        let s = hoja.seleccion()
        anclaFila = Int(s.anclaFila)
        anclaColumna = Int(s.anclaColumna)
        elegir(Int(s.fila), Int(s.columna), extender: true)
    }

    /// Lo que se ensena: lo escrito y un margen para seguir escribiendo.
    private func recalcularTamano() {
        let t = hoja.tamano()
        let c = max(Int(t.first ?? 0) + 5, 26)
        filas = max(Int(t.count > 1 ? t[1] : 0) + 50, 200)
        if c != columnas || rejilla.tableColumns.isEmpty {
            columnas = min(c, 16_384)
            ponerColumnas()
        }
        rejilla.reloadData()
    }

    private func ponerColumnas() {
        for col in rejilla.tableColumns { rejilla.removeTableColumn(col) }
        let cabecera = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("#"))
        cabecera.title = ""
        cabecera.width = 44
        cabecera.resizingMask = []
        rejilla.addTableColumn(cabecera)
        let anchos = Dictionary(hoja.anchos().map { (Int($0.columna), CGFloat($0.ancho)) }, uniquingKeysWith: { a, _ in a })
        for i in 0..<columnas {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("\(i)"))
            col.title = letrasDeColumna(i)
            col.width = anchos[i] ?? 90
            col.minWidth = 24
            col.headerCell.alignment = .center
            rejilla.addTableColumn(col)
        }
    }

    // MARK: Datos

    private func celda(_ f: Int, _ c: Int) -> CeldaHoja? {
        let b = f / ControladorHoja.filasPorBloque
        if bloques[b] == nil {
            let desde = UInt32(b * ControladorHoja.filasPorBloque)
            var mapa: [Int: [Int: CeldaHoja]] = [:]
            for x in hoja.celdas(desdeFila: desde, hastaFila: desde + UInt32(ControladorHoja.filasPorBloque),
                                 desdeColumna: 0, hastaColumna: UInt32(columnas)) {
                mapa[Int(x.fila), default: [:]][Int(x.columna)] = x
            }
            bloques[b] = mapa
        }
        return bloques[b]?[f]?[c]
    }

    func numberOfRows(in tableView: NSTableView) -> Int { filas }

    private var rango: (f0: Int, c0: Int, f1: Int, c1: Int) {
        (min(fila, anclaFila), min(columna, anclaColumna), max(fila, anclaFila), max(columna, anclaColumna))
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let id = tableColumn?.identifier else { return nil }
        let vista = (tableView.makeView(withIdentifier: id, owner: self) as? NSTextField) ?? {
            let t = NSTextField(labelWithString: "")
            t.identifier = id
            t.lineBreakMode = .byTruncatingTail
            t.drawsBackground = true
            return t
        }()
        if id.rawValue == "#" {
            vista.stringValue = "\(row + 1)"
            vista.alignment = .center
            vista.textColor = .secondaryLabelColor
            vista.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            vista.backgroundColor = .controlBackgroundColor
            return vista
        }
        let c = Int(id.rawValue) ?? 0
        let x = celda(row, c)
        let e = x?.estilo
        vista.stringValue = x.map { textoDeCelda($0) } ?? ""
        var letra = NSFont.systemFont(ofSize: 12)
        if e?.negrita == true { letra = NSFontManager.shared.convert(letra, toHaveTrait: .boldFontMask) }
        if e?.cursiva == true { letra = NSFontManager.shared.convert(letra, toHaveTrait: .italicFontMask) }
        vista.font = letra
        vista.lineBreakMode = e?.ajustar == true ? .byWordWrapping : .byTruncatingTail
        vista.textColor = x?.error == true ? .systemRed : (colorDeHex(e?.color) ?? .labelColor)
        switch e?.alineacion {
        case "c": vista.alignment = .center
        case "d": vista.alignment = .right
        case "i": vista.alignment = .left
        default: vista.alignment = x?.numero != nil ? .right : .left
        }
        let r = rango
        let activa = row == fila && c == columna
        let dentro = (r.f0...r.f1).contains(row) && (r.c0...r.c1).contains(c)
        vista.backgroundColor = activa ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.25)
            : dentro ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.12)
            : (colorDeHex(e?.fondo) ?? .clear)
        var adornos: [NSAttributedString.Key: Any] = [.font: letra, .foregroundColor: vista.textColor ?? NSColor.labelColor]
        if e?.subrayado == true { adornos[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if e?.tachado == true { adornos[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if adornos.count > 2 {
            let p = NSMutableParagraphStyle()
            p.alignment = vista.alignment
            adornos[.paragraphStyle] = p
            vista.attributedStringValue = NSAttributedString(string: vista.stringValue, attributes: adornos)
        }
        return vista
    }

    /// Tras un cambio: todo se vuelve a calcular y se repinta lo que se ve.
    private func trasCambio() {
        bloques = [:]
        recalcularTamano()
        programarGuardado()
        // La primera vez que se edita un libro: el archivo no cambia.
        if hoja.avisoAlEditar() {
            aviso.stringValue = "El archivo original no cambia: lo editado queda en el chat como tablas (el móvil las ve igual)."
            aviso.isHidden = false
        }
    }

    // MARK: Elegir y editar

    /// Elige una celda; con `extender` (⇧) alarga lo elegido desde el ancla.
    private func elegir(_ f: Int, _ c: Int, extender: Bool = false) {
        let antes = rango
        fila = max(0, min(f, filas - 1))
        columna = max(0, min(c, columnas - 1))
        if !extender {
            anclaFila = fila
            anclaColumna = columna
        }
        hoja.elegir(s: SeleccionHoja(anclaFila: UInt32(anclaFila), anclaColumna: UInt32(anclaColumna),
                                     fila: UInt32(fila), columna: UInt32(columna)))
        let r = rango
        referencia.stringValue = r.f0 == r.f1 && r.c0 == r.c1 ? "\(letrasDeColumna(columna))\(fila + 1)"
            : "\(letrasDeColumna(r.c0))\(r.f0 + 1):\(letrasDeColumna(r.c1))\(r.f1 + 1)"
        barra.stringValue = hoja.contenido(fila: UInt32(fila), columna: UInt32(columna))
        let filasRepintar = IndexSet(integersIn: min(antes.f0, r.f0)...max(antes.f1, r.f1))
        rejilla.reloadData(forRowIndexes: filasRepintar, columnIndexes: IndexSet(integersIn: 0..<rejilla.numberOfColumns))
        rejilla.scrollRowToVisible(fila)
        rejilla.scrollColumnToVisible(columna + 1)
    }

    @objc private func clic() {
        let f = rejilla.clickedRow, c = rejilla.clickedColumn - 1
        guard f >= 0, c >= 0 else { return }
        let extender = NSEvent.modifierFlags.contains(.shift)
        elegir(f, c, extender: extender)
    }

    @objc private func dobleClic() {
        clic()
        guard modelo.editando else { return }
        ventana.makeFirstResponder(barra)
    }

    /// Enter en la barra: se escribe la celda y se baja una.
    @objc private func confirmar() {
        if hoja.poner(fila: UInt32(fila), columna: UInt32(columna), contenido: barra.stringValue) {
            trasCambio()
        }
        elegir(fila + 1, columna)
        ventana.makeFirstResponder(rejilla)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            let original = hoja.contenido(fila: UInt32(fila), columna: UInt32(columna))
            // Sin nada escrito, ⎋ es el del visor: sale de pantalla completa o cierra.
            if barra.stringValue == original {
                VentanaLisa.escapar(ventana)
                return true
            }
            barra.stringValue = original
            ventana.makeFirstResponder(rejilla)
            return true
        }
        // Tab escribiendo: se deja escrito y se va a la derecha (⇧, izquierda).
        if selector == #selector(NSResponder.insertTab(_:)) || selector == #selector(NSResponder.insertBacktab(_:)) {
            if hoja.poner(fila: UInt32(fila), columna: UInt32(columna), contenido: barra.stringValue) { trasCambio() }
            elegir(fila, columna + (selector == #selector(NSResponder.insertTab(_:)) ? 1 : -1))
            ventana.makeFirstResponder(rejilla)
            return true
        }
        return false
    }

    private var escribiendo: Bool {
        guard let r = ventana.firstResponder as? NSText else { return false }
        return r === barra.currentEditor()
    }

    private func accion(_ e: NSEvent) -> AccionHoja? {
        let m = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return AccionHoja.de(tecla: e.keyCode, letra: e.charactersIgnoringModifiers ?? "",
                             mayus: m.contains(.shift), comando: m.contains(.command), opcion: m.contains(.option),
                             control: m.contains(.control), escribiendo: escribiendo)
    }

    /// Las teclas con ⌘ (antes que los menus). `true` si era suya.
    func atajo(_ e: NSEvent) -> Bool {
        let m = e.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        if m == [.control, .command], e.keyCode == 3, ventana.isKeyWindow {
            ventana.toggleFullScreen(nil)
            return true
        }
        guard e.modifierFlags.contains(.command) || e.modifierFlags.contains(.control),
              ventana.isKeyWindow, let a = accion(e) else { return false }
        hacer(a)
        return true
    }

    /// Las teclas de la rejilla. `true` si era suya.
    func tecla(_ e: NSEvent) -> Bool {
        let m = e.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        if let a = accion(e) {
            hacer(a)
            return true
        }
        let ext = m.contains(.shift)
        // Viendo, solo moverse, copiar y salir: escribir no edita.
        if !modelo.editando, [36, 76].contains(e.keyCode) || (m.subtracting(.shift).isEmpty
            && e.characters?.unicodeScalars.first.map({ !CharacterSet.controlCharacters.contains($0) }) == true) {
            return true
        }
        if e.keyCode == 53, m.isEmpty { VentanaLisa.escapar(ventana); return true }
        switch e.keyCode {
        case 123: elegir(fila, columna - 1, extender: ext); return true
        case 124: elegir(fila, columna + 1, extender: ext); return true
        case 125: elegir(fila + 1, columna, extender: ext); return true
        case 126: elegir(fila - 1, columna, extender: ext); return true
        case 48: elegir(fila, columna + (ext ? -1 : 1)); return true
        case 36, 76: ventana.makeFirstResponder(barra); return true
        default: break
        }
        // Escribir algo empieza a editar la celda en la barra.
        if m.subtracting(.shift).isEmpty, let s = e.characters, let u = s.unicodeScalars.first,
           !CharacterSet.controlCharacters.contains(u) {
            barra.stringValue = s
            ventana.makeFirstResponder(barra)
            barra.currentEditor()?.selectedRange = NSRange(location: (s as NSString).length, length: 0)
            return true
        }
        return false
    }

    /// **Hace lo que pide una tecla o un boton.**
    func hacer(_ a: AccionHoja) {
        // Viendo, lo que cambia la hoja no se hace (como Windows sin editar).
        if !modelo.editando {
            switch a {
            case .copiar, .elegirTodo, .hojaSiguiente, .hojaAnterior, .borde, .cancelar: break
            default: return NSSound.beep()
            }
        }
        switch a {
        case .deshacer, .rehacer:
            let hoja0 = hoja.activa()
            let hecho = a == .deshacer ? hoja.deshacer() : hoja.rehacer()
            guard hecho else { NSSound.beep(); return }
            if hoja.activa() != hoja0 {
                trasCambioDeHoja()
            } else {
                let s = hoja.seleccion()
                anclaFila = Int(s.anclaFila)
                anclaColumna = Int(s.anclaColumna)
                trasCambio()
                elegir(Int(s.fila), Int(s.columna), extender: true)
            }
            programarGuardado()
        case .copiar, .cortar:
            let copia = hoja.copiar()
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(copia.texto, forType: .string)
            pb.setString(copia.html, forType: .html)
            if a == .cortar, hoja.borrarSeleccion() { trasCambio(); barra.stringValue = "" }
        case .pegar:
            let pb = NSPasteboard.general
            if hoja.pegar(html: pb.string(forType: .html), texto: pb.string(forType: .string)) {
                let s = hoja.seleccion()
                anclaFila = Int(s.anclaFila)
                anclaColumna = Int(s.anclaColumna)
                trasCambio()
                elegir(Int(s.fila), Int(s.columna), extender: true)
            } else {
                NSSound.beep()
            }
        case .elegirTodo:
            let t = hoja.tamano()
            anclaFila = 0
            anclaColumna = 0
            elegir(max(Int(t.count > 1 ? t[1] : 1) - 1, 0), max(Int(t.first ?? 1) - 1, 0), extender: true)
        case let .formato(f):
            if escribiendo { confirmar(); elegir(fila - 1, columna) }
            if hoja.formato(f: f) { trasCambio() }
        case .empezar:
            ventana.makeFirstResponder(barra)
            barra.currentEditor()?.selectedRange = NSRange(location: (barra.stringValue as NSString).length, length: 0)
        case .borrar:
            if hoja.borrarSeleccion() { trasCambio() }
            barra.stringValue = ""
        case .cancelar:
            barra.stringValue = hoja.contenido(fila: UInt32(fila), columna: UInt32(columna))
            ventana.makeFirstResponder(rejilla)
        case .hojaSiguiente:
            irAHoja(Int(hoja.activa()) + 1)
        case .hojaAnterior:
            irAHoja(Int(hoja.activa()) - 1)
        case let .borde(dx, dy):
            let t = hoja.tamano()
            let ultimaC = max(Int(t.first ?? 1) - 1, 0), ultimaF = max(Int(t.count > 1 ? t[1] : 1) - 1, 0)
            let f = dy < 0 ? 0 : dy > 0 ? max(ultimaF, fila) : fila
            let c = dx < 0 ? 0 : dx > 0 ? max(ultimaC, columna) : columna
            elegir(f, c, extender: NSEvent.modifierFlags.contains(.shift))
        }
    }

    // MARK: Formato (de todo lo elegido)

    @objc private func deshacer() { hacer(.deshacer) }
    @objc private func rehacer() { hacer(.rehacer) }
    @objc private func negrita() { hacer(.formato(.negrita)) }
    @objc private func cursiva() { hacer(.formato(.cursiva)) }
    @objc private func subrayado() { hacer(.formato(.subrayado)) }
    @objc private func tachado() { hacer(.formato(.tachado)) }
    @objc private func ajustar() { hacer(.formato(.ajustar)) }
    @objc private func borrarFormato() { hacer(.formato(.borrar)) }
    @objc private func alinearIzquierda() { hacer(.formato(.alinear(alineacion: "i"))) }
    @objc private func alinearCentro() { hacer(.formato(.alinear(alineacion: "c"))) }
    @objc private func alinearDerecha() { hacer(.formato(.alinear(alineacion: "d"))) }

    @objc private func elegirFormato(_ s: NSPopUpButton) {
        let nf: String? = [nil, "numero", "moneda", "porcentaje", "fecha"][max(0, min(s.indexOfSelectedItem, 4))]
        hacer(.formato(.numero(formato: nf)))
    }

    /// De un menu de colores: 1 es «sin color», 2… los de la paleta.
    private func colorElegido(_ s: NSPopUpButton, _ paleta: [ColorHoja]) -> String?? {
        let i = s.indexOfSelectedItem
        if i == 1 { return .some(nil) }
        guard i >= 2, i - 2 < paleta.count else { return nil }
        return .some(paleta[i - 2].hex)
    }

    @objc private func elegirFondo(_ s: NSPopUpButton) {
        if let c = colorElegido(s, hojaFondos()) { hacer(.formato(.fondo(color: c))) }
    }

    @objc private func elegirLetra(_ s: NSPopUpButton) {
        if let c = colorElegido(s, hojaColoresDeLetra()) { hacer(.formato(.letra(color: c))) }
    }

    @objc private func columnaCambiada(_ n: Notification) {
        guard let col = n.userInfo?["NSTableColumn"] as? NSTableColumn, let i = Int(col.identifier.rawValue) else { return }
        if hoja.ponerAncho(columna: UInt32(i), ancho: UInt32(max(col.width, 16).rounded())) { programarGuardado() }
    }

    // MARK: Guardar

    private func programarGuardado() {
        guardado?.cancel()
        let hoja = self.hoja
        let tarea = DispatchWorkItem { ControladorHoja.guardarYa(hoja) }
        guardado = tarea
        colaGuardar.asyncAfter(deadline: .now() + 1.0, execute: tarea)
    }

    private nonisolated static func guardarYa(_ hoja: HojaDeCalculo) {
        do {
            if try hoja.guardar() {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .pixpinCambioLocal, object: nil)
                }
            }
        } catch {
            let e = "\(error)"
            DispatchQueue.main.async { NSLog("PixPin: no se pudo guardar la hoja: %@", e) }
        }
    }

    func windowWillClose(_ notification: Notification) {
        if ventana.firstResponder === barra.currentEditor() { confirmar() }
        guardado?.cancel()
        let hoja = self.hoja
        colaGuardar.async { ControladorHoja.guardarYa(hoja) }
        NotificationCenter.default.removeObserver(self)
        alCerrar?(self)
    }
}

/// **Las hojas de calculo abiertas**: una ventana por mensaje.
@MainActor
public final class HojasDeCalculo {
    public static let compartidas = HojasDeCalculo()
    private var abiertas: [String: ControladorHoja] = [:]

    public func abrir(_ mensaje: MensajeChat, en chat: String, almacen: Almacen) {
        let clave = chat + "\u{0}" + mensaje.id
        if let c = abiertas[clave] {
            c.ventana.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let nucleo = almacen.nucleo
        let id = mensaje.id
        let titulo = mensaje.nombre.isEmpty ? "Tabla" : mensaje.nombre
        Task { [self] in
            let hecho = await Task.detached(priority: .userInitiated) { () -> Result<HojaDeCalculo, Error> in
                Result { try nucleo.abrirHojaDeCalculo(chat: chat, mensaje: id) }
            }.value
            switch hecho {
            case let .success(hoja):
                let c = ControladorHoja(hoja: hoja, titulo: titulo)
                c.alCerrar = { [weak self] _ in self?.abiertas[clave] = nil }
                self.abiertas[clave] = c
                c.ventana.makeKeyAndOrderFront(nil)
                NSApp.activate()
            case let .failure(e):
                almacen.ponerError("No se puede abrir la hoja: \(e)")
            }
        }
    }
}


/// Lo que ve la barra del pin de la hoja.
@MainActor
final class ModeloHojaPin: ObservableObject {
    @Published var editando = false
    @Published var nombre = ""
    weak var controlador: ControladorHoja?
}

/// **La barra del pin de la hoja**: viendo, el lapiz; editando, el ojo
/// (el formato va en la barra de la ventana, debajo).
struct BarraHojaPin: View {
    @ObservedObject var modelo: ModeloHojaPin

    var body: some View {
        BarraVisor(nombre: modelo.nombre, ext: (modelo.nombre as NSString).pathExtension) {
            BotonVerEditar(editando: modelo.editando) {
                modelo.controlador?.ponerEditando(!modelo.editando)
            }
        }
    }
}
