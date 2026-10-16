// **La ventana de las automatizaciones** (tanda E6): la lista que en
// Windows esta en Ajustes → Asistente (`ventana_ajustes::filas_de_
// automatizaciones`), con lo mismo por fila —su interruptor, «Correr
// ahora» y el aspa de borrar, que pregunta—, mas lo que el Mac anade: el
// editor (crear y cambiar sin pedirselo al asistente) y el historial de
// las ultimas vueltas de este Mac.
//
// Plana y oscura como las demas ventanas con la barra comun (`Cabecera`,
// `Paleta.v2`). Lo que se lee y se escribe va al nucleo fuera del hilo
// principal; el fichero es el mismo que el de Windows y Android.

import AppKit
import PixPinCore
import SwiftUI

@MainActor
final class ModeloAutomatizaciones: ObservableObject {
    let nucleo: Nucleo
    @Published private(set) var lista: [FichaAutomatizacion] = []
    @Published private(set) var historial: [VueltaAutomatizacion] = []
    @Published private(set) var cargado = false
    @Published var error: String?

    init(nucleo: Nucleo) {
        self.nucleo = nucleo
    }

    func cargar() async {
        let nucleo = self.nucleo
        let r = await Task.detached(priority: .userInitiated) { () -> (Result<[FichaAutomatizacion], Error>, [VueltaAutomatizacion]) in
            (Result { try nucleo.automatizaciones() }, nucleo.automatizacionesHistorial())
        }.value
        switch r.0 {
        case let .success(l):
            lista = l
            error = nil
        case let .failure(e):
            error = "Las automatizaciones no se entienden: " + ModeloAjustes.texto(de: e)
        }
        historial = r.1
        cargado = true
    }

    /// Hace algo con el nucleo y relee; si falla, lo dice abajo.
    func cambiar(_ trabajo: @escaping @Sendable (Nucleo) throws -> Void) async {
        let nucleo = self.nucleo
        do {
            try await Task.detached(priority: .userInitiated) { try trabajo(nucleo) }.value
            NotificationCenter.default.post(name: .pixpinCambioLocal, object: nil)
        } catch {
            self.error = ModeloAjustes.texto(de: error)
        }
        await cargar()
    }

    func activar(_ f: FichaAutomatizacion, _ activa: Bool) async {
        let id = f.id
        await cambiar { _ = try $0.automatizacionActivar(id: id, activa: activa) }
    }

    func borrar(_ f: FichaAutomatizacion) async {
        let id = f.id
        await cambiar { _ = try $0.automatizacionBorrar(id: id) }
    }

    func guardar(_ f: FichaAutomatizacion) async -> String? {
        let nucleo = self.nucleo
        do {
            _ = try await Task.detached(priority: .userInitiated) { try nucleo.automatizacionGuardar(ficha: f) }.value
            NotificationCenter.default.post(name: .pixpinCambioLocal, object: nil)
            await cargar()
            return nil
        } catch {
            return ModeloAjustes.texto(de: error)
        }
    }
}

public struct VentanaAutomatizaciones: View {
    @StateObject private var modelo: ModeloAutomatizaciones
    @ObservedObject private var motor = MotorAutomatizaciones.compartido
    @State private var editando: FichaAutomatizacion?
    @State private var buscar = ""

    public init(almacen: Almacen) {
        _modelo = StateObject(wrappedValue: ModeloAutomatizaciones(nucleo: almacen.nucleo))
    }

    private var visibles: [FichaAutomatizacion] {
        let q = buscar.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return modelo.lista }
        return modelo.lista.filter { ($0.nombre + " " + $0.detalle).lowercased().contains(q) }
    }

    private var subtitulo: String {
        if let c = motor.corriendo { return "Corriendo «\(c)»…" }
        return modelo.lista.count == 1 ? "1 automatización" : "\(modelo.lista.count) automatizaciones"
    }

    public var body: some View {
        VStack(spacing: 0) {
            Cabecera("Automatizaciones", subtitulo: subtitulo,
                     buscador: BuscadorCabecera($buscar, pista: "Buscar automatizaciones")) {
                BotonCabecera(icono: "plus", rotulo: "Nueva", ayuda: "Nueva automatización (⌘N)", activo: true) {
                    editando = EditorAutomatizacion.nueva()
                }
                .keyboardShortcut("n")
                BotonCabecera(icono: "arrow.clockwise", ayuda: "Releer (⌘R)") { Task { await modelo.cargar() } }
                    .keyboardShortcut("r")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if modelo.cargado, modelo.lista.isEmpty {
                        vacia
                    }
                    ForEach(visibles, id: \.id) { f in
                        FilaAutomatizacion(ficha: f,
                                           activar: { a in Task { await modelo.activar(f, a) } },
                                           correr: { MotorAutomatizaciones.compartido.aMano(f.id) },
                                           editar: { editando = f },
                                           borrar: { preguntarBorrar(f) })
                    }
                    if !modelo.historial.isEmpty {
                        Text("Historial de este Mac")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Paleta.v2.gris)
                            .padding(.top, 14)
                        VStack(spacing: 0) {
                            ForEach(Array(modelo.historial.prefix(30).enumerated()), id: \.offset) { _, v in
                                FilaVuelta(vuelta: v)
                            }
                        }
                        .background(Paleta.v2.tarjeta, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(20)
            }
            .background(Paleta.v2.fondo)
        }
        .overlay(alignment: .bottom) {
            if let e = modelo.error {
                Text(e)
                    .font(.system(size: 12))
                    .foregroundStyle(Paleta.v2.texto)
                    .padding(8)
                    .background(Paleta.v2.rojo.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                    .padding()
                    .onTapGesture { modelo.error = nil }
            }
        }
        .environment(\.colorScheme, .dark)
        .sheet(item: Binding(get: { editando.map(Editando.init) }, set: { editando = $0?.ficha })) { e in
            EditorAutomatizacion(ficha: e.ficha, nucleo: modelo.nucleo) { f in
                await modelo.guardar(f)
            }
        }
        .ventanaConCabecera()
        .task { await modelo.cargar() }
        .onReceive(motor.$vueltas) { _ in Task { await modelo.cargar() } }
        .onReceive(NotificationCenter.default.publisher(for: .pixpinCambioLocal)) { _ in
            Task { await modelo.cargar() }
        }
        .frame(minWidth: 560, minHeight: 420)
    }

    private var vacia: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ninguna todavía")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Paleta.v2.texto)
            Text("Pídeselas al asistente: «cada vez que capture, ponlo en el chat de la obra», «cada día a las 8, resumen de tareas pendientes». O crea una con «Nueva».")
                .font(.system(size: 13))
                .foregroundStyle(Paleta.v2.gris)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Paleta.v2.tarjeta, in: RoundedRectangle(cornerRadius: 12))
    }

    /// El aspa: pregunta como Windows («No se puede deshacer»).
    private func preguntarBorrar(_ f: FichaAutomatizacion) {
        let alerta = NSAlert()
        alerta.messageText = "¿Borro la automatización «\(f.nombre)»? No se puede deshacer."
        alerta.alertStyle = .warning
        alerta.addButton(withTitle: "Borrar")
        alerta.addButton(withTitle: "Cancelar")
        guard alerta.runModal() == .alertFirstButtonReturn else { return }
        Task { await modelo.borrar(f) }
    }
}

