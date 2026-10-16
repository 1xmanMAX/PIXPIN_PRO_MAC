#!/usr/bin/env bash
# Corre las pruebas de la app (`apple/app/Tests`, las de `swift test`) en un
# Mac SIN Xcode, solo con las Command Line Tools: alli `swift test` no puede
# (`no such module 'XCTest'`). Despues de `herramientas/xcframework.sh`:
#
#     apple/herramientas/pruebas-sin-xcode.sh                 # todas
#     apple/herramientas/pruebas-sin-xcode.sh Almacen Sincro  # las que contengan eso
#     apple/herramientas/pruebas-sin-xcode.sh --list          # cuales hay
#
# Como: monta en `apple/target/pruebas-sin-xcode/` (no se versiona) un
# paquete de SwiftPM aparte con
#   - `XCTest`: un XCTest de bolsillo (`pruebas-sin-xcode/XCTest/`) con lo
#     que usan las pruebas, y el ejecutor;
#   - `PixPinKit`: el de la app, tal cual (enlace a `app/Sources/PixPinKit`);
#   - `PixPinKitTests`: un ejecutable con los ficheros de prueba (enlaces, sin
#     tocarlos) y un `main.swift` que escribe `generar-main.py` con cada
#     `func test...()`.
# Ni las pruebas ni `app/Package.swift` cambian: la CI (con Xcode) sigue con
# `swift test` y el XCTest de verdad.
#
# Sale con 0 si todo pasa y con 1 si algo falla (2 si una prueba se cuelga).
set -euo pipefail

APPLE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AQUI="$APPLE/herramientas/pruebas-sin-xcode"
PRUEBAS="$APPLE/app/Tests/PixPinKitTests"
PAQ="$APPLE/target/pruebas-sin-xcode"

if [ ! -d "$APPLE/PixPinCore/PixPinCoreFFI.xcframework" ]; then
    echo "Falta PixPinCore/PixPinCoreFFI.xcframework: primero apple/herramientas/xcframework.sh" >&2
    exit 1
fi

mkdir -p "$PAQ/Sources/PixPinKitTests"
ln -sfn "$AQUI/XCTest" "$PAQ/Sources/XCTest"
ln -sfn "$APPLE/app/Sources/PixPinKit" "$PAQ/Sources/PixPinKit"

# Los ficheros de prueba, enlazados uno a uno (los que ya no esten, fuera).
find "$PAQ/Sources/PixPinKitTests" -type l -delete
for f in "$PRUEBAS"/*.swift; do
    ln -s "$f" "$PAQ/Sources/PixPinKitTests/$(basename "$f")"
done
python3 "$AQUI/generar-main.py" PixPinKitTests "$PAQ/Sources/PixPinKitTests/main.swift" "$PRUEBAS"/*.swift

cat > "$PAQ/Package.swift" <<EOF
// swift-tools-version:6.0
// GENERADO por apple/herramientas/pruebas-sin-xcode.sh: no se edita.
import PackageDescription

let package = Package(
    name: "PruebasSinXcode",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "$APPLE/PixPinCore"),
    ],
    targets: [
        .target(name: "XCTest", path: "Sources/XCTest"),
        .target(
            name: "PixPinKit",
            dependencies: [.product(name: "PixPinCore", package: "PixPinCore")],
            path: "Sources/PixPinKit",
            // Para el \`@testable import PixPinKit\` de las pruebas.
            swiftSettings: [.unsafeFlags(["-enable-testing"])]
        ),
        .executableTarget(
            name: "PixPinKitTests",
            dependencies: ["XCTest", "PixPinKit", .product(name: "PixPinCore", package: "PixPinCore")],
            path: "Sources/PixPinKitTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
EOF

cd "$PAQ"
swift build --product PixPinKitTests
exec "$PAQ/.build/debug/PixPinKitTests" "$@"
