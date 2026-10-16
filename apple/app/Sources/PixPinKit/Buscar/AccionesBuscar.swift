// **Lo que hace cada cosa del buscador** (D8): las ordenes de
// `EstadoBuscar` hechas con lo de la app. Es `Ventana::hacer` y `orden` de
// `buscar_todo.rs` de Windows, que alli manda pedidos a la app; aqui se
// llama a lo de siempre:
//
// - un mensaje o una tarea se ven en su chat, en su pagina y marcados
//   (`PeticionDeChat` + `SaltoAMensaje`);
// - un fichero se abre como desde su burbuja (el visor de planos, el lector
//   de PDF, el pin de Office, el editor de notas, o su app);
// - una captura se pinea, se copia como imagen, se conserva o va a la
//   papelera de PixPin con ⌘Z;
// - una tarea se marca o desmarca sin cerrar (como `PedirYSeguir`);
// - una leccion abre Lecciones; un momento, su detalle del timeline
//   (`PeticionDeMomento`);
// - las acciones: apuntar al Inbox, nota y lienzo nuevos en «Mensajes
//   guardados», capturar, la ultima captura como pin y las ventanas.

import AppKit
import PixPinCore
import SwiftUI

@MainActor
struct EjecutorBuscar {
    let modelo: ModeloBuscar
    let abrirVentana: (String) -> Void
    let cerrar: () -> Void
    let vaciar: () -> Void
    let vistaRapida: (URL) -> Void

    private var almacen: Almacen { modelo.almacen }
    private var nucleo: Nucleo { modelo.almacen.nucleo }

    func hacer(_ o: OrdenBuscar) {
        switch o {
        case .noEsMia, .nada:
            break
        case .buscar:
            modelo.refrescar()
        case .vaciar:
            vaciar()
        case .cerrar:
            cerrar()
        case let .hacer(f, verEnChat):
            if f.resultado != nil { modelo.recordar(f) }
            if verEnChat, let r = f.resultado {
                saltar(r)
            } else {
                principal(f)
            }
        case let .opcion(op, f):
            opcion(op, f)
        case let .copiar(f):
            copiar(f)
        case let .borrarCaptura(r):
            borrar(r)
        case .deshacer:
            deshacer()
        case let .abrirCon(f):
            guard let ruta = f.resultado?.ruta else { return }
            let apps = AbrirCon.apps(URL(fileURLWithPath: ruta)).prefix(8).map { OpcionBuscar.abrirCon(app: $0) }
            modelo.estado.abrirMenu(apps + [.otraApp])
        case let .abrirMenu(f):
            modelo.estado.abrirMenu(opcionesDeMenu(f))
        }
    }

    // MARK: Lo de ↩

    private func principal(_ f: FilaBuscar) {
        switch f {
        case let .accion(a):
            accion(a)
        case let .resultado(r):
            switch r.clase {
            case .chat:
                guard let chat = r.chat else { return }
                PeticionDeChat.compartida.salto = nil
                PeticionDeChat.compartida.chat = chat
                ir(IdVentana.proyectos)
            case .mensaje:
                saltar(r)
            case .fichero:
                abrirFichero(r)
            case .captura:
                guard let ruta = r.ruta else { return NSSound.beep() }
                if GestorPines.compartido.pinear(fichero: URL(fileURLWithPath: ruta)) {
                    cerrar()
                } else {
                    NSSound.beep()
                }
            case .tarea:
                marcar(r, hecha: !r.hecha)
            case .leccion:
                ir("lecciones")
            case .momento:
                if let id = r.momento {
                    PeticionDeMomento.compartida.pedido = .init(id: id, consulta: r.titulo)
                }
                ir(IdVentana.timeline)
            }
        }
    }

    /// Abre una ventana de la app y cierra el buscador.
    private func ir(_ id: String) {
        abrirVentana(id)
        NSApp.activate()
        cerrar()
    }

    /// El mensaje en su chat: la pagina donde esta, desplazada y marcada.
    private func saltar(_ r: ResultadoBusqueda) {
        guard let chat = r.chat else { return }
        PeticionDeChat.compartida.salto = r.posicion.map {
            SaltoAMensaje(chat: chat, mensaje: r.mensaje, posicion: $0)
        }
        PeticionDeChat.compartida.chat = chat
        ir(IdVentana.proyectos)
    }

