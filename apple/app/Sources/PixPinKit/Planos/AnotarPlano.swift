// **Anotar el plano a mano** (A, `plano_cad::anotar` de Windows): el
// lienzo de verdad encima del plano, con su barra de herramientas, su panel
// de estilo y sus teclas, como en Android v0.114 («anotar en el visor de
// planos usa las herramientas del motor del lienzo, sin herramientas
// propias»).
//
// Como va:
// - Rust abre la capa del plano como editor (`Plano.anotar`): la
//   `anot-<uid>` del mensaje si el plano es de un chat (viaja), la de la
//   cache si se abrio desde el Finder, en las unidades de su `.hoja`;
// - su vista (`VistaEditorLienzoNS`) va dentro de la del plano, con el
//   papel transparente y **la camara del plano**: cada vez que el plano se
//   mueve o se acerca, la vista del lienzo se pone donde cae la capa
//   (`x = cero_x + x_capa * u`, `y = cero_y - y_capa * u`). La rueda, el
//   pellizco y el boton derecho siguen moviendo el plano;
// - al terminar (A otra vez, o el boton), lo escrito se guarda, la `.hoja`
//   va detras de la capa y el visor vuelve a leer las cotas y los marcos
//   (anotando se pueden borrar o mover: son figuras de la capa).
//
// Medir, marcar y anotar no van a la vez (el arrastre seria de todos), como
// en Windows.

import AppKit
import PixPinCore

/// El lienzo encima del plano mientras se anota.
@MainActor
final class AnotadorPlano {
    let modelo: ModeloEditorLienzo
    let vista: VistaEditorLienzoNS
    /// Como cae la capa en el dibujo (el de cuando se empezo: con el se
    /// escribe la `.hoja`).
    let encaje: EncajePlano
    private let plano: Plano
    private var vigia: NSObjectProtocol?

    /// La referencia con que el lienzo avisa al guardar.
    var referencia: String { "plano|" + plano.rutaDeLaCapa() }

    init(plano: Plano, nucleo: Nucleo?, titulo: String) throws {
        self.plano = plano
        let editor = try plano.anotar()
        encaje = plano.encaje()
        modelo = ModeloEditorLienzo(editor: editor, referencia: "plano|" + plano.rutaDeLaCapa(), nucleo: nucleo,
                                    titulo: titulo)
        // Trazo limpio: sobre un plano se senala, no se boceta.
        modelo.cambiarEstilo(.rugosidad(valor: 0))
        vista = VistaEditorLienzoNS(modelo: modelo)
        vista.papelTransparente = true
        vista.autoresizingMask = [.width, .height]
        // La capa de un plano que no es de ningun chat: su `.hoja` la pone
        // el visor cuando el lienzo guarda (en un chat la escribe el editor).
        let encaje = self.encaje
        vigia = NotificationCenter.default.addObserver(forName: .pixpinLienzoGuardado, object: nil, queue: .main) {
            [plano] n in
            guard (n.object as? String) == "plano|" + plano.rutaDeLaCapa() else { return }
            Task.detached(priority: .utility) { _ = try? plano.ponerHoja(encaje: encaje) }
        }
    }

    /// **La camara del lienzo para la del plano**: `camara` (unidades del
    /// dibujo por pixel), `escala` (pixeles por punto) y el tamano de la
    /// vista en puntos.
    static func camaraDelLienzo(_ camara: CamaraPlano, escala: Double, tamano: CGSize,
                                encaje e: EncajePlano) -> (origen: CGPoint, zoom: CGFloat) {
        // Unidades del dibujo por punto de la pantalla.
        let s = camara.px * escala
        let w = Double(tamano.width), h = Double(tamano.height)
        return (CGPoint(x: (camara.centroX - w / 2 * s - e.ceroX) / e.u,
                        y: (e.ceroY - camara.centroY - h / 2 * s) / e.u),
                CGFloat(e.u / s))
    }

    /// Pone la vista del lienzo donde cae la capa con la camara del plano.
    func seguir(_ camara: CamaraPlano, escala: Double, tamano: CGSize) {
        guard encaje.u > 0, camara.px > 0, escala > 0 else { return }
        let c = AnotadorPlano.camaraDelLienzo(camara, escala: escala, tamano: tamano, encaje: encaje)
        vista.ponerCamara(origen: c.origen, zoom: c.zoom)
    }

    /// **Termina**: lo que se escribia se queda escrito y la capa se guarda
    /// (con su `.hoja`) fuera del hilo principal.
    func terminar() async {
        if let v = vigia { NotificationCenter.default.removeObserver(v) }
        vigia = nil
        vista.removeFromSuperview()
        let editor = modelo.editor, plano = self.plano, encaje = self.encaje
        await Task.detached(priority: .userInitiated) {
            _ = editor.terminarTexto()
            if (try? editor.guardar()) == true {
                _ = try? plano.ponerHoja(encaje: encaje)
                await MainActor.run { NotificationCenter.default.post(name: .pixpinCambioLocal, object: nil) }
            }
        }.value
    }
}
