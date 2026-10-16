// **Una conversacion de varias personas, grabada por turnos y pasada a
// texto con nombres** (tanda E5). Es `conversacion.rs` de Windows y
// `ConversacionActivity.kt` del movil.
//
// Se dice cuantos hablan (2 a 9) y como se llaman, y cada uno dice cuando
// le toca: asi se sabe quien dijo cada cosa sin adivinarlo por la voz. Como
// en Windows, se graba **sin parar** (un solo `.m4a`) y las teclas **1..9**
// dicen quien habla desde ese momento; **0** es «no habla nadie» (eso no
// sale en el texto). Tambien vale pulsar la ficha de la persona.
//
// Al terminar entra en el chat como `VOZ` con `turnos` (los campos del
// movil) y se pasa a texto turno a turno: `[0:12] **Pepe:** …`.
//
// Teclado: preparando, Tab (⇧Tab) cambia de nombre, Intro empieza y Esc
// cierra; grabando, 1–9 y 0, Intro termina y Esc cierra (tira lo grabado).

import AppKit
import PixPinCore
import SwiftUI

enum ConversacionPorTurnos {
    /// Cuantos pueden hablar: del 2 al 9, una tecla por persona.
    static let maximo = 9

    /// Los colores del movil (`COLORES`), y tres mas para llegar a nueve.
    static let colores: [UInt32] = [0x1E88E5, 0xE53935, 0x43A047, 0xFB8C00, 0x8E24AA, 0x00897B, 0x6D4C41,
                                    0xD81B60, 0x3949AB]

    /// Como se llama la persona `i`: lo escrito, o «Persona 2».
    static func nombre(_ nombres: [String], _ i: Int) -> String {
        let n = nombres.indices.contains(i) ? nombres[i].trimmingCharacters(in: .whitespaces) : ""
        return n.isEmpty ? "Persona \(i + 1)" : n
    }

    /// Lo que hace una tecla grabando: 1..9 una persona (fila de arriba o
    /// teclado numerico) y 0 nadie. `nil`: no es de las suyas.
    enum Tecla: Equatable { case persona(Int), nadie }

    static func tecla(_ letra: Character?) -> Tecla? {
        guard let letra, let n = letra.wholeNumberValue, letra.isASCII else { return nil }
        return n == 0 ? .nadie : .persona(n - 1)
    }
}

@MainActor
final class ModeloConversacion: ObservableObject {
    enum Paso { case preparar, grabar }

    @Published var paso = Paso.preparar
    @Published var cuantos = 2
    @Published var nombres = Array(repeating: "", count: ConversacionPorTurnos.maximo)
    @Published private(set) var hablando: Int?
    @Published private(set) var abriendo = false
    /// `(milisegundo, quien)` de cada tecla; `quien` vacio = nadie.
    private(set) var cambios: [CambioDeTurno] = []
    let aviso = AvisoCorto()
    private let mic = MicrofonoSuelto()
    var alTerminar: ((NotaGrabada, [TurnoVoz]) -> Void)?
    var cerrar: (() -> Void)?

    var llevadoMs: Int64 { mic.llevadoMs }
    var desde: Date? { mic.desde }

    func menos() { cuantos = max(cuantos - 1, 2) }
    func mas() { cuantos = min(cuantos + 1, ConversacionPorTurnos.maximo) }

    /// Empieza a grabar (el microfono se abre sin parar la ventana).
    func empezar() {
        guard paso == .preparar, !abriendo else { return }
        abriendo = true
        let fichero = Ventanita.carpeta("conversacion").appendingPathComponent("conversacion-\(Ventanita.ahoraMs).m4a")
        Task {
            do {
                try await mic.empezar(en: fichero)
                cambios = []
                hablando = nil
                paso = .grabar
            } catch {
                aviso.decir(MicrofonoSuelto.explicar(error))
            }
            abriendo = false
        }
    }

    /// Desde ahora habla `quien` (o nadie).
    func cambiar(_ quien: Int?) {
        guard paso == .grabar, mic.grabando, hablando != quien else { return }
        if let quien, quien >= cuantos { return }
        let nombre = quien.map { ConversacionPorTurnos.nombre(nombres, $0) } ?? ""
        cambios.append(CambioDeTurno(ms: mic.llevadoMs, quien: nombre))
        hablando = quien
    }

