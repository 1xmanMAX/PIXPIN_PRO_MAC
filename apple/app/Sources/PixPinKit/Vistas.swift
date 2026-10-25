// La ventana de Proyectos: la lista de chats a la izquierda y el chat a la
// derecha, como en Windows y en el movil.
//
// El chat es una `LazyVStack`: solo existen las filas que se ven, y la
// pagina anterior se pide al llegar arriba (§4bis.2 del plan). Las burbujas
// con fichero (fotos por su miniatura, archivos, dibujos) y lo que entra al
// soltar o pegar estan en `Chat/Adjuntos.swift`; la caja de escribir (la
// isla), en `Chat/CajaEscribir.swift`; su hoja del clip, en
// `Chat/HojaAdjuntar.swift`; la lupa (⌘F), en `Chat/BuscarEnChat.swift`, y
// la escala (⌘+ / ⌘− / ⌘0), en `Chat/EscalaChat.swift`.

import AppKit
import PixPinCore
import SwiftUI

public struct VentanaProyectos: View {
    @ObservedObject var almacen: Almacen
    @State private var elegido: String?
    /// El ancho de la lista (se recuerda) y el que tenia al empezar a estirarla.
    @AppStorage("proyectos.anchoLista") private var anchoLista: Double = 320
    @State private var anchoAlEmpezar: Double?
    /// La ventana, para los botones de la franja.
    @State private var ventana = RefVentana()
    /// El proyecto que se va a borrar, mientras se pregunta.
    @State private var aBorrar: FichaChat?
    /// Un chat que pide abrir Buscar (ver `Buscar/Buscar.swift`).
    @ObservedObject private var peticion = PeticionDeChat.compartida
    @Environment(\.openWindow) private var abrirVentana

    /// La ventana no cabe lista y chat: se ve como el movil.
    @State private var estrecho = false

    public init(almacen: Almacen) { self.almacen = almacen }

