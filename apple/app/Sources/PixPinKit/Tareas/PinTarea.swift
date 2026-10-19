// El pin de una tarea (Windows, 17-oct): una tarea sola fijada en la
// pantalla como recordatorio, que solo ensena su titulo, su prioridad, su
// hora, sus #etiquetas y la nota de por que no se esta haciendo. La nota va
// DENTRO de la tarea (tras `💬`), asi que viaja al movil y se ve en Tareas.
//
// La tarea se reconoce por su titulo y no por su numero: el chat o el movil
// pueden reordenar la lista mientras el pin esta en la pantalla. Se relee
// al cambiar algo (`pixpinCambioLocal`, y tras sincronizar).

import AppKit
import PixPinCore
import SwiftUI

@MainActor
final class ModeloPinTarea: ObservableObject {
    let chat: String
    let lista: String
    let titulo: String
    let nucleo: Nucleo
    @Published private(set) var marcas: MarcasTarea?
    @Published private(set) var hecha = false
    @Published private(set) var seFue = false

    init(chat: String, lista: String, titulo: String, nucleo: Nucleo) {
        (self.chat, self.lista, self.titulo, self.nucleo) = (chat, lista, titulo, nucleo)
    }

    func releer() {
        guard let t = try? nucleo.tareaPorTitulo(chat: chat, lista: lista, titulo: titulo) else {
            seFue = true
            return
        }
        seFue = false
        marcas = marcasDeTarea(texto: t.crudo, desfaseMs: desfaseLocalMs())
        hecha = t.hecha
    }

    func ponerNota(_ nota: String) {
        _ = try? nucleo.ponerNotaTarea(chat: chat, lista: lista, titulo: titulo, nota: nota)
        avisar()
        releer()
    }

    func marcar(_ h: Bool) {
        guard let t = try? nucleo.tareaPorTitulo(chat: chat, lista: lista, titulo: titulo) else { return }
        _ = try? nucleo.marcarTarea(chat: chat, mensaje: lista, indice: t.indice, crudo: t.crudo, hecha: h)
        avisar()
        releer()
    }

    private func avisar() {
        NotificationCenter.default.post(name: .pixpinCambioLocal, object: nil)
        NotificationCenter.default.post(name: .pixpinTareasCambiadas, object: chat)
    }
}

struct VistaPinTarea: View {
    @ObservedObject var modelo: ModeloPinTarea
    let cerrar: () -> Void
    @State private var escribiendo = false
    @State private var nota = ""
    @FocusState private var foco: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Toggle("", isOn: Binding(get: { modelo.hecha }, set: { modelo.marcar($0) }))
                    .toggleStyle(.checkbox).labelsHidden()
                if let u = modelo.marcas?.marcaUrgencia { Text(u) }
                Text(modelo.seFue ? "\(modelo.titulo) (ya no está)" : modelo.titulo)
                    .font(.system(size: 14, weight: .semibold))
                    .strikethrough(modelo.hecha)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Button(action: cerrar) { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).help("Quitar el pin")
            }
            if let m = modelo.marcas {
                HStack(spacing: 6) {
                    if let h = m.horaMs {
                        Label(AtajosDeHora.legible(fechaDeLocales(h), ahora: Date()), systemImage: "alarm")
                    }
                    ForEach(m.etiquetas, id: \.self) { Text("#\($0)") }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            if escribiendo {
                TextField("Por qué no se está haciendo", text: $nota)
                    .textFieldStyle(.roundedBorder)
                    .focused($foco)
                    .onSubmit {
                        escribiendo = false
                        modelo.ponerNota(nota)
                    }
                    .onExitCommand { escribiendo = false }
            } else {
                Button {
                    nota = modelo.marcas?.nota ?? ""
                    escribiendo = true
                    foco = true
                } label: {
                    Text(modelo.marcas?.nota.map { "💬 \($0)" } ?? "💬 Añadir una nota")
                        .font(.caption).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(10)
        .frame(width: 280)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor.opacity(0.5)))
    }
}

/// **Los pines de tarea abiertos**: uno por tarea.
@MainActor
public final class PinesDeTareas {
    public static let compartidos = PinesDeTareas()
    private var abiertos: [String: (PanelFlotanteVoz, ModeloPinTarea)] = [:]
    private var vigia: NSObjectProtocol?

    /// Pone en la pantalla el pin de la tarea `titulo` (sin marcas) de la
    /// lista `lista` del chat `chat`.
    public func abrir(chat: String, lista: String, titulo: String, nucleo: Nucleo) {
        let clave = "\(chat)/\(lista)/\(titulo)"
        if let (p, m) = abiertos[clave] {
            m.releer()
            p.orderFrontRegardless()
            return
        }
        let modelo = ModeloPinTarea(chat: chat, lista: lista, titulo: titulo, nucleo: nucleo)
        modelo.releer()
        let panel = PanelFlotanteVoz.nuevo(NSSize(width: 280, height: 120))
        let vista = NSHostingView(rootView: VistaPinTarea(modelo: modelo) { [weak self] in self?.cerrar(clave) })
        panel.contentView = vista
        panel.setContentSize(vista.fittingSize)
        panel.colocar("PixPinPinTarea")
        // Uno encima de otro, que no se tapen.
        let n = CGFloat(abiertos.count)
        panel.setFrameOrigin(NSPoint(x: panel.frame.minX, y: panel.frame.minY + n * (panel.frame.height + 8)))
        panel.orderFrontRegardless()
        abiertos[clave] = (panel, modelo)
        if vigia == nil {
            vigia = NotificationCenter.default.addObserver(forName: .pixpinCambioLocal, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    for (_, m) in PinesDeTareas.compartidos.abiertos.values { m.releer() }
                }
            }
        }
    }

    func cerrar(_ clave: String) {
        abiertos.removeValue(forKey: clave)?.0.close()
    }

    /// Cuantos hay en la pantalla (para las pruebas).
    var cuantos: Int { abiertos.count }
}
