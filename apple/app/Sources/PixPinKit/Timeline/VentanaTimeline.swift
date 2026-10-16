// La ventana del timeline: la barra comun, lo que toca segun el modo
// (lo buscado, un dia o la pestana), el detalle encima y el aviso abajo.
// Las teclas son las de Windows (`tecla` de `timeline/ventana.rs`), con ⌘
// donde alli va Ctrl.

import AppKit
import PixPinCore
import SwiftUI

public struct VentanaTimeline: View {
    @StateObject private var modelo: ModeloTimeline
    @StateObject private var dictado = DictadoTimeline()
    /// El detalle abierto: la lista desde la que se abrio (sus ids), cual y
    /// que foto.
    @State private var detalle: DetalleTimeline?
    private let almacen: Almacen

    public init(almacen: Almacen) {
        self.almacen = almacen
        _modelo = StateObject(wrappedValue: ModeloTimeline(nucleo: almacen.nucleo))
    }

    public var body: some View {
        VStack(spacing: 0) {
            Cabecera("Timeline", subtitulo: subtitulo,
                     buscador: BuscadorCabecera($modelo.consulta, pista: "Buscar en el timeline")) {
                SegmentosCabecera(ModeloTimeline.Pestana.allCases.map { ($0, $0.rotulo) },
                                  eleccion: Binding(get: { modelo.pestana },
                                                    set: { p in cambiarPestana(p) }))
                    .fixedSize()
                MenuExportarTimeline(modelo: modelo)
            }
            contenido
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ventanaConCabecera()
        .frame(minWidth: 640, minHeight: 520)
        .overlay {
            if let d = detalle {
                DetalleMomento(modelo: modelo, almacen: almacen, detalle: Binding(get: { d }, set: { detalle = $0 }),
                               cerrar: { detalle = nil })
            }
        }
        .overlay(alignment: .bottom) { AvisoTimeline(modelo: modelo) }
        .background { teclas }
        .onChange(of: modelo.consulta) { _, _ in modelo.consultaCambiada() }
        .task { await modelo.recargar() }
        .onDisappear { dictado.cancelar() }
    }

    /// «Últimas 24 horas · 4 momentos», o lo de lo que se ve.
    private var subtitulo: String {
        func n(_ x: Int, _ uno: String, _ varios: String) -> String { x == 1 ? "1 \(uno)" : "\(x) \(varios)" }
        switch modelo.modo {
        case .buscar:
            return n(modelo.encontrados.count, "resultado", "resultados")
        case let .dia(iso):
            return "\(ModeloTimeline.rotulo(iso: iso)) · \(n(Int(modelo.totalMomentos), "momento", "momentos"))"
        case .pestana(.hoy):
            return "Últimas 24 horas · \(n(Int(modelo.totalMomentos), "momento", "momentos"))"
        case .pestana(.momentos):
            return n(Int(modelo.totalArchivo), "día", "días")
        case .pestana(.estado):
            return modelo.elegidos.isEmpty ? "Calendario" : n(modelo.elegidos.count, "día elegido", "días elegidos")
        case .pestana(.lecciones):
            return "Lecciones aprendidas"
        }
    }

    @ViewBuilder
    private var contenido: some View {
        switch modelo.modo {
        case .buscar:
            ResultadosTimeline(modelo: modelo, abrir: abrirDetalle)
        case let .dia(iso):
            VStack(spacing: 0) {
                BarraDelDia(iso: iso) { Task { await modelo.volverDelDia() } }
                LineaDeMomentos(modelo: modelo, abrir: abrirDetalle)
            }
        case .pestana(.hoy):
            VStack(spacing: 0) {
                LineaDeMomentos(modelo: modelo, abrir: abrirDetalle)
                CajaTimeline(modelo: modelo, dictado: dictado)
            }
        case .pestana(.momentos):
            ArchivoTimeline(modelo: modelo, abrir: abrirDetalle)
        case .pestana(.estado):
            EstadoTimeline(modelo: modelo)
        case .pestana(.lecciones):
            ListaLeccionesTimeline(nucleo: almacen.nucleo, consulta: modelo.consulta)
        }
    }

    private func cambiarPestana(_ p: ModeloTimeline.Pestana) {
        Task { await modelo.cambiar(a: p) }
    }

    private func abrirDetalle(_ m: MomentoTimeline, foto: Int) {
        let lista = modelo.visibles.map(\.id)
        detalle = DetalleTimeline(lista: lista.contains(m.id) ? lista : [m.id], id: m.id, foto: foto)
    }

    /// Las teclas de la ventana: ⌘1…4, Esc por capas, ⌘Z del borrado y
    /// ⌘⇧M el microfono (⌘M ya es minimizar en el Mac).
    private var teclas: some View {
        ZStack {
            ForEach(ModeloTimeline.Pestana.allCases) { p in
                Button("") { Task { await modelo.cambiar(a: p) } }
                    .keyboardShortcut(KeyEquivalent(Character(String(p.rawValue))), modifiers: .command)
            }
            Button("") { Task { await modelo.deshacerBorrado() } }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(modelo.deshacer == nil)
            Button("") { escape() }
                .keyboardShortcut(.escape, modifiers: [])
            Button("") { Task { await dictado.pulsar(modelo: modelo) } }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            Button("") { Task { await modelo.recargar() } }
                .keyboardShortcut("r", modifiers: .command)
        }
        .opacity(0)
        .allowsHitTesting(false)
    }

    /// Esc va por capas: el detalle, la busqueda, la correccion, la caja,
    /// el dia, «Hoy» y, al final, cierra.
    private func escape() {
        if detalle != nil {
            detalle = nil
        } else if modelo.buscando {
            modelo.consulta = ""
        } else if modelo.corrigiendo != nil || !modelo.texto.isEmpty || !modelo.pegadas.isEmpty {
            modelo.vaciarCaja()
        } else if case .dia = modelo.modo {
            Task { await modelo.volverDelDia() }
        } else if modelo.pestana != .hoy {
            Task { await modelo.cambiar(a: .hoy) }
        } else {
            NSApp.keyWindow?.performClose(nil)
        }
    }
}

/// La franja de un dia abierto: «‹ Volver» y su fecha.
struct BarraDelDia: View {
    let iso: String
    let volver: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: volver) {
                Label("Volver", systemImage: "chevron.left")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Paleta.v2.acento)
            Text(ModeloTimeline.rotulo(iso: iso).capitalizedPrimera)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Paleta.v2.texto)
            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(height: 44)
        .overlay(alignment: .bottom) { Paleta.v2.linea.frame(height: 1) }
    }
}

