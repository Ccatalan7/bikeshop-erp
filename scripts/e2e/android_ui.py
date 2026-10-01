#!/usr/bin/env python3
"""Manos y ojos para recorrer la app real en el emulador Android.

Lo comparten los recorridos nativos (`android_task_form_journey.py`,
`android_workshop_journey.py`), que lanza `run_android_local_journey.sh`: APK
sellado para el stack local, cuentas sintéticas y `adb reverse` del 54321.

Toca por identidad semántica: lee el árbol de accesibilidad que Flutter publica
en Android (`uiautomator dump`) y toca el centro del nodo cuyo nombre, pista o
texto corresponde. Las trampas que costaron corridas están en
docs/development/AGENT_MACOS_APP_CONTROL.md §4.c.

Deja en ANDROID_E2E_FRAMES_DIR los frames claro/oscuro (`cmd uimode night`, la
app en «Sistema») y, por cada estado, el árbol semántico de la app en texto.
Nunca guarda el árbol ni la captura del login.
"""

from __future__ import annotations

import os
import re
import struct
import subprocess
import sys
import time
import xml.etree.ElementTree as ElementTree
import zlib
from dataclasses import dataclass
from pathlib import Path

def _env(name: str, default: str = "") -> str:
    # Los nombres TASK_FORM_* son los del primer recorrido; siguen valiendo.
    return os.environ.get(f"ANDROID_E2E_{name}") or os.environ.get(
        f"TASK_FORM_ANDROID_{name}", default)


ADB = _env("ADB", "adb")
SERIAL = _env("SERIAL")
PACKAGE = _env("PACKAGE", "com.vinabike.erp")
PICKER_PACKAGE = "com.google.android.documentsui"
DEVICE_DIR = "/sdcard/Download"

evidence: list[str] = []


def say(message: str) -> None:
    print(f"{time.strftime('%H:%M:%S')} {message}", flush=True)


class JourneyError(RuntimeError):
    pass


# ── adb ─────────────────────────────────────────────────────────────────────
def adb(*args: str, timeout: float = 60, check: bool = True) -> bytes:
    command = [ADB, *(["-s", SERIAL] if SERIAL else []), *args]
    result = subprocess.run(command, capture_output=True, timeout=timeout)
    if check and result.returncode != 0:
        raise JourneyError(f"adb {args[0]} falló: {result.stderr.decode(errors='replace')[-300:]}")
    return result.stdout


def shell(command: str, timeout: float = 60, check: bool = True) -> str:
    return adb("shell", command, timeout=timeout, check=check).decode(errors="replace")


def quote(text: str) -> str:
    return "'" + text.replace("'", "'\\''") + "'"


# ── Árbol semántico ─────────────────────────────────────────────────────────
@dataclass
class Node:
    cls: str
    package: str
    text: str
    desc: str
    hint: str
    resource: str
    bounds: tuple[int, int, int, int]
    clickable: bool
    checked: bool
    selected: bool
    focused: bool
    password: bool
    scrollable: bool

    @property
    def name(self) -> str:
        parts = [self.desc, self.text, self.hint]
        return " ".join(" ".join(part.split()) for part in parts if part).strip()

    @property
    def center(self) -> tuple[int, int]:
        x1, y1, x2, y2 = self.bounds
        return (x1 + x2) // 2, (y1 + y2) // 2

    @property
    def area(self) -> int:
        x1, y1, x2, y2 = self.bounds
        return max(0, x2 - x1) * max(0, y2 - y1)


BOUNDS = re.compile(r"\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]")


