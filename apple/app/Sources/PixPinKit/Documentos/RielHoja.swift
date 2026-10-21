import AppKit
import PixPinCore
import SwiftUI

/// **El riel de la hoja de calculo** (Windows, `visor_hoja/riel.rs`): el
/// mismo de los PDF a la derecha, con lapiz, marcador y marco.
///
/// - Marcador: en la celda activa; `x` la columna e `y` la hoja por
///   `porHoja` mas la fila, en la linea `marcas` del `.pixpin-lectura` del
///   libro (la del PDF), con su vista en el `.vistas.json`.
/// - Lapiz: la tinta de cada hoja (`anot-<uid>-h<i>`, pixeles de la hoja).
/// - Marco: los marcos numerados de la hoja (`parte` = la hoja).
@MainActor
final class RielHoja {
    static let porHoja: Double = 10_000_000
    let modelo = ModeloLector()
    let capaTinta = CapaTintaDoc()
    let capaMarcos = CapaMarcosVista()
    private let url: URL?
    private let nucleo: Nucleo?
    private(set) var marcos: MarcosDoc
    private var hoja = 0
    var irA: ((Int, Int, Int) -> Void)?
    var celdaActiva: (() -> (hoja: Int, fila: Int, columna: Int))?

    init(url: URL?, nucleo: Nucleo?) {
        self.url = url
        self.nucleo = nucleo
        marcos = MarcosDoc(documento: url, nucleo: nucleo)
    }

    private(set) lazy var tinta: HerramientasDeTinta = {
        let t = HerramientasDeTinta(nucleo: nucleo)
        t.editores = { [weak self] in self?.capaTinta.editor.map { [$0] } ?? [] }
        t.elegir = { [weak self] h in self?.elegir(h) }
        t.deshacer = { [weak self] in if self?.capaTinta.editor?.deshacer() == true { self?.capaTinta.guardarLuego() } }
        t.rehacer = { [weak self] in if self?.capaTinta.editor?.rehacer() == true { self?.capaTinta.guardarLuego() } }
        t.repintar = { [weak self] in self?.capaTinta.needsDisplay = true }
        return t
    }()

    func montar(en raiz: NSView, rejilla: NSView, arriba: CGFloat) {
        for c in [capaTinta, capaMarcos] as [NSView] {
            c.frame = rejilla.bounds
            c.autoresizingMask = [.width, .height]
            rejilla.addSubview(c)
        }
        capaMarcos.documento = rejilla
        capaMarcos.marcos = marcos
        capaMarcos.parte = 0
        let isla = NSHostingView(rootView: VStack(alignment: .trailing, spacing: 10) {
            IslaRiel(modelo: modelo, marcar: { [weak self] in self?.modelo.poniendoMarca.toggle() },
                     lapiz: url == nil ? nil : { [weak self] in self?.alternarLapiz() },
                     imprimir: { [weak self] in self?.alternarMarcos() })
            PuntosDeMarcas(modelo: modelo) { [weak self] m in self?.ir(a: m) }
        }.fixedSize())
        let tira = NSHostingView(rootView: TiraMarcas(modelo: modelo) { [weak self] e in self?.ponerMarca(e) }.fixedSize())
        for v in [isla, tira] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            raiz.addSubview(v)
        }
        NSLayoutConstraint.activate([
            isla.trailingAnchor.constraint(equalTo: raiz.trailingAnchor, constant: -22),
            isla.topAnchor.constraint(equalTo: raiz.topAnchor, constant: arriba),
            tira.centerXAnchor.constraint(equalTo: raiz.centerXAnchor),
            tira.bottomAnchor.constraint(equalTo: raiz.bottomAnchor, constant: -40),
        ])
        tinta.montar(en: raiz, modelo: modelo)
        raiz.ponerFichasDeMarcos(marcos) { [weak self] i in self?.irAMarco(i) }
        leerMarcas()
        cambioDeHoja(0)
    }

    // MARK: Hojas

    func cambioDeHoja(_ i: Int) {
        capaTinta.guardarYa()
        hoja = i
        capaMarcos.parte = i
        capaTinta.editor = nil
        abrirTinta(crear: modelo.anotando)
    }

    private func abrirTinta(crear: Bool) {
        guard let url, let nucleo else { return }
        let ruta = nucleo.rutaDeTintaDeHoja(libro: url.path, hoja: UInt32(hoja))
        guard crear || FileManager.default.fileExists(atPath: ruta),
              let ed = try? EditorLienzo.deFichero(ruta: ruta, crear: true) else { return }
        capaTinta.editor = ed
        if modelo.anotando { tinta.aplicar(a: ed, herramienta: modelo.herramienta, color: modelo.color) }
    }

    // MARK: Lapiz

    func alternarLapiz() { elegir(modelo.anotando ? "leer" : tinta.alEmpezar) }

    private func elegir(_ h: String) {
        if h != "leer", marcos.activo { alternarMarcos() }
        modelo.herramienta = h
        tinta.ensenar(h)
        capaTinta.anotando = h != "leer"
        if h == "leer" { capaTinta.guardarYa(); return }
        modelo.poniendoMarca = false
        if let ed = capaTinta.editor { tinta.aplicar(a: ed, herramienta: h, color: modelo.color) } else { abrirTinta(crear: true) }
    }

    // MARK: Marcos

    func alternarMarcos() {
        if modelo.anotando { elegir("leer") }
        marcos.activo.toggle()
        modelo.enmarcando = marcos.activo
        capaMarcos.needsDisplay = true
        capaMarcos.window?.invalidateCursorRects(for: capaMarcos)
    }

    /// La ficha de un marco: a su hoja y a el.
    func irAMarco(_ i: Int) {
        guard i < marcos.lista.count else { return }
        let m = marcos.lista[i]
        if Int(m.parte) != hoja { irAHoja?(Int(m.parte)) }
        capaMarcos.scrollToVisible(m.rect.insetBy(dx: -20, dy: -20))
    }
    var irAHoja: ((Int) -> Void)?

    func quitarUltimoMarco() -> Bool {
        guard marcos.activo, marcos.quitarUltimo() else { return false }
        capaMarcos.needsDisplay = true
        return true
    }

    // MARK: Marcadores

    private func leerMarcas() {
        guard let url, let nucleo else { return }
        modelo.marcas = nucleo.lecturaDeDocumento(documento: url.path).marcas
    }

    private func guardarMarcas() {
        guard let url, let nucleo else { return }
        var l = nucleo.lecturaDeDocumento(documento: url.path)
        l.marcas = modelo.marcas
        try? nucleo.guardarLecturaDeDocumento(documento: url.path, lectura: l, altos: [])
    }

    private func ponerMarca(_ emoji: String) {
        modelo.poniendoMarca = false
        guard let c = celdaActiva?() else { return }
        modelo.marcas = conMarca(modelo.marcas, x: Double(c.columna), y: Double(c.hoja) * RielHoja.porHoja + Double(c.fila),
                                 emoji: emoji, ahora: Int64(Date().timeIntervalSince1970 * 1000))
        guardarMarcas()
    }

    func ir(a m: MarcaDocumento) {
        let y = max(m.y, 0).rounded()
        let h = Int((y / RielHoja.porHoja).rounded(.down))
        irA?(h, Int(y - Double(h) * RielHoja.porHoja), Int(max(m.x, 0).rounded()))
    }

    func quitar(_ m: MarcaDocumento) {
        modelo.marcas.removeAll { $0.id == m.id }
        guardarMarcas()
    }
}