    public var body: some View {
        // Como en Windows: la franja fina arriba, la lista a la izquierda
        // (se estira por su borde) y el chat sobre su papel a la derecha.
        VStack(spacing: 0) {
            FranjaProyectos(ventana: ventana)
            HStack(spacing: 0) {
                // Estrecha, como el movil: o la lista o el chat (con ← para volver).
                if !estrecho || elegido == nil {
                ListaProyectos(almacen: almacen, elegido: $elegido) { chat in
                    // Todo el proyecto en la hoja de compartir comun (D1):
                    // sus hojas en PDF, web..., sus originales y el .pixpin.
                    Button("Compartir…") { HojaCompartir.abrir(.proyectos([chat]), almacen: almacen) }
                    // La musica y las notas de voz de todos, como en Windows (D3).
                    if chat.esGuardados {
                        Button("Biblioteca de audio") { BibliotecaAudio.abrir(almacen: almacen) }
                    }
                    if !chat.esGuardados {
                        Button("Borrar", role: .destructive) { aBorrar = chat }
                    }
                }
                // Como `confirmar_destructivo` de Windows: el borrado viaja.
                .confirmationDialog(aBorrar.map { "¿Borrar «\($0.nombre)»?" } ?? "",
                                    isPresented: Binding(get: { aBorrar != nil },
                                                         set: { if !$0 { aBorrar = nil } }),
                                    titleVisibility: .visible, presenting: aBorrar) { chat in
                    Button("Borrar", role: .destructive) {
                        if elegido == chat.id { elegido = nil }
                        Task { await almacen.borrarProyecto(chat.id) }
                    }
                } message: { _ in
                    Text("Se borra también en tus otros aparatos la próxima vez que sincronices. "
                        + "Queda una copia en la papelera de PixPin por si te arrepientes.")
                }
                .frame(width: estrecho ? nil : anchoLista)
                .frame(maxWidth: estrecho ? .infinity : nil)
                }
                if !estrecho {
                Paleta.proyectos.separador
                    .frame(width: 1)
                    .overlay { asaLista }
                }
                if !estrecho || elegido != nil {
                ZStack(alignment: .topLeading) {
                    PapelChat()
                    if let chat = elegido {
                        VistaChat(almacen: almacen, chat: chat).id(chat)
                    } else {
                        Text("Elige un proyecto")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(.black.opacity(0.25), in: Capsule())
                    }
                    if estrecho {
                        Button { elegido = nil } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 30, height: 30)
                                .background(.regularMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Volver a los proyectos")
                        .padding(8)
                    }
                }
                .frame(minWidth: estrecho ? 0 : 380, maxWidth: .infinity)
                }
            }
            .onGeometryChange(for: Bool.self) { $0.size.width < anchoLista + 380 } action: { estrecho = $0 }
        }
        .ignoresSafeArea(.container, edges: .top)
        .toolbar(removing: .title)
        .toolbar(.hidden, for: .windowToolbar)
        .background(AccesoVentana { v in
            ventana.ventana = v
            VentanaLisa.vestirEntera(v)
        })
        .task {
            await almacen.cargarChats()
            // El chat «Asistente», fijo detras de «Mensajes guardados» (E1).
            await almacen.asegurarAsistente()
            // Lo que el asistente dejo a medias al cerrarse PixPin (una vez).
            Task { await AsistenteEnElChat.compartido.retomarAlArrancar(almacen) }
        }
        .onChange(of: elegido) { _, visible in almacen.aligerar(visible: visible) }
        .onDisappear { almacen.nadaAlFrente() }
        .onReceive(peticion.$chat) { pedido in
            guard let pedido else { return }
            elegido = pedido
            peticion.chat = nil
        }
        .overlay(alignment: .bottom) {
            if let error = almacen.error {
                Text(error).font(.caption).padding(6)
                    .background(.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                    .padding()
            }
        }
    }

    /// El borde de la lista: se arrastra para estirarla (260 a 540, como
    /// `LISTA_MINIMA` y `LISTA_MAXIMA` de Windows).
    private var asaLista: some View {
        Color.clear
            .frame(width: 7)
            .contentShape(Rectangle())
            .onHover { dentro in
                if dentro { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(DragGesture(coordinateSpace: .global)
                .onChanged { g in
                    if anchoAlEmpezar == nil { anchoAlEmpezar = anchoLista }
                    anchoLista = min(max((anchoAlEmpezar ?? anchoLista) + g.translation.width, 260), 540)
                }
                .onEnded { _ in anchoAlEmpezar = nil })
    }
}

public struct VistaChat: View {
    @ObservedObject var almacen: Almacen
    let chat: String
    @State private var borrador = ""
    /// Algo arrastrado encima del chat (para marcarlo).
    @State private var soltando = false
    /// El vigia de ⌘V mientras el chat esta en pantalla.
    @State private var vigiaPegar: Any?
    /// El de las teclas del chat (⌘F, ⌘+ / ⌘− / ⌘0, ⌘G, Esc de la lupa).
    @State private var vigiaTeclas: Any?
    /// La ventana del chat: las teclas solo cuentan en ella.
    @State private var ventana = RefVentana()
    /// Un salto a un mensaje que pide Buscar (`Chat/SaltoAMensaje.swift`).
    @ObservedObject private var peticion = PeticionDeChat.compartida
    /// El mensaje marcado tras un salto, y al que desplazarse.
    @State private var destacado: String?
    @State private var irA: String?
    /// Sube al llegar la pagina del salto: entonces se desplaza.
    @State private var saltos = 0
    /// Se esta viendo una pagina del medio: no se baja solo al final.
    @State private var enSalto = false
    /// Lo que toca el menu de los mensajes: a quien se responde, lo
    /// elegido, la hoja de escribir y el aviso (`Chat/MenuMensaje.swift`).
    @StateObject private var menu: ChatAbierto
    /// La lupa del chat (`Chat/BuscarEnChat.swift`).
    @StateObject private var buscador: BuscadorDelChat
    /// La escala del chat, en por ciento (`Chat/EscalaChat.swift`).
    @AppStorage(EscalaChat.clave) private var escala = EscalaChat.porDefecto
    /// Sube para devolver el foco a la caja de escribir.
    @State private var focoCaja = 0
    @Environment(\.openWindow) private var abrirVentana

    public init(almacen: Almacen, chat: String) {
        self.almacen = almacen
        self.chat = chat
        _menu = StateObject(wrappedValue: ChatAbierto(chat: chat, almacen: almacen))
        _buscador = StateObject(wrappedValue: BuscadorDelChat(chat: chat, nucleo: almacen.nucleo))
    }

    private var eleccion: Eleccion { menu.eleccion }

    /// La escala como factor.
    private var f: CGFloat { CGFloat(EscalaChat.valida(escala)) / 100 }

    /// El ultimo fijado de lo cargado («Mensaje fijado», arriba).
    private var fijado: MensajeChat? { (almacen.mensajes[chat] ?? []).last(where: \.fijado) }

    /// Aquel al que se responde, si sigue cargado.
    private var respondido: MensajeChat? {
        guard let id = menu.respondiendo else { return nil }
        return (almacen.mensajes[chat] ?? []).first { $0.id == id }
    }

    /// Lo que se ve: la conversacion cargada o, buscando, lo que casa.
    private var filas: [MensajeChat] {
        buscador.filtrando ? buscador.hallados.map(\.mensaje) : (almacen.mensajes[chat] ?? [])
    }

    /// El resultado elegido con ↑ ↓, buscando.
    private var elegidoEnBusqueda: String? {
        guard buscador.filtrando, let i = buscador.elegido else { return nil }
        return buscador.hallados[safe: i]?.id
    }

    public var body: some View {
        VStack(spacing: 0) {
            if almacen.chats.first(where: { $0.id == chat })?.esAsistente == true {
                CabeceraDelAsistente(almacen: almacen, chat: chat)
                Divider()
            }
            if buscador.abierto {
                BarraBuscarEnChat(buscador: buscador, verEnContexto: verEnContexto)
                Divider()
            }
            if let fijado, !buscador.filtrando {
                BarraDeFijado(fijado: fijado) { ir(a: fijado.id) }
                Divider()
            }
            ScrollViewReader { lector in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6 * f) {
                        if !buscador.filtrando, almacen.quedanAnteriores(chat: chat) {
                            ProgressView().frame(maxWidth: .infinity)
                                .task { await almacen.cargarAnteriores(chat: chat) }
                        }
                        ForEach(filas, id: \.id) { m in fila(m) }
                        if !buscador.filtrando, almacen.quedanPosteriores(chat: chat) {
                            ProgressView().frame(maxWidth: .infinity)
                                .task { await almacen.cargarPosteriores(chat: chat) }
                        }
                    }
                    .padding()
                }
                .defaultScrollAnchor(.bottom)
                .overlay {
                    if buscador.filtrando, !buscador.cargando, buscador.hallados.isEmpty {
                        Text("Nada con eso")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(.black.opacity(0.25), in: Capsule())
                    }
                }
                .onChange(of: almacen.mensajes[chat]?.last?.id) { _, ultimo in
                    if let ultimo, !enSalto, !buscador.filtrando { lector.scrollTo(ultimo, anchor: .bottom) }
                }
                .onChange(of: saltos) { _, _ in
                    guard let id = irA else { return }
                    // Una vuelta despues: que la pila perezosa ya tenga la fila.
                    DispatchQueue.main.async { lector.scrollTo(id, anchor: .center) }
                }
                // Buscando, ↑ ↓ llevan al resultado elegido.
                .onChange(of: elegidoEnBusqueda) { _, id in
                    guard let id else { return }
                    DispatchQueue.main.async { lector.scrollTo(id, anchor: .center) }
                }
            }
            .environment(\.font, .system(size: 13 * f))
            .environment(\.escalaChat, f)
            .environment(\.agujaDelChat, buscador.filtrando ? buscador.texto : "")
            if !eleccion.vacia {
                Divider()
                BarraDeElegidos(cuantos: eleccion.ids.count,
                                copiar: { menu.copiar(menu.elegidos()) },
                                compartir: { menu.compartir(menu.elegidos()) },
                                fijar: { menu.fijar(menu.elegidos()) },
                                reenviar: { menu.reenviar(menu.elegidos()) },
                                unirPdf: menu.sePuedenUnir(menu.elegidos()) ? { menu.unirPdf(menu.elegidos()) } : nil,
                                borrar: { borrar(menu.elegidos()) },
                                cancelar: { menu.eleccion.vaciar() })
            } else if let resultados = buscador.resultados {
                // Buscando, el recuento manda sobre la respuesta, que sigue
                // colgada y vuelve al cerrar la lupa (Windows).
                BarraDeResultados(rotulo: resultados, verEnContexto: verEnContexto)
            } else if let respondido {
                // Esc suelta antes lo elegido y luego la respuesta (Windows).
                Divider()
                BarraDeRespuesta(citado: respondido) { menu.respondiendo = nil }
            }
            // Lo que suena, encima de la caja de escribir (D3).
            BarraReproductor().padding(.horizontal, 10).padding(.top, 4)
            // El asistente: «Parar», su aviso y la lista de `@` (E1).
            BarraDelAsistente(chat: chat, borrador: $borrador, almacen: almacen)
                .environment(\.escalaChat, f)
            IslaDeEscribir(borrador: $borrador, chat: chat, almacen: almacen, foco: focoCaja,
                           enviar: enviar, escaparVacio: escaparVacio, adjuntar: adjuntar)
                .environment(\.escalaChat, f)
        }
        .task {
            // Si se vino por un salto, la carga es la suya.
            if atenderSalto() || enSalto { return }
            await almacen.abrir(chat: chat)
        }
        .onReceive(peticion.$salto) { _ in _ = atenderSalto() }
        // Lo elegido que ya no esta cargado (borrado, otra pagina) se olvida.
        .onChange(of: almacen.mensajes[chat]?.count) { _, _ in
            menu.eleccion.quedarse(con: Set(idsCargados))
        }
        // Describir, cambiar el nombre o la hora de avisar: una linea.
        .sheet(item: $menu.escritura) { e in
            HojaEscritura(escritura: e) { menu.guardar(e, $0) }
        }
        .overlay(alignment: .bottom) {
            if let aviso = menu.aviso { AvisoDelChat(texto: aviso).padding(.bottom, 64 * f) }
        }
        .animation(.easeOut(duration: 0.15), value: menu.aviso)
        // Soltar ficheros o fotos en el chat los adjunta (se copian).
        .onDrop(of: EntradaDeFicheros.tipos, isTargeted: $soltando) { proveedores in
            MainActor.assumeIsolated {
                EntradaDeFicheros.soltar(proveedores, en: chat, almacen: almacen)
            }
            return true
        }
        .overlay {
            if soltando {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8, 5]))
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
        .background(AccesoVentana { ventana.ventana = $0 })
        .onAppear {
            vigilarPegar()
            vigilarTeclas()
            menu.irA = { id in ir(a: id) }
        }
        .onDisappear {
            dejarDeVigilarPegar()
            if let v = vigiaTeclas { NSEvent.removeMonitor(v) }
            vigiaTeclas = nil
        }
    }

