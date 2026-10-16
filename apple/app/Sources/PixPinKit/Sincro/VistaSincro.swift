// La ventana de Sincronizar: quien es este Mac (y cambiarle el nombre), el
// codigo del grupo, todos los aparatos del grupo (los de la Wi-Fi y los que
// no, con «sincronizado hace X»), salir del grupo y las copias de
// seguridad. Como la ventana de Windows, en pequeno (`VistaAparatos`,
// `VistaCopias`).

import AppKit
import PixPinCore
import SwiftUI

public struct VistaSincro: View {
    @ObservedObject var sincro: Sincronizador
    @ObservedObject var vecinos: Vecinos
    @State private var codigo = ""
    @State private var direccion = ""
    @State private var verCopias = false

    public init(sincro: Sincronizador) {
        _sincro = ObservedObject(wrappedValue: sincro)
        _vecinos = ObservedObject(wrappedValue: sincro.vecinos)
    }

    public var body: some View {
        Form {
            SeccionEsteAparato(sincro: sincro)

            if let codigo = sincro.codigoLegible {
                grupo(codigo)
            } else {
                sinGrupo
            }

            if sincro.fase != nil || sincro.ultimoResultado != nil || sincro.error != nil || !sincro.presencia {
                Section("Actividad") {
                    if !sincro.presencia {
                        // Sin presencia, el movil no puede llamar a este Mac.
                        Label("La presencia está apagada en los ajustes ([sincro] presencia = false): "
                            + "desde aquí puedes sincronizar, pero el móvil no podrá encontrar este "
                            + "equipo ni llamarlo.", systemImage: "eye.slash")
                            .foregroundStyle(.red)
                    }
                    if let fase = sincro.fase {
                        HStack { ProgressView().controlSize(.small); Text(fase) }
                    }
                    if let r = sincro.ultimoResultado {
                        Text(r).textSelection(.enabled)
                    }
                    if let e = sincro.error {
                        Label(e, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }
            }

            Section {
                Button("Ver las copias…") { verCopias = true }
            } header: {
                Text("Copias de seguridad")
            } footer: {
                Text("Cómo estaba cada conversación antes de recibir algo por Wi-Fi y antes de cada "
                    + "sincronización. Y los proyectos borrados, para recuperarlos.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 420)
        // Los del grupo que Bonjour no ensena, en su direccion recordada.
        .onAppear { sincro.mirarRecordadas() }
        // «¿Qué sincronizar?» antes de una vuelta con un aparato.
        .sheet(item: $sincro.pregunta) { p in VistaElegirSincro(p) }
        .sheet(isPresented: $verCopias) {
            VistaCopias(nucleo: sincro.nucleo) { [weak sincro] in sincro?.alTraerCambios?() }
        }
    }

    // MARK: - Con grupo

    private func grupo(_ legible: String) -> some View {
        Group {
            Section {
                HStack {
                    Text(legible)
                        .font(.system(.title2, design: .monospaced).weight(.semibold))
                        .textSelection(.enabled)
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(legible, forType: .string)
                    } label: { Image(systemName: "doc.on.doc") }
                        .help("Copiar el código")
                }
            } header: {
                Text("Código del grupo")
            } footer: {
                Text("En el otro aparato: Sincronizar › Unirse a un grupo, con este código.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            SeccionTusAparatos(sincro: sincro, vecinos: vecinos)

            Section {
                Toggle("Sincronizar solo (al aparecer un aparato, 30 s después de un cambio, "
                    + "cada 10 min y las tareas al instante)",
                       isOn: $sincro.automatica)
                    .disabled(!sincro.presencia)
                if sincro.bajoConsumo {
                    Label("Modo de bajo consumo: solo a mano.", systemImage: "battery.25")
                        .foregroundStyle(.secondary)
                }
                Button("Sincronizar ahora con todos") {
                    Task { await sincro.sincronizarAhora() }
                }
                .disabled(sincro.ocupado || !sincro.filas.contains { $0.direccion != nil })
                .help(sincro.filas.filter { $0.direccion != nil }.count >= 2
                    ? "Sin preguntar nada, uno detrás de otro y en dos rondas, para que todos acaben con todo."
                    : "Sin preguntar nada, con lo elegido la última vez.")
            }
        }
    }

    // MARK: - Sin grupo

    private var sinGrupo: some View {
        Group {
            Section {
                Text("Crea un grupo aquí y únete desde tus otros aparatos, o únete al grupo que ya tienes en tu PC o tu móvil.")
                    .foregroundStyle(.secondary)
                Button("Crear un grupo") { Task { await sincro.crearGrupo() } }
                    .disabled(sincro.ocupado)
            } header: {
                Text("Grupo")
            }
            Section {
                TextField("Código (K7Q2M-9XMPA)", text: $codigo)
                    .font(.system(.body, design: .monospaced))
                TextField("Dirección (opcional: 192.168.1.20:47474)", text: $direccion)
                Button("Unirse") {
                    let dir = Direccion(texto: direccion)
                    Task { await sincro.unirse(codigo: codigo, direccion: dir) }
                }
                .disabled(sincro.ocupado || !codigoValido(codigo: codigo))
            } header: {
                Text("Unirse a un grupo")
            } footer: {
                Text("Sin dirección se busca en la Wi-Fi un aparato con ese código y PixPin abierto.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
