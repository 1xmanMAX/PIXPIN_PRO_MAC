// **Sacar el dibujo del lienzo**: exportar (PNG, SVG, PDF), copiar como
// PNG, compartir e imprimir, como en Windows (`ventana_editor/exportar.rs`:
// Ctrl+Mayus+E, Ctrl+Mayus+C, Ctrl+Mayus+S y Ctrl+P; aqui ⇧⌘E, ⇧⌘C, ⇧⌘S y
// ⌘P, y los botones del grupo «Compartir e imprimir» de la barra).
//
// Las hojas (todo, lo elegido o cada marco) las decide el motor
// (`editor_exportar.rs`) y el SVG lo escribe el motor. El PNG, el PDF y el
// papel los pinta el mismo `PintorLienzo` de la pantalla sobre un mapa de
// bits, un PDF vectorial o la impresora (`PintorDeHojas`).
//
// Compartir es la hoja del Mac (`NSSharingServicePicker`) con el lienzo en
// el formato que se elija; la hoja de compartir comun de Windows
// (`compartir/`, D1) aun no existe en el Mac.

import AppKit
import PixPinCore
import UniformTypeIdentifiers

/// Los formatos que salen.
enum FormatoSalidaLienzo: String, CaseIterable {
    case png, svg, pdf

    var titulo: String {
        switch self {
        case .png: return "Imagen PNG"
        case .svg: return "Dibujo SVG"
        case .pdf: return "Documento PDF"
        }
    }

    var tipo: UTType {
        switch self {
        case .png: return .png
        case .svg: return .svg
        case .pdf: return .pdf
        }
    }
}

extension QueExportar {
    var titulo: String {
        switch self {
        case .todo: return "Todo el lienzo"
        case .seleccion: return "Lo elegido"
        case .marcos: return "Cada marco"
        }
    }
}

extension ModeloEditorLienzo {
    /// Lo que sale de fabrica: lo elegido si hay algo elegido; si no, todo.
    var queDeFabrica: QueExportar { editor.cuantosElegidos() > 0 ? .seleccion : .todo }

    /// **Los ficheros de `que` en `formato`**: uno por hoja (el PDF, uno con
    /// una pagina por hoja). Vacio si no hay nada.
    func ficheros(_ formato: FormatoSalidaLienzo, que: QueExportar, transparente: Bool,
                  escala: CGFloat = 2) -> [Data] {
        switch formato {
        case .svg:
            if let fondo {
                editor.ponerPapel(ancho: Float(fondo.tamano.width), alto: Float(fondo.tamano.height), png: fondo.png())
            }
            return editor.svgParaExportar(que: que, transparente: transparente).map { Data($0.utf8) }
        case .png:
            let version = editor.version()
            return editor.hojasParaExportar(que: que).compactMap { h in
                PintorDeHojas.imagen(h.plano, caja: h.caja, escala: escala, transparente: transparente,
                                     tapados: tapados, version: version, fotos: { [weak self] in self?.foto($0) })
                    .flatMap(PintorDeHojas.png)
            }
        case .pdf:
            return pdf(que: que, transparente: transparente).map { [$0] } ?? []
        }
    }

    /// Un PDF vectorial con una pagina por hoja, del tamano de la hoja.
    func pdf(que: QueExportar, transparente: Bool) -> Data? {
        let hojas = editor.hojasParaExportar(que: que)
        guard !hojas.isEmpty else { return nil }
        let datos = NSMutableData()
        guard let consumidor = CGDataConsumer(data: datos as CFMutableData),
              let ctx = CGContext(consumer: consumidor, mediaBox: nil, nil) else { return nil }
        let version = editor.version()
        for h in hojas {
            var pagina = CGRect(origin: .zero, size: h.caja.size)
            ctx.beginPage(mediaBox: &pagina)
            ctx.translateBy(x: 0, y: pagina.height)
            ctx.scaleBy(x: 1, y: -1)
            PintorDeHojas.pintar(h.plano, caja: h.caja, en: ctx, destino: pagina, transparente: transparente,
                                 tapados: tapados, version: version, fotos: { [weak self] in self?.foto($0) })
            ctx.endPage()
        }
        ctx.closePDF()
        return datos as Data
    }

    /// El nombre limpio para un fichero.
    var nombreDeFichero: String {
        let limpio = titulo.components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>")).joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        return limpio.isEmpty ? "Lienzo" : limpio
    }

