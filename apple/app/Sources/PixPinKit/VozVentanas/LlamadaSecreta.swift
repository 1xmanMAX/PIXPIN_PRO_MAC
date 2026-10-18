// **La llamada secreta** (tanda E5): una nota de voz con hora suena como si
// llamaran. Es `llamada.rs` de Windows y `LlamadaSecretaActivity.kt` del
// movil; lo que no es ventana (si un recordatorio es una llamada, quien
// llama) esta en el nucleo (`llamada.rs`).
//
// - **Sonando**: una ventanita «Llamada entrante» encima de todo, abajo a
//   la derecha, con quien llama, Contestar y Colgar, y un tono de llamada en
//   bucle (los del Mac, `ToneLibrary`). Si nadie contesta en 45 s se corta y
//   queda dicho como «Llamada perdida · <quien>» en la ventanita de avisos,
//   con «+10 min» y «Abrir».
// - **Contestada**: la nota suena con el reloj de la llamada y cuelga sola
//   al acabar. **Lo que cambia en el Mac**: no tiene una salida «de
//   llamadas» aparte (la `eCommunications` de Windows, el auricular del
//   movil); la nota sale por la salida de siempre **bajita**, para que no
//   la oiga quien este alrededor, y «Altavoz» la sube.
// - **Volver a llamar en** 5 min, 15, 30, 1 h o 2 h (sonando o ya
//   contestada): la misma alarma a otra hora (`volverARecordar`) y cuelga.
//
// Teclado: Intro contesta, Esc cuelga.
//
// **El horario de clases** (Windows, 17-oct) llama con la misma tarjeta:
// debajo del nombre, la hora y el aula (`detalle`); al contestar suena la
// nota de voz de la clase, si la hay, y despues la voz de la app lee lo
// apuntado con `>` (`texto`). «Volver a llamar en» lo pospone en memoria.

import AppKit
import AVFoundation
import PixPinCore
import SwiftUI

// MARK: - Lo puro

enum Llamada {
    /// Cuanto suena antes de darla por perdida (`SEGUNDOS_SONANDO`).
    static let segundosSonando: TimeInterval = 45
    /// Lo que tarda en colgar sola tras acabar la nota.
    static let colgarTras: TimeInterval = 0.9
    /// Los minutos de «Volver a llamar en» (`VOLVER_EN` del movil).
    static let volverEn = [5, 15, 30, 60, 120]
    /// El volumen «al oido» y el del altavoz.
    static let volumenAlOido: Float = 0.3
    static let volumenAltavoz: Float = 1

    enum Fase: Equatable { case sonando, contestada }

    /// «5 min» o «1 h», como el movil.
    static func rotulo(deVolver minutos: Int) -> String {
        minutos < 60 ? "\(minutos) min" : "\(minutos / 60) h"
    }

    /// La hora a la que vuelve a llamar si se pide en `minutos`.
    static func horaDeVolver(_ ahora: Date, minutos: Int) -> Date {
        ahora.addingTimeInterval(TimeInterval(minutos) * 60)
    }

    /// Si toca colgar sola: sonando demasiado, o la nota ya acabo hace un
    /// rato.
    static func tocaColgar(_ fase: Fase, desde: Date, ahora: Date, acaboEn: Date?) -> Bool {
        // En milisegundos enteros: restar fechas deja decimales sueltos.
        func ms(_ a: Date, _ b: Date) -> Int { Int((a.timeIntervalSince(b) * 1000).rounded()) }
        switch fase {
        case .sonando: return ms(ahora, desde) >= Int(segundosSonando * 1000)
        case .contestada: return acaboEn.map { ms(ahora, $0) >= Int(colgarTras * 1000) } ?? false
        }
    }

    /// La ventanita: abajo a la derecha de la pantalla del raton (`area` es
    /// su `visibleFrame`, con el origen abajo como en AppKit).
    static func marco(en area: CGRect) -> CGRect {
        let (w, h): (CGFloat, CGFloat) = (340, 520)
        return CGRect(x: area.maxX - w - 24, y: area.minY + 24, width: w, height: h)
    }

