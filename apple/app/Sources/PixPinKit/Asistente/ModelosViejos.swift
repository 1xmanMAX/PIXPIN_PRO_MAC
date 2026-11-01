// **Lo que quedo bajado del asistente local** (Windows
// `asistente/modelos_viejos.rs`, 27-oct-2026).
//
// El asistente contesta solo con la nube (como Windows y Android): el
// `llama-server` de llama.cpp y los modelos (Qwen3.5 2B/0.8B, Gemma 4 E2B)
// que se bajaban a `<datos>/modelos` ya no se usan, y ocupan de 1 a 7 GB.
// Como en Windows, **se pregunta una vez**: la ventana del asistente dice
// cuanto ocupan y ofrece «Liberar» (borra solo esa carpeta) o «Dejarlos»
// (no vuelve a avisar); Ajustes → Asistente tiene el boton mientras quede
// algo. Lo de medir y borrar es del nucleo (`iaModelosViejos*`).

import Foundation
import PixPinCore
import SwiftUI

/// Donde el Mac bajaba el asistente local (`<datos>/modelos`). Era solo
/// suya: lo demas (Whisper, las voces...) vive en otras carpetas.
public func carpetaDeModelosViejos() -> URL {
    carpetaDeDatos().appendingPathComponent("modelos", isDirectory: true)
}

@MainActor
public final class ModelosViejos: ObservableObject {
    public static let compartidos = ModelosViejos()

    /// Lo que ocupan si aun no se dijo «Dejarlos» (la tarjeta del asistente).
    @Published public private(set) var porAvisar: UInt64?
    /// Lo que ocupan, se dijera o no (el boton de Ajustes).
    @Published public private(set) var ocupan: UInt64?
    /// Lo dicho al liberar: listo, o que no se pudo.
    @Published public private(set) var aviso: String?
    @Published public private(set) var borrando = false

    let carpeta: URL

    init(carpeta: URL = carpetaDeModelosViejos()) {
        self.carpeta = carpeta
    }

    /// Vuelve a mirar el disco, fuera del hilo principal (el nucleo recuerda
    /// lo medido 30 s).
    public func mirar() async {
        let c = carpeta.path
        let (avisar, total) = await Task.detached(priority: .utility) {
            (iaModelosViejosPorAvisar(carpeta: c), iaModelosViejosOcupan(carpeta: c))
        }.value
        porAvisar = avisar
        ocupan = total
    }

    /// «Dejarlos»: la tarjeta no vuelve a salir (el boton de Ajustes sigue).
    public func dejarlos() {
        iaModelosViejosNoAvisar(carpeta: carpeta.path)
        porAvisar = nil
    }

    /// «Liberar»: la carpeta entera fuera.
    public func liberar() async {
        guard !borrando else { return }
        borrando = true
        let c = carpeta.path
        let r: Result<UInt64, Error> = await Task.detached(priority: .utility) {
            Result { try iaModelosViejosBorrar(carpeta: c) }
        }.value
        borrando = false
        switch r {
        case .success:
            aviso = "Listo: los modelos locales se borraron y el espacio quedó libre."
        case .failure:
            aviso = "No se pudieron borrar todos los modelos locales. Cierra lo que los use y prueba otra vez desde Ajustes → Asistente."
        }
        await mirar()
    }

    /// «1,9 GB», «740 MB», como Windows.
    nonisolated static func tamano(_ bytes: UInt64) -> String {
        iaTamanoEnDisco(bytes: bytes)
    }
}

/// La tarjeta de la ventana del asistente: una vez, mientras quede algo.
struct TarjetaModelosViejos: View {
    @ObservedObject var viejos: ModelosViejos

    var body: some View {
        if let b = viejos.porAvisar {
            let tamano = ModelosViejos.tamano(b)
            VStack(alignment: .leading, spacing: 8) {
                Label("Los modelos locales ya no se usan", systemImage: "externaldrive.badge.minus")
                    .font(.headline)
                Text("El asistente contesta ahora solo con la nube (Claude o DeepSeek). Lo que bajaste para el modelo de este Mac sigue ocupando \(tamano) en el disco.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Liberar \(tamano)") { Task { await viejos.liberar() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(viejos.borrando)
                    Button("Dejarlos") { viejos.dejarlos() }
                        .disabled(viejos.borrando)
                    if viejos.borrando { ProgressView().controlSize(.small) }
                }
            }
            .padding(12)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        } else if let aviso = viejos.aviso {
            Text(aviso).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// El boton de Ajustes → Asistente («Modelos locales antiguos»).
struct FilaModelosViejos: View {
    @ObservedObject var viejos = ModelosViejos.compartidos

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if let b = viejos.ocupan {
                Button("Liberar \(ModelosViejos.tamano(b))") { Task { await viejos.liberar() } }
                    .buttonStyle(BotonAjustes())
                    .disabled(viejos.borrando)
            } else {
                Text("Nada que liberar").font(.caption).foregroundStyle(.secondary)
            }
            if let aviso = viejos.aviso {
                Text(aviso).font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 260, alignment: .trailing)
            }
        }
        .task { await viejos.mirar() }
    }
}