/// Para el `sheet(item:)`: la ficha con un id que no cambia al editarla.
private struct Editando: Identifiable {
    let ficha: FichaAutomatizacion
    var id: String { ficha.id.isEmpty ? "nueva" : ficha.id }
}

/// Una fila de la lista: nombre, cuando y que hace, y sus botones.
struct FilaAutomatizacion: View {
    let ficha: FichaAutomatizacion
    let activar: (Bool) -> Void
    let correr: () -> Void
    let editar: () -> Void
    let borrar: () -> Void
    @State private var encima = false

    private var linea: String {
        if let r = ficha.rota { return "No se entiende: \(r)" }
        var t = ficha.detalle
        if let a = ficha.otroAparato { t += " · corre en \(a.isEmpty ? "otro aparato" : a)" }
        if let u = ficha.ultimaVez {
            let f = fechaDeLocales(u).formatted(date: .abbreviated, time: .shortened)
            t += " · última vez: \(f)"
        }
        return t
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: ficha.rota != nil ? "exclamationmark.triangle" : icono)
                .font(.system(size: 16))
                .foregroundStyle(ficha.rota != nil ? Paleta.v2.naranja : ficha.activa ? Paleta.v2.acento : Paleta.v2.gris)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(ficha.nombre)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Paleta.v2.texto)
                Text(linea)
                    .font(.system(size: 12))
                    .foregroundStyle(ficha.rota != nil ? Paleta.v2.naranja : Paleta.v2.gris)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if ficha.rota == nil {
                BotonCabecera(icono: "play.fill", ayuda: "Correr ahora", tenue: true, accion: correr)
                BotonCabecera(icono: "pencil", ayuda: "Cambiar", tenue: true, accion: editar)
                Toggle("", isOn: Binding(get: { ficha.activa }, set: activar))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .help(ficha.activa ? "Encendida" : "Apagada")
            }
            BotonCabecera(icono: "xmark", ayuda: "Borrar", tenue: true, accion: borrar)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(encima ? Paleta.v2.tarjetaEncima : Paleta.v2.tarjeta, in: RoundedRectangle(cornerRadius: 12))
        .onHover { encima = $0 }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { if ficha.rota == nil { editar() } }
    }

    private var icono: String {
        switch ficha.disparador {
        case "al_capturar": "camera.viewfinder"
        case "a_la_hora": "clock"
        case "al_sincronizar": "arrow.triangle.2.circlepath"
        default: "hand.tap"
        }
    }
}

/// Una vuelta del historial.
struct FilaVuelta: View {
    let vuelta: VueltaAutomatizacion

    private var disparo: String {
        switch vuelta.disparo {
        case "al_capturar": "al capturar"
        case "a_la_hora": "a su hora"
        case "al_sincronizar": "al sincronizar"
        default: "a mano"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: vuelta.bien ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(vuelta.bien ? Paleta.v2.verde : Paleta.v2.naranja)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(vuelta.nombre).font(.system(size: 13, weight: .medium)).foregroundStyle(Paleta.v2.texto)
                    Text(disparo).font(.system(size: 11)).foregroundStyle(Paleta.v2.gris)
                    Spacer()
                    Text(fechaDe(ms: vuelta.cuando).formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 11))
                        .foregroundStyle(Paleta.v2.gris)
                }
                Text(vuelta.resumen)
                    .font(.system(size: 12))
                    .foregroundStyle(Paleta.v2.cuerpo)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Paleta.v2.linea.frame(height: 1) }
    }
}