    /// El tono de llamada del Mac que haya, por orden de preferencia; si no,
    /// un sonido del sistema.
    static func tono() -> URL? {
        let tonos = "/System/Library/PrivateFrameworks/ToneLibrary.framework/Versions/A/Resources/Ringtones"
        let candidatos = ["\(tonos)/Opening.m4r", "\(tonos)/Reflection.m4r", "\(tonos)/Apex.m4r",
                          "/System/Library/Sounds/Submarine.aiff", "/System/Library/Sounds/Glass.aiff"]
        return candidatos.first { FileManager.default.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    /// Lo que se lee de quien llama (vacio: «Llamada»).
    static func titulo(_ nombre: String) -> String {
        let n = nombre.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "Llamada" : n
    }

    /// Si un recordatorio que vencio a las `cuando` aun suena como llamada
    /// al verlo `ahora`: lo que vencio con la app cerrada hace rato ya es
    /// una llamada perdida.
    static func aunSuena(_ cuando: Date, ahora: Date) -> Bool {
        ahora.timeIntervalSince(cuando) < 10 * 60
    }
}

// MARK: - El modelo

@MainActor
final class ModeloLlamada: ObservableObject {
    let llamada: LlamadaSecreta
    let nucleo: Nucleo
    @Published private(set) var fase = Llamada.Fase.sonando
    @Published private(set) var desde = Date()
    @Published private(set) var altavoz = false
    @Published private(set) var dicho: String?
    private var timbre: AVAudioPlayer?
    private var voz: AVAudioPlayer?
    private var acaboEn: Date?
    private var reloj: Timer?
    var cerrar: (() -> Void)?
    /// La hora y el aula de una clase (el horario).
    let detalle: String
    /// Lo que lee la voz al contestar, tras la nota (el horario).
    let textoALeer: String?
    private let habla = AVSpeechSynthesizer()
    private var leido = false

    init(_ llamada: LlamadaSecreta, nucleo: Nucleo, detalle: String = "", texto: String? = nil) {
        self.llamada = llamada
        self.nucleo = nucleo
        self.detalle = detalle
        self.textoALeer = texto
    }

    /// Si es un aviso del horario (y no la nota de un chat).
    var esDelHorario: Bool { llamada.mensaje.hasPrefix("horario:") }

    var nombre: String { Llamada.titulo(llamada.nombre) }

    /// Empieza a sonar: el tono por la salida de siempre, en bucle (una
    /// llamada se oye en el cuarto; lo secreto es lo que se dice despues).
    func sonar() {
        if let t = Llamada.tono(), let p = try? AVAudioPlayer(contentsOf: t) {
            p.numberOfLoops = -1
            p.play()
            timbre = p
        }
        desde = Date()
        let r = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.latir() }
        }
        RunLoop.main.add(r, forMode: .common)
        reloj = r
    }

