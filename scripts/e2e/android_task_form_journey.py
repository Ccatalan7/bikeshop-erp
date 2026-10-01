#!/usr/bin/env python3
"""C1 nativo: el mecánico adjunta, abre y retira archivos desde el
TaskFormDialog real de lib/main.dart en el emulador Android.

Lo lanza scripts/e2e/run_task_form_android_local.sh, que instala el APK sellado
para el stack local, prepara las cuentas sintéticas y deja `adb reverse` del
puerto 54321. Aquí no hay llaves: sólo el correo y la contraseña de un solo uso
del empleado, que se teclean en el login y nunca se escriben en un archivo.
Las manos y los ojos (árbol semántico, gestos, frames) están en android_ui.py.

    python3 scripts/e2e/android_task_form_journey.py          # recorrido
    python3 scripts/e2e/android_task_form_journey.py probe    # nombres en pantalla
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
    count,
    count_after_scrolling,
    dump,
    evidence,
    find_all,
    frames_dir,
    hide_keyboard,
    login,
    night,
    open_route,
    pick_in_documents_ui,
    press,
    push_files,
    required,
    run,
    set_system_theme,
    tap,
    themed,
    type_into,
    wait_for,
    wait_gone,
)

FILES = {
    "pastilla-trasera.png": (196, 120, 64),
    "rotor-delantero.png": (96, 128, 168),
}
# La insignia de un adjunto sin subir es un nodo propio llamado sólo así;
# el estado de la tarea se nombra «Pendiente al crear…» o «Estado Pendiente».
PENDING = re.compile(r"^Pendiente$")


def journey() -> None:
    email = required("TASK_FORM_E2E_EMAIL")
    password = required("TASK_FORM_E2E_PASSWORD")
    title = required("TASK_FORM_E2E_TASK_TITLE")
    assignee = required("TASK_FORM_E2E_ASSIGNEE")

    night(False)
    push_files(frames_dir, FILES)
    evidence.append("archivos_en_Download=2")

    # 1–2. Login real del empleado y tema «Sistema».
    login(email, password)
    set_system_theme()

    # 3. Taller → Vista: Tareas → Nueva tarea.
    open_route("/taller/pegas")
    # Teléfono: «Vista: Lista» abre una hoja con «Tareas / Tareas operativas…».
    view = wait_for(re.compile(r"^Vista: "), timeout=90, what="el selector de vista del taller")
    if not re.search(r"^Vista: Tareas\b", view.name):
        tap(view)
        press(re.compile(r"^(\S+\s)?Tareas(\s|$)"))
        # En Tareas el teléfono titula la pantalla y el selector pasa a la barra.
        wait_for(re.compile(r"^(Vista: Tareas\b|Tareas Planificación operativa$)"),
                 what="la vista Tareas del taller")
    evidence.append("vista=tareas")
    themed("lista-de-tareas")

    press(re.compile(r"^Nueva( tarea)?$"))
    wait_for("Nueva Tarea", what="el formulario «Nueva Tarea»")
    type_into("Título de la tarea", title)
    type_into("Descripción (Opcional)", "Pastillas gastadas hasta el metal, fotos antes del cambio.")
    hide_keyboard()

    # Asignar a la compañera desde el directorio de la bandeja.
    press(re.compile(r"Asignar a"))
    press(assignee, timeout=20)
    if not find_all(dump(), re.compile(re.escape(assignee))):
        raise JourneyError(f"«Asignar a» no quedó en {assignee}")
    evidence.append("asignar=companera_elegida")

    # 4. Dos fotos desde el selector de archivos del sistema.
    press("Agregar archivo")
    pick_in_documents_ui(list(FILES))
    wait_for("Adjuntos (2)", timeout=60, what="«Adjuntos (2)»")
    pending = count_after_scrolling(PENDING, 2)
    if pending != 2:
        raise JourneyError(f"se esperaban 2 pendientes y hay {pending}")
    evidence.append("elegidos=2_pendientes")
    themed("nueva-tarea-con-pendientes")

    # 5. Guardar: crea la tarea, sube los dos y cierra.
    press("Guardar")
    wait_gone("Nueva Tarea", timeout=120, what="el formulario tras guardar")
    # La fila se toca por su propia acción: el nodo más chico con el título es
    # «Marcar … como completada», y tocarlo completa la tarea.
    # Su nombre suma el texto de los hijos: «Ver detalles de X X Detalles».
    details = re.compile(r"^(Ver|Ocultar) detalles de " + re.escape(title) + r"(\s|$)")
    row = wait_for(details, timeout=60, what="la tarea en la lista")
    evidence.append("guardar=tarea_y_2_subidas_cerrado")

    # La fila compacta se expande: la lista nombra a quien quedó asignada (el
    # directorio de la bandeja, no get_tenant_users) y cuenta los adjuntos.
    if row.name.startswith("Ver detalles"):
        tap(row)
    wait_for(re.compile(r"^Asignación\b.*" + re.escape(assignee)), timeout=30,
             what=f"«Asignación» con {assignee} en la lista")
    wait_for(re.compile(r"^Adjuntos 2 archivos\b"), timeout=30, what="«Adjuntos 2 archivos»")
    evidence.append("lista=asignada_y_2_archivos")
    themed("lista-con-adjuntos")

    # 6. Reabrir desde la acción de adjuntos de la fila.
    press(re.compile(r"^Adjuntos 2 archivos\b|Ver 2 adjuntos"))
    # Abre desplazada hasta los adjuntos: el título queda arriba, fuera del
    # árbol; la edición se reconoce por su «Actualizar».
    wait_for("Actualizar", timeout=60, what="la tarea abierta para editar")
    wait_for("Adjuntos (2)", timeout=60)
    if count_after_scrolling("Abrir adjunto", 2) != 2:
        raise JourneyError("la tarea reabierta no ofrece abrir sus 2 adjuntos")
    if count(PENDING):
        raise JourneyError("la tarea reabierta muestra pendientes")
    evidence.append("reabierta=2_subidos")
    themed("tarea-con-adjuntos")

    # 7. Abrir un adjunto: URL firmada y bytes privados en el visor.
    press("Abrir adjunto")
    # El visor del teléfono se nombra por el archivo («rotor-delantero.png
    # PNG»); «Acercar» sólo está en la barra de escritorio.
    viewer = re.compile(r"^(" + "|".join(re.escape(name) for name in FILES) + r") PNG$")
    wait_for(viewer, timeout=60, what="el visor del adjunto")
    time.sleep(1.5)
    evidence.append("abrir=visor")
    themed("visor-adjunto")
    # El fondo modal también se llama «Cerrar» y cubre la pantalla: se toca
    # el botón, nunca el centro del fondo.
    close = find_all(dump(), "Cerrar", cls="Button")
    if not close:
        raise JourneyError("el visor no ofrece «Cerrar»")
    tap(close[0])
    wait_for("Actualizar", timeout=30)

    # 8. Retirar los dos: vínculo y bytes fuera.
    for remaining in (1, 0):
        press("Quitar adjunto")
        wait_for("¿Eliminar adjunto?", timeout=20)
        press("Eliminar")
        if remaining:
            wait_for(f"Adjuntos ({remaining})", timeout=60)
        else:
            wait_for("Sin archivos adjuntos", timeout=60)
    if find_all(dump(), re.compile(r"limpieza pendiente")):
        raise JourneyError("la retirada dejó limpieza pendiente con Storage arriba")
    evidence.append("retirar=2_sin_limpieza_pendiente")
    themed("tarea-sin-adjuntos")
    press("Cancelar")
    wait_gone("Actualizar", timeout=30, what="la tarea abierta")
    themed("lista-final")


if __name__ == "__main__":
    sys.exit(run(journey, "C1 nativo"))
