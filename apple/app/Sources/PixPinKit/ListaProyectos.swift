// **Las piezas de la ventana de Proyectos que se ven como en Windows**
// (`ventana_chat.rs`, el chat de estilo Telegram, 15-oct-2026):
//
// - `FranjaProyectos`: la franja fina de arriba (24) del color de la barra,
//   con «PixPin Max» a la izquierda y −, ☐ y ✕ planos a la derecha.
// - `ListaProyectos`: la columna de la izquierda, con el buscador en
//   capsula (35 de alto, 7 de margen), los dos botones redondos dorados, las
//   filas de 62 con el avatar de 46 y sus iniciales, y el boton redondo de
//   proyecto nuevo (54) abajo a la derecha.
//
// Los colores siguen el tema del sistema, como en Windows (`Paleta.proyectos`).

import AppKit
import PixPinCore
import SwiftUI

/// La franja de arriba: el nombre de la app y los botones de la ventana.
struct FranjaProyectos: View {
    static let alto: CGFloat = 24
    let ventana: RefVentana
    /// «Figuras» del interruptor: abre su ventana.
    var figuras: () -> Void = {}

    var body: some View {
        HStack(spacing: 0) {
            Text("PixPin Max")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Paleta.proyectos.texto)
                .padding(.leading, 12)
            Spacer()
            BotonFranja(simbolo: "minus", ayuda: "Minimizar (⌘M)") { ventana.ventana?.miniaturize(nil) }
            BotonFranja(simbolo: "square", ayuda: "Maximizar") { ventana.ventana?.zoom(nil) }
            BotonFranja(simbolo: "xmark", ayuda: "Cerrar (⌘W)", cerrar: true) { VentanaLisa.cerrar(ventana.ventana) }
        }
        .frame(height: Self.alto)
        // El interruptor Chat · Figuras, en medio (Windows c687285: la parte
        // «Proyectos» de en medio se quito).
        .overlay { InterruptorChatFiguras(figuras: figuras) }
        .background {
            // Desde la franja se lleva la ventana, y el doble clic la agranda.
            Paleta.proyectos.barra
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
                .simultaneousGesture(TapGesture(count: 2).onEnded { ventana.ventana?.zoom(nil) })
        }
    }
}

/// **El interruptor Chat · Figuras** de la barra (`ventana_chat/interruptor.rs`
/// y `pixpin_ui::interruptor` de Windows): dos partes de 76, con 3 de aire
/// arriba y abajo. «Figuras» no se queda elegida: abre su ventana aparte y
/// el chat sigue como estaba.
struct InterruptorChatFiguras: View {
    let figuras: () -> Void
    @State private var encima = false

    var body: some View {
        HStack(spacing: 0) {
            Text("Chat")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white)
                .frame(width: 76, height: FranjaProyectos.alto - 6)
                .background(Paleta.proyectos.filaElegida, in: Capsule())
            Button(action: figuras) {
                Text("Figuras")
                    .font(.system(size: 11))
                    .foregroundStyle(Paleta.proyectos.texto)
                    .frame(width: 76, height: FranjaProyectos.alto - 6)
                    .background(encima ? Paleta.proyectos.botonEncima : .clear, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { encima = $0 }
            .help("Figuras")
        }
        .background(Paleta.proyectos.lista.opacity(0.5), in: Capsule())
    }
}

/// Un boton de la franja: rectangulo plano del alto de la franja; con el
/// raton encima, gris (la ✕, roja con la cruz blanca), como en Windows.
struct BotonFranja: View {
    let simbolo: String
    let ayuda: String
    var cerrar = false
    let accion: () -> Void
    @State private var encima = false

