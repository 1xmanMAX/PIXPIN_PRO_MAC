#!/usr/bin/env python3
"""**PixPin -> PinDesk por dentro**, como el commit 322e8a2 de Windows.

    apple/herramientas/renombrar-a-pindesk.py <raiz> [<raiz>...]

Renombra las carpetas `pixpin-<x>` de los crates (salvo `pixpin-nucleo`, que da
nombre a los simbolos de UniFFI y al .swift de la app) y, dentro de los .rs,
.toml y .lock:

- los nombres de los crates (`pixpin-x`, `pixpin_x`) en cualquier sitio;
- las variables `PIXPIN_*` -> `PINDESK_*`;
- fuera de las cadenas, los identificadores y comentarios (`PixPin` ->
  `PinDesk`, `pixpin` -> `pindesk`).

Las cadenas no se tocan salvo los nombres de crates y las variables: lo que se
escribe en disco o se manda a otro aparato lo decide cada cambio a mano
(`docs/formato-pindesk.md` de Windows). Con `--comprobar <win> <antes> <despues>`
se aplica a Windows en `antes` y se compara con `despues`.
"""
import os
import re
import subprocess
import sys
import tempfile

QUEDAN = {'nucleo'}  # pixpin-nucleo se queda
EXT = ('.rs', '.toml', '.lock')


def crates_de(raices):
    nombres = set()
    for r in raices:
        for zona in ('', 'crates', 'apps', 'nucleo', 'por-adaptar', 'por-traducir'):
            d = os.path.join(r, zona)
            if os.path.isdir(d):
                for x in os.listdir(d):
                    if x.startswith('pixpin-') and os.path.isdir(os.path.join(d, x)):
                        nombres.add(x[len('pixpin-'):])
    return nombres - QUEDAN


def patrones(crates):
    alt = '|'.join(sorted((re.escape(c) for c in crates), key=len, reverse=True))
    guion = re.compile(r'\bpixpin-(' + alt + r')\b')
    bajo = re.compile(r'\bpixpin_(' + '|'.join(sorted((re.escape(c.replace('-', '_')) for c in crates), key=len, reverse=True)) + r')\b')
    return guion, bajo


def nombres(texto, guion, bajo):
    texto = guion.sub(lambda m: 'pindesk-' + m.group(1), texto)
    texto = bajo.sub(lambda m: 'pindesk_' + m.group(1), texto)
    return re.sub(r'\bPIXPIN_', 'PINDESK_', texto)


def codigo(texto):
    """Fuera de cadenas: identificadores y comentarios (`PixPin`, `Pixpin`,
    `pixpin` -> `PinDesk`, `Pindesk`, `pindesk`). No se tocan los nombres que
    se siguen escribiendo con el nombre viejo (fase B: `pixpin:files`,
    `.pixpin-lectura`, `.pixpin2d`...), ni `pixpin_nucleo`, ni «PixPin Max»."""
    texto = re.sub(r'(?<![.])PixPin(?!Max|\s+Max| · hoja|:)', 'PinDesk', texto)
    texto = re.sub(r'(?<![.])(?<!Paquete)Pixpin', 'Pindesk', texto)
    texto = re.sub(r'\.pixpin(?![\w\-])', '.pindesk', texto)
    return re.sub(r'(?<![A-Za-z0-9./\-])pixpin(?![A-Za-z0-9:\-]|_nucleo)', 'pindesk', texto)


CADENA = re.compile(r'''r(#*)"(?:.|\n)*?"\1|b?"(?:\\.|[^"\\])*"|b?'(?:\\.|[^'\\\n])'(?![A-Za-z_])''')


def rust(texto, guion, bajo):
    texto = nombres(texto, guion, bajo)
    fuera, pos = [], 0
    for m in CADENA.finditer(texto):
        fuera.append(codigo(texto[pos:m.start()]))
        fuera.append(m.group(0))
        pos = m.end()
    fuera.append(codigo(texto[pos:]))
    return ''.join(fuera)


def toml(texto, guion, bajo):
    texto = nombres(texto, guion, bajo)
    lineas = []
    for l in texto.split('\n'):
        i = l.find('#')
        if i >= 0 and l[:i].count('"') % 2 == 0:
            l = l[:i] + codigo(l[i:])
        lineas.append(l)
    return '\n'.join(lineas)


def renombrar(raiz, crates):
    guion, bajo = patrones(crates)
    for d, subs, fs in os.walk(raiz, topdown=False):
        if '/target' in d or '/.git' in d:
            continue
        for f in fs:
            p = os.path.join(d, f)
            if f.endswith(EXT):
                t = open(p, encoding='utf-8', errors='surrogateescape').read()
                n = rust(t, guion, bajo) if f.endswith('.rs') else (nombres(t, guion, bajo) if f.endswith('.lock') else toml(t, guion, bajo))
                if n != t:
                    open(p, 'w', encoding='utf-8', errors='surrogateescape').write(n)
        for s in subs:
            if s.startswith('pixpin-') and s[len('pixpin-'):] in crates:
                os.rename(os.path.join(d, s), os.path.join(d, 'pindesk-' + s[len('pixpin-'):]))


def comprobar(win, antes, despues):
    tmp = tempfile.mkdtemp(prefix='renombrar-')
    for c, r in (('a', antes), ('b', despues)):
        os.makedirs(os.path.join(tmp, c))
        tar = subprocess.run(['git', '-C', win, 'archive', r, 'crates', 'apps'], check=True, capture_output=True).stdout
        subprocess.run(['tar', '-x', '-C', os.path.join(tmp, c)], input=tar, check=True)
    a = os.path.join(tmp, 'a')
    cr = crates_de([os.path.join(a, 'crates'), os.path.join(a, 'apps')]) | {''}
    cr.discard('')
    renombrar(a, cr | {'x'})
    # apps/pixpin -> apps/pindesk (sin guion)
    if os.path.isdir(os.path.join(a, 'apps', 'pixpin')):
        os.rename(os.path.join(a, 'apps', 'pixpin'), os.path.join(a, 'apps', 'pindesk'))
    r = subprocess.run(['diff', '-r', '-u', a, os.path.join(tmp, 'b')], capture_output=True, text=True)
    print(r.stdout)
    print(tmp, file=sys.stderr)


def generar(win, rev, destino):
    """Windows en `rev` (crates y apps) con el renombre aplicado, en `destino`."""
    os.makedirs(destino)
    tar = subprocess.run(['git', '-C', win, 'archive', rev, 'crates', 'apps'], check=True, capture_output=True).stdout
    subprocess.run(['tar', '-x', '-C', destino], input=tar, check=True)
    renombrar(destino, crates_de([os.path.join(destino, 'crates'), os.path.join(destino, 'apps')]))
    if os.path.isdir(os.path.join(destino, 'apps', 'pixpin')):
        os.rename(os.path.join(destino, 'apps', 'pixpin'), os.path.join(destino, 'apps', 'pindesk'))


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == '--generar':
        generar(*sys.argv[2:5])
    elif len(sys.argv) > 1 and sys.argv[1] == '--comprobar':
        comprobar(*sys.argv[2:5])
    else:
        raices = sys.argv[1:]
        cr = crates_de(raices)
        for r in raices:
            renombrar(r, cr)
