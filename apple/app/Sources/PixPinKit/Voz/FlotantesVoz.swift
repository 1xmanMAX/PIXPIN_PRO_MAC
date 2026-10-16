// **El reproductor y el microfono flotantes** (tanda D3): las dos
// ventanitas de Windows (`ventana_chat/reproductor_flotante.rs` y
// `microfono_flotante.rs`), siempre encima y sin abrir el chat.
//
// - **Reproductor flotante**: un audio suena con su barra (atras 10, play o
//   pausa, adelante 10, la pista con su bolita, la velocidad y el aspa). Uno
//   solo: otro audio cambia la pista. Varios a la vez esperan en fila y
//   suenan seguidos. Al acabar el ultimo se va sola; en pausa se queda.
//   Espacio pausa o sigue, ← / → saltan 10 s y ⎋ la cierra.
// - **Microfono flotante**: graba con el microfono grande en rojo, un aro
//   que late y el tiempo; un clic en cualquier sitio (o ↩) la para y la
//   guarda en el proyecto; ⎋ la tira sin preguntar. Guardada, ofrece
//   «Convertir en llamada» —la hora, que nace una hora mas tarde y en punto,
//   con «En 15 min», «En 1 hora» y «Mañana 9:00», ↑ / ↓ de cinco en cinco
//   minutos y la hora tecleada— o «Listo»; si nadie toca nada se va sola a
//   los 10 s. La llamada es el recordatorio del mensaje (`recuerdaEn`, el
//   que viaja), como «Recordármelo» del chat.

import AppKit
import PixPinCore
import SwiftUI

/// Un panel flotante que si coge el teclado (sin activar la app entera).
final class PanelFlotanteVoz: NSPanel {
    var alTeclear: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if alTeclear?(event) == true { return }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        if let e = NSApp.currentEvent, alTeclear?(e) == true { return }
    }

    static func nuevo(_ tam: NSSize) -> PanelFlotanteVoz {
        let p = PanelFlotanteVoz(contentRect: NSRect(origin: .zero, size: tam),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        return p
    }

    /// Abajo a la derecha de la pantalla del raton, o donde se dejo.
    func colocar(_ autoguardado: String) {
        if !setFrameUsingName(autoguardado),
           let pantalla = (NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main) {
            let v = pantalla.visibleFrame
            setFrameOrigin(NSPoint(x: v.maxX - frame.width - 24, y: v.minY + 24))
        }
        setFrameAutosaveName(autoguardado)
    }
}

// MARK: - El reproductor flotante

@MainActor
public final class ReproductorFlotante {
    public static let compartido = ReproductorFlotante()
    private var panel: PanelFlotanteVoz?
    private var vigia: Any?
    private var cierre: DispatchWorkItem?

    /// **Hace sonar `pistas`** en el flotante: la abre o, si ya esta, le
    /// cambia la fila.
    public func abrir(_ pistas: [Pista]) {
        let r = ReproductorVoz.compartido
        r.poner(pistas)
        guard r.hayAlgo else { return NSSound.beep() }
        cierre?.cancel()
        let p = panel ?? crear()
        panel = p
        p.makeKeyAndOrderFront(nil)
    }

    public var abierto: Bool { panel?.isVisible == true }

    private func crear() -> PanelFlotanteVoz {
        let vista = NSHostingView(rootView: VistaReproductorFlotante { [weak self] in self?.cerrar() })
        let p = PanelFlotanteVoz.nuevo(vista.fittingSize)
        p.contentView = vista
        p.setContentSize(NSSize(width: 380, height: max(vista.fittingSize.height, 92)))
        p.colocar("PixPinReproductorFlotante")
        p.alTeclear = { [weak self] e in self?.tecla(e) ?? false }
        // Al acabar el ultimo se va sola (con la barra llena un momento);
        // si se para desde otro sitio, tambien.
        let r = ReproductorVoz.compartido
        vigia = r.$sonando.combineLatest(r.$actual, r.$acabadas).receive(on: DispatchQueue.main)
            .sink { [weak self] sonando, actual, _ in
                MainActor.assumeIsolated { self?.mirar(sonando: sonando, actual: actual) }
            }
        return p
    }

