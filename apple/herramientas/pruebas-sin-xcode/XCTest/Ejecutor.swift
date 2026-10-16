// El ejecutor de las pruebas: lo que hace `xctest` con las de verdad. La
// lista de pruebas la escribe `generar-main.py` (un `main.swift` con cada
// `func test...()` de `apple/app/Tests`).
import Foundation

/// Una prueba: su clase, su nombre, como crear la instancia y como correrla.
public struct PruebaRegistrada {
    /// Sincrona o `async`: las sincronas corren tal cual en el hilo
    /// principal, FUERA de toda tarea, para que un `wait(for:)` en ellas siga
    /// atendiendo la cola principal (como en XCTest).
    public enum Cuerpo {
        case sincrona(@MainActor (XCTestCase) throws -> Void)
        case asincrona(@MainActor (XCTestCase) async throws -> Void)
    }

    public let clase: String
    public let nombre: String
    let crear: @MainActor () -> XCTestCase
    let cuerpo: Cuerpo

    public init(clase: String, nombre: String, crear: @escaping @MainActor () -> XCTestCase, cuerpo: Cuerpo) {
        self.clase = clase
        self.nombre = nombre
        self.crear = crear
        self.cuerpo = cuerpo
    }
}

private let ayuda = """
Uso: pruebas-sin-xcode [--list] [--timeout SEGUNDOS] [FILTRO...]

  FILTRO      solo las pruebas cuyo "Clase/testNombre" contiene el texto
              (o encaja con la expresion regular). Varios: cualquiera vale.
  --list      lista las pruebas (con el filtro) sin correrlas.
  --timeout   cada prueba tiene este maximo (300 s por omision); si se pasa,
              se corta todo con error (una prueba colgada no deja seguir).
"""

/// Corre `op` en una tarea del hilo principal y gira el bucle de eventos
/// hasta que acaba: el `main.swift` es sincrono (si fuera `async`, todo iria
/// dentro de un bloque de la cola principal y un `wait(for:)` ya no podria
/// atenderla).
@MainActor
func correrAsincrono(_ op: @escaping @MainActor () async throws -> Void) throws {
    final class Caja: @unchecked Sendable { var hecho = false; var error: Error? }
    let caja = Caja()
    Task { @MainActor in
        do { try await op() } catch { caja.error = error }
        caja.hecho = true
    }
    while !caja.hecho {
        _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    if let e = caja.error { throw e }
}

/// Corre las pruebas que pasen el filtro y escribe el resumen como XCTest.
/// Devuelve el codigo de salida (0 si todo fue bien). Desde el `main.swift`
/// (sincrono), dentro de `MainActor.assumeIsolated`.
@MainActor
public func ejecutarPruebas(_ todas: [PruebaRegistrada], modulo: String,
                            argumentos: [String] = Array(CommandLine.arguments.dropFirst())) -> Int32 {
    var filtros: [String] = []
    var listar = false
    var limite: TimeInterval = 300
    var resto = argumentos[...]
    while let a = resto.popFirst() {
        switch a {
        case "--list", "-l": listar = true
        case "--timeout": limite = TimeInterval(resto.popFirst() ?? "") ?? limite
        case "--filter": if let f = resto.popFirst() { filtros.append(f) }
        case "-h", "--help": print(ayuda); return 0
        default: filtros.append(a)
        }
    }
    let elegidas = todas.filter { p in
        let id = "\(p.clase)/\(p.nombre)"
        return filtros.isEmpty || filtros.contains { f in
            id.contains(f) || "\(p.clase).\(p.nombre)".contains(f) || id.range(of: f, options: .regularExpression) != nil
        }
    }
    if listar {
        for p in elegidas { print("\(modulo).\(p.clase)/\(p.nombre)") }
        return 0
    }
    if elegidas.isEmpty {
        print("error: ninguna prueba encaja con \(filtros)")
        return 1
    }

    // Como `xctest`: la salida sale al momento aunque vaya a un tubo.
    setvbuf(stdout, nil, _IOLBF, 0)
    let inicio = Date()
    print("Test Suite 'All tests' started at \(inicio).")
    var pasadas = 0, saltadas = 0
    var fallidas: [String] = []
    var totalFallos = 0
    for p in elegidas {
        let nombre = "-[\(modulo).\(p.clase) \(p.nombre)]"
        print("Test Case '\(nombre)' started.")
        EstadoPrueba.actual.empezar(nombre)
        let vigia = Vigia(nombre: nombre, segundos: limite)
        let t0 = Date()
        var saltada: XCTSkip?
        let caso = p.crear()
        caso.name = nombre
        do {
            try caso.setUpWithError()
            caso.setUp()
            do {
                switch p.cuerpo {
                case let .sincrona(f): try f(caso)
                case let .asincrona(f): try correrAsincrono { try await f(caso) }
                }
            } catch let s as XCTSkip {
                saltada = s
            } catch {
                apuntarError(error, "test")
            }
        } catch let s as XCTSkip {
            saltada = s
        } catch {
            apuntarError(error, "setUpWithError")
        }
        caso.cerrar()
        vigia.parar()
        let fallos = EstadoPrueba.actual.terminar()
        let tiempo = String(format: "%.3f", Date().timeIntervalSince(t0))
        if !fallos.isEmpty {
            totalFallos += fallos.count
            fallidas.append(nombre)
            print("Test Case '\(nombre)' failed (\(tiempo) seconds).")
        } else if let s = saltada {
            saltadas += 1
            print("Test Case '\(nombre)' skipped (\(tiempo) seconds): \(s.description)")
        } else {
            pasadas += 1
            print("Test Case '\(nombre)' passed (\(tiempo) seconds).")
        }
    }
    let total = String(format: "%.3f", Date().timeIntervalSince(inicio))
    print("Test Suite 'All tests' \(fallidas.isEmpty ? "passed" : "failed") at \(Date()).")
    print("\t Executed \(elegidas.count) tests, with \(saltadas) tests skipped and \(totalFallos) failures in \(total) seconds")
    print("Resumen: \(pasadas) pasaron, \(fallidas.count) fallaron, \(saltadas) se saltaron (de \(elegidas.count)).")
    for f in fallidas { print("  FALLO \(f)") }
    return fallidas.isEmpty ? 0 : 1
}

/// Si una prueba se cuelga (una espera que nunca llega), corta todo con un
/// error claro en vez de quedarse parado para siempre.
private final class Vigia: @unchecked Sendable {
    private let reloj: DispatchSourceTimer

    init(nombre: String, segundos: TimeInterval) {
        reloj = DispatchSource.makeTimerSource(queue: .global())
        reloj.schedule(deadline: .now() + segundos)
        reloj.setEventHandler {
            print("error: \(nombre) sigue tras \(Int(segundos)) s: se corta (¿una espera colgada?).")
            fflush(stdout)
            exit(2)
        }
        reloj.resume()
    }

    func parar() { reloj.cancel() }
}
