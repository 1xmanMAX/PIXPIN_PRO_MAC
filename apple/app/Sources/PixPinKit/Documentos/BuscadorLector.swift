// **Buscar dentro del documento** (D9 de Windows, `buscador.rs`): la caja de
// buscar de un navegador, que es la que el usuario ya conoce.
//
// - ⌘F la abre (Ctrl+F alla) con lo escrito elegido; lo que se teclea busca
//   al momento, sin mirar mayusculas ni tildes («arbol» encuentra «Árbol»,
//   «espana» encuentra «España»).
// - ↩ o ⌘G van a la siguiente y ⇧↩ o ⇧⌘G a la anterior (F3 y Mayus+F3
//   alla, que aqui tambien valen), dando la vuelta al llegar al final;
//   «3 de 12»; ⎋ la cierra. Con la caja cerrada, ⌘G sigue con lo ultimo.
// - Todas las coincidencias marcadas en dorado claro y la actual en naranja
//   (`MARCA` y `MARCA_ACTUAL` de Windows). La primera es la primera **desde
//   donde se esta leyendo**: escribir no manda al principio del libro.
//
// Busca PDFKit (`beginFindString`), en segundo plano y hoja a hoja; un Word
// o un PowerPoint tambien, que sus hojas llevan el texto (`PintorOffice`).

import AppKit
import PDFKit
import SwiftUI

@MainActor
public final class BuscadorLector: ObservableObject {
    @Published public var abierto = false
    @Published public var consulta = ""
    @Published public private(set) var buscando = false
    @Published public private(set) var total = 0
    @Published public private(set) var actual: Int?
    /// Sube cada vez que hay que poner el foco en la caja.
    @Published private(set) var foco = 0

    /// Las coincidencias, en orden de lectura.
    private(set) var coincidencias: [PDFSelection] = []
    /// El documento y la hoja por donde se lee.
    var documento: () -> (PDFDocument?, Int) = { (nil, 0) }
    /// Saltar a la actual y marcar las que toque.
    var mostrar: (_ actual: PDFSelection?, _ todas: [PDFSelection]) -> Void = { _, _ in }
    /// Un visor sin PDF (el reflujado, E7) busca el solo: da cuantas hay y
    /// la primera desde donde se lee, y luego pinta la actual y, si
    /// `marcar`, todas. Puesto esto, no se usa `documento` ni `mostrar`.
    var buscarEnTexto: ((String) -> (Int, Int?))?
    var mostrarEnTexto: ((_ actual: Int?, _ marcar: Bool) -> Void)?

    private var desde = 0
    private var irAlLlegar = false
    private var vigias: [NSObjectProtocol] = []
    private weak var buscandoEn: PDFDocument?
    private var tarea: DispatchWorkItem?

    static let colorMarca = NSColor(srgbRed: 0xE8 / 255, green: 0xC0 / 255, blue: 0x6A / 255, alpha: 0.32)
    static let colorActual = NSColor(srgbRed: 1, green: 0x8C / 255, blue: 0, alpha: 0.62)

