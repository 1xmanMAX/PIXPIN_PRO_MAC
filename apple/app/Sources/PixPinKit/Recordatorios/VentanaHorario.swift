// **El calendario semanal del horario** (Windows, 18-oct): las asignaturas a
// la izquierda y la semana a la derecha. Se arrastra una asignatura a la
// rejilla para poner una clase; un bloque se mueve arrastrandolo, se alarga
// por su borde de abajo y se borra con su menu. Todo se guarda en el MISMO
// `horario.md` (`SemanaHorario`, nucleo), asi que se sigue pudiendo
// escribir a mano («Como texto») y los avisos salen de lo mismo.
//
// Desde el 25-oct-2026 (Windows 5139e5d) no es una ventana aparte: es la
// vista «Horario» de Tareas (Tarjetas · Kanban · Horario), y «Horario de
// clases…» abre Tareas en ella. Donde va cada parte lo decide el nucleo
// (`disponerHorarioDeTareas`, el mismo `pixpin_ui::vista_tareas` de
// Windows). Pulsar una asignatura ensena debajo sus tareas pendientes; las
// tareas con hora (`⏰`) de la semana salen como chapitas en su dia y su
// hora, y pulsar una la ensena en las tarjetas.

import AppKit
import PixPinCore
import SwiftUI

@MainActor
final class ModeloSemana: ObservableObject {
    private(set) var semana: SemanaHorario?
    let nucleo: Nucleo
    @Published private(set) var asignaturas: [AsignaturaHorario] = []
    @Published private(set) var bloques: [BloqueHorario] = []
    @Published var error: String?

    init(nucleo: Nucleo) {
        self.nucleo = nucleo
        abrir()
    }

    /// Lee `horario.md` (al crear el modelo y al volver a la vista: pudo
    /// cambiar como texto).
    func abrir() {
        do {
            semana = try SemanaHorario.abrir(nucleo: nucleo)
            error = nil
        } catch {
            semana = nil
            self.error = "\(error)"
        }
        releer()
    }

    func releer() {
        asignaturas = semana?.asignaturas() ?? []
        bloques = semana?.bloques() ?? []
    }

    /// «3 asignaturas · 5 clases», el subtitulo de la barra.
    var subtitulo: String { "\(asignaturas.count) asignaturas · \(bloques.count) clases" }

    /// Hace un cambio, lo guarda y avisa al vigia.
    func cambiar(_ hacer: (SemanaHorario) -> Void) {
        guard let semana else { return }
        hacer(semana)
        do {
            try semana.guardar()
            Recordatorios.compartido.releer()
        } catch {
            self.error = "No se pudo guardar el horario: \(error)"
        }
        releer()
    }
}

/// **El panel Horario** dentro de la ventana de Tareas (la barra de arriba
/// la pone ella).
struct VentanaHorario: View {
    @ObservedObject var modelo: ModeloSemana
    @ObservedObject var tareas: ModeloTareas
    /// 6 (lunes a sabado) o 7 con el domingo (el boton de la barra).
    var dias: Int = 6
    /// Una chapita pulsada: esa tarea en las tarjetas.
    var alPulsarTarea: (TareaConLista) -> Void = { _ in }
    /// «Abrir en Tareas» de una asignatura: sus tarjetas.
    var abrirEnTareas: (String) -> Void = { _ in }
    @State private var nueva = ""
    @State private var arrastrandoFin: (Int, CGFloat)?
    /// La asignatura elegida en la lista (su nombre).
    @State private var elegida: String?
    /// De 7:00 a 22:00.
    static let desde: UInt32 = 7 * 60
    static let hasta: UInt32 = 22 * 60
    static let nombresDias = ["Lun", "Mar", "Mié", "Jue", "Vie", "Sáb", "Dom"]
    /// El alto de la chapita de una tarea y lo que junta dos en una hora.
    static let altoChip: Float = 18
    static let pasoChip: UInt32 = 30
    /// Cuantas tareas pendientes se ensenan de la asignatura elegida.
    static let tareasALaVista = 8
    /// El hueco entre la barra de arriba y el panel.
    static let hueco: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            let d = disponerHorarioDeTareas(
                area: CajaVistaTareas(x: 0, y: Float(Self.hueco), ancho: Float(geo.size.width),
                                      alto: Float(max(0, geo.size.height - Self.hueco))),
                escala: 1)
            ZStack(alignment: .topLeading) {
                lateral
                    .frame(width: CGFloat(d.lateral.ancho), height: CGFloat(d.lateral.alto), alignment: .topLeading)
                    .offset(x: CGFloat(d.lateral.x), y: CGFloat(d.lateral.y))
                TimelineView(.everyMinute) { ctx in
                    rejilla(d, tam: geo.size, ahora: ctx.date)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .overlay(alignment: .bottom) {
            if let e = modelo.error {
                Text(e).font(.caption).padding(6).background(.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 6)).padding()
            }
        }
    }