    /// Los turnos hasta ahora (para el «N turnos» del pie).
    var turnos: [TurnoVoz] { turnosDeLaConversacion(cambios: cambios, finMs: mic.llevadoMs) }

    func terminar() {
        guard paso == .grabar else { return }
        let cambios = self.cambios
        Task {
            guard let nota = await mic.parar() else { return }
            guard nota.duracionMs >= FormatoVoz.minimoMs else {
                try? FileManager.default.removeItem(at: nota.url)
                aviso.decir("Demasiado corta: mantén pulsado un poco más.", segundos: 3)
                paso = .preparar
                return
            }
            alTerminar?(nota, turnosDeLaConversacion(cambios: cambios, finMs: nota.duracionMs))
            cerrar?()
        }
    }

    /// Cerrar sin terminar tira lo grabado: no se guarda a escondidas.
    func soltar() { mic.cancelar() }

    func tecla(_ e: NSEvent, abajo: Bool) -> Bool {
        guard abajo else { return false }
        if e.keyCode == TeclaVoz.escape { cerrar?(); return true }
        switch paso {
        case .preparar:
            // Tab, Intro y las letras los lleva la caja del nombre.
            return false
        case .grabar:
            if TeclaVoz.esIntro(e) { terminar(); return true }
            switch ConversacionPorTurnos.tecla(TeclaVoz.letra(e)) {
            case let .persona(i)?: cambiar(i)
            case .nadie?: cambiar(nil)
            case nil: return false
            }
            return true
        }
    }
}

struct VistaConversacion: View {
    @ObservedObject var m: ModeloConversacion
    @ObservedObject private var aviso: AvisoCorto
    @FocusState private var escribiendo: Int?

    init(m: ModeloConversacion) {
        self.m = m
        aviso = m.aviso
    }

    var body: some View {
        VStack(spacing: 0) {
            switch m.paso {
            case .preparar: preparar
            case .grabar: grabar
            }
        }
        .background(ColoresVoz.fondo)
    }

