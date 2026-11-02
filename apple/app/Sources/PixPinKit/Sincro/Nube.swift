// **La nube de los chats compartidos** (Windows c5c94e4, 1-nov-2026,
// `docs/nube.md` de Windows): `sincronizar/nube_ui.rs` y la chapa de la
// lista, en nativo.
//
// Lo de dentro es Rust (`pixpin-nucleo/src/nube.rs` sobre
// `pindesk_sincro::nube`, el mismo crate que Windows): la direccion en
// `sincro/nube/ajustes.json`, la llave `pxn_…` en el Llavero
// (`LlaveroDelSistema`), el modo de cada chat en `sincro/nube/chats.json`
// y los dos hilos que suben y bajan (cada 3 s con 4 s de quietud, las
// novedades con la conexion abierta, espera creciente sin red), que son
// hilos de Rust: nada de la nube corre en el hilo principal. La red va por
// `TransporteHttps` (URLSession), como el asistente y Jev.
//
// - `NubeDelMac`: arranca los hilos y guarda el estado de cada chat para
//   la nubecita.
// - `SeccionNube` y `VistaAjustesNube`: Sincronizar → Nube (direccion,
//   llave, Guardar, Probar con el espacio y la persona).
// - `ChapaNube`: la nubecita del avatar (azul subiendo, verde al dia, gris
//   sin red, roja si la llave no vale).
// - `BotonEnLinea` y `EnLineaDelVisor`: «En línea / Sin conexión» de los
//   visores de un chat de la nube.

import AppKit
import PixPinCore
import SwiftUI

/// Los textos de la nube (`nube-*` y `chat-nuevo-nube*` de Windows).
enum TextosNube {
    static var titulo: String { Lengua.t("nube-titulo") }
    static var portadaComo: String { Lengua.t("nube-portada-como") }
    static var ajustes: String { Lengua.t("nube-ajustes") }
    static var explica: String { Lengua.t("nube-explica") }
    static var direccion: String { Lengua.t("nube-direccion") }
    static var llave: String { Lengua.t("nube-llave") }
    static var llaveGuardada: String { Lengua.t("nube-llave-guardada") }
    static var olvidar: String { Lengua.t("nube-olvidar") }
    static var guardar: String { Lengua.t("nube-guardar") }
    static var probar: String { Lengua.t("nube-probar") }
    static var guardado: String { Lengua.t("nube-guardado") }
    static var direccionMala: String { Lengua.t("nube-direccion-mala") }
    static var llaveMala: String { Lengua.t("nube-llave-mala") }
    static var noContesta: String { Lengua.t("nube-no-contesta") }
    static var queVa: String { Lengua.t("nube-que-va") }
    static var faltaConfigurar: String { Lengua.t("nube-falta-configurar") }
    static var modoTitulo: String { Lengua.t("nube-modo-titulo") }
    static var modoLocal: String { Lengua.t("nube-modo-local") }
    static var modoNube: String { Lengua.t("nube-modo-nube") }
    static var modoLocalDetalle: String { Lengua.t("nube-modo-local-detalle") }
    static var modoNubeDetalle: String { Lengua.t("nube-modo-nube-detalle") }
    static var enLinea: String { Lengua.t("nube-en-linea") }
    static var sinConexion: String { Lengua.t("nube-sin-conexion") }
    static var cerrarTitulo: String { Lengua.t("nube-cerrar-titulo") }
    static var cerrarPregunta: String { Lengua.t("nube-cerrar-pregunta") }
    static var chatNuevo: String { Lengua.t("chat-nuevo-nube") }
    static var chatNuevoDetalle: String { Lengua.t("chat-nuevo-nube-detalle") }

    /// El dorado de «Sin conexión» (`DORADO` del lector de Windows,
    /// `#E8C06A`); en modo claro, uno mas oscuro que se lea sobre el
    /// material claro.
    static let dorado = Color(claro: 0xA87A12, oscuro: 0xE8C06A)

    /// `nube-probado`: «Conectado: espacio X.»
    static func probado(_ espacio: String) -> String {
        Lengua.t("nube-probado", ["espacio": espacio])
    }
}

// MARK: - Los hilos y el estado

/// **La nube de este Mac**: arranca los hilos de Rust y guarda como va
/// cada chat de la nube (por su ficha) para la nubecita de la lista.
@MainActor
public final class NubeDelMac: ObservableObject {
    public static let compartida = NubeDelMac()
    /// `FichaChat.id` -> como va.
    @Published public private(set) var estados: [String: EstadoNube] = [:]
    private(set) var nucleo: Nucleo?
    /// Llego algo de la nube a disco: hay que releer los chats.
    private var alTraer: (@MainActor () -> Void)?
    private var turno = 0