    /// Lo que no es letra ni cifra no cuenta: buscar solo espacios no
    /// encuentra nada (marcar cada espacio no sirve a nadie).
    var consultaLimpia: String { consulta.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// «3 de 12», «Sin resultados», «Buscando…» o nada.
    public var rotulo: String {
        if consultaLimpia.isEmpty { return "" }
        if let a = actual, total > 0 { return "\(a + 1) de \(total)" }
        if buscando { return "Buscando…" }
        return total == 0 ? "Sin resultados" : "\(total)"
    }

    /// Abre la caja (⌘F): el foco a ella, con lo escrito elegido.
    func abrir() {
        abierto = true
        foco += 1
        if !consultaLimpia.isEmpty {
            if buscarEnTexto != nil { pintar() } else { mostrar(laActual, coincidencias) }
        }
    }

    func cerrar() {
        abierto = false
        cancelar()
        if let m = mostrarEnTexto { m(nil, false) } else { mostrar(nil, []) }
    }

    /// Lo escrito cambio: se vuelve a buscar un instante despues de la
    /// ultima letra (no a cada una en un libro largo).
    func escrito() {
        tarea?.cancel()
        let t = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.buscar(ir: true) }
        }
        tarea = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: t)
    }

    /// A la siguiente, y del final vuelta a la primera.
    func siguiente() { mover(1) }
    /// A la anterior, y de la primera vuelta a la ultima.
    func anterior() { mover(-1) }

    private var laActual: PDFSelection? {
        actual.flatMap { $0 < coincidencias.count ? coincidencias[$0] : nil }
    }

    private func mover(_ paso: Int) {
        if consultaLimpia.isEmpty { return }
        let n = buscarEnTexto != nil ? total : coincidencias.count
        if n == 0 {
            // Cerrada y con lo ultimo buscado (F3 de Windows): se busca otra vez.
            if !buscando { buscar(ir: true) }
            return
        }
        actual = actual.map { (($0 + paso) % n + n) % n } ?? (paso > 0 ? 0 : n - 1)
        pintar()
    }

    private func pintar() {
        if let m = mostrarEnTexto {
            m(actual, abierto)
            return
        }
        let todas = abierto ? coincidencias : laActual.map { [$0] } ?? []
        for s in coincidencias { s.color = BuscadorLector.colorMarca }
        laActual?.color = BuscadorLector.colorActual
        mostrar(laActual, todas)
    }

    private func cancelar() {
        tarea?.cancel()
        if let d = buscandoEn, d.isFinding { d.cancelFindString() }
        for v in vigias { NotificationCenter.default.removeObserver(v) }
        vigias = []
        buscando = false
    }

    /// Vuelve a buscar con lo escrito ahora.
    func buscar(ir: Bool) {
        cancelar()
        coincidencias = []
        total = 0
        actual = nil
        let q = consultaLimpia
        if let buscarEnTexto {
            guard !q.isEmpty else {
                mostrarEnTexto?(nil, false)
                return
            }
            let (n, primera) = buscarEnTexto(q)
            total = n
            actual = ir && n > 0 ? (primera ?? 0) : nil
            pintar()
            return
        }
        let (doc, hoja) = documento()
        guard let doc, !q.isEmpty else {
            mostrar(nil, [])
            return
        }
        desde = hoja
        irAlLlegar = ir
        buscandoEn = doc
        buscando = true
        let centro = NotificationCenter.default
        vigias.append(centro.addObserver(forName: .PDFDocumentDidFindMatch, object: doc, queue: .main) { [weak self] n in
            let s = n.userInfo?["PDFDocumentFoundSelection"] as? PDFSelection
            MainActor.assumeIsolated { if let s { self?.llego(s) } }
        })
        vigias.append(centro.addObserver(forName: .PDFDocumentDidEndFind, object: doc, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.acabo() }
        })
        doc.beginFindString(q, withOptions: [.caseInsensitive, .diacriticInsensitive])
    }

    private func llego(_ s: PDFSelection) {
        coincidencias.append(s)
        total = coincidencias.count
        s.color = BuscadorLector.colorMarca
        // La primera desde donde se lee: alli se salta en cuanto llega.
        if actual == nil, irAlLlegar, let p = s.pages.first, let d = buscandoEn, d.index(for: p) >= desde {
            actual = coincidencias.count - 1
            irAlLlegar = false
            pintar()
        }
    }

    private func acabo() {
        buscando = false
        for v in vigias { NotificationCenter.default.removeObserver(v) }
        vigias = []
        if actual == nil, !coincidencias.isEmpty, irAlLlegar {
            actual = 0
        }
        irAlLlegar = false
        pintar()
    }
}

/// **La caja de buscar**, arriba en medio del lector, oscura como su barra.
struct CajaBuscar: View {
    @ObservedObject var buscador: BuscadorLector
    @FocusState private var enfocada: Bool

    var body: some View {
        if buscador.abierto {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color(white: 0.78))
                TextField("Buscar en el documento", text: $buscador.consulta)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .frame(width: 240)
                    .focused($enfocada)
                    .onSubmit {
                        if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                            buscador.anterior()
                        } else {
                            buscador.siguiente()
                        }
                        enfocada = true
                    }
                    .onExitCommand { buscador.cerrar() }
                    .onChange(of: buscador.consulta) { buscador.escrito() }
                Text(buscador.rotulo)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color(white: 0.78))
                    .fixedSize()
                Button { buscador.anterior() } label: { Image(systemName: "chevron.up") }
                    .help("Anterior (⇧↩ o ⇧⌘G)")
                Button { buscador.siguiente() } label: { Image(systemName: "chevron.down") }
                    .help("Siguiente (↩ o ⌘G)")
                Button { buscador.cerrar() } label: { Image(systemName: "xmark") }
                    .help("Cerrar (⎋)")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color(red: 0.96, green: 0.96, blue: 0.97))
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(Color(red: 0.118, green: 0.118, blue: 0.125, opacity: 0.97),
                        in: RoundedRectangle(cornerRadius: 12))
            .environment(\.colorScheme, .dark)
            .onAppear { enfocada = true }
            .onChange(of: buscador.foco) { enfocada = true }
        }
    }
}