    // MARK: Las asignaturas

    private var lateral: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Asignaturas").font(.headline)
            HStack {
                TextField("Nueva asignatura (@aula opcional)", text: $nueva).textFieldStyle(.roundedBorder).onSubmit(anadir)
                Button(action: anadir) { Image(systemName: "plus") }.disabled(nueva.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if modelo.asignaturas.isEmpty {
                Text("Escribe una asignatura arriba y arrástrala a la semana.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(modelo.asignaturas.enumerated()), id: \.element.nombre) { i, a in
                        fila(i, a)
                    }
                }
            }
            if let e = elegida, modelo.asignaturas.contains(where: { $0.nombre == e }) {
                Divider()
                tareasDe(e)
            }
            Text("Arrastra una asignatura a la semana para poner una clase.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func fila(_ i: Int, _ a: AsignaturaHorario) -> some View {
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
        .background(Self.color(a.color).opacity(elegida == a.nombre ? 0.32 : 0.15), in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { elegida = elegida == a.nombre ? nil : a.nombre }
        .draggable("asignatura:\(i)")
        .contextMenu {
            Button("Abrir en Tareas") { abrirEnTareas(a.nombre) }
            Button("Borrar", role: .destructive) {
                if elegida == a.nombre { elegida = nil }
                modelo.cambiar { $0.borrarAsignatura(i: UInt32(i)) }
            }
        }
    }

    /// Las tareas pendientes de la asignatura elegida (su lista del chat
    /// «Asignaturas»), con su casilla, y «Abrir en Tareas».
    private func tareasDe(_ nombre: String) -> some View {
        let lista = tareas.listaDeAsignatura(nombre)
        let pendientes = lista?.tareas.filter { !$0.hecha } ?? []
        return VStack(alignment: .leading, spacing: 4) {
            Text("Tareas de \(nombre)").font(.subheadline.bold())
            if pendientes.isEmpty {
                Text("Sin tareas pendientes. En Tareas, elige la asignatura al apuntar.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(pendientes.prefix(Self.tareasALaVista)), id: \.indice) { t in
                Toggle(isOn: Binding(get: { false }, set: { hecha in
                    guard hecha, let lista else { return }
                    Task { await tareas.marcar(TareaConLista(lista: lista, tarea: t), hecha: true) }
                })) {
                    Text(marcasDeTarea(texto: t.texto, desfaseMs: desfaseLocalMs()).vista).lineLimit(1)
                }
                .toggleStyle(.checkbox)
            }
            Button("Abrir en Tareas") { abrirEnTareas(nombre) }
                .buttonStyle(.link)
        }
    }

    private func anadir() {
        let t = nueva.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        nueva = ""
        modelo.cambiar { _ = $0.anadirAsignatura(escrito: t) }
    }

    // MARK: La semana

    /// El numero del dia del mes de un dia (dias desde 1970).
    private static func numeroDelDia(_ dia: Int64) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        return cal.component(.day, from: Date(timeIntervalSince1970: TimeInterval(dia) * 86_400))
    }

    private func rejilla(_ d: DisposicionHorario, tam: CGSize, ahora: Date) -> some View {
        let s = d.semana
        let x0 = CGFloat(s.x), y0 = CGFloat(s.y)
        let ancho = CGFloat(s.ancho) / CGFloat(dias)
        let alto = CGFloat(s.alto) / CGFloat(Self.hasta - Self.desde)
        let colHoras = CGFloat(d.columnaHoras), cabDias = CGFloat(d.cabeceraDias)
        let yDe = { (m: UInt32) -> CGFloat in y0 + CGFloat(Int(m) - Int(Self.desde)) * alto }
        let ahoraMs = milisegundosLocales(ahora)
        let lunes = lunesALaVista(hoyMsLocales: ahoraMs, dias: UInt8(dias))
        let hoy = Int(ahoraMs / 86_400_000 - lunes)
        let minutoAhora = UInt32((ahoraMs % 86_400_000) / 60_000)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10).fill(Paleta.v2.caja.opacity(0.6))
                .frame(width: CGFloat(s.ancho) + 4, height: CGFloat(s.alto) + 4)
                .position(x: x0 + CGFloat(s.ancho) / 2, y: y0 + CGFloat(s.alto) / 2)
            // Hoy, un poco mas claro.
            if (0 ..< dias).contains(hoy) {
                Rectangle().fill(Color.white.opacity(0.03))
                    .frame(width: ancho, height: CGFloat(s.alto))
                    .position(x: x0 + ancho * (CGFloat(hoy) + 0.5), y: y0 + CGFloat(s.alto) / 2)
            }
            // Las horas: raya entera en punto, tenue a la media.
            ForEach(Array(stride(from: Self.desde, through: Self.hasta, by: 30)), id: \.self) { m in
                let y = yDe(m)
                Path { p in p.move(to: CGPoint(x: x0, y: y)); p.addLine(to: CGPoint(x: x0 + CGFloat(s.ancho), y: y)) }
                    .stroke(Color.white.opacity(m % 60 == 0 ? 0.08 : 0.035))
                if m % 60 == 0 {
                    Text("\(m / 60):00").font(.system(size: 11.5)).foregroundStyle(Paleta.v2.gris)
                        .frame(width: colHoras - 8, alignment: .trailing)
                        .position(x: x0 - colHoras / 2 - 4, y: y)
                }
            }
            // Los dias, con su numero; hoy en una pastilla azul.
            ForEach(0 ..< dias, id: \.self) { dia in
                let x = x0 + CGFloat(dia) * ancho
                if dia > 0 {
                    Path { p in p.move(to: CGPoint(x: x, y: y0)); p.addLine(to: CGPoint(x: x, y: y0 + CGFloat(s.alto))) }
                        .stroke(Color.white.opacity(0.06))
                }
                Text("\(Self.nombresDias[dia]) \(Self.numeroDelDia(lunes + Int64(dia)))")
                    .font(.system(size: 12))
                    .foregroundStyle(dia == hoy ? Color.white : Paleta.v2.cuerpo)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(dia == hoy ? Paleta.v2.azulLleno : .clear, in: Capsule())
                    .position(x: x + ancho / 2, y: y0 - cabDias / 2)
            }
            bloques(x0: x0, ancho: ancho, alto: alto, yDe: yDe)
            chips(x0: x0, ancho: ancho, lunes: lunes, yDe: yDe)
            // La rayita roja de la hora de ahora.
            if (0 ..< dias).contains(hoy), (Self.desde ... Self.hasta).contains(minutoAhora) {
                let y = yDe(minutoAhora)
                Path { p in
                    p.move(to: CGPoint(x: x0 + CGFloat(hoy) * ancho, y: y))
                    p.addLine(to: CGPoint(x: x0 + CGFloat(hoy + 1) * ancho, y: y))
                }
                .stroke(Color(hex: 0xFF453A), lineWidth: 2)
                .allowsHitTesting(false)
            }
        }
        .frame(width: tam.width, height: tam.height, alignment: .topLeading)
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { cosas, punto in
            guard let cosa = cosas.first, punto.x > x0, punto.y > y0,
                  punto.x < x0 + CGFloat(s.ancho), punto.y < y0 + CGFloat(s.alto) else { return false }
            let dia = UInt8(min(dias - 1, max(0, Int((punto.x - x0) / ancho))))
            let minuto = Int(Self.desde) + Int((punto.y - y0) / alto)
            if cosa.hasPrefix("asignatura:"), let i = UInt32(cosa.dropFirst(11)) {
                modelo.cambiar { $0.soltar(asignatura: i, dia: dia, minuto: UInt32(minuto)) }
            } else if cosa.hasPrefix("bloque:"), let i = Int(cosa.dropFirst(7)), i < modelo.bloques.count {
                modelo.cambiar { $0.mover(i: UInt32(i), dia: dia, inicio: Int64(minuto / 15 * 15)) }
            }
            return true
        }
    }

