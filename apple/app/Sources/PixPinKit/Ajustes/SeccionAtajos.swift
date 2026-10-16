// La pestana «Atajos» de Ajustes, como la de Windows: todos los comandos
// del catalogo con su atajo (se pulsa el atajo para cambiarlo, ⌫ lo quita,
// Esc cancela), las regiones guardadas, silenciar todos y las apps delante
// de las cuales no actuan.
//
// Al grabar se sueltan todos los atajos (`GestorAtajos.pausar`): si no,
// pulsar uno que ya existe haria su comando en vez de grabarse. La tecla se
// lee con `addLocalMonitorForEvents`: solo en esta ventana y sin pedir el
// permiso de Accesibilidad.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

public struct SeccionAtajos: View {
    @ObservedObject var atajos: GestorAtajos
    /// Que fila esta grabando ahora (una sola a la vez).
    @State private var grabando: String?
    /// El ultimo aviso de cada fila (por su id).
    @State private var avisos: [String: ResultadoAtajo] = [:]

    public init(atajos: GestorAtajos) {
        self.atajos = atajos
    }

    public var body: some View {
        Form {
            Section {
                Toggle("Silenciar todos los atajos", isOn: Binding(
                    get: { atajos.silenciados },
                    set: { atajos.silenciar($0) }))
                Text("Los atajos valen en todo el Mac. Mejor con ⌃⌥ (Control + Option), como el ⌃⌥X de capturar: ⌘ con una letra es de cada app y ⇧⌘3/4/5 son las capturas de macOS. Pulsa «Cambiar» y luego el atajo; ⌫ lo quita y Esc cancela.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(atajos.noEntendidos, id: \.self) { raro in
                    Label("No se entendió: \(raro)", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            ForEach(ComandoAtajo.Grupo.allCases, id: \.self) { grupo in
                let comandos = ComandoAtajo.allCases.filter { $0.grupo == grupo && atajos.disponibles.contains($0) }
                if !comandos.isEmpty {
                    Section(grupo.rawValue) {
                        ForEach(comandos) { c in fila(c) }
                    }
                }
            }
            seccionRegiones
            seccionIgnorados
            Section {
                HStack {
                    Spacer()
                    Button("Restablecer todos los atajos") {
                        avisos = [:]
                        atajos.restablecerTodos()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Comandos

    private func fila(_ c: ComandoAtajo) -> some View {
        LabeledContent {
            HStack(spacing: 6) {
                GrabadorCombinacion(id: c.id, actual: atajos.enlaces.atajo(de: c), grabando: $grabando,
                                    atajos: atajos) { nueva in
                    avisos[c.id] = atajos.cambiar(c, a: nueva)
                }
                Button {
                    avisos[c.id] = atajos.restablecer(c)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .help("Volver al de fábrica (\(c.deFabrica?.descripcion ?? "sin atajo"))")
                .disabled(atajos.enlaces.atajo(de: c) == c.deFabrica)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(c.titulo)
                if let m = avisos[c.id]?.mensaje {
                    Text(m).font(.caption)
                        .foregroundStyle(avisos[c.id].map(esRechazo) == true ? .red : .orange)
                } else if atajos.fallidos.contains(c), let a = atajos.enlaces.atajo(de: c) {
                    Text("\(a.descripcion) lo tiene otra app o el sistema.").font(.caption).foregroundStyle(.red)
                }
            }
        }
    }

    private func esRechazo(_ r: ResultadoAtajo) -> Bool {
        if case .rechazado = r { return true }
        return false
    }

    // MARK: Regiones

    private var seccionRegiones: some View {
        Section {
            ForEach(atajos.regiones) { r in
                LabeledContent {
                    HStack(spacing: 6) {
                        GrabadorCombinacion(id: r.id.uuidString, actual: r.combinacion, grabando: $grabando,
                                            atajos: atajos) { nueva in
                            avisos[r.id.uuidString] = atajos.cambiarAtajo(region: r.id, a: nueva)
                        }
                        Button(role: .destructive) {
                            atajos.quitarRegion(r.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Quitar la región")
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("Nombre", text: Binding(
                            get: { r.nombre },
                            set: { atajos.renombrarRegion(r.id, a: $0) }))
                            .textFieldStyle(.plain)
                            .labelsHidden()
                        Text("\(r.ancho) × \(r.alto) en (\(r.x), \(r.y))")
                            .font(.caption).foregroundStyle(.secondary)
                        if let m = avisos[r.id.uuidString]?.mensaje {
                            Text(m).font(.caption).foregroundStyle(.red)
                        } else if atajos.regionesFallidas.contains(r.id) {
                            Text("El sistema no dejó registrar su atajo.").font(.caption).foregroundStyle(.red)
                        }
                    }
                }
            }
            HStack {
                Text("Una región captura siempre el mismo trozo de pantalla y lo copia, sin abrir la captura.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Guardar la última zona") { guardarUltimaZona() }
                    .disabled(Capturador.ultimaZonaGlobal() == nil)
                    .help("La última zona que elegiste al capturar")
            }
        } header: {
            Text("Regiones")
        }
    }

    private func guardarUltimaZona() {
        guard let zona = Capturador.ultimaZonaGlobal() else { return NSSound.beep() }
        let alto = NSScreen.screens.first?.frame.height ?? 0
        let n = atajos.regiones.count + 1
        atajos.anadir(.desde(appKit: zona, altoPantallaPrincipal: alto, nombre: "Región \(n)"))
    }

    // MARK: Apps ignoradas

    private var seccionIgnorados: some View {
        Section {
            ForEach(atajos.ignorados, id: \.self) { app in
                HStack {
                    Text(app)
                    Spacer()
                    Button {
                        atajos.dejarDeIgnorar(app)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Que los atajos vuelvan a actuar delante de \(app)")
                }
            }
            HStack {
                Text("Con una de estas apps delante, los atajos no hacen nada (p. ej. un gestor de contraseñas). El menú de PixPin sí.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Añadir app…") { elegirApp() }
            }
        } header: {
            Text("No actuar delante de")
        }
    }

    private func elegirApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.prompt = "Añadir"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            let nombre = FileManager.default.displayName(atPath: url.path)
            atajos.ignorar(nombre.hasSuffix(".app") ? String(nombre.dropLast(4)) : nombre)
        }
    }
}

/// Ensena un atajo y graba otro: «Cambiar» y luego la combinacion. ⌫ lo
/// deja sin atajo y Esc cancela. Solo graba una fila a la vez (`grabando`).
struct GrabadorCombinacion: View {
    let id: String
    let actual: AtajoGlobal.Combinacion?
    @Binding var grabando: String?
    let atajos: GestorAtajos
    let alCambiar: (AtajoGlobal.Combinacion?) -> Void
    @State private var monitor: Any?
    @State private var pista: String?

    private var esta: Bool { grabando == id }

    var body: some View {
        HStack(spacing: 6) {
            Text(esta ? (pista ?? "Pulsa el atajo…") : (actual?.descripcion ?? "—"))
                .font(.body.monospaced())
                .foregroundStyle(actual == nil && !esta ? .secondary : .primary)
                .frame(minWidth: 70)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(esta ? Color.accentColor : Color.secondary.opacity(0.4)))
            Button(esta ? "Cancelar" : "Cambiar") {
                if esta { grabando = nil } else { grabando = id }
            }
            .controlSize(.small)
        }
        .onChange(of: grabando) { _, nuevo in
            if nuevo == id { empezar() } else { parar() }
        }
        .onDisappear {
            if esta { grabando = nil }
            parar()
        }
    }

    private func empezar() {
        guard monitor == nil else { return }
        pista = nil
        atajos.pausar()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { evento in
            // Solo valores (no el `NSEvent`) cruzan al actor principal.
            let codigo = evento.keyCode
            let flags = evento.modifierFlags
            let comido = MainActor.assumeIsolated { manejar(codigo: codigo, flags: flags) }
            return comido ? nil : evento
        }
    }

    /// Lo que hace una tecla mientras se graba. `true`: se la come.
    private func manejar(codigo: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        guard esta else { return false }
        let mods = AtajoGlobal.Combinacion.modificadores(de: flags)
        if codigo == 53 { // Esc
            grabando = nil
            return true
        }
        if codigo == 51 || codigo == 117, mods == 0 { // ⌫ o Supr: sin atajo
            terminar(con: nil)
            return true
        }
        let nueva = AtajoGlobal.Combinacion(tecla: UInt32(codigo), modificadores: mods)
        guard AtajoGlobal.Combinacion.teclaValida(nueva.tecla) else {
            pista = "Una letra, una cifra o F1–F20"
            return true
        }
        guard nueva.tieneModificadorFuerte else {
            pista = "Con ⌃, ⌥ o ⌘"
            return true
        }
        terminar(con: nueva)
        return true
    }

    /// Suelta la pausa ANTES de cambiar: asi el cambio se registra ya y se
    /// sabe si otra app lo tiene.
    private func terminar(con nueva: AtajoGlobal.Combinacion?) {
        grabando = nil
        parar()
        alCambiar(nueva)
    }

    private func parar() {
        guard let m = monitor else { return }
        NSEvent.removeMonitor(m)
        monitor = nil
        atajos.reanudar()
    }
}
