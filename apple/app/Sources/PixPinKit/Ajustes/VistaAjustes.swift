// La ventana de Ajustes (⌘,), como la de Windows pero con lo que tiene
// sentido en un Mac. Dos pestanas: «General» (aspecto, galeria, carpeta de
// datos, abrir al iniciar sesion y sincronizar) y «Atajos» (todos los
// comandos, regiones y apps ignoradas: `SeccionAtajos`).

import AppKit
import SwiftUI

public struct VistaAjustes: View {
    @ObservedObject var modelo: ModeloAjustes
    @ObservedObject var atajos: GestorAtajos

    public init(modelo: ModeloAjustes, atajos: GestorAtajos) {
        self.modelo = modelo
        self.atajos = atajos
    }

    public var body: some View {
        TabView {
            general
                .tabItem { Label("General", systemImage: "gearshape") }
            SeccionAtajos(atajos: atajos)
                .tabItem { Label("Atajos", systemImage: "keyboard") }
        }
        .frame(width: 600)
        .frame(minHeight: 520)
    }

    private var general: some View {
        Form {
            Section("General") {
                Picker("Aspecto", selection: $modelo.tema) {
                    ForEach(Tema.allCases) { t in Text(t.nombre).tag(t) }
                }
                Toggle("Abrir al iniciar sesión", isOn: Binding(
                    get: { modelo.abrirAlIniciar },
                    set: { modelo.fijar(abrirAlIniciar: $0) }
                ))
                if modelo.esperaAprobacion {
                    HStack {
                        Text("Falta permitirlo en Ajustes del Sistema.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Abrir Elementos de inicio") { modelo.abrirElementosDeInicio() }
                            .controlSize(.small)
                    }
                }
            }
            Section("Capturar") {
                LabeledContent("Atajo para capturar una zona",
                               value: atajos.enlaces.atajo(de: .capturarRegion)?.descripcion ?? "—")
                Stepper(value: Binding(
                    get: { modelo.diasCaducidad },
                    set: { modelo.fijar(diasCaducidad: $0) }
                ), in: 0 ... 400) {
                    LabeledContent("Las capturas de la galería se van a los",
                                   value: modelo.diasCaducidad == 0 ? "nunca" : "\(modelo.diasCaducidad) días")
                }
                Text("0 = no se va ninguna. Se guarda en pixpinmax.toml, igual que en Windows.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            SeccionGestosYPila()
            Section("Sincronizar") {
                Toggle("Sincronizar sola con los aparatos del grupo", isOn: Binding(
                    get: { modelo.sincroAutomatica },
                    set: { modelo.fijar(sincroAutomatica: $0) }
                ))
                Text("Al aparecer un aparato del grupo en la Wi‑Fi y 30 s después de un cambio. Se pausa en modo de bajo consumo.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            SeccionAjustesPdf(nucleo: modelo.nucleo)
            Section("Datos") {
                LabeledContent("Carpeta de datos") {
                    Text(modelo.carpetaDatos.path)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Button("Mostrar en Finder") { modelo.mostrarCarpetaEnFinder() }
                }
            }
            if let error = modelo.error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .task { if !modelo.cargado { await modelo.cargar() } }
    }
}
