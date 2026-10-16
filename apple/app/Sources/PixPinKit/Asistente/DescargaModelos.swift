// **Bajar el modelo local** del asistente, cuando el usuario lo pide (la
// tarjeta de la ventana del asistente), nunca al instalar: el motor
// `llama-server` de llama.cpp para macOS (~12 MB, Metal) y el GGUF elegido
// en Ajustes → Asistente (Qwen3.5 2B, ~1,9 GB; 0.8B, ~0,7 GB; Gemma 4 E2B
// para «mejor vista», ~4,1 GB). Lo mismo que Windows y Android.
//
// Lo baja URLSession (con su proxy y sus certificados) a un temporal; el
// nucleo de Rust dice adonde va cada fichero (`iaRutaDescarga`), comprueba
// su huella SHA-256 (`iaVerificarDescarga`: si no coincide, lo borra) y da
// el motor por bueno tras sacarlo con `tar` (`iaTerminarMotor`). Lo que ya
// esta no se vuelve a bajar.

import Foundation
import PixPinCore

/// Donde viven los modelos en este Mac (no viajan: son gigas).
public func carpetaDeModelos() -> URL {
    carpetaDeDatos().appendingPathComponent("modelos", isDirectory: true)
}

@MainActor
public final class DescargaModelos: ObservableObject {
    public static let compartida = DescargaModelos()

    public enum Estado: Equatable {
        case quieta
        /// `fraccion` de 0 a 1 del total; `fichero` el que baja.
        case bajando(fraccion: Double, fichero: String)
        case comprobando(fichero: String)
        case lista
        case error(String)
    }

    @Published public private(set) var estado: Estado = .quieta
    /// Lo que se baja (el id del modelo).
    @Published public private(set) var modelo: String?

    let carpeta: URL
    private var tarea: Task<Void, Never>?
    private var actual: URLSessionDownloadTask?

    init(carpeta: URL = carpetaDeModelos()) {
        self.carpeta = carpeta
    }

    public var ocupada: Bool {
        switch estado {
        case .bajando, .comprobando: return true
        default: return false
        }
    }

    /// Lo que hay y lo que falta (lee el disco: barato).
    public func catalogo() -> CatalogoLocal {
        iaCatalogoLocal(carpeta: carpeta.path)
    }

    /// Cuanto falta por bajar para tener `id` listo (motor incluido).
    public func faltan(_ id: String) -> UInt64 {
        let c = catalogo()
        let motor = c.motor.listo ? 0 : c.motor.bytes
        let ficheros = c.modelos.first { $0.id == id }?.ficheros.filter { !$0.listo } ?? []
        return motor + ficheros.reduce(0) { $0 + $1.bytes }
    }

    /// **Baja lo que falte** del modelo `id` (y el motor).
    public func bajar(_ id: String) {
        guard !ocupada else { return }
        modelo = id
        tarea = Task { [weak self] in
            await self?.trabajar(id)
        }
    }

    public func cancelar() {
        actual?.cancel()
        tarea?.cancel()
        estado = .quieta
    }

    private func trabajar(_ id: String) async {
        let c = catalogo()
        guard let m = c.modelos.first(where: { $0.id == id }) else {
            estado = .error("No conozco el modelo «\(id)».")
            return
        }
        var pendientes: [(que: String, f: FicheroIa)] = []
        if !c.motor.listo { pendientes.append(("motor", c.motor)) }
        pendientes += m.ficheros.filter { !$0.listo }.map { (m.id, $0) }
        let total = Double(max(1, pendientes.reduce(0) { $0 + $1.f.bytes }))
        var hecho: UInt64 = 0
        let raiz = carpeta.path
        do {
            for (que, f) in pendientes {
                try Task.checkCancellation()
                let destino = URL(fileURLWithPath: try iaRutaDescarga(carpeta: raiz, que: que, nombre: f.nombre))
                let base = hecho
                // Un fichero del tamano justo pero sin marca (se corto al
                // verificar): se verifica sin volver a bajarlo.
                let tam = (try? FileManager.default.attributesOfItem(atPath: destino.path)[.size] as? UInt64) ?? nil
                if tam != f.bytes {
                    estado = .bajando(fraccion: Double(base) / total, fichero: f.nombre)
                    let bajado = try await descargar(f.url) { [weak self] escritos in
                        self?.estado = .bajando(fraccion: Double(base + UInt64(escritos)) / total, fichero: f.nombre)
                    }
                    try? FileManager.default.removeItem(at: destino)
                    try FileManager.default.moveItem(at: bajado, to: destino)
                }
                estado = .comprobando(fichero: f.nombre)
                try await Task.detached(priority: .utility) {
                    try iaVerificarDescarga(carpeta: raiz, que: que, nombre: f.nombre)
                }.value
                if que == "motor" {
                    try await sacarMotor(destino)
                }
                hecho += f.bytes
            }
            estado = .lista
        } catch is CancellationError {
            estado = .quieta
        } catch let e as URLError where e.code == .cancelled {
            estado = .quieta
        } catch {
            estado = .error(ModeloAjustes.texto(de: error))
        }
    }

    /// Saca el `.tar.gz` del motor con el `tar` del sistema.
    private func sacarMotor(_ tgz: URL) async throws {
        let raiz = carpeta.path
        try await Task.detached(priority: .utility) {
            let dentro = try iaCarpetaMotor(carpeta: raiz)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            p.arguments = ["-xzf", tgz.path, "-C", dentro, "--strip-components", "1"]
            try p.run()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else {
                throw ErrorNucleo.Asistente(detalle: "no se pudo sacar el motor (tar \(p.terminationStatus))")
            }
            try iaTerminarMotor(carpeta: raiz)
        }.value
    }

    /// Baja `url` a un temporal, avisando de lo escrito.
    private func descargar(_ url: String, avance: @escaping @MainActor (Int64) -> Void) async throws -> URL {
        guard let u = URL(string: url) else { throw URLError(.badURL) }
        let delegado = DelegadoDescarga(avance: avance)
        let sesion = URLSession(configuration: .default, delegate: delegado, delegateQueue: nil)
        defer { sesion.finishTasksAndInvalidate() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<URL, Error>) in
                delegado.fin = c
                let t = sesion.downloadTask(with: u)
                actual = t
                t.resume()
            }
        } onCancel: {
            sesion.invalidateAndCancel()
        }
    }
}

/// El progreso y el final de una descarga.
final class DelegadoDescarga: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let avance: @MainActor (Int64) -> Void
    var fin: CheckedContinuation<URL, Error>?
    private var ultimo = Date.distantPast

    init(avance: @escaping @MainActor (Int64) -> Void) {
        self.avance = avance
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        // La barra no necesita mas de 5 avisos por segundo.
        guard Date().timeIntervalSince(ultimo) > 0.2 else { return }
        ultimo = Date()
        let avance = self.avance
        Task { @MainActor in avance(totalBytesWritten) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // El temporal de URLSession se borra al volver: se mueve ya.
        let aqui = FileManager.default.temporaryDirectory.appendingPathComponent("pixpin-modelo-\(UUID().uuidString)")
        do {
            if let http = downloadTask.response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
                throw ErrorNucleo.Asistente(detalle: "el servidor contestó \(http.statusCode)")
            }
            try FileManager.default.moveItem(at: location, to: aqui)
            fin?.resume(returning: aqui)
        } catch {
            fin?.resume(throwing: error)
        }
        fin = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            fin?.resume(throwing: error)
            fin = nil
        }
    }
}
