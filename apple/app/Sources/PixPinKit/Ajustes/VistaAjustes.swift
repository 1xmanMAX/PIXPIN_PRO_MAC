// La ventana de Ajustes (⌘,), como la de Windows (`ventana_ajustes.rs`,
// maqueta `Ajustes2`): a la izquierda el buscador y las secciones; a la
// derecha, las opciones de la seccion en tarjetas, cada una con su
// explicacion debajo. Un punto azul marca lo que no esta como de fabrica, y
// al lado sale el boton de volver a fabrica; arriba, «Restablecer
// <seccion>» hace lo mismo con todas. Lo tocado se deshace con ⌘Z (o
// «Deshacer»). Oscura y plana, con los colores de Windows (`Paleta.v2`).
//
// A diferencia de Windows, cada cambio se guarda al momento (en la cola del
// `ModeloAjustes`): una ventana de Ajustes del Mac no tiene «Listo».
//
// Las filas salen de `FilasAjustes`; la seccion «Atajos» es `SeccionAtajos`.

import AppKit
import PixPinCore
import SwiftUI

public struct VistaAjustes: View {
    @ObservedObject var modelo: ModeloAjustes
    @ObservedObject var atajos: GestorAtajos
    @State private var seccion: SeccionAjustes = .general
    @State private var busqueda = ""
    @FocusState private var buscando: Bool

    public init(modelo: ModeloAjustes, atajos: GestorAtajos) {
        self.modelo = modelo
        self.atajos = atajos
    }

    private typealias P = Paleta.v2

    public var body: some View {
        HStack(spacing: 0) {
            columna
            Rectangle().fill(P.linea).frame(width: 1)
            contenido
        }
        .frame(minWidth: 860, idealWidth: 940, minHeight: 560, idealHeight: 640)
        .background(P.fondo)
        .environment(\.colorScheme, .dark)
        .tint(P.acento)
        .background(AccesoVentana { $0.appearance = NSAppearance(named: .darkAqua) })
        .task { if !modelo.cargado { await modelo.cargar() } }
        .onReceive(NotificationCenter.default.publisher(for: .pixpinIrASeccionAjustes)) { n in
            if let id = n.object as? String, let s = SeccionAjustes(rawValue: id) {
                busqueda = ""
                seccion = s
            }
        }
    }

    // MARK: La columna

    private var columna: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ajustes")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(P.texto)
                .padding(.horizontal, 8)
                .padding(.top, 14)
                .padding(.bottom, 6)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(P.gris)
                TextField("Buscar un ajuste…", text: $busqueda)
                    .textFieldStyle(.plain)
                    .focused($buscando)
                    .onExitCommand { busqueda = "" }
                if !busqueda.isEmpty {
                    Button { busqueda = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(P.gris)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 8).fill(P.caja))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(buscando ? P.acento : Color.white.opacity(0.08)))
            .padding(.bottom, 6)
            // ⌘F lleva al buscador, como Ctrl+F en Windows.
            Button("") { buscando = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0).frame(width: 0, height: 0)
            ForEach(SeccionAjustes.allCases) { s in
                BotonSeccion(seccion: s, elegida: busqueda.isEmpty && seccion == s) {
                    busqueda = ""
                    seccion = s
                }
            }
            Spacer(minLength: 8)
            Button {
                modelo.deshacer()
            } label: {
                Label("Deshacer", systemImage: "arrow.uturn.backward")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BotonAjustes())
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!modelo.sePuedeDeshacer)
            .help("Deshacer el último cambio (⌘Z)")
            Text("Se guarda al momento en pixpinmax.toml. ● = distinto del valor de fábrica.")
                .font(.caption2).foregroundStyle(P.gris)
                .padding(.horizontal, 4).padding(.bottom, 12)
        }
        .padding(.horizontal, 10)
        .frame(width: 248)
        .background(Color(hex: 0x232326))
    }

    // MARK: El contenido

    @ViewBuilder private var contenido: some View {
        if busqueda.trimmingCharacters(in: .whitespaces).isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                cabecera(titulo: seccion.titulo, subtitulo: seccion.subtitulo, restablecer: seccion != .atajos)
                if seccion == .atajos {
                    SeccionAtajos(atajos: atajos)
                        .scrollContentBackground(.hidden)
                } else {
                    ScrollView {
                        tarjetas(FilasAjustes.de(seccion))
                            .padding(.horizontal, 28).padding(.bottom, 28)
                    }
                }
            }
        } else {
            let filas = FilasAjustes.buscar(busqueda)
            VStack(alignment: .leading, spacing: 0) {
                cabecera(titulo: "Resultados para «\(busqueda)»",
                         subtitulo: filas.isEmpty
                             ? "Ningún ajuste habla de «\(busqueda)». Prueba con otra palabra."
                             : filas.count == 1 ? "1 ajuste encontrado en todas las secciones."
                             : "\(filas.count) ajustes encontrados en todas las secciones.",
                         restablecer: false)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(SeccionAjustes.allCases) { s in
                            let suyas = filas.filter { $0.seccion == s }
                            if !suyas.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(s.titulo).font(.headline).foregroundStyle(P.texto)
                                    tarjetas(suyas)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 28).padding(.bottom, 28)
                }
            }
        }
    }

    private func cabecera(titulo: String, subtitulo: String, restablecer: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(titulo).font(.system(size: 22, weight: .semibold)).foregroundStyle(P.texto)
                Text(subtitulo).font(.callout).foregroundStyle(P.gris)
                if let error = modelo.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(P.rojo)
                }
            }
            Spacer()
            if restablecer {
                Button("Restablecer \(seccion.titulo)") { FilasAjustes.restablecer(seccion, modelo) }
                    .buttonStyle(BotonAjustes())
                    .disabled(!FilasAjustes.hayCambios(en: seccion, modelo))
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 14)
    }

    /// Las filas en tarjetas, una por grupo, con el nombre del grupo encima.
    private func tarjetas(_ filas: [FilaAjuste]) -> some View {
        let grupos = filas.reduce(into: [(String, [FilaAjuste])]()) { r, f in
            if let i = r.firstIndex(where: { $0.0 == f.grupo }) { r[i].1.append(f) } else { r.append((f.grupo, [f])) }
        }
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(grupos, id: \.0) { grupo, suyas in
                Text(grupo.uppercased())
                    .font(.caption.weight(.semibold)).foregroundStyle(P.gris)
                    .padding(.top, 10).padding(.leading, 4)
                VStack(spacing: 0) {
                    ForEach(Array(suyas.enumerated()), id: \.element.id) { i, f in
                        if i > 0 { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }
                        FilaVista(fila: f, modelo: modelo)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 10).fill(P.caja))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.10)))
            }
        }
    }
}

