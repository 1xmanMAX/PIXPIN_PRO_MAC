// Un `XCTest` de bolsillo para correr las pruebas de la app SIN Xcode (solo
// con las Command Line Tools, que no traen XCTest). Lo usa
// `herramientas/pruebas-sin-xcode.sh`; la CI sigue con el XCTest de verdad.
//
// Tiene SOLO lo que usan `apple/app/Tests` (XCTestCase con setUp/tearDown,
// la familia XCTAssert*, XCTFail, XCTUnwrap, XCTSkip y las esperas). Si una
// prueba nueva usa algo que no esta, no compila: se anade aqui, imitando lo
// que hace el XCTest de Apple (mensajes incluidos).
//
// Las pruebas corren una a una, como en XCTest: cada una con su instancia
// nueva, las sincronas en el hilo principal y las `async` en el ejecutor que
// pida su clase (`@MainActor` o no).
import Foundation

// MARK: - Estado de la prueba en curso

/// Los fallos de la prueba que corre ahora. Las aserciones pueden llegar de
/// otros hilos (los cierres de una espera), por eso va con cerrojo.
final class EstadoPrueba: @unchecked Sendable {
    static let actual = EstadoPrueba()
    private let cerrojo = NSLock()
    private var nombre: String?
    private var fallos: [String] = []

    func empezar(_ nombre: String) {
        cerrojo.lock(); defer { cerrojo.unlock() }
        self.nombre = nombre
        fallos = []
    }

    func terminar() -> [String] {
        cerrojo.lock(); defer { cerrojo.unlock() }
        nombre = nil
        return fallos
    }

    /// Sin `file` (un error que se escapa de la prueba), como XCTest:
    /// `<unknown>:0`.
    func fallo(_ texto: String, file: StaticString?, line: UInt) {
        // `#filePath` apunta al enlace de la carpeta de compilacion; se da la
        // ruta de verdad (la de `apple/app/Tests`) para que se pueda abrir.
        let ruta = file.map { URL(fileURLWithPath: "\($0)").resolvingSymlinksInPath().path } ?? "<unknown>"
        cerrojo.lock()
        let quien = nombre ?? "(fuera de una prueba)"
        fallos.append(texto)
        cerrojo.unlock()
        print("\(ruta):\(line): error: \(quien) : \(texto)")
        fflush(stdout)
    }
}

private func fallar(_ cabecera: String, _ mensaje: String, file: StaticString?, line: UInt) {
    let texto = mensaje.isEmpty ? cabecera : "\(cabecera) - \(mensaje)"
    EstadoPrueba.actual.fallo(texto, file: file, line: line)
}

private func describir<T>(_ valor: T) -> String {
    String(describing: valor)
}

/// Evalua una expresion de una asercion; si lanza, es un fallo (como XCTest:
/// `XCTAssertEqual failed: threw error "..."`).
private func evaluar<T>(_ nombre: String, _ mensaje: () -> String, file: StaticString, line: UInt,
                        _ cuerpo: () throws -> T) -> T? {
    do {
        return try cuerpo()
    } catch {
        fallar("\(nombre) failed: threw error \"\(error)\"", mensaje(), file: file, line: line)
        return nil
    }
}

// MARK: - Errores que entiende el ejecutor

/// `throw XCTSkip("...")`: la prueba se salta (no falla).
public struct XCTSkip: Error, CustomStringConvertible {
    public let message: String?
    public init(_ message: String? = nil, file: StaticString = #filePath, line: UInt = #line) {
        self.message = message
    }
    public var description: String { message ?? "Test skipped" }
}

/// Lo que lanza `XCTUnwrap` con `nil`: el fallo ya quedo apuntado, el
/// ejecutor no lo cuenta dos veces.
struct FalloYaApuntado: Error {}

// MARK: - Aserciones

public func XCTFail(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    fallar("failed", message, file: file, line: line)
}

public func XCTAssertTrue(_ expression: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String = "",
                          file: StaticString = #filePath, line: UInt = #line) {
    guard let v = evaluar("XCTAssertTrue", message, file: file, line: line, expression) else { return }
    if !v { fallar("XCTAssertTrue failed", message(), file: file, line: line) }
}

public func XCTAssertFalse(_ expression: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String = "",
                           file: StaticString = #filePath, line: UInt = #line) {
    guard let v = evaluar("XCTAssertFalse", message, file: file, line: line, expression) else { return }
    if v { fallar("XCTAssertFalse failed", message(), file: file, line: line) }
}