    /// **Arranca la nube** (una vez, al arrancar la app). Sin direccion ni
    /// llave los hilos no hacen nada.
    public func arrancar(nucleo: Nucleo, alTraer: @escaping @MainActor () -> Void) {
        guard self.nucleo == nil else { return }
        self.nucleo = nucleo
        self.alTraer = alTraer
        // El HTTPS de la app y el Llavero, antes de que los hilos los pidan.
        TransporteHttps.instalar()
        LlaveroDelSistema.instalar()
        let aviso = AvisoDeLaNube()
        Task.detached(priority: .utility) { nucleo.arrancarNube(aviso: aviso) }
        releer()
    }

    /// Vuelve a mirar el estado de cada chat de la nube.
    public func releer() {
        guard let nucleo else { return }
        turno += 1
        let mio = turno
        Task {
            let lista = await Task.detached(priority: .utility) { nucleo.estadosDeLaNube() }.value
            guard mio == self.turno else { return }
            var nuevo: [String: EstadoNube] = [:]
            for e in lista { nuevo[e.ficha] = e.estado }
            if nuevo != self.estados { self.estados = nuevo }
        }
    }

    fileprivate func avisado(trajo: Bool) {
        releer()
        if trajo { alTraer?() }
    }
}

/// El `AvisoNube` del nucleo: lo llaman los hilos de la nube (de Rust).
final class AvisoDeLaNube: AvisoNube, @unchecked Sendable {
    func cambio(trajo: Bool) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { NubeDelMac.compartida.avisado(trajo: trajo) }
        }
    }
}

// MARK: - Sincronizar → Nube

/// La caja «Nube» de la ventana de Sincronizar (`pintar_portada` de
/// Windows): que es y el boton a sus ajustes.
struct SeccionNube: View {
    let nucleo: Nucleo
    @State private var abierta = false

    var body: some View {
        Section {
            Text(TextosNube.portadaComo).foregroundStyle(.secondary)
            Button {
                abierta = true
            } label: {
                Label(TextosNube.ajustes, systemImage: "icloud")
            }
        } header: {
            Text(TextosNube.titulo)
        }
        .sheet(isPresented: $abierta) { VistaAjustesNube(nucleo: nucleo) }
    }
}

/// **Los ajustes de la nube** (`nube_ui.rs` de Windows): la direccion de la
/// web, la llave del aparato, Guardar y Probar.
struct VistaAjustesNube: View {
    let nucleo: Nucleo
    @Environment(\.dismiss) private var cerrar
    @State private var direccion = ""
    @State private var llave = ""
    @State private var guardada: String?
    @State private var probando = false
    /// Lo que paso al guardar o probar, y si fue bien.
    @State private var aviso: (texto: String, bien: Bool)?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Text(TextosNube.explica).foregroundStyle(.secondary)
                }
                Section {
                    TextField(TextosNube.direccion, text: $direccion, prompt: Text(verbatim: "https://…"))
                        .autocorrectionDisabled()
                    SecureField(TextosNube.llave, text: $llave, prompt: Text(verbatim: "pxn_…"))
                    if let guardada {
                        HStack {
                            Text("\(TextosNube.llaveGuardada) \(guardada)")
                                .font(.callout.monospaced())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(TextosNube.olvidar, role: .destructive) { olvidar() }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.red)
                        }
                    }
                }
                Section {
                    HStack {
                        Button(TextosNube.guardar) { guardar() }
                            .keyboardShortcut(.defaultAction)
                        Button {
                            probar()
                        } label: {
                            Label(TextosNube.probar, systemImage: "icloud")
                        }
                        .disabled(probando)
                        Spacer()
                        if probando { ProgressView().controlSize(.small) }
                    }
                    if !probando, let aviso {
                        Text(aviso.texto)
                            .foregroundStyle(aviso.bien ? Color.green : Color.red)
                            .textSelection(.enabled)
                    }
                } footer: {
                    Text(TextosNube.queVa).font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button(Lengua.t("ajustes-cerrar")) { cerrar() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(minWidth: 480, minHeight: 420)
        .onAppear(perform: leer)
    }

    private func leer() {
        LlaveroDelSistema.instalar()
        let a = nucleo.nubeAjustes()
        direccion = a.direccion
        guardada = a.llaveGuardada
        if aviso == nil, let u = nucleo.nubeUltimoSaludo() {
            aviso = u.bien ? (TextosNube.probado(u.texto), true) : ("\(TextosNube.noContesta) \(u.texto)", false)
        }
    }

    private func guardar() {
        LlaveroDelSistema.instalar()
        let l = llave.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            switch try nucleo.nubeGuardar(direccion: direccion, llave: l.isEmpty ? nil : l) {
            case .guardado:
                llave = ""
                guardada = nucleo.nubeAjustes().llaveGuardada
                aviso = (TextosNube.guardado, true)
            case .direccionMala:
                aviso = (TextosNube.direccionMala, false)
            case .llaveMala:
                aviso = (TextosNube.llaveMala, false)
            }
        } catch {
            aviso = (textoDeError(error), false)
        }
        NubeDelMac.compartida.releer()
    }

    private func olvidar() {
        do {
            try nucleo.nubeOlvidarLlave()
            guardada = nil
        } catch {
            aviso = (textoDeError(error), false)
        }
        NubeDelMac.compartida.releer()
    }

    private func probar() {
        guard !probando else { return }
        probando = true
        aviso = nil
        TransporteHttps.instalar()
        let nucleo = self.nucleo
        Task {
            let r: Result<SaludoNube, Error> = await Task.detached(priority: .userInitiated) {
                Result { try nucleo.nubeProbar() }
            }.value
            probando = false
            switch r {
            case let .success(s):
                aviso = (TextosNube.probado(s.persona.map { "\(s.espacio) · \($0)" } ?? s.espacio), true)
            case let .failure(e):
                aviso = ("\(TextosNube.noContesta) \(textoDeError(e))", false)
            }
            NubeDelMac.compartida.releer()
        }
    }
}