// MARK: - Piezas

/// Una seccion de la columna.
private struct BotonSeccion: View {
    let seccion: SeccionAjustes
    let elegida: Bool
    let accion: () -> Void
    @State private var encima = false

    var body: some View {
        Button(action: accion) {
            HStack(spacing: 10) {
                Image(systemName: seccion.icono).frame(width: 20)
                Text(seccion.titulo)
                Spacer()
            }
            .font(.system(size: 13, weight: elegida ? .semibold : .regular))
            .foregroundStyle(elegida ? Color.white : Paleta.v2.cuerpo)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(elegida ? Paleta.v2.azulLleno : encima ? Color.white.opacity(0.06) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { encima = $0 }
    }
}

/// Una fila: titulo y explicacion a la izquierda, el control a la derecha.
private struct FilaVista: View {
    let fila: FilaAjuste
    @ObservedObject var modelo: ModeloAjustes

    var body: some View {
        if fila.titulo.isEmpty, case let .vista(hacer) = fila.control {
            // Sin titulo: lo suyo ocupa la tarjeta entera.
            VStack(alignment: .leading, spacing: 8) { hacer(modelo) }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(fila.titulo).foregroundStyle(Paleta.v2.texto)
                        if fila.restablecible, fila.cambiada(modelo) {
                            Circle().fill(Paleta.v2.acento).frame(width: 7, height: 7)
                                .help("Distinto del valor de fábrica")
                            Button {
                                FilasAjustes.restablecer(fila, modelo)
                            } label: {
                                Image(systemName: "arrow.counterclockwise").font(.caption)
                            }
                            .buttonStyle(.plain).foregroundStyle(Paleta.v2.gris)
                            .help("Volver al valor de fábrica")
                        }
                    }
                    if !fila.ayuda.isEmpty {
                        Text(fila.ayuda).font(.caption).foregroundStyle(Paleta.v2.gris)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ControlVista(control: fila.control, modelo: modelo)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

private struct ControlVista: View {
    let control: ControlAjuste
    @ObservedObject var modelo: ModeloAjustes

    var body: some View {
        switch control {
        case let .interruptor(get, set):
            Toggle("", isOn: Binding(get: { get(modelo) }, set: { set(modelo, $0) }))
                .toggleStyle(.switch).labelsHidden()
        case let .opcion(opciones, get, set):
            Picker("", selection: Binding(get: { get(modelo) }, set: { set(modelo, $0) })) {
                ForEach(opciones.indices, id: \.self) { i in Text(opciones[i]).tag(i) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .fixedSize()
        case let .numero(rango, paso, texto, get, set):
            let n = get(modelo)
            HStack(spacing: 0) {
                Button { set(modelo, n - paso) } label: { Image(systemName: "minus").frame(width: 30, height: 26) }
                    .disabled(n <= rango.lowerBound)
                Text(texto(n)).monospacedDigit().frame(minWidth: 84)
                Button { set(modelo, n + paso) } label: { Image(systemName: "plus").frame(width: 30, height: 26) }
                    .disabled(n >= rango.upperBound)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Paleta.v2.texto)
            .background(RoundedRectangle(cornerRadius: 7).fill(Paleta.v2.fondo))
        case let .boton(titulo, accion):
            Button(titulo) { accion(modelo) }.buttonStyle(BotonAjustes())
        case let .vista(hacer):
            hacer(modelo)
        case .nada:
            EmptyView()
        }
    }
}

/// El boton plano de Windows (blanco al 8 %, 13 % con el raton encima).
struct BotonAjustes: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Cuerpo(configuration: configuration)
    }

    private struct Cuerpo: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var activo
        @State private var encima = false

        var body: some View {
            configuration.label
                .font(.system(size: 12.5))
                .foregroundStyle(activo ? Paleta.v2.texto : Paleta.v2.gris.opacity(0.6))
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 7)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.18 : encima && activo ? 0.13 : 0.08)))
                .onHover { encima = $0 }
        }
    }
}