public func XCTAssertNil(_ expression: @autoclosure () throws -> Any?, _ message: @autoclosure () -> String = "",
                         file: StaticString = #filePath, line: UInt = #line) {
    guard let v = evaluar("XCTAssertNil", message, file: file, line: line, expression) else { return }
    if let algo = v { fallar("XCTAssertNil failed: \"\(describir(algo))\"", message(), file: file, line: line) }
}

public func XCTAssertNotNil(_ expression: @autoclosure () throws -> Any?, _ message: @autoclosure () -> String = "",
                            file: StaticString = #filePath, line: UInt = #line) {
    guard let v = evaluar("XCTAssertNotNil", message, file: file, line: line, expression) else { return }
    if v == nil { fallar("XCTAssertNotNil failed", message(), file: file, line: line) }
}

public func XCTAssertEqual<T: Equatable>(_ expression1: @autoclosure () throws -> T,
                                         _ expression2: @autoclosure () throws -> T,
                                         _ message: @autoclosure () -> String = "",
                                         file: StaticString = #filePath, line: UInt = #line) {
    guard let a = evaluar("XCTAssertEqual", message, file: file, line: line, expression1),
          let b = evaluar("XCTAssertEqual", message, file: file, line: line, expression2) else { return }
    if a != b {
        fallar("XCTAssertEqual failed: (\"\(describir(a))\") is not equal to (\"\(describir(b))\")",
               message(), file: file, line: line)
    }
}

public func XCTAssertEqual<T: FloatingPoint>(_ expression1: @autoclosure () throws -> T,
                                             _ expression2: @autoclosure () throws -> T,
                                             accuracy: T,
                                             _ message: @autoclosure () -> String = "",
                                             file: StaticString = #filePath, line: UInt = #line) {
    guard let a = evaluar("XCTAssertEqual", message, file: file, line: line, expression1),
          let b = evaluar("XCTAssertEqual", message, file: file, line: line, expression2) else { return }
    // Como XCTest: NaN nunca es igual; el resto, si la distancia cabe.
    if a.isNaN || b.isNaN || abs(a - b) > accuracy {
        fallar("XCTAssertEqual failed: (\"\(describir(a))\") is not equal to (\"\(describir(b))\") +/- (\"\(describir(accuracy))\")",
               message(), file: file, line: line)
    }
}

public func XCTAssertNotEqual<T: Equatable>(_ expression1: @autoclosure () throws -> T,
                                            _ expression2: @autoclosure () throws -> T,
                                            _ message: @autoclosure () -> String = "",
                                            file: StaticString = #filePath, line: UInt = #line) {
    guard let a = evaluar("XCTAssertNotEqual", message, file: file, line: line, expression1),
          let b = evaluar("XCTAssertNotEqual", message, file: file, line: line, expression2) else { return }
    if a == b {
        fallar("XCTAssertNotEqual failed: (\"\(describir(a))\") is equal to (\"\(describir(b))\")",
               message(), file: file, line: line)
    }
}

private func comparar<T: Comparable>(_ nombre: String, _ simbolo: String, _ cumple: (T, T) -> Bool,
                                     _ expression1: () throws -> T, _ expression2: () throws -> T,
                                     _ message: () -> String, file: StaticString, line: UInt) {
    guard let a = evaluar(nombre, message, file: file, line: line, expression1),
          let b = evaluar(nombre, message, file: file, line: line, expression2) else { return }
    if !cumple(a, b) {
        fallar("\(nombre) failed: (\"\(describir(a))\") is not \(simbolo) (\"\(describir(b))\")",
               message(), file: file, line: line)
    }
}

public func XCTAssertGreaterThan<T: Comparable>(_ expression1: @autoclosure () throws -> T,
                                                _ expression2: @autoclosure () throws -> T,
                                                _ message: @autoclosure () -> String = "",
                                                file: StaticString = #filePath, line: UInt = #line) {
    comparar("XCTAssertGreaterThan", "greater than", (>), expression1, expression2, message, file: file, line: line)
}

public func XCTAssertGreaterThanOrEqual<T: Comparable>(_ expression1: @autoclosure () throws -> T,
                                                       _ expression2: @autoclosure () throws -> T,
                                                       _ message: @autoclosure () -> String = "",
                                                       file: StaticString = #filePath, line: UInt = #line) {
    comparar("XCTAssertGreaterThanOrEqual", "greater than or equal to", (>=), expression1, expression2, message,
             file: file, line: line)
}