def dump(attempts: int = 6) -> list[Node]:
    """El árbol de la ventana activa. Un spinner de Flutter no deja «idle» a
    uiautomator: se reintenta en vez de fallar a la primera."""
    last = ""
    for _ in range(attempts):
        raw = adb("exec-out", "uiautomator", "dump", "/dev/tty", timeout=40, check=False)
        text = raw.decode(errors="replace")
        start, end = text.find("<?xml"), text.find("</hierarchy>")
        if start >= 0 and end > start:
            root = ElementTree.fromstring(text[start : end + len("</hierarchy>")])
            nodes = []
            for element in root.iter("node"):
                match = BOUNDS.match(element.get("bounds", ""))
                if not match:
                    continue
                attr = element.get
                nodes.append(
                    Node(
                        cls=attr("class", ""),
                        package=attr("package", ""),
                        text=attr("text", ""),
                        desc=attr("content-desc", ""),
                        hint=attr("hint", "") or "",
                        resource=attr("resource-id", ""),
                        bounds=tuple(int(value) for value in match.groups()),  # type: ignore[arg-type]
                        clickable=attr("clickable") == "true",
                        checked=attr("checked") == "true",
                        selected=attr("selected") == "true",
                        focused=attr("focused") == "true",
                        password=attr("password") == "true",
                        scrollable=attr("scrollable") == "true",
                    )
                )
            if dismiss_system_dialog(nodes):
                continue
            return nodes
        last = text.strip()[-200:]
        time.sleep(1)
    raise JourneyError(f"uiautomator no entregó el árbol: {last}")


# Diálogos del sistema que no son del recorrido: el emulador con 2 GB avisa
# «System UI isn't responding» al arrancar, y Android 13+ pide permiso de
# notificaciones la primera vez. Se espera y se niega (lo más privado).
SYSTEM_DIALOG_ANSWERS = {"Wait", "Esperar", "Don’t allow", "Don't allow", "No permitir"}


def dismiss_system_dialog(nodes: list[Node]) -> bool:
    for node in nodes:
        system = node.package == "android" or node.package.endswith("permissioncontroller")
        if system and node.clickable and node.name in SYSTEM_DIALOG_ANSWERS:
            x, y = node.center
            shell(f"input tap {x} {y}")
            evidence.append(f"sistema={node.name.replace(' ', '_')}")
            time.sleep(1.5)
            return True
    return False


def matches(node: Node, name: str | re.Pattern[str]) -> bool:
    label = node.name
    if isinstance(name, re.Pattern):
        return bool(name.search(label))
    # Un nombre exacto acepta su duplicado «X X» (etiqueta + tooltip).
    return label == name or label == f"{name} {name}"


def find_all(
    nodes: list[Node],
    name: str | re.Pattern[str],
    *,
    package: str | None = PACKAGE,
    cls: str | None = None,
) -> list[Node]:
    return [
        node
        for node in nodes
        if (package is None or node.package == package)
        and (cls is None or node.cls.endswith(cls))
        and node.area > 0
        and matches(node, name)
    ]


def wait_for(
    name: str | re.Pattern[str],
    *,
    timeout: float = 45,
    package: str | None = PACKAGE,
    cls: str | None = None,
    what: str | None = None,
) -> Node:
    deadline = time.monotonic() + timeout
    while True:
        found = find_all(dump(), name, package=package, cls=cls)
        if found:
            return min(found, key=lambda node: node.area)
        if time.monotonic() > deadline:
            raise JourneyError(f"no apareció {what or describe(name)}")
        time.sleep(1)


def wait_gone(name: str | re.Pattern[str], *, timeout: float = 90, what: str | None = None) -> None:
    deadline = time.monotonic() + timeout
    while find_all(dump(), name):
        if time.monotonic() > deadline:
            raise JourneyError(f"sigue en pantalla {what or describe(name)}")
        time.sleep(1.5)


def count(name: str | re.Pattern[str], *, cls: str | None = None) -> int:
    return len(find_all(dump(), name, cls=cls))


def count_after_scrolling(name: str | re.Pattern[str], expected: int) -> int:
    """En teléfono el formulario cabe en 700 px lógicos y los adjuntos quedan
    bajo el borde: se desplaza hasta verlos todos (o hasta que no crezcan)."""
    scroll_into_view(name, timeout=30)
    seen = count(name)
    for _ in range(3):
        if seen >= expected:
            break
        swipe_up()
        seen = max(seen, count(name))
    return seen


def describe(name: str | re.Pattern[str]) -> str:
    return f"«{name.pattern if isinstance(name, re.Pattern) else name}»"