/// «Abrir al iniciar sesion» (`SMAppService`), con el aviso si falta el
/// visto bueno en Ajustes del Sistema.
struct ControlArranque: View {
    @ObservedObject var modelo: ModeloAjustes

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Toggle("", isOn: Binding(get: { modelo.abrirAlIniciar }, set: { modelo.fijar(abrirAlIniciar: $0) }))
                .toggleStyle(.switch).labelsHidden()
            if modelo.esperaAprobacion {
                Button("Permitirlo en Ajustes del Sistema") { modelo.abrirElementosDeInicio() }
                    .buttonStyle(BotonAjustes())
            }
        }
    }
}

/// La escala de la interfaz, con sus escalones (`EscalaChat.escalones`): el
/// chat abierto la coge al vuelo, que lee la misma clave.
struct ControlEscalaInterfaz: View {
    @AppStorage(EscalaChat.clave) private var escala = EscalaChat.porDefecto

    var body: some View {
        Picker("", selection: Binding(get: { EscalaChat.valida(escala) }, set: { escala = $0 })) {
            ForEach(EscalaChat.escalones, id: \.self) { n in
                Text(verbatim: "\(n) %").tag(n)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
    }
}

/// **La clave de un proveedor de la nube** (la «pantalla de claves» de
/// Windows): pegarla y guardarla en el Llavero, ver la que hay (enmascarada),
/// **probarla** (una llamada minima: unos pocos tokens; al guardar se prueba
/// sola, como en Windows) y borrarla. Nunca se ensena entera.
struct ClaveNube: View {
    let proveedor: ProveedorNube
    @State private var escrita = ""
    @State private var guardada: String?
    @State private var aviso: String?
    /// La ultima prueba: en curso (`nil` dentro) o su resultado.
    @State private var prueba: Result<String, Error>??

    private var probando: Bool {
        if case .some(.none) = prueba { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if let guardada {
                HStack(spacing: 8) {
                    Text(guardada).font(.system(.caption, design: .monospaced)).foregroundStyle(Paleta.v2.verde)
                    Button("Probar") { probar() }.buttonStyle(BotonAjustes())
                        .disabled(probando)
                        .help("Una llamada mínima con la clave (unos pocos tokens)")
                    Button("Borrar") { borrar() }.buttonStyle(BotonAjustes())
                }
            }
            switch prueba {
            case .some(.none):
                HStack(spacing: 6) { ProgressView().controlSize(.mini); Text("Probando…").font(.caption) }
            case let .some(.some(.success(t))):
                Text("✓ " + t).font(.caption).foregroundStyle(Paleta.v2.verde)
            case let .some(.some(.failure(e))):
                Text("⚠️ " + ModeloAjustes.texto(de: e)).font(.caption).foregroundStyle(Paleta.v2.rojo)
            case .none:
                EmptyView()
            }
            HStack(spacing: 6) {
                SecureField(guardada == nil ? "Pega aquí la clave" : "Pega otra para cambiarla", text: $escrita)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .onSubmit(guardar)
                Button("Guardar", action: guardar)
                    .buttonStyle(BotonAjustes())
                    .disabled(escrita.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let aviso { Text(aviso).font(.caption).foregroundStyle(Paleta.v2.rojo) }
        }
        .onAppear(perform: leer)
    }

    private func leer() {
        guardada = iaClaveEnmascarada(proveedorId: proveedor.rawValue)
    }

    private func guardar() {
        let clave = escrita.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clave.isEmpty else { return }
        do {
            try iaGuardarClave(proveedorId: proveedor.rawValue, clave: clave)
            escrita = ""
            aviso = nil
            leer()
            probar()
            return
        } catch {
            aviso = "No se pudo guardar: \(ModeloAjustes.texto(de: error))"
        }
        leer()
    }

    private func probar() {
        prueba = .some(nil)
        let id = proveedor.rawValue
        TransporteHttps.instalar()
        Task {
            let r = await Task.detached(priority: .userInitiated) {
                Result { try iaProbarClave(proveedorId: id) }
            }.value
            prueba = .some(r)
        }
    }

    private func borrar() {
        do {
            try iaBorrarClave(proveedorId: proveedor.rawValue)
            aviso = nil
            prueba = nil
        } catch {
            aviso = "No se pudo borrar: \(ModeloAjustes.texto(de: error))"
        }
        leer()
    }
}