public func XCTAssertLessThan<T: Comparable>(_ expression1: @autoclosure () throws -> T,
                                             _ expression2: @autoclosure () throws -> T,
                                             _ message: @autoclosure () -> String = "",
                                             file: StaticString = #filePath, line: UInt = #line) {
    comparar("XCTAssertLessThan", "less than", (<), expression1, expression2, message, file: file, line: line)
}

public func XCTAssertLessThanOrEqual<T: Comparable>(_ expression1: @autoclosure () throws -> T,
                                                    _ expression2: @autoclosure () throws -> T,
                                                    _ message: @autoclosure () -> String = "",
                                                    file: StaticString = #filePath, line: UInt = #line) {
    comparar("XCTAssertLessThanOrEqual", "less than or equal to", (<=), expression1, expression2, message,
             file: file, line: line)
}

public func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T,
                                    _ message: @autoclosure () -> String = "",
                                    file: StaticString = #filePath, line: UInt = #line,
                                    _ errorHandler: (_ error: Error) -> Void = { _ in }) {
    do {
        _ = try expression()
        fallar("XCTAssertThrowsError failed: did not throw an error", message(), file: file, line: line)
    } catch {
        errorHandler(error)
    }
}

public func XCTAssertNoThrow<T>(_ expression: @autoclosure () throws -> T,
                                _ message: @autoclosure () -> String = "",
                                file: StaticString = #filePath, line: UInt = #line) {
    do {
        _ = try expression()
    } catch {
        fallar("XCTAssertNoThrow failed: threw error \"\(error)\"", message(), file: file, line: line)
    }
}

public func XCTUnwrap<T>(_ expression: @autoclosure () throws -> T?, _ message: @autoclosure () -> String = "",
                         file: StaticString = #filePath, line: UInt = #line) throws -> T {
    if let v = try expression() { return v }
    fallar("XCTUnwrap failed: expected non-nil value of type \"\(T.self)\"", message(), file: file, line: line)
    throw FalloYaApuntado()
}

// MARK: - Esperas

open class XCTestExpectation: @unchecked Sendable {
    private let cerrojo = NSLock()
    private var veces = 0
    public let expectationDescription: String
    open var expectedFulfillmentCount = 1
    open var isInverted = false
    open var assertForOverFulfill = false
    var abierta = true

    public init(description expectationDescription: String = "no description provided") {
        self.expectationDescription = expectationDescription
    }

    open func fulfill(file: StaticString = #filePath, line: UInt = #line) {
        cerrojo.lock()
        veces += 1
        let demasiadas = veces > expectedFulfillmentCount && assertForOverFulfill && abierta
        cerrojo.unlock()
        if demasiadas {
            fallar("API violation - multiple calls made to -[XCTestExpectation fulfill] for \(expectationDescription).",
                   "", file: file, line: line)
        }
    }

    var cumplida: Bool {
        cerrojo.lock(); defer { cerrojo.unlock() }
        return veces >= expectedFulfillmentCount
    }
}

open class XCTWaiter: @unchecked Sendable {
    public enum Result: Int, Sendable {
        case completed = 1, timedOut, incorrectOrder, invertedFulfillment, interrupted
    }

    public init() {}

    /// Espera sin bloquear el hilo (para pruebas `async`). No apunta fallos:
    /// como el XCTWaiter de Apple sin delegado, solo da el resultado.
    open func fulfillment(of expectations: [XCTestExpectation], timeout seconds: TimeInterval,
                          enforceOrder: Bool = false) async -> Result {
        let limite = Date().addingTimeInterval(seconds)
        while Date() < limite {
            if let r = XCTWaiter.resultado(expectations, final: false) { return r }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return XCTWaiter.resultado(expectations, final: true) ?? .timedOut
    }

    /// Bloquea el hilo, pero sigue girando su bucle de eventos (como XCTest):
    /// lo que se entregue a la cola principal llega aunque se espere en ella.
    @discardableResult
    open func wait(for expectations: [XCTestExpectation], timeout seconds: TimeInterval,
                   enforceOrder: Bool = false) -> Result {
        let limite = Date().addingTimeInterval(seconds)
        while Date() < limite {
            if let r = XCTWaiter.resultado(expectations, final: false) { return r }
            _ = RunLoop.current.run(mode: .default, before: min(limite, Date().addingTimeInterval(0.005)))
        }
        return XCTWaiter.resultado(expectations, final: true) ?? .timedOut
    }

    /// `nil` si aun hay que esperar. Las invertidas solo se resuelven al
    /// final (cumplidas = fallo; sin cumplir = bien).
    static func resultado(_ expectations: [XCTestExpectation], final: Bool) -> Result? {
        let normales = expectations.filter { !$0.isInverted }
        let invertidas = expectations.filter { $0.isInverted }
        if invertidas.contains(where: \.cumplida) { return .invertedFulfillment }
        if normales.allSatisfy(\.cumplida) {
            if invertidas.isEmpty || final { return .completed }
            return nil
        }
        return final ? (normales.allSatisfy(\.cumplida) ? .completed : .timedOut) : nil
    }
}

// MARK: - XCTestCase

open class XCTestCase {
    /// `-[Modulo.Clase testAlgo]`, como lo escribe XCTest.
    public internal(set) var name = ""
    open var continueAfterFailure = true
    private enum BloqueDeCierre {
        case sincrono(() throws -> Void)
        case asincrono(() async throws -> Void)
    }
    private var bloquesDeCierre: [BloqueDeCierre] = []
    private var esperasCreadas: [XCTestExpectation] = []
    private let cerrojo = NSLock()

