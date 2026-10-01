#!/usr/bin/env python3
"""C3 nativo: la foto heredada de un trabajo se ve en el teléfono desde su
copia privada, con lib/main.dart contra la base local (PLANS.md, 2026-09-30).

Lo lanza scripts/e2e/run_android_local_journey.sh --journey c3-photo sobre la
fixture C3 que Root ya dejó lista y retenida (trabajo con su foto, recibo de
copia verificado y el original público sintético ya en 404): este recorrido
no la prepara ni la retira. Entra como la cuenta del taller de esa fixture,
abre el trabajo por el enlace del ERP y deja claro/oscuro de la miniatura. Si
la miniatura se ve, vino de la copia privada: el original ya no existe y el
cliente nunca vuelve a la URL pública cuando la lectura privada falla (en ese
caso muestra un candado, «No se pudo abrir el archivo del trabajo»).

    python3 scripts/e2e/android_c3_private_photo_journey.py          # recorrido
    python3 scripts/e2e/android_c3_private_photo_journey.py probe    # nombres en pantalla
"""

from __future__ import annotations

import re
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.dont_write_bytecode = True

from android_ui import (  # noqa: E402
    JourneyError,
    dump,
    evidence,
    find_all,
    login,
    night,
    open_route,
    required,
    run,
    screen_size,
    scroll_into_view,
    set_system_theme,
    swipe_up,
    themed,
    wait_for,
)

LOCKED = re.compile(r"No se pudo abrir el archivo del trabajo")


def journey() -> None:
    email = required("C3_E2E_EMAIL")
    password = required("C3_E2E_PASSWORD")
    job_id = required("C3_E2E_JOB_ID")

    night(False)
    login(email, password)
    set_system_theme()

    open_route(f"/taller/pegas/{job_id}")
    # En el teléfono la cabecera dice «Ficha del trabajo»; en escritorio,
    # «Editar Trabajo».
    wait_for(re.compile(r"^(Ficha del trabajo|Editar Trabajo)$"), timeout=90,
             what="el trabajo con la foto heredada")
    # En el teléfono la sección «Adjuntos» lleva la miniatura como imagen
    # (sin botón «Adjuntar archivo», 2026-09-30); sube a la mitad superior
    # para que la miniatura quede entera.
    section = scroll_into_view(re.compile(r"^Adjuntos$"), timeout=60)
    _, height = screen_size()
    if section.center[1] > height * 0.6:
        swipe_up()
        section = wait_for(re.compile(r"^Adjuntos$"), timeout=20)
    # La miniatura resuelve su permiso actual (RPC y URL firmada de 300 s) y
    # baja la copia privada: se espera a que no quede cargando.
    deadline = time.monotonic() + 45
    while True:
        nodes = dump()
        if find_all(nodes, LOCKED):
            raise JourneyError("la miniatura quedó con candado: la copia privada no se leyó")
        loading = [node for node in nodes if node.cls.endswith("ProgressBar")]
        if not loading:
            break
        if time.monotonic() > deadline:
            raise JourneyError("la miniatura sigue cargando")
        time.sleep(1)
    time.sleep(2)
    if find_all(dump(), LOCKED):
        raise JourneyError("la miniatura quedó con candado: la copia privada no se leyó")
    x1, y1, x2, y2 = section.bounds
    thumbnails = [node for node in dump() if node.cls.endswith("ImageView")
                  and x1 <= node.bounds[0] and node.bounds[2] <= x2
                  and y1 <= node.bounds[1] and node.bounds[3] <= min(y2, height)]
    if not thumbnails:
        raise JourneyError("la sección de adjuntos no muestra la miniatura entera")
    themed("miniatura-privada-del-trabajo")
    evidence.append("miniatura=copia_privada_sin_candado")


if __name__ == "__main__":
    sys.exit(run(journey, "C3 nativo"))