    var body: some View {
        Button(action: accion) {
            Label(ayuda, systemImage: simbolo)
                .labelStyle(.iconOnly)
                .font(.system(size: simbolo == "square" ? 10 : 11, weight: .light))
                .foregroundStyle(encima && cerrar ? Color.white : Paleta.proyectos.texto)
                .frame(width: 44, height: FranjaProyectos.alto)
                .background(encima ? (cerrar ? Paleta.proyectos.cerrarEncima : Paleta.proyectos.botonEncima) : .clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { encima = $0 }
        .help(ayuda)
    }
}

/// La columna de los proyectos.
struct ListaProyectos<Menu: View>: View {
    @ObservedObject var almacen: Almacen
    @Binding var elegido: String?
    /// El menu de clic derecho de cada fila (lo pone la ventana).
    @ViewBuilder let menu: (FichaChat) -> Menu
    @Environment(\.openWindow) private var abrirVentana
    @State private var filtro = ""
    @State private var creando = false
    @State private var nuevo = ""
    @FocusState private var enLista: Bool

    private var visibles: [FichaChat] {
        let f = filtro.trimmingCharacters(in: .whitespaces)
        guard !f.isEmpty else { return almacen.chats }
        return almacen.chats.filter { $0.nombre.localizedStandardContains(f) || $0.resumen.localizedStandardContains(f) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                // Como la cabecera de Windows: galeria, timeline y tareas a mano.
                BotonRedondo(simbolo: "photo.on.rectangle", ayuda: "Galería") {
                    abrirVentana(id: IdVentana.galeria)
                }
                BotonRedondo(simbolo: "clock.arrow.circlepath", ayuda: "Timeline") {
                    abrirVentana(id: IdVentana.timeline)
                }
                BotonRedondo(simbolo: "checklist", ayuda: "Tareas") {
                    abrirVentana(id: IdVentana.tareas)
                }
                BotonRedondo(simbolo: "arrow.triangle.2.circlepath", ayuda: "Sincronizar") {
                    abrirVentana(id: "sincronizar")
                }
            }
            .padding(.horizontal, 7)
            .padding(.top, 7)
            CapsulaBuscar(texto: $filtro)
                .padding(.horizontal, 7)
                .padding(.vertical, 6)
            Paleta.proyectos.separador.frame(height: 1)
            ScrollViewReader { lector in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visibles, id: \.id) { chat in
                            FilaProyecto(chat: chat, elegida: chat.id == elegido)
                                .id(chat.id)
                                .onTapGesture {
                                    elegido = chat.id
                                    enLista = true
                                }
                                .contextMenu { menu(chat) }
                        }
                    }
                }
                .focusable()
                .focusEffectDisabled()
                .focused($enLista)
                // ↑ y ↓ pasan de proyecto, como en la lista del sistema.
                .onKeyPress(.upArrow) { mover(-1, lector) }
                .onKeyPress(.downArrow) { mover(1, lector) }
            }
        }
        .background(Paleta.proyectos.lista, ignoresSafeAreaEdges: [])
        .overlay(alignment: .bottomTrailing) {
            BotonNuevo { creando = true }
                .padding(16)
                .popover(isPresented: $creando, arrowEdge: .top) {
                    HStack {
                        TextField("Proyecto nuevo", text: $nuevo)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                            .onSubmit(crear)
                        Button("Crear", action: crear)
                            .keyboardShortcut(.defaultAction)
                            .disabled(nuevo.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(12)
                }
        }
    }

    private func mover(_ paso: Int, _ lector: ScrollViewProxy) -> KeyPress.Result {
        let lista = visibles
        guard !lista.isEmpty else { return .ignored }
        let i = lista.firstIndex { $0.id == elegido } ?? (paso > 0 ? -1 : lista.count)
        let j = min(max(i + paso, 0), lista.count - 1)
        elegido = lista[j].id
        lector.scrollTo(lista[j].id)
        return .handled
    }

    private func crear() {
        let nombre = nuevo.trimmingCharacters(in: .whitespaces)
        guard !nombre.isEmpty else { return }
        nuevo = ""
        creando = false
        Task { await almacen.crearChat(nombre: nombre) }
    }
}

/// El buscador de la lista: una capsula del color del buscador de Windows.
struct CapsulaBuscar: View {
    @Binding var texto: String