    /// El fichero de la hoja `i` de `n`: el elegido si solo hay una, y con su
    /// numero detras si hay varias (`ruta_numerada` de Windows).
    static func numerada(_ url: URL, _ i: Int, _ n: Int) -> URL {
        guard n > 1 else { return url }
        let tronco = url.deletingPathExtension().lastPathComponent
        return url.deletingLastPathComponent()
            .appendingPathComponent("\(tronco)-\(i + 1)").appendingPathExtension(url.pathExtension)
    }

    private func avisar(_ texto: String) {
        let a = NSAlert()
        a.messageText = "Exportar el lienzo"
        a.informativeText = texto
        if let w = vista?.window { a.beginSheetModal(for: w) } else { a.runModal() }
    }

    // MARK: Exportar

    /// **Exportar…** (⇧⌘E): el panel de guardar con el formato, que sacar y
    /// el fondo transparente.
    func exportar() {
        desplegado = nil
        guard let ventana = vista?.window else { return }
        let panel = NSSavePanel()
        panel.title = "Exportar el lienzo"
        panel.nameFieldStringValue = nombreDeFichero
        let opciones = OpcionesExportarLienzo(que: queDeFabrica)
        panel.accessoryView = opciones.vista
        panel.allowedContentTypes = [opciones.formato.tipo]
        opciones.alCambiarFormato = { [weak panel] f in panel?.allowedContentTypes = [f.tipo] }
        panel.beginSheetModal(for: ventana) { [weak self] r in
            MainActor.assumeIsolated {
                guard r == .OK, let url = panel.url, let self else { return }
                let datos = self.ficheros(opciones.formato, que: opciones.que, transparente: opciones.transparente)
                guard !datos.isEmpty else { return self.avisar("No hay nada que exportar con esto.") }
                do {
                    for (i, d) in datos.enumerated() {
                        try d.write(to: Self.numerada(url, i, datos.count), options: .atomic)
                    }
                } catch {
                    self.avisar("No se pudo exportar el lienzo.\n\n\(error.localizedDescription)")
                }
            }
        }
    }

    /// **Copiar como PNG** (⇧⌘C): lo elegido o todo, al portapapeles.
    func copiarComoPNG() {
        guard let png = ficheros(.png, que: queDeFabrica, transparente: false).first else {
            NSSound.beep()
            return
        }
        let tablero = NSPasteboard.general
        tablero.clearContents()
        tablero.setData(png, forType: .png)
    }

    // MARK: Compartir

