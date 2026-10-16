// **Las figuras del lienzo** (el boton `Figuras` de la barra de Windows,
// `ventana_editor/figuras.rs`): la grafica de una funcion, la tabla en
// blanco, pegar una tabla de Excel, los instrumentos de graficar (el plano,
// la recta y el espacio) y la biblioteca de figuras guardadas.
//
// Como en Windows, el panel es el menu nativo (sabe de teclado y de bordes
// de pantalla); los cajetines, aqui, hojas del Mac. La geometria y la
// biblioteca son de Rust (`editor_figuras.rs`). Todo entra en medio de la
// vista, agrupado, elegido y en un paso de deshacer.
//
// Lo que falta respecto a Windows: editar una tabla ya dibujada, meter lo
// elegido en su celda y las tablas de coordenadas.

import AppKit
import PixPinCore

extension ModeloEditorLienzo {
    /// **El menu de las figuras**, bajo el raton.
    func abrirFiguras() {
        guard let vista else { return }
        let menu = NSMenu(title: "Figuras")
        func item(_ titulo: String, _ accion: @escaping () -> Void) {
            menu.addItem(AccionMenuLienzo.item(titulo, accion))
        }
        item("Gráfica de una función…") { [weak self] in self?.pedirGrafica() }
        item("Tabla en blanco…") { [weak self] in self?.pedirTablaEnBlanco() }
        item("Pegar tabla (de Excel)") { [weak self] in self?.pegarTabla() }
        menu.addItem(.separator())
        for (ejes, titulo) in [(UInt8(2), "Plano de funciones"), (1, "Recta de funciones"), (3, "Espacio xyz")] {
            item(titulo) { [weak self] in
                guard let self else { return }
                let c = vista.centroMundo
                if self.editor.estamparInstrumento(ejes: ejes, centroX: Float(c.x), centroY: Float(c.y)) {
                    vista.trasCambio()
                }
            }
        }
        let guardadas = (try? nucleo?.figurasGuardadas()) ?? []
        if !guardadas.isEmpty {
            menu.addItem(.separator())
            for f in guardadas {
                item(f.nombre) { [weak self] in self?.estamparGuardada(f.id) }
            }
        }
        if nucleo != nil {
            menu.addItem(.separator())
            if editor.cuantosElegidos() > 0 {
                item("Guardar lo elegido como figura…") { [weak self] in self?.guardarComoFigura() }
            }
            for f in guardadas {
                item("Quitar «\(f.nombre)»") { [weak self] in _ = try? self?.nucleo?.quitarFigura(id: f.id) }
            }
        }
        if menu.items.last?.isSeparatorItem == true { menu.removeItem(at: menu.items.count - 1) }
        let punto = vista.convert(vista.window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil)
        menu.popUp(positioning: nil, at: punto, in: vista)
    }

    private func estamparGuardada(_ id: String) {
        guard let vista, let nucleo else { return }
        let c = vista.centroMundo
        if (try? nucleo.estamparFigura(editor: editor, id: id, centroX: Float(c.x), centroY: Float(c.y))) == true {
            vista.trasCambio()
        }
    }

    /// Una tabla con estas celdas en medio de la vista.
    func estamparTabla(_ celdas: [[String]], cabecera: Bool) {
        guard let vista else { return }
        let c = vista.centroMundo
        if editor.estamparTabla(celdas: celdas, cabecera: cabecera, centroX: Float(c.x), centroY: Float(c.y)) {
            vista.trasCambio()
        }
    }

    /// **Pegar tabla**: las celdas que trae el portapapeles (renglones y
    /// tabuladores, lo que deja copiar unas celdas de Excel o de Sheets).
    func pegarTabla() {
        guard let texto = NSPasteboard.general.string(forType: .string),
              let celdas = celdasDeTexto(texto: texto) else {
            avisoFiguras("El portapapeles no trae una tabla")
            return
        }
        estamparTabla(celdas, cabecera: true)
    }

    private func avisoFiguras(_ texto: String) {
        let a = NSAlert()
        a.messageText = "Figuras"
        a.informativeText = texto
        if let w = vista?.window { a.beginSheetModal(for: w) } else { a.runModal() }
    }

    /// **La tabla en blanco**: cuantas filas y columnas.
    func pedirTablaEnBlanco() {
        guard let ventana = vista?.window else { return }
        let filas = NSTextField(string: "4"), columnas = NSTextField(string: "3")
        let cabecera = NSButton(checkboxWithTitle: "Cabecera", target: nil, action: nil)
        cabecera.state = .on
        let a = NSAlert()
        a.messageText = "Tabla en blanco"
        a.accessoryView = CajetinLienzo.formulario([("Filas", filas), ("Columnas", columnas)], extra: cabecera)
        a.addButton(withTitle: "Insertar")
        a.addButton(withTitle: "Cancelar")
        a.window.initialFirstResponder = filas
        a.beginSheetModal(for: ventana) { [weak self] r in
            MainActor.assumeIsolated {
                guard r == .alertFirstButtonReturn else { return }
                let f = min(50, max(1, filas.integerValue)), c = min(20, max(1, columnas.integerValue))
                self?.estamparTabla(Array(repeating: Array(repeating: "", count: c), count: f),
                                    cabecera: cabecera.state == .on)
            }
        }
    }