    public required init() {}

    open func setUp() {}
    open func setUpWithError() throws {}
    open func tearDown() {}
    open func tearDownWithError() throws {}

    open func addTeardownBlock(_ block: @escaping () -> Void) {
        cerrojo.lock(); defer { cerrojo.unlock() }
        bloquesDeCierre.append(.sincrono(block))
    }

    open func addTeardownBlock(_ block: @escaping () async throws -> Void) {
        cerrojo.lock(); defer { cerrojo.unlock() }
        bloquesDeCierre.append(.asincrono(block))
    }

    open func expectation(description: String) -> XCTestExpectation {
        let e = XCTestExpectation(description: description)
        e.assertForOverFulfill = true
        cerrojo.lock(); esperasCreadas.append(e); cerrojo.unlock()
        return e
    }

    open func wait(for expectations: [XCTestExpectation], timeout seconds: TimeInterval,
                   enforceOrder: Bool = false, file: StaticString = #filePath, line: UInt = #line) {
        let r = XCTWaiter().wait(for: expectations, timeout: seconds, enforceOrder: enforceOrder)
        apuntarEspera(r, expectations, seconds, file: file, line: line)
    }

    open func fulfillment(of expectations: [XCTestExpectation], timeout seconds: TimeInterval,
                          enforceOrder: Bool = false, file: StaticString = #filePath, line: UInt = #line) async {
        let r = await XCTWaiter().fulfillment(of: expectations, timeout: seconds, enforceOrder: enforceOrder)
        apuntarEspera(r, expectations, seconds, file: file, line: line)
    }

    private func apuntarEspera(_ r: XCTWaiter.Result, _ expectations: [XCTestExpectation], _ seconds: TimeInterval,
                               file: StaticString, line: UInt) {
        for e in expectations { e.abierta = false }
        switch r {
        case .completed: break
        case .invertedFulfillment:
            let cuales = expectations.filter { $0.isInverted && $0.cumplida }.map { "\"\($0.expectationDescription)\"" }
            fallar("Asynchronous wait failed: Fulfilled inverted expectation \(cuales.joined(separator: ", ")).", "",
                   file: file, line: line)
        default:
            let cuales = expectations.filter { !$0.isInverted && !$0.cumplida }.map { "\"\($0.expectationDescription)\"" }
            fallar("Asynchronous wait failed: Exceeded timeout of \(seconds) seconds, with unfulfilled expectations: \(cuales.joined(separator: ", ")).",
                   "", file: file, line: line)
        }
        cerrojo.lock()
        esperasCreadas.removeAll { e in expectations.contains { $0 === e } }
        cerrojo.unlock()
    }

    // Lo que hace XCTest al final de cada prueba, en su orden.
    @MainActor func cerrar() {
        let (bloques, sinEsperar) = cerrojo.withLock {
            defer { bloquesDeCierre = []; esperasCreadas = [] }
            return (Array(bloquesDeCierre.reversed()), esperasCreadas)
        }
        for e in sinEsperar {
            fallar("Failed due to unwaited expectation '\(e.expectationDescription)'.", "", file: nil, line: 0)
        }
        for b in bloques {
            do {
                switch b {
                case let .sincrono(f): try f()
                case let .asincrono(f): try correrAsincrono { try await f() }
                }
            } catch { apuntarError(error, "teardown block") }
        }
        tearDown()
        do { try tearDownWithError() } catch { apuntarError(error, "tearDownWithError") }
    }
}

func apuntarError(_ error: Error, _ donde: String) {
    if error is FalloYaApuntado { return }
    fallar("failed: caught error: \"\(error)\"", donde == "test" ? "" : "en \(donde)", file: nil, line: 0)
}