    /// Un fichero, como desde su burbuja.
    private func abrirFichero(_ r: ResultadoBusqueda) {
        if r.tipo == "DIBUJO" {
            abrirLienzo(r)
            return
        }
        guard let ruta = r.ruta else {
            // De otro aparato o aun sin llegar: su sitio en el chat.
            return saltar(r)
        }
        let url = URL(fileURLWithPath: ruta)
        let titulo = r.titulo.isEmpty ? nil : r.titulo
        if VentanasDePlano.compartidas.abrirSiEsSuyo(url, titulo: r.titulo) {
            return cerrar()
        }
        if AbrirDocumento.abrir(url, nucleo: nucleo, titulo: titulo) {
            return cerrar()
        }
        if r.tipo == "IMAGEN" || r.tipo == "VIDEO" || r.tipo == "VOZ" {
            return vistaRapida(url)
        }
        NSWorkspace.shared.open(url)
        cerrar()
    }

    /// El mensaje entero (su texto, su referencia), leido del chat.
    private func mensaje(_ r: ResultadoBusqueda) async -> MensajeChat? {
        guard let chat = r.chat, let pos = r.posicion else { return nil }
        let nucleo = self.nucleo
        let pagina = try? await Task.detached(priority: .userInitiated) {
            try nucleo.mensajes(chat: chat, desde: pos, cuantos: 1)
        }.value
        return pagina?.mensajes.first { $0.id == r.mensaje }
    }

    private func abrirLienzo(_ r: ResultadoBusqueda) {
        Task {
            guard let chat = r.chat, let m = await mensaje(r), let ref = m.referencia else { return saltar(r) }
            VentanasDeLienzo.compartidas.abrir(referencia: ref, en: chat, titulo: r.titulo, almacen: almacen)
            cerrar()
        }
    }

    private func marcar(_ r: ResultadoBusqueda, hecha: Bool) {
        guard let chat = r.chat, let msg = r.mensaje, let i = r.tarea else { return }
        let nucleo = self.nucleo
        let crudo = r.crudo
        Task {
            let sigue = try? await Task.detached(priority: .userInitiated) {
                try nucleo.marcarTarea(chat: chat, mensaje: msg, indice: i, crudo: crudo, hecha: hecha)
            }.value
            if sigue == true {
                modelo.avisar(hecha ? "Hecha" : "Pendiente otra vez")
                NotificationCenter.default.post(name: .pixpinCambioLocal, object: nil)
            } else {
                NSSound.beep()
            }
            modelo.refrescar(mantener: true)
        }
    }

    // MARK: Las acciones

    private func accion(_ a: AccionBuscar) {
        switch a {
        case let .apuntarTarea(t):
            guard !t.trimmingCharacters(in: .whitespaces).isEmpty else { return NSSound.beep() }
            let nucleo = self.nucleo
            let desfase = desfaseLocalMs()
            Task {
                do {
                    _ = try await Task.detached(priority: .userInitiated) {
                        try nucleo.apuntarTarea(texto: t, desfaseMs: desfase)
                    }.value
                    NotificationCenter.default.post(name: .pixpinCambioLocal, object: nil)
                    modelo.avisar("Apuntada en el Inbox")
                    vaciar()
                } catch {
                    modelo.avisar("No se pudo apuntar: \(error)")
                }
            }
        case let .nuevaNota(t):
            Task {
                guard let guardados = try? nucleo.chatGuardados(),
                      let m = await almacen.escribir(nota: t.isEmpty ? "# Nota nueva" : t, en: guardados.id) else {
                    return NSSound.beep()
                }
                EditoresDeNotas.compartidos.abrir(m, en: guardados.id, almacen: almacen)
                cerrar()
            }
        case .nuevoLienzo:
            Task {
                guard let guardados = try? nucleo.chatGuardados(),
                      let m = await almacen.crearLienzo(en: guardados.id), let ref = m.referencia else {
                    return NSSound.beep()
                }
                VentanasDeLienzo.compartidas.abrir(referencia: ref, en: guardados.id, titulo: "Lienzo nuevo",
                                                   almacen: almacen)
                cerrar()
            }
        case .capturar:
            guard let capturador = Capturador.principal else { return NSSound.beep() }
            cerrar()
            // Un poco despues, para que el buscador ya no salga en la foto.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { capturador.capturar() }
        case .ultimaCaptura:
            let p = try? nucleo.galeria(desde: 0, cuantos: 1, dias: Int64(AjusteCaducidad.dias),
                                        desfaseMs: desfaseLocalMs())
            guard let c = p?.capturas.first,
                  GestorPines.compartido.pinear(fichero: URL(fileURLWithPath: c.ruta)) else {
                modelo.avisar("Aún no hay capturas")
                return
            }
            cerrar()
        case let .ventana(id, _):
            ir(id)
        }
    }

    // MARK: El menu

