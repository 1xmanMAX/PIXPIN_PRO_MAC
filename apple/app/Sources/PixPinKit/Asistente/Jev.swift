// **Jev de TypeSafe en el Mac** (Windows 28-oct-2026, `docs/jev.md`): su
// clave en Ajustes → Asistente, los textos de Windows (los de
// `pixpin-store/i18n`, por el nucleo) y los puntitos del estado de Claude,
// DeepSeek y Jev junto al boton de sincronizar (Windows 851979e).
//
// Lo que pregunta cada funcion (lo importante de una clase, Anki, la
// prioridad de las tareas, el modelo del asistente) vive en el nucleo de
// Rust (`pixpin-nucleo/src/jev*`); aqui solo se pinta. La red es la de
// `TransporteHttps` y la clave va al Llavero (`LlaveroDelSistema`).

import AppKit
import PixPinCore
import SwiftUI

/// Los textos de Jev en el idioma de la app (los de Windows).
enum JevTextos {
    static let idioma = Locale.preferredLanguages.first ?? "es"
    static let actuales = textosDeJev(locale: idioma)
}

/// **La clave de TypeSafe** (la fila «Clave de TypeSafe (Jev)»): pegarla y
/// guardarla en el Llavero, ver la que hay (enmascarada), probarla con la
/// lista de modelos (no gasta) y borrarla. Como `ClaveNube`.
struct ClaveJev: View {
    @State private var escrita = ""
    @State private var guardada: String?
    @State private var aviso: String?
    /// La ultima prueba: en curso (`nil` dentro) o su resultado.
    @State private var prueba: Result<String, Error>??

    private var t: TextosJev { JevTextos.actuales }

    private var probando: Bool {
        if case .some(.none) = prueba { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if let guardada {
                HStack(spacing: 8) {
                    Text(guardada).font(.system(.caption, design: .monospaced)).foregroundStyle(Paleta.v2.verde)
                    Button(t.borrar) { borrar() }.buttonStyle(BotonAjustes())
                }
            }
            switch prueba {
            case .some(.none):
                HStack(spacing: 6) { ProgressView().controlSize(.mini); Text(t.probando).font(.caption) }
                    .foregroundStyle(Paleta.v2.gris)
            case let .some(.some(.success(modelo))):
                Text("✓ " + textoJevProbada(locale: JevTextos.idioma, modelo: modelo))
                    .font(.caption).foregroundStyle(Paleta.v2.verde)
            case let .some(.some(.failure(e))):
                Text("⚠️ " + ModeloAjustes.texto(de: e)).font(.caption).foregroundStyle(Paleta.v2.rojo)
            case .none:
                EmptyView()
            }
            HStack(spacing: 6) {
                SecureField(t.claveMarcador, text: $escrita)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .onSubmit(guardarYProbar)
                // Vacio con una guardada: la vuelve a probar (Windows).
                Button(t.guardarYProbar, action: guardarYProbar)
                    .buttonStyle(BotonAjustes())
                    .disabled(probando || (escrita.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && guardada == nil))
            }
            if let aviso { Text(aviso).font(.caption).foregroundStyle(Paleta.v2.rojo) }
        }
        .onAppear(perform: leer)
    }

    private func leer() {
        guardada = jevClaveEnmascarada()
    }

    private func guardarYProbar() {
        LlaveroDelSistema.instalar()
        let clave = escrita.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clave.isEmpty {
            do {
                try jevGuardarClave(clave: clave)
                escrita = ""
                aviso = nil
            } catch {
                aviso = ModeloAjustes.texto(de: error)
                leer()
                return
            }
        }
        leer()
        guard guardada != nil else { return }
        prueba = .some(nil)
        TransporteHttps.instalar()
        Task {
            let r = await Task.detached(priority: .userInitiated) {
                Result { try jevProbarClave() }
            }.value
            prueba = .some(r)
        }
    }

    private func borrar() {
        do {
            try jevBorrarClave()
            aviso = nil
            prueba = nil
        } catch {
            aviso = ModeloAjustes.texto(de: error)
        }
        leer()
    }
}

// MARK: - Los puntitos del estado de las IA