    /// **La grafica de una funcion**: las formulas (una curva por renglon)
    /// y su ventana, como el cajetin de Windows; si algo no se entiende, lo
    /// dice y se vuelve a pedir.
    func pedirGrafica(formulas: String = "sin(x)", limites: [String] = ["-5", "5", "-3", "3", "40"]) {
        guard let ventana = vista?.window else { return }
        let campo = NSTextField(string: formulas)
        campo.placeholderString = "x^2 - 2x · sin(x)/x · x^2 si x<0; 2x si x>=0"
        let numeros = limites.map { NSTextField(string: $0) }
        let a = NSAlert()
        a.messageText = "Gráfica de una función"
        a.informativeText = "Una curva por renglón (separadas por «;;» o con ⌥↩). Por partes: x^2 si x<0; 2x si x>=0"
        a.accessoryView = CajetinLienzo.formulario(
            [("y =", campo), ("x desde", numeros[0]), ("x hasta", numeros[1]), ("y desde", numeros[2]),
             ("y hasta", numeros[3]), ("Píxeles por unidad", numeros[4])], extra: nil, ancho: 340)
        a.addButton(withTitle: "Insertar")
        a.addButton(withTitle: "Cancelar")
        a.window.initialFirstResponder = campo
        a.beginSheetModal(for: ventana) { [weak self] r in
            MainActor.assumeIsolated {
                guard r == .alertFirstButtonReturn, let self, let vista = self.vista else { return }
                let lineas = campo.stringValue.components(separatedBy: ";;")
                let n = numeros.map { Double(CajetinMedida.numero($0.stringValue) ?? .nan) }
                let c = vista.centroMundo
                do {
                    if try self.editor.estamparGrafica(formulas: lineas, xDesde: n[0], xHasta: n[1], yDesde: n[2],
                                                       yHasta: n[3], escala: n[4], centroX: Float(c.x),
                                                       centroY: Float(c.y)) {
                        vista.trasCambio()
                    }
                } catch {
                    // Se dice que falla y se vuelve a pedir con lo tecleado.
                    let aviso = avisoDeGrafica(formulas: lineas, xDesde: n[0], xHasta: n[1], yDesde: n[2],
                                               yHasta: n[3], escala: n[4]) ?? "\(error)"
                    let otra = NSAlert()
                    otra.messageText = "Gráfica de una función"
                    otra.informativeText = aviso
                    otra.beginSheetModal(for: ventana) { _ in
                        MainActor.assumeIsolated {
                            self.pedirGrafica(formulas: campo.stringValue, limites: numeros.map(\.stringValue))
                        }
                    }
                }
            }
        }
    }

    /// **Guardar lo elegido como figura**, con su nombre.
    func guardarComoFigura() {
        guard let ventana = vista?.window, let nucleo else { return }
        let nombre = NSTextField(string: "")
        nombre.placeholderString = "Figura"
        let a = NSAlert()
        a.messageText = "Guardar como figura"
        a.accessoryView = CajetinLienzo.formulario([("Nombre", nombre)], extra: nil)
        a.addButton(withTitle: "Guardar")
        a.addButton(withTitle: "Cancelar")
        a.window.initialFirstResponder = nombre
        a.beginSheetModal(for: ventana) { [weak self] r in
            MainActor.assumeIsolated {
                guard r == .alertFirstButtonReturn, let self else { return }
                _ = try? nucleo.guardarFigura(editor: self.editor, nombre: nombre.stringValue)
            }
        }
    }
}

/// Un formulario de etiquetas y campos para el `accessoryView` de un aviso.
@MainActor
enum CajetinLienzo {
    static func formulario(_ filas: [(String, NSView)], extra: NSView?, ancho: CGFloat = 240) -> NSView {
        var vistas: [[NSView]] = filas.map { [NSTextField(labelWithString: $0.0), $0.1] }
        if let extra { vistas.append([NSGridCell.emptyContentView, extra]) }
        let rejilla = NSGridView(views: vistas)
        rejilla.rowSpacing = 6
        rejilla.column(at: 0).xPlacement = .trailing
        rejilla.column(at: 1).width = ancho
        rejilla.layoutSubtreeIfNeeded()
        rejilla.frame.size = rejilla.fittingSize
        return rejilla
    }
}

/// Un item de menu que hace un cierre (los menus de figuras y compartir).
@MainActor
final class AccionMenuLienzo: NSObject {
    private let accion: () -> Void
    private static var vivas: [AccionMenuLienzo] = []

    private init(_ accion: @escaping () -> Void) { self.accion = accion }

    @MainActor
    static func item(_ titulo: String, _ accion: @escaping () -> Void) -> NSMenuItem {
        let a = AccionMenuLienzo(accion)
        // El item no retiene su `target`: se guardan aqui (pocos y ligeros).
        vivas.append(a)
        if vivas.count > 200 { vivas.removeFirst(vivas.count - 200) }
        let item = NSMenuItem(title: titulo, action: #selector(hacer), keyEquivalent: "")
        item.target = a
        return item
    }

    @objc private func hacer() { accion() }
}