# ── Gestos ──────────────────────────────────────────────────────────────────
def tap(node: Node, pause: float = 0.8) -> None:
    x, y = node.center
    shell(f"input tap {x} {y}")
    time.sleep(pause)


def press(name: str | re.Pattern[str], *, timeout: float = 45, cls: str | None = None,
          package: str | None = PACKAGE, pause: float = 0.8) -> Node:
    node = scroll_into_view(name, cls=cls, package=package, timeout=timeout)
    tap(node, pause)
    return node


def long_press(node: Node) -> None:
    x, y = node.center
    shell(f"input swipe {x} {y} {x} {y} 900")
    time.sleep(0.8)


def screen_size() -> tuple[int, int]:
    match = re.search(r"(\d+)x(\d+)", shell("wm size"))
    return (int(match.group(1)), int(match.group(2))) if match else (1080, 2400)


def swipe_up() -> None:
    width, height = screen_size()
    shell(f"input swipe {width // 2} {int(height * 0.72)} {width // 2} {int(height * 0.38)} 400")
    time.sleep(0.9)


def swipe_down() -> None:
    width, height = screen_size()
    shell(f"input swipe {width // 2} {int(height * 0.38)} {width // 2} {int(height * 0.72)} 400")
    time.sleep(0.9)


def scroll_into_view(name: str | re.Pattern[str], *, cls: str | None = None,
                     package: str | None = PACKAGE, timeout: float = 45) -> Node:
    """Espera el nodo; si no está, desplaza hacia abajo y después hacia arriba:
    un formulario puede abrir desplazado y dejar arriba lo que se busca
    (el cliente del trabajo nuevo, 2026-09-30)."""
    deadline = time.monotonic() + timeout
    swipes = 0
    while True:
        nodes = dump()
        found = find_all(nodes, name, package=package, cls=cls)
        if found:
            node = min(found, key=lambda item: item.area)
            _, height = screen_size()
            # La última fila de una hoja inferior llega casi al borde (en
            # 1080x2400 «Tareas» centra en y=2274): sólo la franja de gestos
            # queda fuera.
            if node.center[1] < height * 0.97:
                return node
        if time.monotonic() > deadline:
            raise JourneyError(f"no apareció {describe(name)}")
        if any(item.scrollable and item.package == PACKAGE for item in nodes) and swipes < 18:
            # Un gesto sobre el teclado escribe (Gboard desliza letras): el
            # 2026-09-30 una «o» entró al título de la tarea. Primero se baja.
            hide_keyboard()
            swipe_up() if swipes < 6 else swipe_down()
            swipes += 1
        else:
            time.sleep(1)


def reveal_end(name: str | re.Pattern[str], *, package: str | None = PACKAGE,
               timeout: float = 45, max_swipes: int = 12) -> Node:
    """Deja a la vista la última fila de un nodo que funde varias.

    Una tarjeta sin semántica propia por fila (la memoria técnica de la bici)
    publica un solo nodo con todo su texto: `scroll_into_view` lo encuentra
    en cuanto asoma su borde superior y la fila buscada queda bajo la pantalla
    (frame 16 del C1/C4 nativo, 2026-09-30). Aquí se desplaza hasta que el
    borde inferior del nodo queda dentro de su área desplazable (un nodo
    recortado informa el borde de esa área, no el suyo); si ya no se puede
    desplazar más, basta con que termine antes de ese borde."""
    _, height = screen_size()
    node = scroll_into_view(name, package=package, timeout=timeout)
    for _ in range(max_swipes):
        nodes = dump()
        found = find_all(nodes, name, package=package)
        if not found:
            raise JourneyError(f"se perdió {describe(name)} al desplazar")
        node = min(found, key=lambda item: item.area)
        x1, y1, _, _ = node.bounds
        viewports = [item for item in nodes if item.scrollable and item.package == PACKAGE
                     and item.bounds[0] <= x1 and item.bounds[1] <= y1
                     and item.bounds[2] >= node.bounds[2] and item.bounds[3] >= node.bounds[3]]
        bottom = min(viewports, key=lambda item: item.area).bounds[3] if viewports else height
        # Recortado, el nodo informa exactamente el borde del área.
        if node.bounds[3] < min(bottom, height) - 8:
            return node
        # Más alto que su área, el nodo recortado conserva los mismos bordes
        # aunque su contenido se mueva: el avance se mide en la pantalla.
        before = adb("exec-out", "screencap", "-p", timeout=60)
        hide_keyboard()
        swipe_up()
        if adb("exec-out", "screencap", "-p", timeout=60) == before:
            raise JourneyError(f"{describe(name)} no termina dentro de la pantalla y ya no se desplaza")
    raise JourneyError(f"no llegué al final de {describe(name)}")