    func contestar() {
        guard fase == .sonando else { return }
        timbre?.stop()
        timbre = nil
        let p = llamada.audio.isEmpty ? nil : try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: llamada.audio))
        guard p != nil || textoALeer != nil else {
            colgar()
            return
        }
        if let p {
            p.volume = Llamada.volumenAlOido
            p.play()
            voz = p
        } else {
            leer()
        }
        fase = .contestada
        desde = Date()
    }

    /// La voz de la app lee lo apuntado (una vez, tras la nota).
    private func leer() {
        guard !leido, let t = textoALeer, !t.isEmpty else { return }
        leido = true
        let u = AVSpeechUtterance(string: t)
        u.voice = AVSpeechSynthesisVoice(language: "es-ES")
        habla.speak(u)
    }

    func cambiarAltavoz() {
        guard fase == .contestada else { return }
        altavoz.toggle()
        voz?.volume = altavoz ? Llamada.volumenAltavoz : Llamada.volumenAlOido
    }

    func colgar() {
        reloj?.invalidate()
        reloj = nil
        timbre?.stop()
        voz?.stop()
        habla.stopSpeaking(at: .immediate)
        timbre = nil
        voz = nil
        cerrar?()
    }

    /// «Volver a llamar en»: la misma alarma mas tarde, y cuelga.
    func volver(en minutos: Int) {
        let cuando = Llamada.horaDeVolver(Date(), minutos: minutos)
        let (nucleo, chat, mensaje) = (self.nucleo, llamada.chat, llamada.mensaje)
        timbre?.stop()
        voz?.stop()
        habla.stopSpeaking(at: .immediate)
        if esDelHorario {
            Recordatorios.compartido.posponerHorario(id: mensaje, nombre: llamada.nombre, a: cuando)
            dicho = "Te vuelve a llamar a las \(AtajosDeHora.legible(cuando, ahora: Date()))"
            Task {
                try? await Task.sleep(for: .seconds(1.6))
                colgar()
            }
            return
        }
        Task {
            let hecho = await Task.detached(priority: .userInitiated) {
                (try? nucleo.volverARecordar(chat: chat, mensaje: mensaje, cuandoUtcMs: milisegundos(cuando))) == true
            }.value
            if hecho {
                Recordatorios.avisarCambio(chat: chat, tarea: false)
                Recordatorios.compartido.releer()
                dicho = "Te vuelve a llamar a las \(AtajosDeHora.legible(cuando, ahora: Date()))"
            } else {
                dicho = "La nota ya no está"
            }
            try? await Task.sleep(for: .seconds(1.6))
            colgar()
        }
    }

    private func latir() {
        let ahora = Date()
        if fase == .contestada, acaboEn == nil, voz?.isPlaying != true {
            // Tras la nota, la voz lee lo apuntado; acaba cuando calla.
            if textoALeer != nil, !leido { leer() }
            if !habla.isSpeaking { acaboEn = ahora }
        }
        if Llamada.tocaColgar(fase, desde: desde, ahora: ahora, acaboEn: acaboEn) {
            if fase == .sonando { perdida() }
            colgar()
        }
    }

    /// Nadie contesto: queda dicho en la ventanita de avisos, con
    /// «+10 min» (vuelve a llamar) y «Abrir».
    private func perdida() {
        let datos = [AvisosRecordatorio.claveChat: llamada.chat, AvisosRecordatorio.claveId: llamada.mensaje]
        CentroAvisos.compartido.mostrarEnLaApp(
            Aviso(id: AvisosRecordatorio.identificador(chat: llamada.chat, id: llamada.mensaje),
                  categoria: .recordatorio, titulo: "Llamada perdida", texto: "Llamada perdida · \(nombre)",
                  datos: datos),
            sonar: false)
    }

    func tecla(_ e: NSEvent) -> Bool {
        switch e.keyCode {
        case TeclaVoz.escape: colgar()
        case TeclaVoz.intro, TeclaVoz.introNumerico: contestar()
        default: return false
        }
        return true
    }
}

// MARK: - La vista