    /// Las clases de la semana (las del domingo, solo si se ve).
    private func bloques(x0: CGFloat, ancho: CGFloat, alto: CGFloat, yDe: @escaping (UInt32) -> CGFloat) -> some View {
        ForEach(Array(modelo.bloques.enumerated()), id: \.offset) { i, b in
            if Int(b.dia) < dias {
                let y0 = yDe(b.inicio)
                let finVisto = arrastrandoFin?.0 == i ? arrastrandoFin!.1 : yDe(b.fin)
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
                            arrastrandoFin = (i, yDe(b.fin) + g.translation.height)
                        }.onEnded { g in
                            let fin = yDe(b.fin) + g.translation.height - yDe(Self.desde)
                            arrastrandoFin = nil
                            let minutos = Int(Self.desde) + Int(fin / alto)
                            modelo.cambiar { $0.alargar(i: UInt32(i), fin: UInt32(max(Int(b.inicio) + 15, minutos))) }
                        })
                }
                .padding(.horizontal, 4).padding(.top, 2)
                .frame(width: ancho - 4, height: max(16, finVisto - y0), alignment: .topLeading)
                .background(Self.color(b.color).opacity(0.75), in: RoundedRectangle(cornerRadius: 5))
                .foregroundStyle(.white)
                .position(x: x0 + ancho * CGFloat(b.dia) + ancho / 2, y: y0 + max(16, finVisto - y0) / 2)
                .draggable("bloque:\(i)")
                .contextMenu {
                    Button("Borrar esta clase", role: .destructive) { modelo.cambiar { $0.borrar(i: UInt32(i)) } }
                }
            }
        }
    }

    /// **Las tareas con hora de la semana**, como chapitas pegadas a la
    /// derecha de su dia, encima de las clases (Windows 25-oct).
    private func chips(x0: CGFloat, ancho: CGFloat, lunes: Int64, yDe: @escaping (UInt32) -> CGFloat) -> some View {
        let conHora = tareas.conHora
        let chips = chipsDeLaSemana(horas: conHora.map { $0.tarea.recuerda ?? 0 }, lunes: lunes, dias: UInt8(dias),
                                    desde: Self.desde, hasta: Self.hasta, paso: Self.pasoChip)
        return ForEach(chips, id: \.indice) { c in
            if Int(c.indice) < conHora.count {
                let t = conHora[Int(c.indice)]
                let k = cajaDeChip(xDia: Float(x0 + CGFloat(c.dia) * ancho), anchoDia: Float(ancho),
                                   y: Float(yDe(c.minuto)), carril: c.carril, alto: Self.altoChip, escala: 1)
                ChipDeTareaHorario(texto: marcasDeTarea(texto: t.tarea.texto, desfaseMs: desfaseLocalMs()).vista,
                                   mas: Int(c.mas))
                    .frame(width: CGFloat(k.ancho), height: CGFloat(k.alto))
                    .position(x: CGFloat(k.x + k.ancho / 2), y: CGFloat(k.y + k.alto / 2))
                    .onTapGesture { alPulsarTarea(t) }
                    .help(t.tarea.texto)
            }
        }
    }

    static func color(_ c: UInt32) -> Color {
        Color(red: Double((c >> 16) & 0xFF) / 255, green: Double((c >> 8) & 0xFF) / 255, blue: Double(c & 0xFF) / 255)
    }
}

/// La chapita de una tarea con hora en la semana: un punto, su texto y,
/// si no caben todas las de su hora, «+2».
struct ChipDeTareaHorario: View {
    let texto: String
    let mas: Int
    @State private var encima = false

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(Paleta.v2.acento).frame(width: 6, height: 6)
            Text(mas > 0 ? "\(texto) +\(mas)" : texto)
                .font(.system(size: 11))
                .foregroundStyle(Paleta.v2.texto)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .background {
            ZStack {
                Capsule().fill(Color.black.opacity(0.55))
                Capsule().fill(Paleta.v2.acento.opacity(encima ? 0.55 : 0.35))
            }
        }
        .contentShape(Capsule())
        .onHover { encima = $0 }
    }
}