    private func mirar(sonando: Bool, actual: String?) {
        guard abierto else { return }
        let r = ReproductorVoz.compartido
        if actual == nil {
            cerrar()
        } else if !sonando, r.cola.isEmpty, r.posicionMs == 0, r.acabadas > 0 {
            // Acabo (se quedo al principio sin sonar): fuera en 0,7 s.
            let t = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    if !ReproductorVoz.compartido.sonando { self?.panel?.orderOut(nil) }
                }
            }
            cierre = t
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: t)
        } else if sonando {
            cierre?.cancel()
        }
    }

    /// El aspa o ⎋: para y se va.
    func cerrar() {
        cierre?.cancel()
        panel?.orderOut(nil)
        if ReproductorVoz.compartido.hayAlgo { ReproductorVoz.compartido.parar() }
    }

    /// Espacio, ← / → y ⎋, como en Windows.
    func tecla(_ e: NSEvent) -> Bool {
        let r = ReproductorVoz.compartido
        switch e.keyCode {
        case 49: if r.sonando { r.pausar() } else { r.seguir() }
        case 123: r.atras()
        case 124: r.adelante()
        case 53: cerrar()
        default: return false
        }
        return true
    }
}

/// Dos filas: el titulo y el tiempo (por aqui se arrastra) con el aspa; y el
/// transporte, la pista y la velocidad.
struct VistaReproductorFlotante: View {
    let cerrar: () -> Void
    @ObservedObject private var r = ReproductorVoz.compartido

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "waveform").foregroundStyle(Color.accentColor)
                Text(r.titulo).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                TiempoReproductor()
                if !r.cola.isEmpty {
                    Text("+\(r.cola.count)").font(.caption2).foregroundStyle(.secondary).help("En la fila")
                }
                Button(action: cerrar) { Image(systemName: "xmark").frame(width: 22, height: 22) }
                    .buttonStyle(.plain)
                    .help("Cerrar (⎋)")
            }
            HStack(spacing: 4) {
                boton("gobackward.10", "Atrás 10 s (←)") { r.atras() }
                boton(r.sonando ? "pause.fill" : "play.fill", "Pausa o seguir (espacio)") {
                    if r.sonando { r.pausar() } else { r.seguir() }
                }
                boton("goforward.10", "Adelante 10 s (→)") { r.adelante() }
                PistaAvance().padding(.horizontal, 4)
                Button { r.otraVelocidad() } label: {
                    Text(VozAlta.rotulo(r.velocidad))
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color.accentColor)
                        .frame(minWidth: 40, minHeight: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Velocidad")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 380)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func boton(_ simbolo: String, _ ayuda: String, _ accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            Image(systemName: simbolo).font(.system(size: 15)).frame(width: 30, height: 26).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(ayuda)
    }
}

// MARK: - La hora de la llamada (puro)

/// **El selector de la hora**, en hora local (`Selector` de Windows). Puro,
/// para probarlo.
struct SelectorHora: Equatable {
    /// La hora elegida. Siempre en el futuro.
    var cuando: Date
    /// Lo tecleado a medias («18», «183», «18:3»).
    var escrito = ""
    var calendario: Calendar = .current

    /// Como el `TimePicker` del movil: **una hora mas tarde, en punto**.
    static func nuevo(_ ahora: Date, calendario: Calendar = .current) -> SelectorHora {
        let hora = (calendario.component(.hour, from: ahora) + 1) % 24
        let cuando = HorasDeRecordar.horaEscrita("\(hora):00", ahora: ahora, calendario: calendario)
            ?? ahora.addingTimeInterval(3600)
        return SelectorHora(cuando: cuando, calendario: calendario)
    }

    /// La hora y el minuto que se ensenan.
    var reloj: (hora: Int, minuto: Int) {
        let c = calendario.dateComponents([.hour, .minute], from: cuando)
        return (c.hour ?? 0, c.minute ?? 0)
    }

    /// Lleva la hora a `c` (sin segundos) y, si quedo en el pasado, al dia
    /// siguiente.
    private mutating func poner(_ c: Date, ahora: Date) {
        var c = calendario.dateInterval(of: .minute, for: c)?.start ?? c
        while c <= ahora { c = calendario.date(byAdding: .day, value: 1, to: c) ?? c.addingTimeInterval(86_400) }
        cuando = c
        escrito = ""
    }

    /// Un atajo («En 15 min», «Mañana 9:00»).
    mutating func atajo(_ c: Date, ahora: Date) { poner(c, ahora: ahora) }

    /// Una hora mas o menos, mismo minuto.
    mutating func moverHora(_ horas: Int, ahora: Date) {
        poner(cuando.addingTimeInterval(TimeInterval(horas) * 3600), ahora: ahora)
    }