/// **Lo que se sabe de Claude, DeepSeek y Jev** (el nucleo:
/// `jev/estado_ia.rs`). Mira cada dos segundos si cambio algo y entonces
/// relee; la comprobacion de verdad la hace el hilo del nucleo.
@MainActor
final class EstadoDeLasIa: ObservableObject {
    static let compartido = EstadoDeLasIa()

    @Published private(set) var estado: EstadoIa
    private var visto: UInt64 = .max
    private var reloj: Timer?

    private init() {
        estado = iaEstado(locale: JevTextos.idioma)
    }

    /// Arranca el estado del nucleo (una vez) y el vistazo de aqui.
    func arrancar() {
        guard reloj == nil else { return }
        LlaveroDelSistema.instalar()
        TransporteHttps.instalar()
        iaEstadoArrancar()
        releer()
        reloj = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { EstadoDeLasIa.compartido.releer() }
        }
    }

    func releer() {
        let n = iaEstadoNovedades()
        // Cada minuto aunque no cambie nada: el «hace N min» avanza.
        let minuto = UInt64(Date().timeIntervalSince1970 / 60)
        let firma = n &+ minuto &* 1_000_003
        guard firma != visto else { return }
        visto = firma
        estado = iaEstado(locale: JevTextos.idioma)
    }

    func comprobarAhora() {
        iaEstadoComprobarAhora()
        releer()
    }
}

/// **Los tres puntitos** a la izquierda del boton de sincronizar: Claude,
/// DeepSeek y Jev de arriba abajo. Verde, funciona; rojo, falla; aro rojo,
/// sin clave; gris, con clave y sin comprobar. Encima, cada uno con su
/// frase; al pulsar, el menu con «Comprobar ahora» y las claves.
struct PuntitosIa: View {
    @ObservedObject private var e = EstadoDeLasIa.compartido
    @Environment(\.colorScheme) private var esquema

    private func color(_ luz: LuzIa) -> Color {
        // Los de Windows; de noche, un punto mas claros.
        let noche = esquema == .dark
        switch luz {
        case .verde: return Color(hex: noche ? 0x66BB6A : 0x43A047)
        case .roja, .hueca: return Color(hex: noche ? 0xEF5350 : 0xE53935)
        case .gris: return Color.secondary.opacity(0.55)
        }
    }

    @ViewBuilder private func punto(_ luz: LuzIa, lado: CGFloat) -> some View {
        if luz == .hueca {
            Circle().strokeBorder(color(luz), lineWidth: max(1, lado * 0.25)).frame(width: lado, height: lado)
        } else {
            Circle().fill(color(luz)).frame(width: lado, height: lado)
        }
    }

    private var globo: String {
        (e.estado.servicios.map(\.linea) + [e.estado.pista]).joined(separator: "\n")
    }

    var body: some View {
        Menu {
            ForEach(e.estado.servicios, id: \.id) { s in
                Button(s.linea) { abrirLasClaves() }
            }
            Divider()
            Button {
                e.comprobarAhora()
            } label: {
                Label(e.estado.comprobar, systemImage: "arrow.clockwise")
            }
            Button {
                abrirLasClaves()
            } label: {
                Label(e.estado.claves, systemImage: "gearshape")
            }
        } label: {
            VStack(spacing: 3) {
                ForEach(e.estado.servicios, id: \.id) { s in punto(s.luz, lado: 6) }
            }
            .padding(.horizontal, 3)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(globo)
        .accessibilityLabel(globo)
        .onAppear { e.arrancar() }
    }

    /// Ajustes → Asistente (donde estan las claves).
    private func abrirLasClaves() {
        ComandosApp.abrirAjustes?()
        VentanaAsistente.irAAjustes()
    }
}

// MARK: - La prioridad de Jev en Tareas

extension Tarea {
    /// La chapita de la prioridad de Jev («✦ Urgente»), si la hay y el
    /// usuario no marco la suya (lo suyo manda; «normal» no se ensena).
    var chapitaDeJev: (texto: String, color: UInt32)? {
        let t = JevTextos.actuales
        switch prioridad {
        case "urgente"?: return ("✦ " + t.prioridadUrgente, 0xE5534B)
        case "alta"?: return ("✦ " + t.prioridadAlta, 0xE8A33D)
        case "baja"?: return ("✦ " + t.prioridadBaja, 0x8B949E)
        default: return nil
        }
    }
}