// MARK: - La nubecita de la lista

/// **La chapa de la nube** (`pintar_chapa_nube` de Windows): arriba a la
/// derecha del avatar de un chat compartido que va por la nube, la nubecita
/// del color de como va, con un aro del color de lo de detras.
struct ChapaNube: View {
    /// El lado del avatar.
    let avatar: CGFloat
    let aro: Color
    let estado: EstadoNube

    private var color: Color {
        switch estado {
        case .subiendo: Color(hex: 0x3B82F6)
        // `VERDE_COMPARTIDO` de Windows.
        case .alDia: Color(hex: 0x2E9E62)
        case .sinRed: Color(hex: 0x8A8F98)
        case .llave: Color(hex: 0xE0453A)
        }
    }

    private var simbolo: String {
        switch estado {
        case .subiendo: "icloud.and.arrow.up.fill"
        case .alDia: "checkmark.icloud.fill"
        case .sinRed, .llave: "icloud.slash.fill"
        }
    }

    var body: some View {
        let lado = max(avatar * 0.46, 10)
        let grosor = max(lado * 0.12, 1)
        ZStack {
            Circle().fill(aro)
            Circle().fill(color).padding(grosor)
            Image(systemName: simbolo)
                .font(.system(size: (lado - 2 * grosor) * 0.45))
                .foregroundStyle(.white)
        }
        .frame(width: lado, height: lado)
        // Asoma un quinto por fuera del avatar, arriba (como en Windows).
        .offset(x: lado * 0.2, y: -lado * 0.2)
        .help(estado == .llave ? TextosNube.faltaConfigurar : TextosNube.titulo)
    }
}

// MARK: - «En línea / Sin conexión»

/// **El boton de un visor** (`en_linea.rs` de Windows): guarda de que es lo
/// anotado (`SitioNube`, o nada fuera de un chat de la nube) y si esta sin
/// conexion. El visor lo pone arriba a la izquierda con `BotonEnLinea` y
/// llama a `alCerrar` cuando ya guardo lo suyo.
@MainActor
final class EnLineaDelVisor: ObservableObject {
    /// `nil`: no es de un chat de la nube (no sale el boton).
    @Published private(set) var sitio: SitioNube?
    @Published private(set) var sinConexion = false
    let nucleo: Nucleo?

    /// El de un documento (PDF, Word, hoja, plano...): lo anotado
    /// `anot-<uid>…` de su adjunto. Se mira fuera del hilo principal.
    init(documento: URL?, nucleo: Nucleo?) {
        self.nucleo = nucleo
        guard let nucleo, let documento else { return }
        let ruta = documento.path
        buscar { nucleo.nubeSitioDeDocumento(ruta: ruta) }
    }

