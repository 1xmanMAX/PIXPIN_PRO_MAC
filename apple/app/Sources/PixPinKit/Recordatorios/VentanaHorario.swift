// **La ventana semanal del horario** (Windows, 18-oct): las asignaturas a la
// izquierda y la semana a la derecha. Se arrastra una asignatura a la
// rejilla para poner una clase; un bloque se mueve arrastrandolo, se alarga
// por su borde de abajo y se borra con su menu. Todo se guarda en el MISMO
// `horario.md` (`SemanaHorario`, nucleo), asi que se sigue pudiendo
// escribir a mano («Editar como texto») y los avisos salen de lo mismo.

import AppKit
import PixPinCore
import SwiftUI

@MainActor
final class ModeloSemana: ObservableObject {
    let semana: SemanaHorario?
    let nucleo: Nucleo
    @Published private(set) var asignaturas: [AsignaturaHorario] = []
    @Published private(set) var bloques: [BloqueHorario] = []
    @Published var error: String?

    init(nucleo: Nucleo) {
        self.nucleo = nucleo
        do { semana = try SemanaHorario.abrir(nucleo: nucleo) } catch {
            semana = nil
            self.error = "\(error)"
        }
        releer()
    }

    func releer() {
        asignaturas = semana?.asignaturas() ?? []
        bloques = semana?.bloques() ?? []
    }

    /// Hace un cambio, lo guarda y avisa al vigia.
    func cambiar(_ hacer: (SemanaHorario) -> Void) {
        guard let semana else { return }
        hacer(semana)
        do {
            try semana.guardar()
            Recordatorios.compartido.releer()
        } catch {
            self.error = "\(error)"
        }
        releer()
    }
}

struct VentanaHorario: View {
    @StateObject private var modelo: ModeloSemana
    @State private var nueva = ""
    @State private var arrastrandoFin: (Int, CGFloat)?
    /// De 7:00 a 22:00.
    static let desde: UInt32 = 7 * 60
    static let hasta: UInt32 = 22 * 60
    static let dias = ["Lun", "Mar", "Mié", "Jue", "Vie", "Sáb", "Dom"]

    init(nucleo: Nucleo) {
        _modelo = StateObject(wrappedValue: ModeloSemana(nucleo: nucleo))
    }