struct VistaLlamada: View {
    @ObservedObject var m: ModeloLlamada

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if m.fase == .contestada {
                    TimelineView(.periodic(from: m.desde, by: 1)) { c in
                        Text(FormatoVoz.marca(ms: Int64(c.date.timeIntervalSince(m.desde) * 1000)))
                    }
                    .monospacedDigit()
                } else {
                    Text("Llamada entrante")
                }
            }
            .font(.system(size: 15)).foregroundStyle(ColoresVoz.texto.opacity(0.7)).padding(.top, 30)
            ZStack {
                Circle().fill(Color.white.opacity(0.12)).frame(width: 112, height: 112)
                Image(systemName: "person.fill").font(.system(size: 52)).foregroundStyle(ColoresVoz.texto)
            }
            .padding(.top, 26)
            Text(m.nombre).font(.system(size: 24)).foregroundStyle(ColoresVoz.texto).lineLimit(2)
                .multilineTextAlignment(.center).padding(.horizontal, 16).padding(.top, 18)
            if !m.detalle.isEmpty {
                Text(m.detalle).font(.system(size: 14)).foregroundStyle(ColoresVoz.texto.opacity(0.75))
                    .multilineTextAlignment(.center).padding(.horizontal, 16).padding(.top, 6)
            }
            Spacer()
            if let dicho = m.dicho {
                Text(dicho).font(.system(size: 14)).foregroundStyle(ColoresVoz.texto).padding(.bottom, 20)
            } else {
                volver
            }
            redondos.padding(.bottom, 30)
        }
        .frame(width: 340, height: 520)
        .background(
            VStack(spacing: 0) {
                Color(hex: 0x101A33).frame(height: 276)
                Color(hex: 0x05070F)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var volver: some View {
        VStack(spacing: 10) {
            Text("Volver a llamar en").font(.system(size: 13)).foregroundStyle(ColoresVoz.texto.opacity(0.7))
            HStack(spacing: 0) {
                ForEach(Llamada.volverEn, id: \.self) { min in
                    Spacer(minLength: 0)
                    Button { m.volver(en: min) } label: {
                        Text(Llamada.rotulo(deVolver: min)).font(.system(size: 13)).foregroundStyle(ColoresVoz.texto)
                            .padding(.horizontal, 10).padding(.vertical, 9)
                            .background(Color.white.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(.plain).focusable(false)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.bottom, 34)
    }

    private var redondos: some View {
        HStack {
            if m.fase == .sonando {
                redondo("phone.down.fill", fondo: ColoresVoz.rojo, rotulo: "Colgar") { m.colgar() }
                Spacer()
                redondo("phone.fill", fondo: ColoresVoz.verde, rotulo: "Contestar") { m.contestar() }
            } else {
                redondo("speaker.wave.2.fill", fondo: m.altavoz ? ColoresVoz.texto : Color.white.opacity(0.16),
                        tinta: m.altavoz ? .black : ColoresVoz.texto, rotulo: "Altavoz") { m.cambiarAltavoz() }
                Spacer()
                redondo("phone.down.fill", fondo: ColoresVoz.rojo, rotulo: "Colgar") { m.colgar() }
            }
        }
        .padding(.horizontal, 58)
    }

    private func redondo(_ icono: String, fondo: Color, tinta: Color = ColoresVoz.texto, rotulo: String,
                         accion: @escaping () -> Void) -> some View {
        VStack(spacing: 6) {
            Button(action: accion) {
                Image(systemName: icono).font(.system(size: 28)).foregroundStyle(tinta)
                    .frame(width: 72, height: 72).background(fondo, in: Circle())
            }
            .buttonStyle(.plain).focusable(false)
            Text(rotulo).font(.system(size: 13)).foregroundStyle(ColoresVoz.texto.opacity(0.7))
        }
    }
}

// MARK: - Sonar

extension Llamada {
    /// Las que estan sonando ahora, por mensaje (dos a la vez se apilan).
    @MainActor private static var sonando: [String: PanelFlotanteVoz] = [:]

    /// **Hace sonar la llamada**: la ventanita encima de todo.
    @MainActor
    static func sonar(_ l: LlamadaSecreta, nucleo: Nucleo, detalle: String = "", texto: String? = nil) {
        let clave = l.chat + "\u{0}" + l.mensaje
        guard sonando[clave] == nil else { return }
        let m = ModeloLlamada(l, nucleo: nucleo, detalle: detalle, texto: texto)
        let p = PanelFlotanteVoz.nuevo(NSSize(width: 340, height: 520))
        p.contentView = NSHostingView(rootView: VistaLlamada(m: m))
        p.level = .statusBar
        let pantalla = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let pantalla {
            var marco = marco(en: pantalla.visibleFrame)
            marco.origin.y += CGFloat(sonando.count) * 30
            p.setFrame(marco, display: false)
        }
        p.alTeclear = { e in MainActor.assumeIsolated { m.tecla(e) } }
        m.cerrar = { [weak p] in
            p?.orderOut(nil)
            sonando[clave] = nil
        }
        sonando[clave] = p
        p.orderFrontRegardless()
        p.makeKey()
        m.sonar()
    }
}