    /// Una burbuja con lo suyo: la marca del salto o del resultado elegido,
    /// lo elegido, el clic y el menu.
    private func fila(_ m: MensajeChat) -> some View {
        Burbuja(mensaje: m, chat: chat, almacen: almacen,
                citado: citado(por: m), irACita: { ir(a: m.respondeA ?? "") })
            .overlay {
                if m.id == destacado || m.id == elegidoEnBusqueda {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
            .overlay(alignment: .topTrailing) {
                if eleccion.ids.contains(m.id) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white, Color.accentColor)
                        .padding(4)
                }
            }
            .background {
                if eleccion.ids.contains(m.id) {
                    RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.18))
                }
            }
            .simultaneousGesture(TapGesture().onEnded { clic(en: m.id) })
            .environment(\.accionesDeMensaje, AccionesDeMensaje(
                mensaje: m,
                marcado: eleccion.ids.contains(m.id),
                marcar: { menu.eleccion.alternar(m.id) },
                borrar: { borrar(menu.sobre(m)) },
                chat: menu))
            .id(m.id)
    }

    /// Aquel al que responde `m`, si esta cargado.
    private func citado(por m: MensajeChat) -> MensajeChat? {
        guard let id = m.respondeA, !id.isEmpty else { return nil }
        return (almacen.mensajes[chat] ?? []).first { $0.id == id }
    }

    /// Lleva a un mensaje cargado y lo marca (la cita, el fijado, el hilo).
    private func ir(a id: String) {
        guard !id.isEmpty, idsCargados.contains(id) else { return }
        destacado = id
        irA = id
        saltos += 1
    }

    /// «Ver en contexto»: apaga la lupa y salta al resultado elegido en su
    /// sitio (cargando su pagina, como un salto desde Buscar).
    private func verEnContexto() {
        guard let salto = buscador.enContexto() else { return }
        if idsCargados.contains(salto.mensaje ?? "") {
            ir(a: salto.mensaje ?? "")
        } else {
            peticion.salto = salto
        }
        focoCaja += 1
    }

    /// ⌘V con ficheros o una imagen en el portapapeles los adjunta, aunque
    /// la caja de escribir tenga el foco (ella solo sabe pegar texto). Con
    /// texto, el ⌘V sigue su camino de siempre.
    private func vigilarPegar() {
        guard vigiaPegar == nil else { return }
        let chat = self.chat
        let almacen = self.almacen
        vigiaPegar = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { evento in
            let teclas = evento.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard teclas == .command, evento.charactersIgnoringModifiers == "v",
                  evento.window != nil, !(evento.window is NSPanel) else { return evento }
            let tomado = MainActor.assumeIsolated {
                EntradaDeFicheros.pegar(en: chat, almacen: almacen)
            }
            return tomado ? nil : evento
        }
    }

    private func dejarDeVigilarPegar() {
        if let vigia = vigiaPegar { NSEvent.removeMonitor(vigia) }
        vigiaPegar = nil
    }

    /// Las teclas del chat, antes que los atajos de la ventana (el ⌘F de la
    /// lista es «Buscar en todo»; con un chat abierto, como en Windows, es
    /// la lupa de la conversacion). Solo en la ventana del chat y sin una
    /// hoja delante.
    private func vigilarTeclas() {
        guard vigiaTeclas == nil else { return }
        let ventana = self.ventana
        let buscador = self.buscador
        let menu = self.menu
        let escala = $escala
        vigiaTeclas = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { evento in
            guard let v = ventana.ventana, evento.window === v, v.attachedSheet == nil else { return evento }
            let teclas = evento.modifierFlags.intersection([.command, .shift, .option, .control])
            let letra = evento.charactersIgnoringModifiers ?? ""
            let esc = evento.keyCode == 53
            let tomada = MainActor.assumeIsolated { () -> Bool in
                // Esc apaga la lupa antes que nada mas.
                if esc, teclas.isEmpty, buscador.abierto {
                    buscador.cerrar()
                    return true
                }
                guard teclas.contains(.command), !teclas.contains(.control), !teclas.contains(.option)
                else { return false }
                if letra.lowercased() == "f", !teclas.contains(.shift) {
                    buscador.abrir()
                    return true
                }
                if letra.lowercased() == "g", buscador.filtrando {
                    buscador.mover(teclas.contains(.shift) ? -1 : 1)
                    return true
                }
                if let pedida = EscalaChat.pedida(tecla: letra, actual: escala.wrappedValue) {
                    escala.wrappedValue = pedida
                    menu.avisar(EscalaChat.aviso(pedida))
                    return true
                }
                return false
            }
            return tomada ? nil : evento
        }
    }

    /// Esc con la caja vacia: suelta lo elegido y, si no, la respuesta.
    private func escaparVacio() -> Bool {
        if !eleccion.vacia {
            menu.eleccion.vaciar()
            return true
        }
        if menu.respondiendo != nil {
            menu.respondiendo = nil
            return true
        }
        return false
    }

    /// Toma el salto pedido si es de este chat: carga su pagina, marca el
    /// mensaje y se desplaza hasta el.
    private func atenderSalto() -> Bool {
        guard let s = peticion.salto, s.chat == chat else { return false }
        peticion.salto = nil
        enSalto = true
        destacado = s.mensaje
        irA = s.mensaje
        let almacen = self.almacen
        Task {
            await almacen.abrir(chat: s.chat, en: s.posicion)
            saltos += 1
        }
        return true
    }

    private var idsCargados: [String] { (almacen.mensajes[chat] ?? []).map(\.id) }

    /// Un clic en una burbuja: ⌘ la elige o la suelta, ⇧ elige el tramo y,
    /// con alguna elegida, un clic sin teclas tambien la alterna (Windows).
    private func clic(en id: String) {
        let teclas = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if teclas.contains(.command) {
            menu.eleccion.alternar(id)
        } else if teclas.contains(.shift), !eleccion.vacia {
            menu.eleccion.tramo(hasta: id, en: idsCargados)
        } else if !eleccion.vacia {
            menu.eleccion.alternar(id)
        }
    }

    /// Pregunta y borra (`Almacen.borrar`). Si se dice que no, lo elegido
    /// sigue elegido.
    private func borrar(_ ids: [String]) {
        guard !ids.isEmpty, ConfirmarBorrar.preguntar(cuantos: ids.count) else { return }
        if let d = destacado, ids.contains(d) { destacado = nil }
        if let r = menu.respondiendo, ids.contains(r) { menu.respondiendo = nil }
        let almacen = self.almacen
        let chat = self.chat
        let menu = self.menu
        Task {
            await almacen.borrar(mensajes: ids, en: chat)
            menu.eleccion.quedarse(con: Set((almacen.mensajes[chat] ?? []).map(\.id)))
        }
    }

    /// Una entrada de la hoja del clip (`Chat/HojaAdjuntar.swift`).
    private func adjuntar(_ accion: AccionAdjuntar) {
        enSalto = false
        let abrir = abrirVentana
        AdjuntarEnChat.hacer(accion, chat: chat, almacen: almacen,
                             avisar: { [menu] in menu.avisar($0) },
                             abrirVentana: { abrir(id: $0) })
    }

    private func enviar() {
        let texto = borrador
        guard !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        enSalto = false
        destacado = nil
        borrador = ""
        // Contestando a un mensaje (Responder, R): la nota lleva `respondeA`.
        let respondeA = menu.respondiendo
        menu.respondiendo = nil
        let almacen = self.almacen
        let chat = self.chat
        Task {
            // Si era para el asistente (su chat, o `@asistente`), contesta.
            if let m = await almacen.escribir(nota: texto, en: chat, respondeA: respondeA) {
                AsistenteEnElChat.compartido.alEnviar([m], chat: chat, almacen: almacen)
            }
        }
    }
}