/// El aviso de abajo, con «Deshacer» (⌘Z) si lo hay.
struct AvisoTimeline: View {
    @ObservedObject var modelo: ModeloTimeline

    var body: some View {
        if let t = modelo.aviso ?? modelo.error {
            HStack(spacing: 12) {
                Text(t).font(.system(size: 13)).foregroundStyle(Paleta.v2.texto)
                if modelo.deshacer != nil {
                    Button("Deshacer") { Task { await modelo.deshacerBorrado() } }
                        .buttonStyle(.plain)
                        .foregroundStyle(Paleta.v2.acento)
                    Chapa(texto: "⌘Z")
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(Paleta.v2.tarjetaEncima, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.1)))
            .padding(.bottom, modelo.modo == .pestana(.hoy) ? 96 : 20)
            .transition(.opacity)
        }
    }
}

/// La pestana «Lecciones» (`timeline/ventana/lecciones.rs`): una tarjeta
/// por leccion con su gravedad, lo que paso y las veces; los chips filtran
/// por gravedad y ordenan, y el buscador de arriba busca en ellas. Clic
/// abre su ficha en la ventana de Lecciones.
struct ListaLeccionesTimeline: View {
    @StateObject private var lecciones: ModeloLecciones
    let consulta: String
    @State private var gravedad: Int64?
    @State private var repetidas = false
    @Environment(\.openWindow) private var abrirVentana

