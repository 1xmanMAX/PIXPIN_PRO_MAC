// El HTTPS del asistente: el `TransporteApp` que pide el nucleo de Rust
// (`pixpin-nucleo/src/asistente/transporte.rs`). Rust arma la peticion de
// Claude o DeepSeek (la misma que en Windows) y aqui URLSession la manda
// con el TLS, el proxy y los certificados del sistema; la respuesta (SSE)
// vuelve a Rust a trozos mientras llega, y si Rust dice que pare (el boton
// «Parar»), se cancela la peticion.
//
// Rust llama a `enviar` desde un hilo suyo y espera: aqui se bloquea ese
// hilo (nunca el principal ni uno de Swift Concurrency) con un semaforo
// hasta que URLSession acaba.
//
// La clave va en las cabeceras y no se escribe en ningun sitio.

import Foundation
import PixPinCore

public final class TransporteHttps: TransporteApp, @unchecked Sendable {
    /// La configuracion de cada peticion. Las pruebas ponen una con un
    /// `URLProtocol` falso: nunca se llama a una API de pago.
    nonisolated(unsafe) static var configuracion: URLSessionConfiguration = {
        let c = URLSessionConfiguration.ephemeral
        // Los mismos plazos que WinHTTP en Windows: 20 s para conectar y
        // hasta 3 min sin recibir nada (pensar tarda).
        c.timeoutIntervalForRequest = 180
        c.timeoutIntervalForResource = 15 * 60
        c.waitsForConnectivity = false
        c.urlCache = nil
        return c
    }()

    private static let cerrojo = NSLock()
    nonisolated(unsafe) private static var instalado = false

    /// La cabecera con el plazo en segundos que pone el nucleo (Jev).
    static let cabeceraPlazo = "X-PixPin-Plazo"

    /// Instala el HTTPS en el nucleo (una vez por proceso; las demas no
    /// hacen nada). Lo llama el asistente y «Probar» antes de usar la nube.
    public static func instalar() {
        cerrojo.lock()
        defer { cerrojo.unlock() }
        guard !instalado else { return }
        // Si ya habia uno (otro camino lo instalo), vale igual.
        try? instalarTransporte(transporte: TransporteHttps())
        instalado = true
    }

    public func enviar(url: String, cabeceras: [CabeceraHttp], cuerpo: Data, receptor: ReceptorHttp) -> String? {
        guard let destino = URL(string: url), destino.scheme == "https" else {
            return "dirección no válida"
        }
        var pedido = URLRequest(url: destino)
        pedido.httpMethod = "POST"
        pedido.setValue("application/json", forHTTPHeaderField: "Content-Type")
        pedido.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        for c in cabeceras {
            pedido.setValue(c.valor, forHTTPHeaderField: c.nombre)
        }
        pedido.httpBody = cuerpo
        let delegado = Delegado(receptor: receptor)
        let cola = OperationQueue()
        cola.maxConcurrentOperationCount = 1
        cola.qualityOfService = .utility
        let sesion = URLSession(configuration: TransporteHttps.configuracion, delegate: delegado, delegateQueue: cola)
        sesion.dataTask(with: pedido).resume()
        delegado.hecho.wait()
        sesion.finishTasksAndInvalidate()
        return delegado.error
    }

    /// Una peticion cualquiera de las conexiones (Google Drive y su OAuth):
    /// su metodo y solo sus cabeceras; la `Location` va a Rust antes que
    /// los datos (la subida reanudable de Drive la necesita).
    public func pedir(metodo: String, url: String, cabeceras: [CabeceraHttp], cuerpo: Data,
                      receptor: ReceptorHttp) -> String? {
        guard let destino = URL(string: url), destino.scheme == "https" else {
            return "dirección no válida"
        }
        var pedido = URLRequest(url: destino)
        pedido.httpMethod = metodo
        for c in cabeceras {
            // El plazo de la peticion (Jev: unos segundos), que no sale a
            // la red (`jev::CABECERA_PLAZO` del nucleo).
            if c.nombre == TransporteHttps.cabeceraPlazo {
                if let s = Double(c.valor), s > 0 { pedido.timeoutInterval = s }
                continue
            }
            pedido.setValue(c.valor, forHTTPHeaderField: c.nombre)
        }
        if !cuerpo.isEmpty { pedido.httpBody = cuerpo }
        let delegado = Delegado(receptor: receptor)
        let cola = OperationQueue()
        cola.maxConcurrentOperationCount = 1
        cola.qualityOfService = .utility
        let sesion = URLSession(configuration: TransporteHttps.configuracion, delegate: delegado, delegateQueue: cola)
        sesion.dataTask(with: pedido).resume()
        delegado.hecho.wait()
        sesion.finishTasksAndInvalidate()
        return delegado.error
    }