    /// **Compartir…** (⇧⌘S): elegir el formato y la hoja del Mac con el
    /// fichero (lo elegido si hay algo elegido; si no, todo).
    func compartir() {
        desplegado = nil
        guard let vista else { return }
        let menu = NSMenu(title: "Compartir")
        for f in FormatoSalidaLienzo.allCases {
            let item = NSMenuItem(title: "Compartir como \(f.rawValue.uppercased())…",
                                  action: #selector(VistaEditorLienzoNS.compartirComo(_:)), keyEquivalent: "")
            item.representedObject = f.rawValue
            item.target = vista
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let exportar = NSMenuItem(title: "Exportar…", action: #selector(VistaEditorLienzoNS.exportarDesdeMenu(_:)),
                                  keyEquivalent: "e")
        exportar.keyEquivalentModifierMask = [.command, .shift]
        exportar.target = vista
        menu.addItem(exportar)
        let copiar = NSMenuItem(title: "Copiar como PNG", action: #selector(VistaEditorLienzoNS.copiarDesdeMenu(_:)),
                                keyEquivalent: "c")
        copiar.keyEquivalentModifierMask = [.command, .shift]
        copiar.target = vista
        menu.addItem(copiar)
        let punto = vista.window?.mouseLocationOutsideOfEventStream ?? .zero
        menu.popUp(positioning: nil, at: vista.convert(punto, from: nil), in: vista)
    }

    /// Los ficheros de `formato` en una carpeta temporal, para compartirlos.
    func ficherosParaCompartir(_ formato: FormatoSalidaLienzo) -> [URL] {
        let datos = ficheros(formato, que: queDeFabrica, transparente: false)
        guard !datos.isEmpty else { return [] }
        let carpeta = FileManager.default.temporaryDirectory
            .appendingPathComponent("pixpin-compartir-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        let base = carpeta.appendingPathComponent(nombreDeFichero).appendingPathExtension(formato.rawValue)
        return datos.enumerated().compactMap { i, d in
            let url = Self.numerada(base, i, datos.count)
            return (try? d.write(to: url)) != nil ? url : nil
        }
    }

    // MARK: Imprimir

    /// **Imprimir…** (⌘P): el dialogo del Mac con su vista previa, una hoja
    /// por pagina y encajada en el papel; en el dialogo se elige que
    /// imprimir (cada marco en su hoja, todo o lo elegido).
    func imprimir() {
        desplegado = nil
        guard let ventana = vista?.window else { return }
        let que: QueExportar = editor.cuantosElegidos() > 0 ? .seleccion
            : (editor.hojasParaExportar(que: .marcos).count > 1 ? .marcos : .todo)
        guard !editor.hojasParaExportar(que: que).isEmpty else {
            NSSound.beep()
            return
        }
        let papel = VistaImpresionLienzo(modelo: self, que: que)
        let info = NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo()
        info.horizontalPagination = .fit
        info.verticalPagination = .fit
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = true
        if let h = papel.hojas.first, h.caja.width > h.caja.height { info.orientation = .landscape }
        let op = NSPrintOperation(view: papel, printInfo: info)
        op.jobTitle = titulo
        op.printPanel.options.insert([.showsPreview, .showsOrientation, .showsPaperSize])
        op.printPanel.addAccessoryController(AccesorioImpresionLienzo(papel: papel))
        op.runModal(for: ventana, delegate: nil, didRun: nil, contextInfo: nil)
    }
}

extension HojaExportada {
    var caja: CGRect { CGRect(x: CGFloat(x0), y: CGFloat(y0), width: CGFloat(x1 - x0), height: CGFloat(y1 - y0)) }
}

extension VistaEditorLienzoNS {
    @objc func compartirComo(_ sender: NSMenuItem) {
        guard let nombre = sender.representedObject as? String, let f = FormatoSalidaLienzo(rawValue: nombre) else { return }
        let urls = modelo.ficherosParaCompartir(f)
        guard !urls.isEmpty else { return NSSound.beep() }
        let selector = NSSharingServicePicker(items: urls)
        let punto = convert(window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil)
        selector.show(relativeTo: NSRect(x: punto.x, y: punto.y, width: 1, height: 1), of: self, preferredEdge: .minY)
    }

    @objc func exportarDesdeMenu(_ sender: Any?) { modelo.exportar() }

    @objc func copiarDesdeMenu(_ sender: Any?) { modelo.copiarComoPNG() }
}

/// Lo que se elige al exportar, debajo del panel de guardar.
@MainActor
final class OpcionesExportarLienzo: NSObject {
    private(set) var formato: FormatoSalidaLienzo = .png
    private(set) var que: QueExportar
    private(set) var transparente = false
    var alCambiarFormato: (FormatoSalidaLienzo) -> Void = { _ in }
    let vista: NSView

    private let popFormato = NSPopUpButton()
    private let popQue = NSPopUpButton()
    private let casilla = NSButton(checkboxWithTitle: "Fondo transparente", target: nil, action: nil)
    private static let ques: [QueExportar] = [.todo, .seleccion, .marcos]

    init(que: QueExportar) {
        self.que = que
        let rejilla = NSGridView(views: [
            [NSTextField(labelWithString: "Formato:"), popFormato],
            [NSTextField(labelWithString: "Qué:"), popQue],
            [NSGridCell.emptyContentView, casilla],
        ])
        rejilla.rowSpacing = 8
        rejilla.column(at: 0).xPlacement = .trailing
        let caja = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 104))
        rejilla.translatesAutoresizingMaskIntoConstraints = false
        caja.addSubview(rejilla)
        NSLayoutConstraint.activate([
            rejilla.centerXAnchor.constraint(equalTo: caja.centerXAnchor),
            rejilla.centerYAnchor.constraint(equalTo: caja.centerYAnchor),
        ])
        vista = caja
        super.init()
        popFormato.addItems(withTitles: FormatoSalidaLienzo.allCases.map(\.titulo))
        popQue.addItems(withTitles: Self.ques.map(\.titulo))
        popQue.selectItem(at: Self.ques.firstIndex(of: que) ?? 0)
        for c in [popFormato, popQue, casilla] as [NSControl] {
            c.target = self
            c.action = #selector(cambio(_:))
        }
    }

    @objc private func cambio(_ sender: Any?) {
        formato = FormatoSalidaLienzo.allCases[max(0, popFormato.indexOfSelectedItem)]
        que = Self.ques[max(0, popQue.indexOfSelectedItem)]
        transparente = casilla.state == .on
        alCambiarFormato(formato)
    }
}

/// **El papel que se imprime**: una pagina por hoja, cada una encajada en la
/// pagina con su margen (`encaje` de Windows).
final class VistaImpresionLienzo: NSView {
    private weak var modelo: ModeloEditorLienzo?
    private(set) var hojas: [HojaExportada]
    @objc dynamic var que: Int {
        didSet {
            guard let modelo else { return }
            let nuevas = MainActor.assumeIsolated {
                modelo.editor.hojasParaExportar(que: VistaImpresionLienzo.ques[que])
            }
            if !nuevas.isEmpty { hojas = nuevas }
        }
    }

