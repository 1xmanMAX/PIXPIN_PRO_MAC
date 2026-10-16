// Los avisos de los temporizadores y las alarmas de las mini-apps: lo que en
// Windows hace el vigia de los recordatorios con el prefijo `mini:`
// (`mini_panel::avisar`, `recordatorios::agenda_de`) y en el movil una
// alarma del sistema (`MiniActivity.kt:473-520`).
//
// - **Cuando**: lo dice el nucleo (`miniCuandoAvisa`, `avisosMiniapps`), el
//   mismo calculo que Windows. Se rehace entero en cada cambio de la
//   mini-app, al arrancar y tras sincronizar.
// - **Con la hora de la pared**: cada aviso es un `DispatchSourceTimer` con
//   `wallDeadline` (cuenta con el reloj de la pared, no con ticks, asi que el
//   Mac dormido no lo retrasa) y al despertar se revisa lo que ya vencio.
// - **Con la app cerrada o dormida**: ademas va una notificacion del sistema
//   (`UNUserNotificationCenter`) a la misma hora y con el mismo
//   identificador (`mini:<id del mensaje>`), si la app va en su `.app`.
// - **Al sonar**: una ventana flotante con el titulo y «Parar», y un sonido
//   en bucle (como el pin y el globo de Windows). Una alarma se queda puesta
//   y vuelve a sonar al dia siguiente, como en Windows y el movil.
//
// Rendimiento: nada sondea. Un temporizador de despacho por aviso puesto, y
// la lectura de todos los chats va fuera del hilo principal.

import AppKit
import PixPinCore
import SwiftUI
import UserNotifications

/// La hora de la pared en milisegundos desde 1970 (la del formato).
func milisegundos(_ fecha: Date = Date()) -> Int64 {
    Int64((fecha.timeIntervalSince1970 * 1000).rounded())
}

@MainActor
public final class AvisosMini {
    public static let compartido = AvisosMini()

    /// El prefijo de los avisos de una mini-app guardada en un chat (el del
    /// movil y Windows). Las que viven solo en memoria llevan `local:`.
    nonisolated static let prefijo = "mini:"

    struct Puesto {
        let cuando: Date
        let texto: String
        let miniapp: String
        let fuente: DispatchSourceTimer
    }

    private(set) var puestos: [String: Puesto] = [:]
    private var nucleo: Nucleo?
    private var vigiaDespertar: NSObjectProtocol?
    private var permisoPedido = false
    private let delegado = DelegadoAvisos()
    private lazy var ventana = VentanaAvisoMini()

    init() {
        vigiaDespertar = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { AvisosMini.compartido.revisarVencidos() }
        }
    }

    /// Empieza a vigilar los avisos de los chats de `nucleo`. Una vez, al
    /// arrancar la app.
    public func vigilar(nucleo: Nucleo) {
        self.nucleo = nucleo
        reprogramar()
    }

    /// Vuelve a leer los avisos de todos los chats (al arrancar y tras una
    /// sincronizacion que trajo cambios) y deja puestos justo esos.
    public func reprogramar() {
        guard let nucleo else { return }
        let desfase = desfaseLocalMs()
        Task { [weak self] in
            let avisos = await Task.detached(priority: .utility) {
                (try? nucleo.avisosMiniapps(desfaseLocalMs: desfase)) ?? []
            }.value
            guard let self else { return }
            let vivos = Set(avisos.map(\.id))
            for id in self.puestos.keys where id.hasPrefix(Self.prefijo) && !vivos.contains(id) {
                self.quitar(id)
            }
            for a in avisos {
                let texto = a.texto.isEmpty ? DocumentoMini.nombre(a.miniapp) : a.texto
                self.programar(id: a.id, miniapp: a.miniapp, texto: texto,
                               cuando: fechaDe(ms: a.cuandoMs))
            }
        }
    }

    /// Pone, cambia o quita el aviso de una mini-app tras tocarla (se rehace
    /// entero, como `mini_panel::avisar` de Windows).
    func avisar(de doc: DocumentoMini) {
        guard doc.miniapp == "temporizador" || doc.miniapp == "alarma" else { return }
        let ahora = Date()
        let cuando = miniCuandoAvisa(miniapp: doc.miniapp, documento: doc.documento,
                                     ahoraMs: milisegundos(ahora), desfaseLocalMs: desfaseLocalMs(ahora))
        let texto = doc.titulo.isEmpty ? DocumentoMini.nombre(doc.miniapp) : doc.titulo
        programar(id: doc.idAviso, miniapp: doc.miniapp, texto: texto,
                  cuando: cuando.map { fechaDe(ms: $0) })
    }

    /// Deja un aviso para `cuando` (o lo quita con `nil`). Lo que ya paso no
    /// se pone: ya aviso cuando tocaba.
    func programar(id: String, miniapp: String, texto: String, cuando: Date?) {
        if let p = puestos[id], p.cuando == cuando, p.texto == texto { return }
        quitar(id)
        guard let cuando, cuando > Date() else { return }
        let fuente = DispatchSource.makeTimerSource(queue: .main)
        fuente.schedule(wallDeadline: .now() + max(0, cuando.timeIntervalSinceNow), leeway: .milliseconds(250))
        fuente.setEventHandler {
            MainActor.assumeIsolated { AvisosMini.compartido.vencer(id) }
        }
        fuente.resume()
        puestos[id] = Puesto(cuando: cuando, texto: texto, miniapp: miniapp, fuente: fuente)
        notificar(id: id, miniapp: miniapp, texto: texto, cuando: cuando)
    }

    func quitar(_ id: String) {
        puestos.removeValue(forKey: id)?.fuente.cancel()
        Self.centro?.removePendingNotificationRequests(withIdentifiers: [id])
    }

    /// Lo vencido mientras el Mac dormia (el temporizador de pared tambien
    /// salta al despertar; esto es por si acaso, y no suena dos veces).
    func revisarVencidos() {
        let ahora = Date()
        for (id, p) in puestos where p.cuando <= ahora {
            vencer(id)
        }
    }

    private func vencer(_ id: String) {
        guard let p = puestos.removeValue(forKey: id) else { return }
        p.fuente.cancel()
        let detalle: String
        if p.miniapp == "alarma" {
            let f = DateFormatter()
            f.timeStyle = .short
            f.dateStyle = .none
            detalle = "Alarma · \(f.string(from: p.cuando))"
            // Sigue encendida: manana a la misma hora del reloj de la pared.
            if let manana = Calendar.current.date(byAdding: .day, value: 1, to: p.cuando) {
                programar(id: id, miniapp: p.miniapp, texto: p.texto, cuando: manana)
            }
        } else {
            detalle = "Tiempo cumplido"
        }
        ventana.mostrar(AvisoSonando(id: id, titulo: p.texto, detalle: detalle, miniapp: p.miniapp))
    }

    // MARK: Notificaciones del sistema

    /// El centro de notificaciones, solo dentro de una `.app` (sin paquete,
    /// como en `swift run`, `UNUserNotificationCenter` se cae).
    private static var centro: UNUserNotificationCenter? {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
            ? UNUserNotificationCenter.current() : nil
    }

    private func notificar(id: String, miniapp: String, texto: String, cuando: Date) {
        guard let centro = Self.centro else { return }
        if !permisoPedido {
            permisoPedido = true
            centro.delegate = delegado
            centro.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        let contenido = UNMutableNotificationContent()
        contenido.title = texto
        contenido.body = miniapp == "alarma" ? "Alarma" : "Tiempo cumplido"
        contenido.sound = .default
        let partes = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: cuando)
        let peticion = UNNotificationRequest(identifier: id, content: contenido,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: partes, repeats: false))
        centro.add(peticion) { _ in }
    }
}