    /// De cinco en cinco minutos; lo que venga de un atajo («18:47») se
    /// encaja primero en el cinco de al lado. Bajar no lleva a mañana.
    mutating func moverMinutos(_ pasos: Int, ahora: Date) {
        let resto = reloj.minuto % 5
        let delta: Int
        switch (pasos.signum(), resto) {
        case (1, 0), (-1, 0): delta = pasos * 5
        case (1, let r): delta = 5 - r + (pasos - 1) * 5
        case (-1, let r): delta = -r + (pasos + 1) * 5
        default: delta = 0
        }
        var c = cuando.addingTimeInterval(TimeInterval(delta) * 60)
        if c <= ahora, pasos < 0 { c = cuando }
        poner(c, ahora: ahora)
    }

    /// Una letra tecleada: cifras y separadores, cinco como mucho. En cuanto
    /// lo escrito es una hora, esa es la elegida.
    mutating func teclear(_ c: Character, ahora: Date) {
        guard c.isASCII, c.isNumber || c == ":" || c == ".", escrito.count < 5 else { return }
        escrito.append(c)
        releer(ahora)
    }

    mutating func borrar(ahora: Date) {
        if !escrito.isEmpty { escrito.removeLast() }
        releer(ahora)
    }

    private mutating func releer(_ ahora: Date) {
        if let c = HorasDeRecordar.horaEscrita(escrito, ahora: ahora, calendario: calendario) { cuando = c }
    }

    /// Si lo tecleado no es una hora (se dice en rojo).
    func escritoMal(ahora: Date) -> Bool {
        !escrito.isEmpty && HorasDeRecordar.horaEscrita(escrito, ahora: ahora, calendario: calendario) == nil
    }

    /// Los atajos: dentro de 15 minutos, de una hora y mañana a las 9.
    static func atajos(_ ahora: Date, calendario: Calendar = .current) -> [(titulo: String, cuando: Date)] {
        let manana = calendario.date(byAdding: DateComponents(day: 1, hour: 9), to: calendario.startOfDay(for: ahora))
            ?? ahora.addingTimeInterval(86_400)
        return [("En 15 min", ahora.addingTimeInterval(15 * 60)), ("En 1 hora", ahora.addingTimeInterval(3600)),
                ("Mañana 9:00", manana)]
    }

    static func == (a: SelectorHora, b: SelectorHora) -> Bool { a.cuando == b.cuando && a.escrito == b.escrito }
}

// MARK: - El microfono flotante

@MainActor
public final class MicrofonoFlotante: ObservableObject {
    public static let compartido = MicrofonoFlotante()

    enum Fase: Equatable {
        case abriendo
        case grabando(desde: Date)
        case guardando
        case guardada(MensajeChat, desde: Date)
        case hora(MensajeChat, SelectorHora)
        case puesta(String)
        case fallo(String)
    }

    @Published private(set) var fase: Fase = .abriendo
    private var panel: PanelFlotanteVoz?
    private var chat = ""
    private var nombreChat = ""
    private weak var almacen: Almacen?
    private var tarea: DispatchWorkItem?
    private var vigia: Any?

    /// **Graba una nota en `chat`** con el microfono flotante. Si ya graba,
    /// para y guarda (otro toque del atajo).
    public func alternar(en chat: String, nombre: String, almacen: Almacen) {
        if case .grabando = fase, panel?.isVisible == true { parar(); return }
        guard GrabadoraVoz.compartida.estado == .quieta else { return NSSound.beep() }
        self.chat = chat
        nombreChat = nombre
        self.almacen = almacen
        fase = .abriendo
        mostrar()
        let g = GrabadoraVoz.compartida
        vigia = g.$estado.receive(on: DispatchQueue.main).sink { [weak self] e in
            MainActor.assumeIsolated {
                guard let self else { return }
                if case let .grabando(c, desde) = e, c == self.chat, self.fase == .abriendo {
                    self.fase = .grabando(desde: desde)
                }
            }
        }
        Task {
            await g.empezar(en: chat, almacen: almacen)
            if g.estado == .quieta, self.fase == .abriendo {
                self.fallo(almacen.error ?? "No se pudo abrir el micrófono")
            }
        }
    }

