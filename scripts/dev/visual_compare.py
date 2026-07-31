#!/usr/bin/env python3
"""Comparar un frame de Claude Design contra la app corriendo.

Existe porque la comparación visual es el corazón del contrato de diseño y
hasta ahora cada agente la improvisaba: decodificar el resultado de DesignSync
a mano, y después sostener el frame y la captura en la cabeza al mismo tiempo.
Sostener dos imágenes en la cabeza es exactamente donde se cuelan las
diferencias que nadie ve.

    visual_compare.py decode <resultado-designsync.txt> [destino/]
    visual_compare.py side <frame.png> <app.png> <salida.png>
    visual_compare.py columns <png> --band Y0 Y1

Sin dependencias: esta máquina no tiene PIL ni ImageMagick, así que el PNG se
decodifica y se escribe acá mismo con `zlib`.

REGLA QUE NO SE PUEDE ROMPER: el compuesto de `side` es para MIRAR, nunca para
medir. Escala una de las dos imágenes, así que cualquier número sacado de él
está mal. Las medidas salen del frame original con `columns`, que es legítimo
porque Design publica recortes sin reescalar. Los valores de color, radio,
sombra y tipografía NO se miden en ninguna imagen: se leen del archivo con
DesignSync. Ver DESIGN_HANDOFF_SYNC_CONTRACT.md.
"""
from __future__ import annotations

import base64
import json
import os
import struct
import sys
import zlib


# ── PNG mínimo ───────────────────────────────────────────────────────────────

def read_png(path: str) -> tuple[int, int, bytearray]:
    """Devuelve (ancho, alto, RGBA) de un PNG de 8 bits por canal."""
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"{path}: no es un PNG")
    pos, idat, width = 8, b"", None
    height = depth = color = None
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos:pos + 4])
        kind = data[pos + 4:pos + 8]
        chunk = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            width, height, depth, color = struct.unpack(">IIBB", chunk[:10])
        elif kind == b"IDAT":
            idat += chunk
        elif kind == b"IEND":
            break
    if depth != 8 or color not in (0, 2, 4, 6):
        raise SystemExit(f"{path}: sólo 8 bits sin paleta (depth={depth} color={color})")

    channels = {0: 1, 2: 3, 4: 2, 6: 4}[color]
    raw = zlib.decompress(idat)
    stride = width * channels
    out = bytearray(width * height * 4)
    previous = bytearray(stride)
    pos = 0
    for y in range(height):
        filter_kind = raw[pos]
        pos += 1
        line = bytearray(raw[pos:pos + stride])
        pos += stride
        # Des-filtrado por scanline, tal como manda la especificación.
        if filter_kind == 1:
            for x in range(channels, stride):
                line[x] = (line[x] + line[x - channels]) & 255
        elif filter_kind == 2:
            for x in range(stride):
                line[x] = (line[x] + previous[x]) & 255
        elif filter_kind == 3:
            for x in range(stride):
                left = line[x - channels] if x >= channels else 0
                line[x] = (line[x] + ((left + previous[x]) >> 1)) & 255
        elif filter_kind == 4:
            for x in range(stride):
                a = line[x - channels] if x >= channels else 0
                b = previous[x]
                c = previous[x - channels] if x >= channels else 0
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[x] = (line[x] + pred) & 255
        previous = line

        for x in range(width):
            source = x * channels
            target = (y * width + x) * 4
            if channels == 1:
                grey = line[source]
                out[target:target + 4] = bytes((grey, grey, grey, 255))
            elif channels == 2:
                grey = line[source]
                out[target:target + 4] = bytes((grey, grey, grey, line[source + 1]))
            elif channels == 3:
                out[target:target + 3] = line[source:source + 3]
                out[target + 3] = 255
            else:
                out[target:target + 4] = line[source:source + 4]
    return width, height, out


def write_png(path: str, width: int, height: int, rgba: bytearray) -> None:
    rows = bytearray()
    for y in range(height):
        rows.append(0)  # filtro "none": el archivo es intermedio, no un entregable
        rows += rgba[y * width * 4:(y + 1) * width * 4]

    def chunk(kind: bytes, payload: bytes) -> bytes:
        return (struct.pack(">I", len(payload)) + kind + payload
                + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF))

    open(path, "wb").write(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(bytes(rows), 6))
        + chunk(b"IEND", b"")
    )


def scale(width: int, height: int, rgba: bytearray, factor: float):
    """Vecino más cercano. Es para mirar, no para medir."""
    new_w, new_h = max(1, int(width * factor)), max(1, int(height * factor))
    out = bytearray(new_w * new_h * 4)
    for y in range(new_h):
        src_y = min(height - 1, int(y / factor))
        for x in range(new_w):
            src_x = min(width - 1, int(x / factor))
            s = (src_y * width + src_x) * 4
            t = (y * new_w + x) * 4
            out[t:t + 4] = rgba[s:s + 4]
    return new_w, new_h, out


# ── Subcomandos ──────────────────────────────────────────────────────────────