/// Con la app delante, el aviso ya sale en su ventana flotante: la
/// notificacion del sistema no se ensena otra vez.
private final class DelegadoAvisos: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler(notification.request.identifier.hasPrefix(AvisosMini.prefijo)
            || notification.request.identifier.hasPrefix("local:") ? [] : [.banner, .sound])
    }
}

// MARK: - La ventana que suena

struct AvisoSonando: Identifiable, Equatable {
    let id: String
    let titulo: String
    let detalle: String
    let miniapp: String
}

@MainActor
final class ModeloAvisoSonando: ObservableObject {
    @Published var avisos: [AvisoSonando] = []
    var alParar: (() -> Void)?
}

/// La ventana flotante del aviso: encima de todo, en todos los escritorios,
/// con un sonido en bucle hasta «Parar» (o un minuto).
@MainActor
final class VentanaAvisoMini {
    private let modelo = ModeloAvisoSonando()
    private var panel: NSPanel?
    private var sonido: NSSound?
    private var callar: Task<Void, Never>?

    func mostrar(_ aviso: AvisoSonando) {
        modelo.avisos.removeAll { $0.id == aviso.id }
        modelo.avisos.append(aviso)
        let panel = self.panel ?? crearPanel()
        self.panel = panel
        let pantalla = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let visible = pantalla?.visibleFrame {
            panel.setFrameOrigin(CGPoint(x: visible.midX - panel.frame.width / 2,
                                         y: visible.maxY - panel.frame.height - 40))
        }
        panel.orderFrontRegardless()
        sonar()
    }

    func parar() {
        callar?.cancel()
        sonido?.stop()
        sonido = nil
        modelo.avisos = []
        panel?.orderOut(nil)
    }

    private func sonar() {
        if sonido == nil {
            let s = NSSound(named: NSSound.Name("Glass")) ?? NSSound(named: NSSound.Name("Ping"))
            s?.loops = true
            s?.play()
            sonido = s
        }
        callar?.cancel()
        callar = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            self?.sonido?.stop()
            self?.sonido = nil
        }
    }

    private func crearPanel() -> NSPanel {
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 320, height: 150),
                            styleMask: [.titled, .closable, .nonactivatingPanel, .fullSizeContentView],
                            backing: .buffered, defer: false)
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        modelo.alParar = { [weak self] in self?.parar() }
        panel.contentView = NSHostingView(rootView: VistaAvisoSonando(modelo: modelo))
        // Cerrar con la x tambien calla.
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: panel,
                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.callar?.cancel()
                self?.sonido?.stop()
                self?.sonido = nil
                self?.modelo.avisos = []
            }
        }
        return panel
    }
}

struct VistaAvisoSonando: View {
    @ObservedObject var modelo: ModeloAvisoSonando

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(modelo.avisos) { a in
                HStack(spacing: 10) {
                    Image(systemName: a.miniapp == "alarma" ? "alarm.fill" : "timer")
                        .font(.title)
                        .foregroundStyle(.red)
                    VStack(alignment: .leading) {
                        Text(a.titulo).font(.headline).lineLimit(2)
                        Text(a.detalle).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Parar") { modelo.alParar?() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 28)
        .padding(.bottom, 14)
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
    }
}