    /// El de un lienzo de la ficha `ficha` (una hoja DIBUJO o PAGINA, o el
    /// lienzo de una foto): su referencia.
    init(ficha: String?, referencia: String?, nucleo: Nucleo?) {
        self.nucleo = nucleo
        guard let nucleo, let ficha, let referencia, !referencia.isEmpty else { return }
        buscar { nucleo.nubeSitioDeLienzo(ficha: ficha, referencia: referencia) }
    }

    /// El de lo que dice `sitio` (Windows 4fdfb7e1: el lector de notas, con
    /// `SesionNota.sitioNube`). Se mira fuera del hilo principal.
    init(nucleo: Nucleo?, sitio: @escaping @Sendable () -> SitioNube?) {
        self.nucleo = nucleo
        guard nucleo != nil else { return }
        buscar(sitio)
    }

    private func buscar(_ f: @escaping @Sendable () -> SitioNube?) {
        guard let nucleo else { return }
        Task { [weak self] in
            let (sitio, sin) = await Task.detached(priority: .utility) { () -> (SitioNube?, Bool) in
                guard let s = f() else { return (nil, false) }
                return (s, nucleo.nubeSinConexion(sitio: s))
            }.value
            guard let self else { return }
            self.sitio = sitio
            self.sinConexion = sin
        }
    }

    func releer() {
        guard let nucleo, let sitio else { return }
        sinConexion = nucleo.nubeSinConexion(sitio: sitio)
    }

    /// Pasa de en linea a sin conexion o al reves.
    func cambiar() {
        guard let nucleo, let sitio else { return }
        do {
            try nucleo.nubePonerSinConexion(sitio: sitio, sin: !sinConexion)
        } catch {
            NSLog("PixPin: no se pudo cambiar «Sin conexión»: %@", textoDeError(error))
        }
        releer()
    }

    /// **Al salir del documento sin conexion** (ya guardado lo suyo): se
    /// pregunta. «Sí» (lo de por omision) descarta lo anotado sin conexion;
    /// «No» vuelve a en linea y lo sube; «Cancelar» lo deja sin conexion
    /// para la proxima vez.
    func alCerrar() {
        releer()
        guard let nucleo, let sitio, sinConexion else { return }
        let alerta = NSAlert()
        alerta.messageText = TextosNube.cerrarTitulo
        alerta.informativeText = TextosNube.cerrarPregunta
        alerta.alertStyle = .warning
        alerta.addButton(withTitle: Lengua.t("asistente-confirmar-si"))
        alerta.addButton(withTitle: Lengua.t("asistente-confirmar-no"))
        alerta.addButton(withTitle: Lengua.t("confirmar-cancelar"))
        let eleccion: AlCerrarNube
        switch alerta.runModal() {
        case .alertFirstButtonReturn: eleccion = .descartar
        case .alertSecondButtonReturn: eleccion = .subir
        default: eleccion = .dejar
        }
        do {
            try nucleo.nubeAlCerrar(sitio: sitio, eleccion: eleccion)
        } catch {
            NSLog("PixPin: «Sin conexión» al cerrar: %@", textoDeError(error))
        }
        releer()
    }
}

/// **«En línea» / «Sin conexión»**: la capsula de arriba a la izquierda de
/// un visor (nube verde, o tachada y dorada). Fuera de un chat de la nube
/// no se ve.
struct BotonEnLinea: View {
    @ObservedObject var modelo: EnLineaDelVisor
    @State private var encima = false

    var body: some View {
        if modelo.sitio != nil {
            let sin = modelo.sinConexion
            Button {
                modelo.cambiar()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: sin ? "icloud.slash.fill" : "checkmark.icloud.fill")
                        .foregroundStyle(sin ? TextosNube.dorado : Color(hex: 0x5CC780))
                    Text(sin ? TextosNube.sinConexion : TextosNube.enLinea)
                        .foregroundStyle(sin ? TextosNube.dorado : Color.primary)
                }
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .brightness(encima ? 0.04 : 0)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { encima = $0 }
            .help(sin ? TextosNube.enLinea : TextosNube.sinConexion)
            // Lo de otro aparato pudo cambiarlo (o el cierre de otra ventana).
            .onAppear { modelo.releer() }
        }
    }
}

/// «En línea / Sin conexión» encima de un visor de SwiftUI (el lienzo,
/// el plano, el modelo), arriba a la izquierda bajo la barra del pin.
struct BotonDeLaNube: View {
    @ObservedObject var modelo: EnLineaDelVisor

    var body: some View {
        if modelo.sitio != nil {
            BotonEnLinea(modelo: modelo)
                .padding(.top, BarraFlotante.alto + 2 * BarraFlotante.separacion + 8)
                .padding(.leading, 16)
        }
    }
}
