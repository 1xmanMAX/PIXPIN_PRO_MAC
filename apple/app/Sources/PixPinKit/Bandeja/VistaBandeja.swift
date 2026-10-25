// **El panel de la barra de menus** (rediseno v2 de Windows,
// `Bandeja2.dc.html`): lo que sale al hacer clic en el icono de PixPin. De
// arriba abajo: el estado de sincronizar y «Sincronizar ahora», un buscador
// de acciones, «Capturar» grande con sus modos, los favoritos, los
// interruptores de los pines y los atajos, las ultimas capturas con sus
// acciones, las ventanas y «Salir», apartado y en rojo.
//
// Las medidas son las de la maqueta (`disposicion.rs`): 440 de ancho, filas
// de 44 y botones de 40 como poco. Sigue el tema del sistema, como alla.
//
// | Tecla | Que hace |
// |---|---|
// | Escribir | Busca una accion |
// | ↑ ↓ / Intro | Elegir y hacer el resultado; sin buscar, Intro captura |
// | Esc | Borra lo buscado, sale de elegir favoritos y al final cierra |
// | ⌘C / ⌦ | Copiar / borrar la captura bajo el raton |
// | ⌘Z | Deshacer el borrado |

import AppKit
import PixPinCore
import SwiftUI

/// Los colores del panel (`Paleta::oscura` y `clara` de Windows).
enum ColoresBandeja {
    static let fondo = Color(claro: 0xFFFFFF, oscuro: 0x1C1C1E)
    static let carta = Color(claro: 0xF2F2F7, oscuro: 0x2A2A2D)
    static let cartaEncima = Color(claro: 0xE5E5EA, oscuro: 0x37373A)
    static let borde = Color(claro: 0xD1D1D6, oscuro: 0x3A3A3C)
    static let texto = Color(claro: 0x1C1C1E, oscuro: 0xF5F5F7)
    static let suave = Color(claro: 0x6E6E73, oscuro: 0x98989D)
    static let chapa = Color(claro: 0xE5E5EA, oscuro: 0x3A3A3C)
    static let azul = Color(hex: 0x0060DF)
    static let azulEncima = Color(hex: 0x0A6CF0)
    static let enlace = Color(claro: 0x0060DF, oscuro: 0x0A84FF)
    static let verde = Color(claro: 0x248A3D, oscuro: 0x30D158)
    static let amarillo = Color(claro: 0x9A7400, oscuro: 0xFFD60A)
    static let naranja = Color(claro: 0xC66900, oscuro: 0xFF9F0A)
    static let rojo = Color(claro: 0xD70015, oscuro: 0xFF453A)
}

public struct VistaBandeja: View {
    @ObservedObject var modelo: ModeloBandeja
    /// Lo mas alto que puede ser (la pantalla menos un margen).
    var altoMaximo: CGFloat
    @FocusState private var enBuscador: Bool

    static let ancho: CGFloat = 340
    static let margen: CGFloat = 10
    static let hueco: CGFloat = 6
    static let fila: CGFloat = 32