    var body: some View {
        HStack(spacing: 4) {
            TextField("", text: $texto, prompt: Text("Buscar").foregroundStyle(Paleta.proyectos.apagado))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Paleta.proyectos.texto)
            if !texto.isEmpty {
                Button { texto = "" } label: {
                    Label("Vaciar", systemImage: "xmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(Paleta.proyectos.apagado)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 35)
        .background(Paleta.proyectos.buscador, in: Capsule())
    }
}

/// Los botones redondos de junto al buscador: el disco dorado del movil
/// (`circulo` y `circulo_icono` de Windows).
struct BotonRedondo: View {
    let simbolo: String
    let ayuda: String
    let accion: () -> Void
    @State private var encima = false

    var body: some View {
        Button(action: accion) {
            Simbolo(nombre: simbolo, lado: 18)
                .accessibilityLabel(ayuda)
                .foregroundStyle(Color(claro: 0x3E2D00, oscuro: 0xFEE8B7))
                .frame(width: 35, height: 35)
                .background(Color(claro: 0xFFDEA6, oscuro: 0x493A11), in: Circle())
                .brightness(encima ? 0.06 : 0)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { encima = $0 }
        .help(ayuda)
    }
}

/// El boton redondo de proyecto nuevo, abajo a la derecha de la lista.
struct BotonNuevo: View {
    let accion: () -> Void
    @State private var encima = false

    var body: some View {
        Button(action: accion) {
            Label("Proyecto nuevo", systemImage: "plus")
                .labelStyle(.iconOnly)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(Paleta.proyectos.contador, in: Circle())
                .brightness(encima ? 0.06 : 0)
                .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { encima = $0 }
        .help("Proyecto nuevo")
    }
}

/// Una fila de la lista: el avatar con sus iniciales, el nombre y debajo
/// la ultima linea (o cuantas hojas tiene); elegida, en azul con el texto
/// blanco.
struct FilaProyecto: View {
    let chat: FichaChat
    let elegida: Bool
    @State private var encima = false

    private var debajo: String {
        // Sin la sintaxis de la nota (`# `, `**`, `- [ ]`) ni caracteres de control.
        let r = String(textoConFormato(chat.resumen).characters).trimmingCharacters(in: .whitespacesAndNewlines)
        if !r.isEmpty { return r }
        return chat.hojas == 1 ? "1 hoja" : "\(chat.hojas) hojas"
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Paleta.avatar(chat.id))
                Text(Paleta.iniciales(chat.nombre))
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.white)
            }
            .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 6) {
                Text(chat.nombre)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(elegida ? Color.white : Paleta.proyectos.texto)
                Text(debajo)
                    .font(.system(size: 13))
                    .foregroundStyle(elegida ? Color.white.opacity(0.85) : Paleta.proyectos.apagado)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            if chat.sinLeer > 0 {
                Text("\(chat.sinLeer)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(elegida ? Paleta.proyectos.filaElegida : .white)
                    .padding(.horizontal, 5)
                    .frame(minWidth: 19, minHeight: 19)
                    .background(elegida ? Color.white : Paleta.proyectos.contador, in: Capsule())
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 10)
        .frame(height: 62)
        .background(elegida ? Paleta.proyectos.filaElegida : encima ? Paleta.proyectos.filaEncima : .clear)
        .contentShape(Rectangle())
        .onHover { encima = $0 }
    }
}

/// El papel del chat, en degradado como en Windows y el movil.
struct PapelChat: View {
    var body: some View {
        LinearGradient(colors: [Paleta.proyectos.papelArriba, Paleta.proyectos.papelAbajo],
                       startPoint: .top, endPoint: .bottom)
    }
}