def keyboard_shown() -> bool:
    # `mIsInputViewShown` queda en true con el teclado ya oculto (visto en
    # Android 16, 2026-09-30): con él, «bajar el teclado» mandaba BACK y salía
    # de la ficha de la bici. Manda la ventana del IME y `mInputShown`.
    state = shell("dumpsys input_method", check=False)
    window = re.search(r"\bmImeWindowVis=(\d+)", state)
    if window is not None:
        return int(window.group(1)) & 2 == 2 or bool(re.search(r"\bmInputShown=true", state))
    return bool(re.search(r"\bmInputShown=true", state))


def hide_keyboard() -> None:
    # BACK sólo si el teclado está arriba: sin teclado cerraría el diálogo. Un
    # teclado que se está cerrando (se eligió un resultado del buscador) sigue
    # «arriba» un instante: BACK caía en la página y pedía descartar el trabajo
    # (2026-09-30). Se confirma tras una pausa.
    if keyboard_shown():
        time.sleep(0.7)
        if keyboard_shown():
            shell("input keyevent 4")
            time.sleep(0.8)


def type_into(label: str | re.Pattern[str], text: str, *, secret: bool = False) -> None:
    # Un campo con valor se nombra «valor + pista»: la pista va al final.
    if isinstance(label, str):
        label = re.compile(r"(^|\s)" + re.escape(label) + "$")
    field = scroll_into_view(label, cls="EditText")
    tap(field, 0.6)
    field = wait_for(label, cls="EditText")
    if not field.focused:
        tap(field, 0.6)
    shell(f"input text {quote(text.replace(' ', '%s'))}", timeout=90)
    time.sleep(0.6)
    if not secret:
        value = " ".join(wait_for(label, cls="EditText").text.split())
        if value != " ".join(text.split()):
            raise JourneyError(f"el campo {describe(label)} quedó con «{value}»")


# ── Evidencia ───────────────────────────────────────────────────────────────
frames_dir = Path(os.environ.get("ANDROID_E2E_FRAMES_DIR")
                  or os.environ.get("TASK_FORM_E2E_FRAMES_DIR", "."))
frame_number = 0
on_login = True


def capture(path: Path) -> None:
    path.write_bytes(adb("exec-out", "screencap", "-p", timeout=60))


def semantics(name: str) -> None:
    """El árbol de la app como lo lee el sistema: clase, nombre y estado."""
    if on_login:
        return
    lines = []
    for node in dump():
        if node.package != PACKAGE or not (node.name or node.clickable):
            continue
        flags = [flag for flag, on in (("toca", node.clickable), ("marcado", node.checked),
                                        ("elegido", node.selected), ("foco", node.focused),
                                        ("desliza", node.scrollable)) if on]
        lines.append(f"{node.cls.rsplit('.', 1)[-1]:<14} {node.name!r:<70} "
                     f"{','.join(flags):<18} {node.bounds}")
    (frames_dir / f"{frame_number:02d}-{name}-semantica.txt").write_text("\n".join(lines) + "\n")


def night(on: bool) -> None:
    shell(f"cmd uimode night {'yes' if on else 'no'}")
    time.sleep(2.0)