    private func opcion(_ op: OpcionBuscar, _ f: FilaBuscar) {
        modelo.estado.menu = nil
        guard let r = f.resultado else { return }
        let url = r.ruta.map { URL(fileURLWithPath: $0) }
        switch op {
        case .verEnChat:
            modelo.recordar(f)
            saltar(r)
        case .abrir:
            modelo.recordar(f)
            abrirFichero(r)
        case .abrirEnEditor:
            Task {
                guard let chat = r.chat, let m = await mensaje(r) else { return NSSound.beep() }
                EditoresDeNotas.compartidos.abrir(m, en: chat, almacen: almacen)
                cerrar()
            }
        case .pinear:
            if let url, GestorPines.compartido.pinear(fichero: url) { cerrar() } else { NSSound.beep() }
        case .copiar:
            copiar(f)
        case .copiarRuta:
            guard let url else { return }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(url.path, forType: .string)
            modelo.avisar("Ruta copiada")
        case .conservar:
            let nucleo = self.nucleo
            let nombre = r.titulo
            Task {
                do {
                    _ = try await Task.detached(priority: .userInitiated) {
                        try nucleo.conservarCaptura(nombre: nombre)
                    }.value
                    modelo.avisar("Conservada: no caduca")
                } catch {
                    modelo.avisar("Ya estaba conservada")
                }
                modelo.refrescar(mantener: true)
            }
        case .borrar:
            borrar(r)
        case .mostrarEnFinder:
            if let url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        case .vistaRapida:
            if let url { vistaRapida(url) }
        case let .abrirCon(app):
            if let url {
                AbrirCon.abrir(url, con: app) { modelo.avisar($0) }
                cerrar()
            }
        case .otraApp:
            if let url { AbrirCon.elegirOtra(url) { modelo.avisar($0) } }
        case let .marcar(hecha):
            marcar(r, hecha: hecha)
        case let .abrirVentana(id, _):
            if r.clase == .momento, let m = r.momento {
                PeticionDeMomento.compartida.pedido = .init(id: m, consulta: r.titulo)
            }
            ir(id)
        }
    }

    // MARK: Copiar y borrar

    /// ⌘C: la imagen de una captura (la pega cualquier programa), el fichero
    /// de un archivo, o el texto.
    private func copiar(_ f: FilaBuscar) {
        guard let r = f.resultado else { return }
        let pb = NSPasteboard.general
        if r.clase == .captura || r.tipo == "IMAGEN", let ruta = r.ruta, let img = NSImage(contentsOfFile: ruta) {
            pb.clearContents()
            pb.writeObjects([img])
            return modelo.avisar("Copiado")
        }
        if r.clase == .fichero, let ruta = r.ruta {
            pb.clearContents()
            pb.writeObjects([URL(fileURLWithPath: ruta) as NSURL])
            pb.setString(ruta, forType: .string)
            return modelo.avisar("Copiado")
        }
        Task {
            var texto = r.titulo
            switch r.clase {
            case .mensaje:
                if let m = await mensaje(r) {
                    texto = m.texto.isEmpty ? (m.transcripcion ?? m.resumen) : m.texto
                }
            case .momento:
                texto = [r.titulo, r.fragmento].filter { !$0.isEmpty }.joined(separator: "\n")
            case .leccion:
                if let id = r.leccion, let l = try? nucleo.leccion(id: id) { texto = l.resumen }
            default:
                break
            }
            pb.clearContents()
            pb.setString(texto, forType: .string)
            modelo.avisar("Copiado")
        }
    }

    /// Supr: la captura a la papelera de PixPin (como el boton de la
    /// galeria), con ⌘Z.
    private func borrar(_ r: ResultadoBusqueda) {
        guard r.clase == .captura else { return }
        let nucleo = self.nucleo
        let nombre = r.titulo
        Task {
            do {
                let b = try await Task.detached(priority: .userInitiated) {
                    try nucleo.borrarCapturas(nombres: [nombre])
                }.value
                modelo.borradas += b
                modelo.estado.seDeshace = true
                modelo.avisar("Captura borrada")
            } catch {
                modelo.avisar("No se pudo borrar: \(error)")
            }
            modelo.refrescar(mantener: true)
        }
    }

    private func deshacer() {
        let b = modelo.borradas
        guard !b.isEmpty else { return }
        modelo.borradas = []
        modelo.estado.seDeshace = false
        modelo.aviso = nil
        let nucleo = self.nucleo
        Task {
            _ = try? await Task.detached(priority: .userInitiated) {
                try nucleo.devolverCapturas(borradas: b)
            }.value
            modelo.refrescar(mantener: true)
        }
    }
}