def cmd_decode(argv: list[str]) -> None:
    """Resultado de DesignSync `get_file` → archivo en disco.

    Un `get_file` grande no entra al contexto: la herramienta lo deja en disco y
    sólo muestra un preview de 2 KB. Este subcomando toma ese archivo y escribe
    el contenido real, decodificando base64 cuando corresponde.
    """
    if not argv:
        raise SystemExit("uso: visual_compare.py decode <resultado.txt> [destino/]")
    payload = json.load(open(argv[0]))
    destination = argv[1] if len(argv) > 1 else "."
    os.makedirs(destination, exist_ok=True)
    name = os.path.basename(payload["path"])
    target = os.path.join(destination, name)
    content = payload["content"]
    if payload.get("isBase64") or name.lower().endswith((".png", ".jpg", ".jpeg")):
        open(target, "wb").write(base64.b64decode(content))
    else:
        open(target, "w").write(content)
    print(f"{target} ({os.path.getsize(target)} bytes)")


def cmd_side(argv: list[str]) -> None:
    """Frame de Design a la izquierda, app a la derecha, misma altura."""
    if len(argv) < 3:
        raise SystemExit("uso: visual_compare.py side <frame.png> <app.png> <salida.png>")
    left_path, right_path, out_path = argv[0], argv[1], argv[2]
    lw, lh, left = read_png(left_path)
    rw, rh, right = read_png(right_path)

    # Se iguala la altura para poder recorrer las dos con la misma mirada. La
    # que se achica se declara, porque cualquier medida sobre ella miente.
    target_h = min(lh, rh)
    notes = []
    if lh != target_h:
        factor = target_h / lh
        lw, lh, left = scale(lw, lh, left, factor)
        notes.append(f"frame escalado x{factor:.3f}")
    if rh != target_h:
        factor = target_h / rh
        rw, rh, right = scale(rw, rh, right, factor)
        notes.append(f"app escalada x{factor:.3f}")

    gap = 12
    width, height = lw + gap + rw, target_h
    canvas = bytearray(b"\xff\x00\xff\xff" * (width * height))  # magenta = hueco
    for y in range(height):
        row = y * width * 4
        canvas[row:row + lw * 4] = left[y * lw * 4:(y + 1) * lw * 4]
        start = row + (lw + gap) * 4
        canvas[start:start + rw * 4] = right[y * rw * 4:(y + 1) * rw * 4]
    # El lector de imágenes corta por encima de 2000 px de lado, y un compuesto
    # que no se puede abrir no sirve para nada. Se achica entero, conservando la
    # proporción, y se declara el factor.
    limit = 1960
    if max(width, height) > limit:
        factor = limit / max(width, height)
        width, height, canvas = scale(width, height, canvas, factor)
        notes.append(f"compuesto x{factor:.3f} para caber en el lector")

    write_png(out_path, width, height, canvas)
    print(f"{out_path} ({width}x{height}) · izquierda={os.path.basename(left_path)} "
          f"derecha={os.path.basename(right_path)}"
          + (" · " + ", ".join(notes) if notes else " · sin escalar"))
    if notes:
        print("  NO midas sobre este compuesto: usa `columns` sobre el original.")


def cmd_columns(argv: list[str]) -> None:
    """Bordes de columna de una banda horizontal, por corridas de píxel oscuro.

    Legítimo sobre un frame publicado por Design: son recortes sin reescalar,
    así que la métrica se puede medir sobre el pixel. Nunca sobre una captura
    de la ventana de Design ni sobre un compuesto.
    """
    if len(argv) < 4 or argv[1] != "--band":
        raise SystemExit("uso: visual_compare.py columns <png> --band Y0 Y1")
    path, y0, y1 = argv[0], int(argv[2]), int(argv[3])
    width, height, rgba = read_png(path)
    y1 = min(y1, height)
    runs, start = [], None
    for x in range(width):
        dark = False
        for y in range(y0, y1):
            offset = (y * width + x) * 4
            luma = (rgba[offset] * 299 + rgba[offset + 1] * 587
                    + rgba[offset + 2] * 114) // 1000
            if luma < 170:
                dark = True
                break
        if dark and start is None:
            start = x
        elif not dark and start is not None:
            runs.append((start, x - 1))
            start = None
    if start is not None:
        runs.append((start, width - 1))

    merged: list[list[int]] = []
    for left, right in runs:
        if merged and left - merged[-1][1] <= 7:
            merged[-1][1] = right
        else:
            merged.append([left, right])
    merged = [m for m in merged if m[1] - m[0] >= 10]
    print(f"{os.path.basename(path)} · banda y={y0}..{y1} · ancho {width}")
    previous_right = None
    for left, right in merged:
        delta = "" if previous_right is None else f"  Δ desde el anterior: {left - previous_right}"
        print(f"  x {left:>5} … {right:<5} (ancho {right - left + 1}){delta}")
        previous_right = right


COMMANDS = {"decode": cmd_decode, "side": cmd_side, "columns": cmd_columns}

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        raise SystemExit(__doc__)
    COMMANDS[sys.argv[1]](sys.argv[2:])