struct Burbuja: View {
    let mensaje: MensajeChat
    let chat: String
    /// Sin observar: una burbuja no se repinta por cada cambio del almacen.
    let almacen: Almacen
    /// Aquel al que responde (si lo hace y esta cargado) y como ir a el.
    var citado: MensajeChat?
    var irACita: () -> Void = {}
    /// Lo buscado en el chat, para resaltarlo en las notas.
    @Environment(\.agujaDelChat) private var aguja
    @Environment(\.escalaChat) private var escala

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let r = mensaje.respondeA, !r.isEmpty {
                CitaDeMensaje(citado: citado, irA: irACita)
            }
            switch mensaje.clase {
            case "NOTA" where mensaje.esDelAsistente:
                NotaDelAsistente(mensaje: mensaje, chat: chat, almacen: almacen)
            case "NOTA" where BurbujaHojaNota.esHoja(mensaje):
                BurbujaHojaNota(mensaje: mensaje, chat: chat, almacen: almacen)
            case "NOTA":
                Text(textoResaltado(mensaje.texto, aguja: aguja)).textSelection(.enabled)
                    .modifier(AccionesDeNota(mensaje: mensaje, chat: chat, almacen: almacen))
            // «TABLA» siempre es tabla; una «MINIAPP» solo si lo que trae lo es.
            case "TABLA":
                BurbujaTabla(mensaje: mensaje, chat: chat, almacen: almacen)
            case "MINIAPP" where BurbujaTareas.esTareas(mensaje):
                BurbujaTareas(mensaje: mensaje)
            case "MINIAPP" where BurbujaTabla.esTabla(mensaje):
                BurbujaTabla(mensaje: mensaje, chat: chat, almacen: almacen)
            case "IMAGEN" where mensaje.ruta != nil:
                BurbujaImagen(mensaje: mensaje, chat: chat, almacen: almacen)
            case "VOZ" where mensaje.ruta != nil:
                BurbujaVoz(mensaje: mensaje, chat: chat, almacen: almacen)
            case "ARCHIVO" where mensaje.ruta != nil:
                BurbujaArchivo(mensaje: mensaje, chat: chat, almacen: almacen)
            case "DIBUJO" where mensaje.referencia != nil:
                BurbujaDibujo(mensaje: mensaje, chat: chat, almacen: almacen)
            // Lo que llega de Windows y del movil (B9, `Chat/BurbujasQueLlegan.swift`).
            case "PAGINA":
                BurbujaPagina(mensaje: mensaje, chat: chat, almacen: almacen)
            case "PROYECTO":
                BurbujaProyecto(mensaje: mensaje, almacen: almacen)
            case "CROQUIS":
                BurbujaCroquis(mensaje: mensaje, chat: chat, almacen: almacen)
            default:
                Label(mensaje.resumen.isEmpty ? mensaje.nombre : mensaje.resumen,
                      systemImage: Burbuja.icono(mensaje.clase))
            }
            // De donde viene, el lienzo del asistente y de quien llego.
            PieDelMovil(mensaje: mensaje, chat: chat, almacen: almacen)
            HStack(spacing: 6) {
                Text(Date(timeIntervalSince1970: TimeInterval(mensaje.cuando) / 1000),
                     format: .dateTime.hour().minute())
                    .font(.system(size: 10 * escala)).foregroundStyle(.secondary)
                MarcasDeMensaje(mensaje: mensaje)
                if let punto = mensaje.punto { PuntoDeProyecto(verde: punto) }
            }
        }
        .padding(8 * escala)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 10 * escala))
        // Las burbujas con menu propio (fichero, nota, voz) llevan estas
        // entradas en el suyo, que tapa a este.
        .contextMenu { EntradasDeMensaje() }
    }

    static func icono(_ clase: String) -> String {
        switch clase {
        case "IMAGEN": "photo"
        case "VOZ": "waveform"
        case "DIBUJO": "scribble.variable"
        case "PAGINA": "doc.richtext"
        case "MINIAPP": "checklist"
        case "PROYECTO": "folder"
        case "CROQUIS": "cube.transparent"
        default: "doc"
        }
    }
}