def settled_change(reference: bytes, attempts: int = 12) -> bytes:
    """La primera vez que cambia `uimode`, la app tarda más de 2 s en pintar el
    oscuro: se espera a que la pantalla difiera de la clara y quede quieta."""
    last = b""
    for _ in range(attempts):
        time.sleep(1)
        frame = adb("exec-out", "screencap", "-p", timeout=60)
        if frame != reference and frame == last:
            return frame
        last = frame
    raise JourneyError("la app no cambió a oscuro al cambiar el sistema")


def themed(name: str) -> None:
    """Claro y oscuro del mismo estado; la app sigue al sistema."""
    global frame_number
    if on_login:
        raise JourneyError("no se capturan frames del login")
    frame_number += 1
    semantics(name)
    night(False)
    light = adb("exec-out", "screencap", "-p", timeout=60)
    (frames_dir / f"{frame_number:02d}-{name}-claro.png").write_bytes(light)
    shell("cmd uimode night yes")
    dark = settled_change(light)
    (frames_dir / f"{frame_number:02d}-{name}-oscuro.png").write_bytes(dark)
    night(False)


def failure_evidence() -> None:
    global frame_number
    if on_login:
        return
    try:
        capture(frames_dir / "fallo.png")
        frame_number += 1
        semantics("fallo")
    except Exception as error:  # noqa: BLE001 — la evidencia no tapa el fallo
        say(f"sin evidencia del fallo: {error}")


# ── PNG pequeños hechos aquí: una foto de taller no cabe en el repo ─────────
def png(width: int, height: int, tint: tuple[int, int, int]) -> bytes:
    def chunk(kind: bytes, data: bytes) -> bytes:
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    rows = bytearray()
    for y in range(height):
        rows.append(0)
        for x in range(width):
            ring = 1 if ((x - width / 2) ** 2 + (y - height / 2) ** 2) ** 0.5 % 18 < 9 else 0.72
            rows.extend(round(channel * ring) for channel in tint)
    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
            + chunk(b"IDAT", zlib.compress(bytes(rows))) + chunk(b"IEND", b""))


def push_files(scratch: Path, files: dict[str, tuple[int, int, int]]) -> None:
    for name, tint in files.items():
        local = scratch / name
        local.write_bytes(png(160, 120, tint))
        adb("push", str(local), f"{DEVICE_DIR}/{name}", timeout=60)
        local.unlink()
        # Que DocumentsUI los liste sin esperar al escáner de medios.
        shell(f"content call --uri content://media --method scan_file --arg {DEVICE_DIR}/{name}",
              check=False)
        shell("am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE "
              f"-d file://{DEVICE_DIR}/{name}", check=False)


# ── Selector de archivos del sistema ────────────────────────────────────────
def pick_in_documents_ui(names: list[str]) -> None:
    """Elige los archivos en DocumentsUI: mantener el primero para entrar en
    selección múltiple, tocar el resto y «Select»."""
    wait_for(re.compile(r"."), package=PICKER_PACKAGE, timeout=30, what="el selector de archivos")
    first = locate_in_picker(names[0])
    if len(names) == 1:
        tap(first, 1.5)
        return
    long_press(first)
    for name in names[1:]:
        tap(locate_in_picker(name))
    marked = re.compile(rf"^{len(names)} (selected|seleccionados)$")
    if not find_all(dump(), marked, package=PICKER_PACKAGE):
        raise JourneyError(f"el selector no marcó los {len(names)} archivos")
    select = find_all(dump(), re.compile(r"^(Select|SELECT|Seleccionar|Abrir|Open|Done|Listo)$"),
                      package=PICKER_PACKAGE)
    if not select:
        raise JourneyError("el selector no ofreció «Select» tras elegir los archivos")
    tap(select[0], 1.5)