    private var preparar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Conversación").font(.system(size: 24)).foregroundStyle(ColoresVoz.texto).padding(.top, 36)
            Text("Se graba sin parar; cada uno pulsa su número (1 a 9) cuando empieza a hablar, y el 0 cuando no habla nadie. La transcripción sale con los nombres.")
                .font(.system(size: 14)).foregroundStyle(ColoresVoz.apagado).padding(.top, 14)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("¿Cuántas personas hablan?").font(.system(size: 16)).foregroundStyle(ColoresVoz.texto)
                Spacer()
                BotonVentanita("−", ancho: 36) { m.menos() }
                Text("\(m.cuantos)").font(.system(size: 18)).foregroundStyle(ColoresVoz.texto).frame(width: 36)
                BotonVentanita("+", ancho: 36) { m.mas() }
            }
            .padding(.top, 24)
            let columnas = m.cuantos > 5 ? 2 : 1
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columnas), spacing: 8) {
                ForEach(0..<m.cuantos, id: \.self) { i in caja(i) }
            }
            .padding(.top, 14)
            Spacer()
            if let t = aviso.texto {
                Text(t).font(.system(size: 14)).foregroundStyle(ColoresVoz.dorado).padding(.bottom, 8)
            }
            HStack {
                BotonVentanita("Cancelar", ancho: 140, alto: 44) { m.cerrar?() }
                Spacer()
                BotonVentanita(m.abriendo ? "Abriendo el micrófono…" : "Empezar a grabar", color: ColoresVoz.azul,
                         ancho: 220, alto: 44) { m.empezar() }
            }
            .padding(.bottom, 26)
        }
        .padding(.horizontal, 40)
        .onAppear { escribiendo = 0 }
    }

    private func caja(_ i: Int) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3).fill(Color(hex: ConversacionPorTurnos.colores[i])).frame(width: 6)
            Text("\(i + 1)").font(.system(size: 15)).foregroundStyle(ColoresVoz.apagado)
            TextField("", text: Binding(get: { m.nombres[i] }, set: { m.nombres[i] = String($0.prefix(30)) }),
                      prompt: Text(ConversacionPorTurnos.nombre([], i)).foregroundStyle(ColoresVoz.apagado))
                .textFieldStyle(.plain).font(.system(size: 15)).foregroundStyle(ColoresVoz.texto)
                .focused($escribiendo, equals: i)
                .onSubmit { m.empezar() }
        }
        .padding(.trailing, 10)
        .frame(height: 38)
        .background(escribiendo == i ? Color(hex: 0x2E3440) : ColoresVoz.cristal, in: RoundedRectangle(cornerRadius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture { escribiendo = i }
    }

    private var grabar: some View {
        let columnas = m.cuantos <= 2 ? m.cuantos : 3
        return VStack(spacing: 0) {
            ZStack {
                HStack {
                    if let desde = m.desde {
                        TimelineView(.periodic(from: desde, by: 1)) { _ in
                            Text("● \(FormatoVoz.marca(ms: m.llevadoMs))").font(.system(size: 18).monospacedDigit())
                                .foregroundStyle(ColoresVoz.rojo)
                        }
                    }
                    Spacer()
                }
                Text("Pulsa el número de quien habla · 0: nadie").font(.system(size: 13))
                    .foregroundStyle(ColoresVoz.apagado)
            }
            .padding(.horizontal, 20).frame(height: 56)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columnas), spacing: 12) {
                ForEach(0..<m.cuantos, id: \.self) { i in ficha(i) }
            }
            .padding(.horizontal, 18)
            .frame(maxHeight: .infinity)
            HStack {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text("\(m.turnos.count) turnos").font(.system(size: 14)).foregroundStyle(ColoresVoz.apagado)
                }
                if let t = aviso.texto {
                    Text(t).font(.system(size: 14)).foregroundStyle(ColoresVoz.dorado)
                }
                Spacer()
                BotonVentanita("Tirar", ancho: 120, alto: 44) { m.cerrar?() }
                BotonVentanita("Terminar y transcribir", color: ColoresVoz.rojo, ancho: 240, alto: 44) { m.terminar() }
            }
            .padding(.horizontal, 20).frame(height: 80)
        }
    }

    private func ficha(_ i: Int) -> some View {
        let activo = m.hablando == i
        let opacidad = activo ? 1 : m.hablando != nil ? 0.25 : 0.55
        return Button { m.cambiar(i) } label: {
            VStack(spacing: 8) {
                Text("\(i + 1)").font(.system(size: 30))
                Text(ConversacionPorTurnos.nombre(m.nombres, i)).font(.system(size: 20)).lineLimit(1)
                Text(activo ? "Hablando…" : " ").font(.system(size: 13))
            }
            .foregroundStyle(ColoresVoz.texto)
            .frame(maxWidth: .infinity, minHeight: m.cuantos > 6 ? 120 : 160)
            .background(Color(hex: ConversacionPorTurnos.colores[i], alfa: opacidad), in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain).focusable(false)
    }
}

extension ConversacionPorTurnos {
    @MainActor private static var abierta: VentanaVoz?

    @MainActor static var abierto: Bool { abierta != nil }

    /// **Abre la conversacion por turnos.** La grabacion llega por
    /// `alTerminar` con sus turnos; cerrar sin terminar no manda nada.
    @MainActor
    static func abrir(alTerminar: @escaping (NotaGrabada, [TurnoVoz]) -> Void) {
        if let abierta {
            abierta.makeKeyAndOrderFront(nil)
            return
        }
        let m = ModeloConversacion()
        m.alTerminar = alTerminar
        let v = VentanaVoz.nueva("Conversación", tam: NSSize(width: 920, height: 660), vista: VistaConversacion(m: m))
        v.alTeclear = { e, abajo in MainActor.assumeIsolated { m.tecla(e, abajo: abajo) } }
        m.cerrar = { [weak v] in v?.close() }
        v.alCerrar = {
            MainActor.assumeIsolated {
                m.soltar()
                abierta = nil
            }
        }
        abierta = v
        v.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