    /// Un clic en la ventana o ↩: para y guarda.
    func parar() {
        guard case .grabando = fase, let almacen else { return }
        fase = .guardando
        let g = GrabadoraVoz.compartida
        g.alGuardar = { [weak self] m in
            guard let self else { return }
            if let m {
                self.fase = .guardada(m, desde: Date())
                self.irseEn(10)
            } else {
                self.fallo("Muy corta o no se pudo guardar")
            }
        }
        Task { await g.parar(almacen: almacen) }
    }

    /// ⎋ grabando: se tira sin preguntar.
    func tirar() {
        GrabadoraVoz.compartida.cancelar()
        cerrar()
    }

    func convertir() {
        guard case let .guardada(m, _) = fase else { return }
        tarea?.cancel()
        fase = .hora(m, SelectorHora.nuevo(Date()))
    }

    func cambiarSelector(_ cambio: (inout SelectorHora) -> Void) {
        guard case .hora(let m, var s) = fase else { return }
        cambio(&s)
        fase = .hora(m, s)
    }

    /// **La llamada**: el recordatorio del mensaje a esa hora (lo que viaja).
    func poner() {
        guard case let .hora(m, s) = fase, let almacen, !s.escritoMal(ahora: Date()) else { return NSSound.beep() }
        let chat = self.chat, cuando = s.cuando
        let ms = Int64((cuando.timeIntervalSince1970 * 1000).rounded())
        Task {
            guard await almacen.cambiar(mensaje: m.id, en: chat, .recordar(cuando: ms)) != nil else {
                self.fallo("La nota ya no está")
                return
            }
            RecordatoriosDeMensajes.programar(chat: chat, id: m.id, texto: HorasDeRecordar.resumen(de: m), cuando: cuando)
            // Quien llama queda apuntado: el nombre de la nota (E5).
            QuienLlama.alPonerLaHora(m, nucleo: almacen.nucleo)
            self.fase = .puesta("Te llamará a las \(HorasDeRecordar.legible(cuando, ahora: Date()))")
            self.irseEn(1.6)
        }
    }

    func cerrar() {
        tarea?.cancel()
        vigia = nil
        panel?.orderOut(nil)
        fase = .abriendo
    }

    private func fallo(_ texto: String) {
        fase = .fallo(texto)
        irseEn(4)
    }

    private func irseEn(_ s: TimeInterval) {
        tarea?.cancel()
        let t = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.cerrar() } }
        tarea = t
        DispatchQueue.main.asyncAfter(deadline: .now() + s, execute: t)
    }

    private func mostrar() {
        let p = panel ?? {
            let vista = NSHostingView(rootView: VistaMicrofonoFlotante(mic: self))
            let p = PanelFlotanteVoz.nuevo(NSSize(width: 300, height: 250))
            p.contentView = vista
            p.colocar("PixPinMicrofonoFlotante")
            p.alTeclear = { [weak self] e in self?.tecla(e) ?? false }
            return p
        }()
        panel = p
        p.makeKeyAndOrderFront(nil)
    }

    /// ⎋, ↩, ⌫, ↑ ↓ y las cifras de la hora, como en Windows.
    func tecla(_ e: NSEvent) -> Bool {
        let ahora = Date()
        switch (e.keyCode, fase) {
        case (53, .grabando), (53, .abriendo): tirar()
        case (53, .hora): cerrar()
        case (53, _): cerrar()
        case (36, .grabando), (76, .grabando): parar()
        case (36, .guardada), (76, .guardada): cerrar()
        case (36, .hora), (76, .hora): poner()
        case (51, .hora): cambiarSelector { $0.borrar(ahora: ahora) }
        case (126, .hora): cambiarSelector { $0.moverMinutos(1, ahora: ahora) }
        case (125, .hora): cambiarSelector { $0.moverMinutos(-1, ahora: ahora) }
        default:
            guard case .hora = fase, let c = e.characters?.first else { return false }
            cambiarSelector { $0.teclear(c, ahora: ahora) }
        }
        return true
    }

    var nombre: String { nombreChat }
}

struct VistaMicrofonoFlotante: View {
    @ObservedObject var mic: MicrofonoFlotante
    @State private var late = false
    private static let rojo = Color(red: 0xE5 / 255, green: 0x53 / 255, blue: 0x4B / 255)