/// Los puntos de los marcadores debajo de la isla: el emoticono; con el
/// raton encima crece y se adelanta.
struct PuntosDeMarcas: View {
    @ObservedObject var modelo: ModeloLector
    let ir: (MarcaDocumento) -> Void
    @State private var encima: Int64?

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            ForEach(Array(modelo.marcas.enumerated()), id: \.element.id) { i, m in
                Button { ir(m) } label: {
                    Text(m.emoji)
                        .font(.system(size: encima == m.id ? 20 : 13))
                        .frame(width: encima == m.id ? 36 : 22, height: encima == m.id ? 36 : 22)
                        .background(Circle().fill(Color(white: 0.12, opacity: encima == m.id ? 0.85 : 0.55)))
                        .offset(x: encima == m.id ? -8 : 0)
                }
                .buttonStyle(.plain)
                .help("\(m.emoji)\(i < 9 ? "  (⌘\(i + 1))" : "")")
                .onHover { encima = $0 ? m.id : (encima == m.id ? nil : encima) }
                .animation(.easeOut(duration: 0.12), value: encima)
            }
        }
    }
}

/// **La tinta sobre una vista de documento** (la rejilla de una hoja): la
/// capa en las coordenadas de esa vista (pixeles de la hoja al 100 %); con
/// el lapiz suelto deja pasar los clics.
@MainActor
class CapaTintaDoc: NSView {
    var editor: EditorLienzo? { didSet { leido = nil; needsDisplay = true } }
    var anotando = false { didSet { window?.invalidateCursorRects(for: self) } }
    private var leido: (version: UInt64, lienzo: LienzoLeido)?
    private let alDia = AlDiaLector()
    private var pendiente: DispatchWorkItem?

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { anotando ? super.hitTest(point) : nil }
    override func resetCursorRects() { if anotando { addCursorRect(visibleRect, cursor: .crosshair) } }

    override func draw(_ sucio: NSRect) {
        guard let ed = editor, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let v = ed.version()
        if leido?.version != v, let l = try? leerLienzo(ed.plano()) { leido = (v, l) }
        guard let l = leido?.lienzo, !l.figuras.isEmpty else { return }
        PintorLienzo(lienzo: l).pintar(en: ctx, limites: sucio)
    }

    private func puntero(_ fase: FasePuntero, _ e: NSEvent) {
        guard let ed = editor else { return }
        let p = convert(e.locationInWindow, from: nil)
        let presion: Float? = e.subtype == .tabletPoint ? Float(e.pressure) : nil
        var mods: UInt32 = 0
        if e.modifierFlags.contains(.shift) { mods |= 1 }
        if e.modifierFlags.contains(.option) { mods |= 2 }
        _ = ed.puntero(fase: fase, x: Float(p.x), y: Float(p.y), presion: presion, modificadores: mods,
                       zoom: Float(enclosingScrollView?.magnification ?? 1))
        needsDisplay = true
        if fase == .soltar { guardarLuego() }
    }

    override func mouseDown(with e: NSEvent) { puntero(.pulsar, e) }
    override func mouseDragged(with e: NSEvent) { puntero(.mover, e) }
    override func mouseUp(with e: NSEvent) { puntero(.soltar, e) }
    override func rightMouseDown(with e: NSEvent) {
        if editor?.deshacer() == true { needsDisplay = true; guardarLuego() }
    }

    func guardarLuego() {
        needsDisplay = true
        pendiente?.cancel()
        guard let ed = editor else { return }
        let alDia = self.alDia
        let w = DispatchWorkItem {
            guard ed.sinGuardar(), let r = try? alDia.guardar(0, ed), r.escrito else { return }
            DispatchQueue.main.async { NotificationCenter.default.post(name: .pixpinCambioLocal, object: nil) }
        }
        pendiente = w
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.8, execute: w)
    }

    func guardarYa() {
        pendiente?.cancel()
        guard let ed = editor, ed.sinGuardar() else { return }
        _ = try? alDia.guardar(0, ed)
    }
}