    public var body: some View {
        VStack(spacing: Self.hueco) {
            cabecera
            buscador
            ScrollViewReader { desplazar in
                ScrollView {
                    VStack(spacing: Self.hueco) {
                        if modelo.enLista { lista } else { normal }
                    }
                    .background(GeometryReader { g in
                        Color.clear.preference(key: AltoBandeja.self, value: g.size.height)
                    })
                }
                .scrollIndicators(.never)
                .frame(height: alturaLista)
                .onChange(of: modelo.elegida) { _, i in
                    withAnimation(.easeOut(duration: 0.1)) { desplazar.scrollTo(i) }
                }
            }
        }
        .padding(Self.margen)
        .frame(width: Self.ancho)
        .background(ColoresBandeja.fondo)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(ColoresBandeja.borde, lineWidth: 1))
        .overlay(alignment: .bottom) { avisoAbajo }
        .onPreferenceChange(AltoBandeja.self) { modelo.altoContenido = $0 }
        .onAppear { enBuscador = true }
    }

    /// Lo de debajo del buscador, sin pasar de la pantalla.
    private var alturaLista: CGFloat {
        let fijo = Self.margen * 2 + 40 + Self.fila + Self.hueco * 2
        return max(Self.fila, min(modelo.altoContenido, altoMaximo - fijo))
    }

    // MARK: Cabecera

    private var cabecera: some View {
        HStack(spacing: 8) {
            Text("P")
                .font(.system(size: 11.9, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(ColoresBandeja.azul, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 1) {
                Text("PixPin").font(.system(size: 12.8, weight: .bold)).foregroundStyle(ColoresBandeja.texto)
                HStack(spacing: 5) {
                    Circle()
                        .fill(modelo.sincronizando ? ColoresBandeja.enlace
                            : modelo.ultimaSincro > 0 ? ColoresBandeja.verde : ColoresBandeja.suave)
                        .frame(width: 7, height: 5)
                    Text(modelo.sincronizando ? "Sincronizando…"
                        : ReglasBandeja.estadoSincro(ultima: modelo.ultimaSincro,
                                                     ahora: Int64(Date().timeIntervalSince1970 * 1000)))
                        .font(.system(size: 10.2))
                        .foregroundStyle(ColoresBandeja.suave)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            BotonBandeja {
                modelo.pedir(.comando(.sincronizar))
            } contenido: { encima in
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Sincronizar ahora")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ColoresBandeja.enlace)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(encima ? ColoresBandeja.cartaEncima : ColoresBandeja.carta, in: RoundedRectangle(cornerRadius: 10))
            }
            .disabled(modelo.sincronizando || modelo.sincro == nil)
            BotonBandeja {
                modelo.pedir(.comando(.abrirAjustes))
            } contenido: { encima in
                Image(systemName: "gearshape")
                    .font(.system(size: 13.6))
                    .foregroundStyle(ColoresBandeja.texto)
                    .frame(width: 30, height: 30)
                    .background(encima ? ColoresBandeja.cartaEncima : ColoresBandeja.carta, in: RoundedRectangle(cornerRadius: 10))
            }
            .help("Ajustes")
        }
        .frame(height: 30)
    }

    // MARK: Buscador

    private var buscador: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(ColoresBandeja.suave)
            TextField(modelo.editando ? "Buscar qué poner de favorito…" : "Buscar una acción… (escribe sin más)",
                      text: $modelo.consulta)
                .textFieldStyle(.plain)
                .font(.system(size: 11.9))
                .foregroundStyle(ColoresBandeja.texto)
                .focused($enBuscador)
                .onKeyPress(phases: .down) { tecla in teclear(tecla) }
        }
        .padding(.horizontal, 12)
        .frame(height: Self.fila)
        .background(ColoresBandeja.carta, in: RoundedRectangle(cornerRadius: 12))
    }

    private func teclear(_ t: KeyPress) -> KeyPress.Result {
        switch t.key {
        case .escape: modelo.escape(); return .handled
        case .return: modelo.intro(); return .handled
        case .upArrow where modelo.enLista: modelo.mover(-1); return .handled
        case .downArrow where modelo.enLista: modelo.mover(1); return .handled
        case .deleteForward where !modelo.enLista:
            if let i = modelo.encima { modelo.borrarCaptura(i); return .handled }
            return .ignored
        default: break
        }
        if t.modifiers.contains(.command) {
            switch t.characters.lowercased() {
            case "z" where modelo.puedeDeshacer:
                modelo.deshacer()
                return .handled
            case "c" where !modelo.enLista:
                if let i = modelo.encima { modelo.copiarCaptura(i); return .handled }
            default: break
            }
        }
        return .ignored
    }

    // MARK: El panel entero

    @ViewBuilder private var normal: some View {
        tarjetaCapturar
        favoritos
        interruptores
        ultimas
        ventanas
        Rectangle().fill(ColoresBandeja.borde).frame(height: 1)
        salir
    }

    private var tarjetaCapturar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                BotonBandeja {
                    modelo.pedir(.comando(.capturarRegion))
                } contenido: { encima in
                    HStack(spacing: 12) {
                        Image(systemName: "viewfinder").font(.system(size: 18.7, weight: .medium))
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Capturar").font(.system(size: 13.6, weight: .semibold))
                            Text("Elige la zona con el ratón").font(.system(size: 10.2)).opacity(0.8)
                        }
                        Spacer()
                        if let a = modelo.chapita(.comando(.capturarRegion)) {
                            Chapita(texto: a, fondo: .white.opacity(0.2), color: .white)
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                    .background(encima ? ColoresBandeja.azulEncima : ColoresBandeja.azul, in: RoundedRectangle(cornerRadius: 12))
                }
                // «Grabar» (clase o reunion), al lado: a la vista nada mas
                // abrir el panel, como en Windows (edd0ffa).
                BotonBandeja {
                    modelo.pedir(.comando(.grabarClase))
                } contenido: { encima in
                    VStack(spacing: 2) {
                        Image(systemName: "mic").font(.system(size: 15, weight: .medium))
                        Text("Grabar").font(.system(size: 10.2, weight: .medium)).lineLimit(1)
                    }
                    .foregroundStyle(ColoresBandeja.rojo)
                    .frame(width: 64, height: 40)
                    .background(ColoresBandeja.rojo.opacity(encima ? 0.26 : 0.16), in: RoundedRectangle(cornerRadius: 12))
                }
                .help(ComandoAtajo.grabarClase.titulo + (modelo.chapita(.comando(.grabarClase)).map { "  \($0)" } ?? ""))
                .disabled(!modelo.atajos.disponible(.grabarClase))
            }
            HStack(spacing: 6) {
                ForEach(AccionBandeja.modos, id: \.comando) { m in
                    BotonBandeja {
                        modelo.pedir(.comando(m.comando))
                    } contenido: { encima in
                        VStack(spacing: 3) {
                            Image(systemName: AccionBandeja.comando(m.comando).simbolo).font(.system(size: 12.8))
                            Text(m.titulo).font(.system(size: 9.3))
                        }
                        .foregroundStyle(ColoresBandeja.texto)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(encima ? ColoresBandeja.cartaEncima : ColoresBandeja.fondo.opacity(0.6),
                                    in: RoundedRectangle(cornerRadius: 10))
                    }
                    .help(m.comando.titulo + (modelo.chapita(.comando(m.comando)).map { "  \($0)" } ?? ""))
                    .disabled(!modelo.atajos.disponible(m.comando))
                }
            }
        }
        .padding(8)
        .background(ColoresBandeja.carta, in: RoundedRectangle(cornerRadius: 14))
    }

    private var favoritos: some View {
        VStack(spacing: Self.hueco) {
            HStack {
                Etiqueta("Favoritos")
                Spacer()
                BotonBandeja { modelo.empezarAEditar() } contenido: { encima in
                    Text("Editar").font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ColoresBandeja.enlace)
                        .padding(.horizontal, 12)
                        .frame(height: 21)
                        .background(encima ? ColoresBandeja.carta : .clear, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Self.hueco), count: 4), spacing: Self.hueco) {
                ForEach(modelo.favoritos, id: \.self) { a in
                    BotonBandeja { modelo.pedir(a) } contenido: { encima in
                        Ficha(simbolo: a.simbolo, titulo: a.titulo, color: Color(hex: a.color), encima: encima)
                    }
                    .help(a.titulo + (modelo.chapita(a).map { "  \($0)" } ?? ""))
                }
                if modelo.favoritos.count < AccionBandeja.tope {
                    BotonBandeja { modelo.empezarAEditar() } contenido: { encima in
                        Ficha(simbolo: "plus", titulo: "Añadir", color: ColoresBandeja.suave, encima: encima, discreta: true)
                    }
                }
            }
        }
    }

    private var interruptores: some View {
        VStack(alignment: .leading, spacing: 0) {
            Etiqueta(modelo.aLaVista == 1 ? "Pines · 1 a la vista" : "Pines · \(modelo.aLaVista) a la vista")
                .padding(.leading, 12)
                .frame(height: 16)
            FilaInterruptor(titulo: "Ocultar los pines", subtitulo: nil, chapita: modelo.chapita(.comando(.alternarPines)),
                            encendido: modelo.ocultos) { modelo.pedir(.comando(.alternarPines)) }
            if modelo.atajos.disponible(.alternarPasoDeClics) {
                FilaInterruptor(titulo: "Dejar pasar el clic", subtitulo: nil,
                                chapita: modelo.chapita(.comando(.alternarPasoDeClics)),
                                encendido: modelo.pasantes) { modelo.pedir(.comando(.alternarPasoDeClics)) }
            }
            Rectangle().fill(ColoresBandeja.borde).frame(height: 1).padding(.horizontal, 12).padding(.vertical, 4)
            Etiqueta("Atajos").padding(.leading, 12).frame(height: 16)
            FilaInterruptor(titulo: "Silenciar los atajos", subtitulo: "para jugar o presentar",
                            chapita: nil, encendido: modelo.silenciados) { modelo.pedir(.comando(.silenciarAtajos)) }
        }
        .padding(4)
        .background(ColoresBandeja.carta, in: RoundedRectangle(cornerRadius: 14))
    }

    private var ultimas: some View {
        VStack(spacing: Self.hueco) {
            HStack {
                Etiqueta("Últimas capturas")
                Spacer()
                BotonBandeja { modelo.pedir(.galeria) } contenido: { encima in
                    Text("Ver la galería").font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ColoresBandeja.enlace)
                        .padding(.horizontal, 10)
                        .frame(height: 21)
                        .background(encima ? ColoresBandeja.carta : .clear, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            if modelo.capturas.isEmpty {
                Text("Aún no hay capturas")
                    .font(.system(size: 11))
                    .foregroundStyle(ColoresBandeja.suave)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(ColoresBandeja.carta, in: RoundedRectangle(cornerRadius: 10))
            } else {
                HStack(spacing: Self.hueco) {
                    ForEach(0..<ModeloBandeja.cuantasCapturas, id: \.self) { i in
                        if i < modelo.capturas.count {
                            miniatura(i)
                        } else {
                            Color.clear.frame(maxWidth: .infinity).frame(height: 42)
                        }
                    }
                }
            }
        }
    }

    private func miniatura(_ i: Int) -> some View {
        let c = modelo.capturas[i]
        let viva = modelo.encima == i
        return ZStack(alignment: .bottomLeading) {
            ColoresBandeja.carta
            if let img = modelo.minis[c.ruta] {
                Image(nsImage: img).resizable().scaledToFill()
            } else {
                Image(systemName: ModeloBandeja.esVideo(c.ruta) ? "video" : "photo")
                    .font(.system(size: 17))
                    .foregroundStyle(ColoresBandeja.suave)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Text(Self.cuando(c.cuando))
                .font(.system(size: 8.5))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 4))
                .padding(4)
            if viva {
                Color.black.opacity(0.35)
                HStack(spacing: 4) {
                    BotonMini(simbolo: "pin", color: .white) { modelo.pinearCaptura(i) }.help("Pinear")
                    BotonMini(simbolo: "doc.on.doc", color: .white) { modelo.copiarCaptura(i) }.help("Copiar (⌘C)")
                    BotonMini(simbolo: "trash", color: Color(hex: 0xFF6961)) { modelo.borrarCaptura(i) }.help("Borrar (⌦)")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 42)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(viva ? ColoresBandeja.enlace : .clear, lineWidth: 2))
        .contentShape(Rectangle())
        .onHover { dentro in
            if dentro { modelo.encima = i } else if modelo.encima == i { modelo.encima = nil }
        }
        .onTapGesture { modelo.abrirCaptura(i) }
        .help(c.nombre)
    }

    /// «10:02» si es de hoy, «ayer», o la fecha corta.
    static func cuando(_ ms: Int64, ahora: Date = Date(), calendario: Calendar = .current) -> String {
        let f = Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
        if calendario.isDate(f, inSameDayAs: ahora) { return f.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) }
        if let ayer = calendario.date(byAdding: .day, value: -1, to: ahora), calendario.isDate(f, inSameDayAs: ayer) { return "ayer" }
        return f.formatted(.dateTime.day().month(.abbreviated))
    }

    private var ventanas: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Self.hueco), GridItem(.flexible(), spacing: Self.hueco)],
                  spacing: Self.hueco) {
            ForEach(AccionBandeja.ventanas, id: \.self) { a in
                BotonBandeja { modelo.pedir(a) } contenido: { encima in
                    HStack(spacing: 10) {
                        Image(systemName: a.simbolo)
                            .font(.system(size: 13.6))
                            .foregroundStyle(colorVentana(a))
                            .frame(width: 22)
                        Text(a.titulo).font(.system(size: 11.9)).foregroundStyle(ColoresBandeja.texto).lineLimit(1)
                        Spacer(minLength: 2)
                        insignia(a)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: Self.fila)
                    .background(encima ? ColoresBandeja.cartaEncima : ColoresBandeja.carta, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private func colorVentana(_ a: AccionBandeja) -> Color {
        switch a {
        case .tareas: ColoresBandeja.verde
        case .lecciones: ColoresBandeja.amarillo
        case .comando(.abrirChat): ColoresBandeja.enlace
        default: ColoresBandeja.suave
        }
    }

    @ViewBuilder private func insignia(_ a: AccionBandeja) -> some View {
        if a == .tareas, let n = modelo.tareas, n > 0 {
            Text("\(n)").font(.system(size: 9.3, weight: .semibold)).foregroundStyle(.white)
                .padding(.horizontal, 7).frame(height: 15)
                .background(ColoresBandeja.azul, in: Capsule())
        } else if a == .lecciones, let n = modelo.lecciones, n > 0 {
            Text("\(n) para hoy").font(.system(size: 9.3, weight: .semibold)).foregroundStyle(ColoresBandeja.naranja)
                .padding(.horizontal, 7).frame(height: 15)
                .background(Color(hex: 0xFF9F0A, alfa: 0.18), in: Capsule())
        }
    }

    private var salir: some View {
        BotonBandeja { modelo.pedir(.comando(.salir)) } contenido: { encima in
            HStack(spacing: 10) {
                Image(systemName: "power").font(.system(size: 13.6)).frame(width: 22)
                Text("Salir de PixPin").font(.system(size: 11.9, weight: .medium))
                Spacer()
                Text("los pines se cierran").font(.system(size: 10.2)).opacity(0.75)
            }
            .foregroundStyle(ColoresBandeja.rojo)
            .padding(.horizontal, 12)
            .frame(height: Self.fila)
            .background(encima ? ColoresBandeja.rojo.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: La lista (buscar y elegir favoritos)

    @ViewBuilder private var lista: some View {
        if modelo.editando {
            HStack {
                Text("Elige tus favoritos (\(modelo.favoritos.count) de \(AccionBandeja.tope))")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ColoresBandeja.texto)
                Spacer()
                BotonBandeja { modelo.terminarDeEditar() } contenido: { encima in
                    Text("Hecho").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 72, height: 30)
                        .background(encima ? ColoresBandeja.azulEncima : ColoresBandeja.azul, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .frame(height: Self.fila)
        }
        let filas = modelo.filas
        if filas.isEmpty {
            Text("Ninguna acción se llama así")
                .font(.system(size: 11))
                .foregroundStyle(ColoresBandeja.suave)
                .frame(maxWidth: .infinity, minHeight: Self.fila)
        }
        VStack(spacing: 0) {
            ForEach(Array(filas.enumerated()), id: \.offset) { i, a in
                BotonBandeja { modelo.activarFila(i) } contenido: { encima in
                    HStack(spacing: 10) {
                        Image(systemName: a.simbolo)
                            .font(.system(size: 12.8))
                            .foregroundStyle(Color(hex: a.color == 0x48484A ? 0x8E8E93 : a.color))
                            .frame(width: 24)
                        Text(a.titulo).font(.system(size: 11.9)).foregroundStyle(ColoresBandeja.texto).lineLimit(1)
                        Spacer()
                        if let c = modelo.chapita(a) { Chapita(texto: c, fondo: ColoresBandeja.chapa, color: ColoresBandeja.suave) }
                        if modelo.editando {
                            Image(systemName: modelo.favoritos.contains(a) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 14.4))
                                .foregroundStyle(modelo.favoritos.contains(a) ? ColoresBandeja.enlace : ColoresBandeja.suave)
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: Self.fila)
                    .background(i == modelo.elegida || encima ? ColoresBandeja.carta : .clear,
                                in: RoundedRectangle(cornerRadius: 10))
                }
                .id(i)
            }
        }
    }

    // MARK: El aviso

    @ViewBuilder private var avisoAbajo: some View {
        if let t = modelo.aviso {
            HStack(spacing: 12) {
                Text(t).font(.system(size: 11)).foregroundStyle(.white).lineLimit(2)
                if modelo.puedeDeshacer {
                    Button("Deshacer") { modelo.deshacer() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x64D2FF))
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 27)
            .background(Color(hex: 0x2C2C2E).opacity(0.96), in: Capsule())
            .padding(.bottom, 12)
            .transition(.opacity)
        }
    }
}

// MARK: - Piezas

private struct AltoBandeja: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Un boton plano que sabe si tiene el raton encima.
private struct BotonBandeja<Contenido: View>: View {
    let accion: () -> Void
    @ViewBuilder let contenido: (Bool) -> Contenido
    @State private var encima = false
    @Environment(\.isEnabled) private var activo

    var body: some View {
        Button(action: accion) { contenido(encima && activo) }
            .buttonStyle(.plain)
            .onHover { encima = $0 }
            .opacity(activo ? 1 : 0.45)
    }
}

private struct Etiqueta: View {
    let texto: String
    init(_ t: String) { texto = t }
    var body: some View {
        Text(texto).font(.system(size: 10.2, weight: .semibold)).foregroundStyle(ColoresBandeja.suave)
    }
}

private struct Chapita: View {
    let texto: String
    let fondo: Color
    let color: Color
    var body: some View {
        Text(texto).font(.system(size: 9.3, weight: .medium)).foregroundStyle(color)
            .padding(.horizontal, 6).frame(height: 15)
            .background(fondo, in: RoundedRectangle(cornerRadius: 5))
    }
}

/// Un favorito: su icono en un circulo de su color y su nombre.
private struct Ficha: View {
    let simbolo: String
    let titulo: String
    let color: Color
    let encima: Bool
    var discreta = false

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: simbolo)
                .font(.system(size: 11.9, weight: .medium))
                .foregroundStyle(discreta ? color : .white)
                .frame(width: 21, height: 21)
                .background(discreta ? Color.clear : color, in: Circle())
                .overlay(Circle().strokeBorder(discreta ? color.opacity(0.6) : .clear, style: StrokeStyle(lineWidth: 1, dash: [3])))
            Text(titulo).font(.system(size: 9.3)).foregroundStyle(ColoresBandeja.texto).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .background(encima ? ColoresBandeja.cartaEncima : ColoresBandeja.carta, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Una fila con su interruptor (no es un `Toggle`: lo que hace es el
/// comando, y lo que ensena es lo que de verdad paso).
private struct FilaInterruptor: View {
    let titulo: String
    let subtitulo: String?
    let chapita: String?
    let encendido: Bool
    let accion: () -> Void

    var body: some View {
        BotonBandeja(accion: accion) { encima in
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(titulo).font(.system(size: 11.9)).foregroundStyle(ColoresBandeja.texto)
                    if let subtitulo {
                        Text(subtitulo).font(.system(size: 9.3)).foregroundStyle(ColoresBandeja.suave)
                    }
                }
                Spacer()
                if let chapita { Chapita(texto: chapita, fondo: ColoresBandeja.chapa, color: ColoresBandeja.suave) }
                Capsule()
                    .fill(encendido ? ColoresBandeja.verde : ColoresBandeja.borde)
                    .frame(width: 28, height: 16)
                    .overlay(alignment: encendido ? .trailing : .leading) {
                        Circle().fill(.white).frame(width: 14, height: 14).padding(2).shadow(radius: 0.5)
                    }
            }
            .padding(.horizontal, 12)
            .frame(height: VistaBandeja.fila)
            .background(encima ? ColoresBandeja.cartaEncima : .clear, in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

private struct BotonMini: View {
    let simbolo: String
    let color: Color
    let accion: () -> Void
    @State private var encima = false

    var body: some View {
        Button(action: accion) {
            Image(systemName: simbolo)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 21, height: 21)
                .background(.black.opacity(encima ? 0.8 : 0.55), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { encima = $0 }
    }
}
