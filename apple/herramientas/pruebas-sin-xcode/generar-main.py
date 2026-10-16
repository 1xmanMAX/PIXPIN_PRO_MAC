#!/usr/bin/env python3
# Escribe el `main.swift` del ejecutor de pruebas sin Xcode: busca en los
# ficheros de prueba cada clase `XCTestCase` y sus `func test...()` (como
# hace XCTest al cargar el paquete) y los registra para `ejecutarPruebas`.
#
#     generar-main.py MODULO SALIDA.swift PRUEBA.swift...
#
# Lo llama `herramientas/pruebas-sin-xcode.sh`; no hace falta a mano.
#
# Lee linea a linea, sin entender Swift entero: una declaracion de tipo en la
# columna 0 abre "la clase de ahora" y cada `func test...()` sangrado que
# venga despues es suyo. Asi estan escritas todas las pruebas de la app.
import re
import sys

TIPO = re.compile(r"^(?:@\w+\s+)*(?:(?:public|internal|final|open)\s+)*(class|extension|struct|enum|actor)\s+(\w+)\s*(?::\s*([^{]+))?")
PRUEBA = re.compile(r"^\s+(?:@\w+\s+)*(?:(?:override|internal|public|open|final|nonisolated)\s+)*func\s+(test\w*)\(\)\s*(async\s+)?(throws\s+)?(?:->\s*Void\s*)?(?:\{.*)?$")


def main():
    modulo, salida, ficheros = sys.argv[1], sys.argv[2], sys.argv[3:]
    clases_de_prueba = set()
    encontradas = []  # (clase, metodo, es_async, lanza)
    for fichero in ficheros:
        actual = None
        with open(fichero, encoding="utf-8") as f:
            for linea in f:
                m = TIPO.match(linea)
                if m:
                    tipo, nombre, herencia = m.groups()
                    actual = nombre
                    if tipo == "class" and herencia and "XCTestCase" in [h.strip() for h in herencia.split(",")]:
                        clases_de_prueba.add(nombre)
                    continue
                m = PRUEBA.match(linea)
                if m and actual:
                    encontradas.append((actual, m.group(1), bool(m.group(2)), bool(m.group(3))))
    pruebas = [p for p in encontradas if p[0] in clases_de_prueba]

    lineas = [
        "// GENERADO por apple/herramientas/pruebas-sin-xcode/generar-main.py: no se edita.",
        "import Foundation",
        "import XCTest",
        "",
        "@MainActor",
        "private func todas() -> [PruebaRegistrada] {",
        "    [",
    ]
    for clase, metodo, es_async, lanza in pruebas:
        llamada = ("try " if lanza else "") + ("await " if es_async else "") + f"($0 as! {clase}).{metodo}()"
        tipo = "asincrona" if es_async else "sincrona"
        lineas.append(f'        PruebaRegistrada(clase: "{clase}", nombre: "{metodo}", '
                      f"crear: {{ {clase}() }}, cuerpo: .{tipo} {{ {llamada} }}),")
    lineas += [
        "    ]",
        "}",
        "",
        "// Sincrono a proposito (ver `correrAsincrono`); el hilo principal ya es",
        "// el del actor principal.",
        f'exit(MainActor.assumeIsolated {{ ejecutarPruebas(todas(), modulo: "{modulo}") }})',
        "",
    ]
    with open(salida, "w", encoding="utf-8") as f:
        f.write("\n".join(lineas))
    print(f"{len(pruebas)} pruebas en {len(clases_de_prueba)} clases")


if __name__ == "__main__":
    main()