    init(nucleo: Nucleo, consulta: String) {
        _lecciones = StateObject(wrappedValue: ModeloLecciones(nucleo: nucleo))
        self.consulta = consulta
    }

    private var vistas: [FichaLeccion] {
        var v = lecciones.lecciones.filter { gravedad == nil || $0.gravedad == gravedad }
        if repetidas { v.sort { ($0.veces, $0.tocada) > ($1.veces, $1.tocada) } }
        return v
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                chip("Todas", gravedad == nil) { gravedad = nil }
                chip("Leve", gravedad == 1) { gravedad = 1 }
                chip("Importante", gravedad == 2) { gravedad = 2 }
                chip("Grave", gravedad == 3) { gravedad = 3 }
                Spacer()
                chip("Recientes", !repetidas) { repetidas = false }
                chip("Más repetidas", repetidas) { repetidas = true }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 12)], spacing: 12) {
                    ForEach(vistas, id: \.id) { l in
                        TarjetaLeccionTimeline(leccion: l) {
                            Task { _ = await lecciones.repasar(l.id, nota: .repetida) }
                        }
                        .onTapGesture { abrirVentana(id: "lecciones") }
                        .onAppear {
                            if l.id == lecciones.lecciones.last?.id { Task { await lecciones.cargarMas() } }
                        }
                    }
                }
                .padding(20)
            }
            .overlay {
                if vistas.isEmpty, !lecciones.cargando {
                    Text(lecciones.texto.isEmpty
                        ? "Aún no hay lecciones. Pulsa la bombilla de un momento para hacerlo lección."
                        : "No hay ninguna lección con eso.")
                        .foregroundStyle(Paleta.v2.gris)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
            }
        }
        .task { await lecciones.recargar() }
        .onAppear { lecciones.texto = consulta }
        .onChange(of: consulta) { _, q in lecciones.texto = q }
    }

    private func chip(_ t: String, _ activo: Bool, _ accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            Text(t).font(.system(size: 12.5))
                .foregroundStyle(activo ? Color.white : Paleta.v2.cuerpo)
                .padding(.horizontal, 12).frame(height: 28)
                .background(activo ? Paleta.v2.acento : Paleta.v2.caja, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Una leccion en su tarjeta: icono y titulo, lo que paso, la gravedad y
/// «↻ +1» (me volvio a pasar).
struct TarjetaLeccionTimeline: View {
    let leccion: FichaLeccion
    let otraVez: () -> Void

    private var gravedad: (String, Color) {
        switch leccion.gravedad {
        case 3: ("Grave", Paleta.v2.rojo)
        case 2: ("Importante", Paleta.v2.naranja)
        default: ("Leve", Paleta.v2.verde)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(leccion.icono)
                Text(leccion.titulo).font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Paleta.v2.texto).lineLimit(2)
            }
            if !leccion.quePaso.isEmpty {
                Text(leccion.quePaso).font(.system(size: 12.5)).foregroundStyle(Paleta.v2.cuerpo).lineLimit(3)
            }
            HStack(spacing: 8) {
                Text(gravedad.0).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(gravedad.1)
                    .padding(.horizontal, 8).frame(height: 20)
                    .background(gravedad.1.opacity(0.15), in: Capsule())
                if leccion.veces > 1 {
                    Text("×\(leccion.veces)").font(.system(size: 11)).foregroundStyle(Paleta.v2.gris)
                }
                Spacer()
                Button(action: otraVez) {
                    Text("↻ +1").font(.system(size: 11.5, weight: .medium))
                        .padding(.horizontal, 8).frame(height: 22)
                        .background(Paleta.v2.caja, in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Paleta.v2.texto)
                .help("Me volvió a pasar +1")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Paleta.v2.tarjeta, in: RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())
    }
}

extension String {
    /// La primera letra en mayuscula («Jueves, 15 de octubre»).
    var capitalizedPrimera: String {
        guard let p = first else { return self }
        return p.uppercased() + dropFirst()
    }
}