    var body: some View {
        HStack(spacing: 0) {
            lista.frame(width: 220)
            Divider()
            rejilla
        }
        .frame(minWidth: 860, minHeight: 560)
        .overlay(alignment: .bottom) {
            if let e = modelo.error {
                Text(e).font(.caption).padding(6).background(.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 6)).padding()
            }
        }
    }

    // MARK: Las asignaturas

    private var lista: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Asignaturas").font(.headline)
            HStack {
                TextField("Geometría @A-12", text: $nueva).textFieldStyle(.roundedBorder).onSubmit(anadir)
                Button(action: anadir) { Image(systemName: "plus") }.disabled(nueva.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(modelo.asignaturas.enumerated()), id: \.element.nombre) { i, a in
                        HStack {
                            Circle().fill(Self.color(a.color)).frame(width: 12, height: 12)
                                .onTapGesture { modelo.cambiar { $0.cambiarColor(i: UInt32(i)) } }
                                .help("Otro color")
                            VStack(alignment: .leading, spacing: 0) {
                                Text(a.nombre)
                                if let aula = a.aula { Text(aula).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                        }
                        .padding(6)
                        .background(Self.color(a.color).opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                        .draggable("asignatura:\(i)")
                        .contextMenu {
                            Button("Borrar", role: .destructive) { modelo.cambiar { $0.borrarAsignatura(i: UInt32(i)) } }
                        }
                    }
                }
            }
            Text("Arrastra una asignatura a la semana para poner una clase.").font(.caption).foregroundStyle(.secondary)
            Button("Editar como texto…") {
                if let r = try? modelo.nucleo.ficheroDelHorario() {
                    EditoresDeNotas.compartidos.abrir(fichero: URL(fileURLWithPath: r), nucleo: modelo.nucleo)
                }
            }
        }
        .padding(12)
    }

    private func anadir() {
        let t = nueva.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        nueva = ""
        modelo.cambiar { _ = $0.anadirAsignatura(escrito: t) }
    }

    // MARK: La semana

    private var rejilla: some View {
        GeometryReader { geo in
            let cabecera: CGFloat = 24, horas: CGFloat = 44
            let ancho = (geo.size.width - horas) / 7
            let alto = (geo.size.height - cabecera) / CGFloat(Self.hasta - Self.desde)
            ZStack(alignment: .topLeading) {
                // Los dias y las horas.
                ForEach(0 ..< 7, id: \.self) { d in
                    Text(Self.dias[d]).font(.caption.bold())
                        .frame(width: ancho).position(x: horas + ancho * (CGFloat(d) + 0.5), y: cabecera / 2)
                }
                ForEach(Array(stride(from: Self.desde, through: Self.hasta, by: 60)), id: \.self) { m in
                    let y = cabecera + CGFloat(m - Self.desde) * alto
                    Path { p in p.move(to: CGPoint(x: horas, y: y)); p.addLine(to: CGPoint(x: geo.size.width, y: y)) }
                        .stroke(Color.secondary.opacity(0.2))
                    Text("\(m / 60):00").font(.caption2).foregroundStyle(.secondary).position(x: horas / 2, y: y)
                }
                ForEach(0 ..< 8, id: \.self) { d in
                    let x = horas + CGFloat(d) * ancho
                    Path { p in p.move(to: CGPoint(x: x, y: cabecera)); p.addLine(to: CGPoint(x: x, y: geo.size.height)) }
                        .stroke(Color.secondary.opacity(0.2))
                }
                // Los bloques.
                ForEach(Array(modelo.bloques.enumerated()), id: \.offset) { i, b in
                    let y0 = cabecera + CGFloat(Int(b.inicio) - Int(Self.desde)) * alto
                    let finVisto = arrastrandoFin?.0 == i ? arrastrandoFin!.1 : CGFloat(Int(b.fin) - Int(Self.desde)) * alto + cabecera
                    VStack(alignment: .leading, spacing: 0) {
                        Text(b.nombre).font(.caption.bold()).lineLimit(1)
                        Text(String(format: "%d:%02d–%d:%02d", b.inicio / 60, b.inicio % 60, b.fin / 60, b.fin % 60))
                            .font(.caption2)
                        if let a = b.aula { Text(a).font(.caption2).lineLimit(1) }
                        Spacer(minLength: 0)
                        // El borde de abajo alarga.
                        Rectangle().fill(Color.clear).frame(height: 6).contentShape(Rectangle())
                            .onHover { $0 ? NSCursor.resizeUpDown.push() : NSCursor.pop() }
                            .gesture(DragGesture().onChanged { g in
                                arrastrandoFin = (i, finVisto + g.translation.height - (arrastrandoFin == nil ? 0 : 0))
                            }.onEnded { g in
                                let fin = CGFloat(Int(b.fin) - Int(Self.desde)) * alto + g.translation.height
                                arrastrandoFin = nil
                                let minutos = Int(Self.desde) + Int(fin / alto)
                                modelo.cambiar { $0.alargar(i: UInt32(i), fin: UInt32(max(Int(b.inicio) + 15, minutos))) }
                            })
                    }
                    .padding(.horizontal, 4).padding(.top, 2)
                    .frame(width: ancho - 4, height: max(16, finVisto - y0), alignment: .topLeading)
                    .background(Self.color(b.color).opacity(0.75), in: RoundedRectangle(cornerRadius: 5))
                    .foregroundStyle(.white)
                    .position(x: horas + ancho * CGFloat(b.dia) + ancho / 2, y: y0 + max(16, finVisto - y0) / 2)
                    .draggable("bloque:\(i)")
                    .contextMenu {
                        Button("Borrar esta clase", role: .destructive) { modelo.cambiar { $0.borrar(i: UInt32(i)) } }
                    }
                }
            }
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { cosas, punto in
                guard let cosa = cosas.first, punto.x > horas, punto.y > cabecera else { return false }
                let dia = UInt8(min(6, max(0, Int((punto.x - horas) / ancho))))
                let minuto = Int(Self.desde) + Int((punto.y - cabecera) / alto)
                if cosa.hasPrefix("asignatura:"), let i = UInt32(cosa.dropFirst(11)) {
                    modelo.cambiar { $0.soltar(asignatura: i, dia: dia, minuto: UInt32(minuto)) }
                } else if cosa.hasPrefix("bloque:"), let i = Int(cosa.dropFirst(7)), i < modelo.bloques.count {
                    modelo.cambiar { $0.mover(i: UInt32(i), dia: dia, inicio: Int64(minuto / 15 * 15)) }
                }
                return true
            }
        }
        .padding(8)
    }

    static func color(_ c: UInt32) -> Color {
        Color(red: Double((c >> 16) & 0xFF) / 255, green: Double((c >> 8) & 0xFF) / 255, blue: Double(c & 0xFF) / 255)
    }
}

/// La ventana, una sola.
@MainActor
enum VentanasDeHorario {
    private static var ventana: NSWindow?

    static func abrir(nucleo: Nucleo) {
        if let v = ventana {
            v.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let v = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 680),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        v.title = "Horario de clases"
        v.isReleasedWhenClosed = false
        v.contentView = NSHostingView(rootView: VentanaHorario(nucleo: nucleo))
        v.center()
        _ = v.setFrameAutosaveName("PixPinHorario")
        ventana = v
        v.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
