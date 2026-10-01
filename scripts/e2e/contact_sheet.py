#!/usr/bin/env python3
"""Hoja de contacto de un recorrido: cada estado, claro y oscuro lado a lado.

    python3 scripts/e2e/contact_sheet.py .tmp/e2e/android-workshop-<fecha>

Lee los `NN-<estado>-claro.png` / `-oscuro.png` que dejan los recorridos
(android_ui.themed, e2e/*_local.spec.ts) y escribe `hoja-de-contacto.png` en
la misma carpeta. Sin bibliotecas de imagen: arma una página y la fotografía
Chrome por el CLI de Playwright (el Mac no tiene PIL ni ImageMagick).
"""

from __future__ import annotations

import html
import re
import struct
import subprocess
import sys
from pathlib import Path

FRAME = re.compile(r"^(\d\d)-(.+)-(claro|oscuro)\.png$")


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__.strip().splitlines()[2].strip(), file=sys.stderr)
        return 64
    folder = Path(sys.argv[1]).resolve()
    states: dict[tuple[str, str], dict[str, Path]] = {}
    for path in sorted(folder.glob("*.png")):
        match = FRAME.match(path.name)
        if match:
            states.setdefault((match.group(1), match.group(2)), {})[match.group(3)] = path
    if not states:
        print(f"sin frames claro/oscuro en {folder}", file=sys.stderr)
        return 1
    # Teléfono (alto > ancho) en columnas angostas; escritorio en anchas: el
    # ancho y el alto están en la cabecera IHDR del PNG.
    first = next(iter(next(iter(states.values())).values()))
    width, height = struct.unpack(">II", first.read_bytes()[16:24])
    cell = 360 if height > width else 760
    cells = []
    for (number, name), pair in sorted(states.items()):
        images = "".join(
            f'<img src="{pair[theme].as_uri()}" alt="{theme}">'
            for theme in ("claro", "oscuro") if theme in pair
        )
        cells.append(f'<figure><div>{images}</div>'
                     f'<figcaption>{number} · {html.escape(name)}</figcaption></figure>')
    page = folder / "hoja-de-contacto.html"
    page.write_text(f"""<!doctype html><meta charset="utf-8">
<style>
  body {{ margin: 16px; background: #eceff1; font: 13px -apple-system, sans-serif; color: #1c2329; }}
  h1 {{ font-size: 16px; margin: 0 0 12px; }}
  main {{ display: grid; grid-template-columns: repeat(auto-fill, minmax({cell}px, 1fr)); gap: 14px; }}
  figure {{ margin: 0; background: #fff; border-radius: 8px; padding: 8px; }}
  figure div {{ display: flex; gap: 6px; }}
  img {{ width: calc(50% - 3px); height: auto; border: 1px solid #cfd8dc; border-radius: 4px; }}
  figcaption {{ margin-top: 6px; font-weight: 600; }}
</style>
<h1>{html.escape(folder.name)} · {len(states)} estados, claro y oscuro</h1>
<main>{''.join(cells)}</main>
""")
    output = folder / "hoja-de-contacto.png"
    root = Path(__file__).resolve().parents[2]
    subprocess.run(
        ["npx", "playwright", "screenshot", "--channel", "chrome", "--full-page",
         "--viewport-size", "1600,900", page.as_uri(), str(output)],
        cwd=root, check=True, stdout=subprocess.DEVNULL,
    )
    page.unlink()
    print(output)
    return 0


if __name__ == "__main__":
    sys.exit(main())