    var body: some View {
        VStack(spacing: 10) {
            switch mic.fase {
            case .abriendo:
                microfono(grabando: false)
                Text("Abriendo el micrófono…").font(.caption).foregroundStyle(.secondary)
            case let .grabando(desde):
                microfono(grabando: true)
                TimelineView(.periodic(from: desde, by: 1)) { c in
                    Text(FormatoVoz.marca(ms: Int64(c.date.timeIntervalSince(desde) * 1000)))
                        .font(.system(size: 20, weight: .medium).monospacedDigit())
                        .foregroundStyle(Self.rojo)
                }
                Text("Clic para parar y guardar · ⎋ la tira").font(.caption).foregroundStyle(.secondary)
            case .guardando:
                ProgressView()
                Text("Guardando…").font(.caption)
            case .guardada:
                Image(systemName: "checkmark.circle.fill").font(.system(size: 40)).foregroundStyle(.green)
                Text("Guardada en «\(mic.nombre)»").font(.callout).multilineTextAlignment(.center)
                HStack {
                    Button("Convertir en llamada") { mic.convertir() }
                    Button("Listo") { mic.cerrar() }.keyboardShortcut(.defaultAction)
                }
            case let .hora(_, s):
                hora(s)
            case let .puesta(texto):
                Image(systemName: "phone.badge.waveform").font(.system(size: 34)).foregroundStyle(.green)
                Text(texto).font(.callout)
            case let .fallo(texto):
                Image(systemName: "exclamationmark.triangle").font(.system(size: 30)).foregroundStyle(.orange)
                Text(texto).font(.callout).multilineTextAlignment(.center)
            }
        }
        .padding(16)
        .frame(width: 300)
        .frame(minHeight: 220)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .contentShape(Rectangle())
        // El toque se coge en toda la ventana: acertarle a un boton sin
        // mirar es pedir demasiado.
        .onTapGesture { if case .grabando = mic.fase { mic.parar() } }
    }

    private func microfono(grabando: Bool) -> some View {
        ZStack {
            Circle().stroke(Self.rojo.opacity(0.5), lineWidth: 3)
                .frame(width: 96, height: 96)
                .scaleEffect(grabando && late ? 1.15 : 1)
                .opacity(grabando ? 1 : 0.3)
            Circle().fill(grabando ? Self.rojo : Color.secondary.opacity(0.4)).frame(width: 76, height: 76)
            Image(systemName: "mic.fill").font(.system(size: 32)).foregroundStyle(.white)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { late = true }
        }
    }

    private func hora(_ s: SelectorHora) -> some View {
        let ahora = Date()
        let (h, m) = s.reloj
        return VStack(spacing: 8) {
            Text("¿Cuándo te llama?").font(.callout)
            HStack(spacing: 14) {
                flechas(arriba: { mic.cambiarSelector { $0.moverHora(1, ahora: Date()) } },
                        abajo: { mic.cambiarSelector { $0.moverHora(-1, ahora: Date()) } })
                Text(String(format: "%02d:%02d", h, m))
                    .font(.system(size: 34, weight: .semibold).monospacedDigit())
                    .foregroundStyle(s.escritoMal(ahora: ahora) ? .red : .primary)
                flechas(arriba: { mic.cambiarSelector { $0.moverMinutos(1, ahora: Date()) } },
                        abajo: { mic.cambiarSelector { $0.moverMinutos(-1, ahora: Date()) } })
            }
            if !s.escrito.isEmpty {
                Text(s.escritoMal(ahora: ahora) ? "«\(s.escrito)» no es una hora" : s.escrito)
                    .font(.caption).foregroundStyle(s.escritoMal(ahora: ahora) ? .red : .secondary)
            }
            HStack(spacing: 4) {
                ForEach(SelectorHora.atajos(ahora), id: \.titulo) { a in
                    Button(a.titulo) { mic.cambiarSelector { $0.atajo(a.cuando, ahora: Date()) } }
                        .controlSize(.small)
                }
            }
            HStack {
                Button("Volver") {
                    if case let .hora(m, _) = mic.fase { mic.volver(m) }
                }
                Button("Poner") { mic.poner() }.keyboardShortcut(.defaultAction)
            }
            Text("↑↓ minutos · teclea la hora · ↩ poner").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func flechas(arriba: @escaping () -> Void, abajo: @escaping () -> Void) -> some View {
        VStack(spacing: 2) {
            Button(action: arriba) { Image(systemName: "chevron.up") }.buttonStyle(.plain)
            Button(action: abajo) { Image(systemName: "chevron.down") }.buttonStyle(.plain)
        }
    }
}

extension MicrofonoFlotante {
    /// «Volver»: a «Guardada» sin poner la hora.
    func volver(_ m: MensajeChat) {
        fase = .guardada(m, desde: Date())
    }
}