    /// **Un GET a una pagina de internet** (la web del asistente con
    /// DeepSeek, `nube::http::bajar_web`, como el de WinHTTP de Windows):
    /// sin cookies ni credenciales y **sin seguir redirecciones** (la 3xx
    /// vuelve a Rust con su `Location`, que la comprueba antes de seguirla).
    /// El `Content-Type` va a Rust antes que los datos. Una pagina `http://`
    /// la puede parar la seguridad de transporte del Mac (ATS): sale el error.
    public func bajarWeb(url: String, cabeceras: [CabeceraHttp], receptor: ReceptorHttp) -> String? {
        guard let destino = URL(string: url), destino.scheme == "https" || destino.scheme == "http" else {
            return "dirección no válida"
        }
        var pedido = URLRequest(url: destino)
        pedido.httpMethod = "GET"
        pedido.httpShouldHandleCookies = false
        pedido.timeoutInterval = 20
        for c in cabeceras {
            if c.nombre == TransporteHttps.cabeceraPlazo {
                if let s = Double(c.valor), s > 0 { pedido.timeoutInterval = min(s, 20) }
                continue
            }
            pedido.setValue(c.valor, forHTTPHeaderField: c.nombre)
        }
        let configuracion = URLSessionConfiguration.ephemeral
        configuracion.httpCookieStorage = nil
        configuracion.httpShouldSetCookies = false
        configuracion.urlCredentialStorage = nil
        configuracion.urlCache = nil
        configuracion.waitsForConnectivity = false
        configuracion.timeoutIntervalForResource = 120
        let delegado = Delegado(receptor: receptor)
        delegado.sinRedirecciones = true
        let cola = OperationQueue()
        cola.maxConcurrentOperationCount = 1
        cola.qualityOfService = .utility
        let sesion = URLSession(configuration: configuracion, delegate: delegado, delegateQueue: cola)
        sesion.dataTask(with: pedido).resume()
        delegado.hecho.wait()
        sesion.finishTasksAndInvalidate()
        return delegado.error
    }

    /// Pasa la respuesta a Rust mientras llega.
    final class Delegado: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        let receptor: ReceptorHttp
        let hecho = DispatchSemaphore(value: 0)
        var error: String?
        /// La web: una redireccion no se sigue, vuelve tal cual a Rust.
        var sinRedirecciones = false
        private var cortado = false

        init(receptor: ReceptorHttp) {
            self.receptor = receptor
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            let http = response as? HTTPURLResponse
            let espera = http?.value(forHTTPHeaderField: "retry-after").flatMap(Double.init) ?? -1
            receptor.estado(codigo: UInt32(http?.statusCode ?? 0), reintentarEnS: espera)
            if let donde = http?.value(forHTTPHeaderField: "Location") {
                receptor.ubicacion(valor: donde)
            }
            if let tipo = http?.value(forHTTPHeaderField: "Content-Type") {
                receptor.tipo(valor: tipo)
            }
            completionHandler(.allow)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(sinRedirecciones ? nil : request)
        }

        /// En la web, ni las credenciales del Mac ni las de nadie: lo que
        /// pide iniciar sesion vuelve con su 401.
        func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            let metodo = challenge.protectionSpace.authenticationMethod
            if sinRedirecciones && metodo != NSURLAuthenticationMethodServerTrust {
                completionHandler(.rejectProtectionSpace, nil)
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            guard !cortado else { return }
            if !receptor.datos(trozo: data) {
                cortado = true
                dataTask.cancel()
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let error, !cortado {
                self.error = TransporteHttps.texto(de: error)
            }
            hecho.signal()
        }
    }

    /// El error de red en palabras (sin la URL, que no aporta).
    static func texto(de error: Error) -> String {
        let e = error as NSError
        switch e.code {
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost: return "sin conexión a internet"
        case NSURLErrorTimedOut: return "tardó demasiado en contestar"
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed: return "no se encuentra el servidor"
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted: return "la conexión segura falló"
        default: return e.localizedDescription
        }
    }
}