    static let ques: [QueExportar] = [.marcos, .todo, .seleccion]

    @MainActor
    init(modelo: ModeloEditorLienzo, que: QueExportar) {
        self.modelo = modelo
        self.que = Self.ques.firstIndex(of: que) ?? 1
        hojas = modelo.editor.hojasParaExportar(que: que)
        super.init(frame: NSRect(x: 0, y: 0, width: 600, height: 800))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    override var isFlipped: Bool { true }

    /// El tamano de una pagina, del papel elegido menos sus margenes.
    private var pagina: NSSize {
        let info = NSPrintOperation.current?.printInfo ?? NSPrintInfo.shared
        return NSSize(width: info.paperSize.width - info.leftMargin - info.rightMargin,
                      height: info.paperSize.height - info.topMargin - info.bottomMargin)
    }

    override func knowsPageRange(_ range: NSRangePointer) -> Bool {
        let p = pagina
        setFrameSize(NSSize(width: p.width, height: p.height * CGFloat(max(1, hojas.count))))
        range.pointee = NSRange(location: 1, length: max(1, hojas.count))
        return true
    }

    override func rectForPage(_ page: Int) -> NSRect {
        let p = pagina
        return NSRect(x: 0, y: CGFloat(page - 1) * p.height, width: p.width, height: p.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, let modelo else { return }
        let p = pagina
        MainActor.assumeIsolated {
            let version = modelo.editor.version()
            for (i, h) in hojas.enumerated() {
                let sitio = NSRect(x: 0, y: CGFloat(i) * p.height, width: p.width, height: p.height)
                guard sitio.intersects(dirtyRect) else { continue }
                // Encajada y centrada, sin agrandar lo pequeno mas del doble.
                let k = min(p.width / h.caja.width, p.height / h.caja.height, 2)
                let w = h.caja.width * k, alto = h.caja.height * k
                let destino = NSRect(x: sitio.midX - w / 2, y: sitio.midY - alto / 2, width: w, height: alto)
                PintorDeHojas.pintar(h.plano, caja: h.caja, en: ctx, destino: destino, transparente: true,
                                     tapados: modelo.tapados, version: version,
                                     fotos: { [weak modelo] in modelo?.foto($0) })
            }
        }
    }
}

/// **Que imprimir**, dentro del dialogo de imprimir (`imprimir-que` de
/// Windows): cada marco en su hoja, todo el lienzo en una hoja o solo lo
/// elegido. La vista previa se rehace al cambiarlo.
final class AccesorioImpresionLienzo: NSViewController, NSPrintPanelAccessorizing {
    private let papel: VistaImpresionLienzo
    private let pop = NSPopUpButton()

    init(papel: VistaImpresionLienzo) {
        self.papel = papel
        super.init(nibName: nil, bundle: nil)
        title = "Lienzo"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    override func loadView() {
        pop.addItems(withTitles: ["Cada marco en su hoja", "Todo el lienzo en una hoja", "Solo lo elegido"])
        pop.selectItem(at: papel.que)
        pop.target = self
        pop.action = #selector(cambio(_:))
        let fila = NSStackView(views: [NSTextField(labelWithString: "Qué imprimir:"), pop])
        fila.edgeInsets = NSEdgeInsets(top: 12, left: 20, bottom: 12, right: 20)
        view = fila
    }

    @objc private func cambio(_ sender: Any?) {
        willChangeValue(forKey: "queElegido")
        papel.que = pop.indexOfSelectedItem
        didChangeValue(forKey: "queElegido")
    }

    @objc var queElegido: Int { papel.que }

    func localizedSummaryItems() -> [[NSPrintPanel.AccessorySummaryKey: String]] {
        [[.itemName: "Qué imprimir", .itemDescription: pop.titleOfSelectedItem ?? ""]]
    }

    func keyPathsForValuesAffectingPreview() -> Set<String> { ["queElegido"] }
}