def locate_in_picker(name: str) -> Node:
    deadline = time.monotonic() + 40
    opened_downloads = False
    while True:
        nodes = dump()
        found = find_all(nodes, name, package=PICKER_PACKAGE)
        if found:
            return found[0]
        if time.monotonic() > deadline:
            raise JourneyError(f"el selector no mostró {name}")
        if not opened_downloads:
            # Recientes puede no listar lo recién copiado: ir a Descargas.
            roots = find_all(nodes, re.compile(r"^(Show roots|Mostrar raíces|Open navigation drawer)$"),
                             package=PICKER_PACKAGE)
            if roots:
                tap(roots[0])
                downloads = find_all(dump(), re.compile(r"^(Downloads|Descargas)$"),
                                     package=PICKER_PACKAGE)
                if downloads:
                    tap(downloads[0], 1.5)
                    opened_downloads = True
                    continue
        time.sleep(1)


# ── Recorrido compartido ───────────────────────────────────────────────────
def required(name: str) -> str:
    value = os.environ.get(name, "")
    if not value:
        raise JourneyError(f"Falta {name}: correr scripts/e2e/run_android_local_journey.sh")
    return value


def open_route(route: str) -> None:
    """El enlace compartido del ERP: el mismo que abre un «vb-ERP ▾»."""
    shell(f"am start -W -a android.intent.action.VIEW -d {quote(f'vinabike://app/open?route={route}')} "
          f"{PACKAGE}")
    time.sleep(2)


def login(email: str, password: str) -> None:
    """La app desde el lanzador, sin sesión: el login real. Hasta salir de él
    no se guarda árbol ni captura."""
    global on_login
    shell(f"am start -W -n {PACKAGE}/.MainActivity")
    wait_for(re.compile(r"Correo"), cls="EditText", timeout=180, what="el login")
    type_into(re.compile(r"Correo"), email)
    type_into(re.compile(r"Contraseña"), password, secret=True)
    hide_keyboard()
    press("Iniciar Sesión")
    wait_gone(re.compile(r"Correo"), timeout=120, what="el login")
    on_login = False
    evidence.append("login=ok")


def set_system_theme() -> None:
    """«Sistema», para tomar claro y oscuro del mismo estado."""
    nodes = dump()
    quick = find_all(nodes, "Configuración rápida")
    if quick:
        tap(quick[0])
        press("Sistema", timeout=20)
        close = find_all(dump(), "Cerrar", cls="Button")
        if close:
            tap(close[0])
        evidence.append("tema=sistema")
        return
    # Teléfono: menú principal → «Apariencia», una hoja con el tema.
    menu = find_all(nodes, re.compile(r"^(Abrir menú principal|Abrir menú de navegación|Open navigation menu)$"))
    if not menu:
        raise JourneyError("no encontré «Configuración rápida» ni el menú lateral")
    tap(menu[0])
    press("Apariencia", timeout=20)
    press("Sistema", timeout=20)
    chosen = find_all(dump(), "Sistema")
    if not any(node.selected or node.checked for node in chosen):
        raise JourneyError("«Sistema» no quedó marcado en el tema")
    # Atrás sólo con la hoja abierta: sobre el panel saldría de la app.
    if find_all(dump(), re.compile(r"^Tema de la aplicación")):
        shell("input keyevent 4")
        time.sleep(1)
    close_menu = find_all(dump(), "Cerrar menú")
    if close_menu:
        tap(close_menu[0])
    evidence.append("tema=sistema")


def probe() -> None:
    for node in dump():
        if node.name or node.clickable:
            print(f"{node.package.rsplit('.', 1)[-1]:<12} {node.cls.rsplit('.', 1)[-1]:<14} "
                  f"{node.name!r:<70} {'toca' if node.clickable else '':<5} {node.bounds}")


def run(journey, title: str) -> int:
    """Corre un recorrido con su evidencia; `probe` lista la pantalla."""
    if sys.argv[1:] == ["probe"]:
        probe()
        return 0
    try:
        frames_dir.mkdir(parents=True, exist_ok=True)
        journey()
    except (JourneyError, subprocess.TimeoutExpired) as error:
        failure_evidence()
        say(f"{title} evidencia hasta el fallo: {' | '.join(evidence)}")
        say(f"FALLO: {error}")
        return 1
    finally:
        night(False)
    say(f"{title} evidencia: {' | '.join(evidence)} | estados={frame_number}")
    return 0