/// Un lienzo en una `NSView` volteada (Y hacia abajo, como el mundo del
/// lienzo). Ajusta lo dibujado a la vista; pintar es recorrer las figuras
/// ya hechas, sin crear trazados por fotograma.
public final class VistaLienzoNS: NSView {
    public var lienzo: LienzoLeido? { didSet { needsDisplay = true } }
    public var imagen: (UInt64) -> CGImage? = { _ in nil }
    /// El doble clic (abrir el dibujo para editarlo). Lo atiende la vista:
    /// un gesto de SwiftUI no siempre llega a traves de una `NSView`.
    public var alDobleClic: (() -> Void)?
    /// Una foto en el chat: llena la vista entera, sin margen (bien cuadrada,
    /// como una imagen normal).
    public var aSangre = false { didSet { needsDisplay = true } }

    override public var isFlipped: Bool { true }

    override public func mouseDown(with event: NSEvent) {
        if event.clickCount == 2, let alDobleClic {
            alDobleClic()
        } else {
            super.mouseDown(with: event)
        }
    }

    override public func draw(_ dirtyRect: NSRect) {
        guard let lienzo, let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setFillColor(lienzo.fondo.cg)
        ctx.fill(bounds)
        let caja = lienzo.caja ?? bounds
        let margen: CGFloat = aSangre ? 0 : 16
        let escala = aSangre
            ? max(bounds.width / max(caja.width, 1), bounds.height / max(caja.height, 1))
            : min((bounds.width - margen * 2) / max(caja.width, 1),
                  (bounds.height - margen * 2) / max(caja.height, 1), 4)
        ctx.saveGState()
        ctx.translateBy(x: margen - caja.minX * escala, y: margen - caja.minY * escala)
        ctx.scaleBy(x: escala, y: escala)
        let visible = CGRect(x: caja.minX - margen / escala, y: caja.minY - margen / escala,
                             width: bounds.width / escala, height: bounds.height / escala)
        PintorLienzo(lienzo: lienzo, imagen: imagen).pintar(en: ctx, limites: visible)
        ctx.restoreGState()
    }
}

