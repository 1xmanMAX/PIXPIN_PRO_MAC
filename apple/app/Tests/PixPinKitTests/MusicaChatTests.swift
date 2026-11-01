@testable import PixPinKit
import XCTest

final class MusicaChatTests: XCTestCase {
    func testElDetalleLlevaElArtistaYLoQueDura() {
        XCTAssertEqual(MusicaChat.detalle(artista: "Queen", tiempo: "3:12"), "Queen · 3:12")
        XCTAssertEqual(MusicaChat.detalle(artista: "Queen", tiempo: ""), "Queen")
        XCTAssertEqual(MusicaChat.detalle(artista: nil, tiempo: "3:12"), "3:12")
    }

    func testLaLineaQueSuenaEsLaUltimaQueEmpezo() {
        let t = FormatoVoz.trozos("[0:05] Uno\n\n[0:10] Dos\n\n[0:20] Tres")
        XCTAssertNil(MusicaChat.porDondeVa(t, ms: 1000), "antes de empezar no suena ninguna")
        XCTAssertEqual(MusicaChat.porDondeVa(t, ms: 12_000), 1)
        XCTAssertEqual(MusicaChat.porDondeVa(t, ms: 99_000), 2)
    }

    func testElDegradadoDeUnaCancionEsSiempreElMismo() {
        XCTAssertEqual(MusicaChat.degradado("abc").0, MusicaChat.degradado("abc").0)
    }
}
