// El horario de clases que llama (Windows, 17-oct): `horario.md` junto a
// los datos, escrito con el editor de notas (una linea por clase, o una
// tabla pegada). Lo lee el nucleo (`horario.rs`) y lo hace sonar el vigia
// (`Recordatorios`) con la tarjeta de la llamada secreta.
//
// Aqui: abrirlo y «Nota de voz para la próxima clase», una grabadora
// flotante que deja la nota donde la busca la llamada de esa clase.

import AppKit
import AVFoundation
import PixPinCore
import SwiftUI

@MainActor
public enum HorarioClases {
    /// Abre el horario en el editor de notas (lo crea con la plantilla).
    public static func abrir(nucleo: Nucleo) {
        do {
            let ruta = try nucleo.ficheroDelHorario()
            EditoresDeNotas.compartidos.abrir(fichero: URL(fileURLWithPath: ruta), nucleo: nucleo)
        } catch {
            CentroAvisos.compartido.mostrarEnLaApp(
                Aviso(id: "horario", categoria: .recordatorio, titulo: "Horario",
                      texto: "No se pudo abrir el horario: \(error)", datos: [:]),
                sonar: false)
        }
    }

    /// **«Nota de voz para la próxima clase»**: graba para la clase en
    /// marcha (o la ultima de hoy, o la proxima).
    public static func grabarParaLaProxima(nucleo: Nucleo) {
        guard let nota = nucleo.notaDeVozDeClase(desfaseMs: desfaseLocalMs()) else {
            CentroAvisos.compartido.mostrarEnLaApp(
                Aviso(id: "horario", categoria: .recordatorio, titulo: "Horario",
                      texto: "El horario no tiene clases: ábrelo y escribe una por línea", datos: [:]),
                sonar: false)
            return
        }
        GrabadoraDeClase.compartida.empezar(nota)
    }
}

/// La grabadora flotante de la nota de una clase.
@MainActor
final class GrabadoraDeClase: ObservableObject {
    static let compartida = GrabadoraDeClase()
    @Published private(set) var clase = ""
    @Published private(set) var grabando = false
    @Published private(set) var dicho: String?
    private var grabadora: AVAudioRecorder?
    private var panel: PanelFlotanteVoz?

    func empezar(_ nota: NotaDeClase) {
        clase = nota.clase
        dicho = nil
        mostrar()
        Task {
            guard await GrabadoraVoz.permisoMicrofono() else {
                dicho = "Sin permiso para el micrófono"
                return
            }
            let ajustes: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100,
                                          AVNumberOfChannelsKey: 1,
                                          AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue]
            // Primero aparte: si se cancela, la nota de antes sigue.
            let destino = URL(fileURLWithPath: nota.ruta)
            let tmp = destino.deletingPathExtension().appendingPathExtension("parte.m4a")
            guard let g = try? AVAudioRecorder(url: tmp, settings: ajustes), g.record() else {
                dicho = "No se pudo grabar"
                return
            }
            grabadora = g
            grabando = true
        }
    }

    func parar(guardar: Bool) {
        guard let g = grabadora else {
            cerrar()
            return
        }
        g.stop()
        grabadora = nil
        grabando = false
        let tmp = g.url
        let destino = tmp.deletingPathExtension().deletingPathExtension().appendingPathExtension("m4a")
        if guardar {
            try? FileManager.default.removeItem(at: destino)
            if (try? FileManager.default.moveItem(at: tmp, to: destino)) != nil {
                dicho = "Guardada para la próxima clase de \(clase)"
            } else {
                dicho = "No se pudo guardar"
            }
        } else {
            try? FileManager.default.removeItem(at: tmp)
            dicho = "Descartada"
        }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            cerrar()
        }
    }

    private func cerrar() {
        panel?.orderOut(nil)
    }

    private func mostrar() {
        let p = panel ?? {
            let p = PanelFlotanteVoz.nuevo(NSSize(width: 300, height: 120))
            p.contentView = NSHostingView(rootView: VistaGrabadoraDeClase(g: self))
            p.colocar("PixPinGrabadoraDeClase")
            p.alTeclear = { [weak self] e in
                MainActor.assumeIsolated {
                    guard let self else { return false }
                    switch e.keyCode {
                    case 53: self.parar(guardar: false)
                    case 36, 76: self.parar(guardar: true)
                    default: return false
                    }
                    return true
                }
            }
            return p
        }()
        panel = p
        p.makeKeyAndOrderFront(nil)
    }
}

struct VistaGrabadoraDeClase: View {
    @ObservedObject var g: GrabadoraDeClase

    var body: some View {
        VStack(spacing: 10) {
            Text("Nota de voz para la próxima clase").font(.caption).foregroundStyle(.secondary)
            Text(g.clase).font(.headline)
            if let d = g.dicho {
                Text(d).font(.callout)
            } else {
                HStack {
                    Image(systemName: "mic.fill").foregroundStyle(g.grabando ? .red : .secondary)
                    Text(g.grabando ? "Grabando…" : "Preparando…")
                    Spacer()
                    Button("Descartar (⎋)") { g.parar(guardar: false) }
                    Button("Guardar (↩)") { g.parar(guardar: true) }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(14)
        .frame(width: 300)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
