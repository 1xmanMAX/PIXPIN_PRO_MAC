#!/usr/bin/env python3
"""**Trae al Mac los crates de Rust de Windows** (fusion a tres bandas).

    apple/herramientas/portar-de-windows.py /ruta/a/PIXPIN_PRO_WINDOWS [commit]

- base:  Windows en el ultimo commit portado (`apple/docs/windows-portado.txt`)
- mac:   lo que hay aqui (`apple/nucleo`, `apple/por-adaptar`, `apple/por-traducir`)
- nuevo: Windows en `commit` (por omision, su HEAD)

Cada fichero de `crates/<x>` y `apps/<x>` de Windows va a la zona del Mac donde
vive `<x>`. Si el Mac no lo toco desde la base, se toma el de Windows; si
Windows no lo toco, se queda el del Mac; si cambiaron los dos, `git merge-file`
(los .rs pasan antes por `rustfmt` —o el de `$RUSTFMT`—, como `cargo fmt` en Windows, para que el
formato no salga como conflicto). `por-traducir/` no se compila: ahi manda
Windows. `por-adaptar/` si se fusiona (nucleo/ depende de alguno, p. ej.
`pixpin-voz`). Los crates nuevos de Windows se listan para
decidir a mano a que zona van. Lo borrado en el Mac (ya en Swift) no vuelve.

Al acabar deja el informe en `target/portar-de-windows.json`, apunta el commit
en `windows-portado.txt` y dice que ficheros quedaron con conflicto
(`<<<<<<< mac`). Despues: resolverlos, `cargo test --workspace`, y portar a
Swift lo de `apps/pixpin` que cambio (el informe lista los ficheros).
"""
import filecmp
import json
import os
import shutil
import subprocess
import sys
import tempfile

APPLE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAC = os.path.dirname(APPLE)
APUNTE = os.path.join(APPLE, 'docs', 'windows-portado.txt')
ZONAS = ('nucleo', 'por-adaptar', 'por-traducir')


def git(win, *args):
    return subprocess.run(['git', '-C', win, *args], check=True, capture_output=True, text=True).stdout.strip()


def ficheros(raiz):
    fuera = set()
    for d, _, fs in os.walk(raiz):
        for f in fs:
            fuera.add(os.path.relpath(os.path.join(d, f), raiz))
    return fuera


def igual(a, b):
    if os.path.exists(a) != os.path.exists(b):
        return False
    return not os.path.exists(a) or filecmp.cmp(a, b, shallow=False)


def formatear(origen, destino):
    """`rustfmt` por la entrada estandar (no sigue los `mod`); si falla, tal cual."""
    with open(origen, 'rb') as e:
        r = subprocess.run([*os.environ.get('RUSTFMT', 'rustfmt').split(), '--edition', '2024', '--emit', 'stdout'], stdin=e, capture_output=True)
    if r.returncode == 0 and r.stdout:
        with open(destino, 'wb') as s:
            s.write(r.stdout)
    elif origen != destino:
        shutil.copy2(origen, destino)


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    win = os.path.abspath(sys.argv[1])
    nuevo = git(win, 'rev-parse', sys.argv[2] if len(sys.argv) > 2 else 'HEAD')
    base = open(APUNTE).read().split()[0]
    tmp = tempfile.mkdtemp(prefix='portar-')
    for cual, commit in (('base', base), ('nuevo', nuevo)):
        os.makedirs(os.path.join(tmp, cual))
        tar = subprocess.run(['git', '-C', win, 'archive', commit, 'crates', 'apps'], check=True, capture_output=True).stdout
        subprocess.run(['tar', '-x', '-C', os.path.join(tmp, cual)], input=tar, check=True)

    pares, nuevos = [], []
    for grupo in ('crates', 'apps'):
        for x in sorted(os.listdir(os.path.join(tmp, 'nuevo', grupo))):
            zona = next((z for z in ZONAS if os.path.isdir(os.path.join(APPLE, z, x))), None)
            if zona:
                pares.append((f'{grupo}/{x}', f'apple/{zona}/{x}'))
            else:
                nuevos.append(f'{grupo}/{x}')

    informe = {k: [] for k in ('tomado', 'fusion', 'conflicto', 'borrado', 'nuevo', 'borrado_en_mac_cambia_en_windows')}
    informe['crates_nuevos'] = nuevos
    for w, m in pares:
        B, M, N = (os.path.join(tmp, 'base', w), os.path.join(MAC, m), os.path.join(tmp, 'nuevo', w))
        for rel in sorted(ficheros(B) | ficheros(M) | ficheros(N)):
            b, mm, n = (os.path.join(r, rel) for r in (B, M, N))
            clave = f'{m}/{rel}'
            if igual(b, n) or igual(mm, n):
                continue
            if igual(b, mm) or (m.startswith('apple/por-traducir/') and os.path.exists(mm)):
                if os.path.exists(n):
                    os.makedirs(os.path.dirname(mm), exist_ok=True)
                    shutil.copy2(n, mm)
                    informe['tomado' if os.path.exists(b) else 'nuevo'].append(clave)
                else:
                    os.remove(mm)
                    informe['borrado'].append(clave)
                continue
            if not os.path.exists(mm):
                informe['borrado_en_mac_cambia_en_windows'].append(clave)
                continue
            if not os.path.exists(n):
                continue
            bb = b if os.path.exists(b) else '/dev/null'
            if rel.endswith('.rs'):
                formatear(mm, mm)
                if bb != '/dev/null':
                    formatear(bb, os.path.join(tmp, 'base.rs'))
                    bb = os.path.join(tmp, 'base.rs')
            r = subprocess.run(['git', 'merge-file', '-L', 'mac', '-L', 'base', '-L', 'windows', mm, bb, n])
            informe['conflicto' if r.returncode else 'fusion'].append(clave)

    cambios_app = git(win, 'diff', '--name-only', base, nuevo, '--', 'apps/pixpin/src').splitlines()
    informe['app_de_windows_cambiada'] = cambios_app
    os.makedirs(os.path.join(APPLE, 'target'), exist_ok=True)
    with open(os.path.join(APPLE, 'target', 'portar-de-windows.json'), 'w') as f:
        json.dump(informe, f, indent=1, ensure_ascii=False)
    with open(APUNTE, 'w') as f:
        f.write(f'{nuevo}\n')
    shutil.rmtree(tmp)
    print(f'Windows {base[:7]} -> {nuevo[:7]}')
    for k, v in informe.items():
        print(f'{k}: {len(v)}')
    for c in informe['conflicto']:
        print('  CONFLICTO', c)
    for c in nuevos:
        print('  CRATE NUEVO (decidir zona)', c)


if __name__ == '__main__':
    main()