public struct VistaLienzo: NSViewRepresentable {
    public let lienzo: LienzoLeido
    /// Cambiarla vuelve a pintar (p. ej. al llegar las fotos del lienzo).
    public var version: Int
    /// La foto de cada `id_objeto`, ya decodificada (una cache: nunca lee
    /// del disco al pintar).
    public var imagen: (UInt64) -> CGImage?

    public init(lienzo: LienzoLeido, version: Int = 0,
                imagen: @escaping (UInt64) -> CGImage? = { _ in nil }) {
        self.lienzo = lienzo
        self.version = version
        self.imagen = imagen
    }

    /// Lo que hace el doble clic (ver `VistaLienzoNS.alDobleClic`).
    var dobleClic: (() -> Void)?
    /// Sin margen, llenando la vista (ver `VistaLienzoNS.aSangre`).
    var aSangre = false

    public func sinMargen() -> VistaLienzo {
        var copia = self
        copia.aSangre = true
        return copia
    }

    /// Con doble clic.
    public func alDobleClic(_ hacer: @escaping () -> Void) -> VistaLienzo {
        var copia = self
        copia.dobleClic = hacer
        return copia
    }

    public func makeNSView(context: Context) -> VistaLienzoNS {
        let v = VistaLienzoNS()
        v.aSangre = aSangre
        v.imagen = imagen
        v.alDobleClic = dobleClic
        v.lienzo = lienzo
        return v
    }

    public func updateNSView(_ v: VistaLienzoNS, context: Context) {
        v.aSangre = aSangre
        v.imagen = imagen
        v.alDobleClic = dobleClic
        v.lienzo = lienzo
    }
}
