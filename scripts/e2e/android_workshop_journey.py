#!/usr/bin/env python3
"""C1/C4 nativo: el recorrido completo del taller en el emulador Android, con
lib/main.dart contra la base local (PLANS.md, 2026-09-30).

Lo lanza scripts/e2e/run_android_local_journey.sh --journey workshop, que
instala el APK sellado, crea las cuentas sintéticas y siembra
workshop_journey_local_fixture.sql (la clienta, el modelo del catálogo, dos
neumáticos con su BSD y el servicio «Enrayado de rueda»). Aquí no hay llaves:
sólo el correo y la contraseña de un solo uso del mecánico, que se teclean en
el login.

Las decisiones del operador, en orden, y lo que cada una demuestra:

1. Trabajo nuevo para la clienta; la bici nace del modelo del catálogo y lo
   que el modelo copia (aro, mazas, frenos, rayos) queda «del modelo, sin
   confirmar» (criterio 1).
2. El diagnóstico muestra el rotor porque la ficha dice freno de disco
   (criterios 2 y 4).
3. Enrayado trasero de 28H: el asistente ya trae el freno de la ficha
   (criterio 3). Un neumático 29 atrás: la línea dice que la ficha lo anota al
   terminar. El buscador esconde el 27,5; con «Mostrar todo» aparece como no
   compatible y, por error, va adelante: la línea dice que no calza.
4. Presupuesto aprobado y facturado (un presupuesto aprobado es de sólo
   lectura: se corrige ya facturado).
5. El encargo con /tarea, para la compañera y sobre la línea del Enrayado. En
   la tarea, una foto: «Actualizar» a la vista con el teclado arriba y el
   visor en oscuro (los dos defectos del C1 nativo, 2026-09-30).
6. Terminar: el servidor rechaza el cierre entero por el 27,5
   (`incompatible`); «Revisar líneas» cierra la hoja de estados y deja las
   líneas; se cambia el 27,5 por otro 29 (con su precio) y termina.
7. La ficha: rueda trasera instalada en el trabajo, sin confirmar el BSD; el
   resumen dice 32/28 y 622, y el historial pone el Enrayado en la rueda
   trasera (criterios 5, 6 y 7): un frame del mapa con su leyenda y otro con
   la fila del servicio a la vista, con su rueda y su trabajo.

El readback de la base (fixture, modo readback) exige ese resultado; este
driver deja por cada estado frames claro/oscuro y el árbol semántico. Los
nombres de los controles son los de la app real (recorrido a mano del
2026-09-30); las trampas de Flutter en Android están en
AGENT_MACOS_APP_CONTROL.md §4.c.

    python3 scripts/e2e/android_workshop_journey.py          # recorrido
    python3 scripts/e2e/android_workshop_journey.py probe    # nombres en pantalla
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
    frames_dir,
    hide_keyboard,
    keyboard_shown,
    login,
    night,
    open_route,
    pick_in_documents_ui,
    press,
    push_files,
    required,
    reveal_end,
    run,
    screen_size,
    scroll_into_view,
    semantics,
    set_system_theme,
    shell,
    swipe_down,
    tap,
    themed,
    type_into,
    wait_for,
    wait_gone,
)

PHOTO = {"rueda-trasera.png": (84, 140, 120)}
SERVICE = "Enrayado de rueda"
# Los neumáticos de la fixture: su BSD sale de su ficha técnica (622 y 584).
TIRE_FITS = "Neumático Maxxis Ardent 29 x 2.25"
TIRE_WRONG = "Neumático Kenda 27.5 x 2.10"
STATUS_CHIP = re.compile(r"^Cambiar o abrir estado")


def journey() -> None:
    email = required("WORKSHOP_E2E_EMAIL")
    password = required("WORKSHOP_E2E_PASSWORD")
    customer = required("WORKSHOP_E2E_CUSTOMER")
    brand = required("WORKSHOP_E2E_BRAND")
    model = required("WORKSHOP_E2E_MODEL")
    coworker = required("WORKSHOP_E2E_COWORKER")

    night(False)
    push_files(frames_dir, PHOTO)
    login(email, password)
    set_system_theme()

    open_job_for(customer)
    add_bike_from_model(brand, model)
    diagnosis_follows_the_bike()
    add_wheel_build("28")
    add_fitting_tire()
    add_wrong_tire()
    job_number = save_job(customer)

    approve_and_invoice()
    commission(coworker, job_number)
    photo_in_the_task()

    blocked_close_and_fix()
    bike_record_after_close(customer, brand)


# ── 1. Trabajo nuevo, y la bici del modelo (criterio 1) ─────────────────────
def open_job_for(customer: str) -> None:
    open_route("/taller/pegas/nueva")
    wait_for(re.compile(r"^Nuevo trabajo"), timeout=90, what="el trabajo nuevo")
    semantics("trabajo-nuevo")
    press(re.compile(r"Seleccionar cliente"), timeout=60)
    # Una sola clienta en el taller: la lista ya la muestra.
    press(re.compile(r"^" + re.escape(customer) + r"(\s|$)"), timeout=30)
    wait_for(re.compile(r"^Cliente " + re.escape(customer)), timeout=30,
             what="la clienta en el trabajo")
    evidence.append("clienta=elegida")


def add_bike_from_model(brand: str, model: str) -> None:
    press(re.compile(r"^Bicicleta \* Seleccione"), timeout=30)
    press("Nueva bicicleta", timeout=30)
    wait_for(re.compile(r"Sección 1 de 4"), timeout=30, what="el editor de la bici")
    # Marca y modelo se eligen de las listas del taller; con ellos, «Buscar»
    # encuentra el modelo en el catálogo.
    type_into("Marca *", brand[:3])
    press(re.compile(r"^" + re.escape(brand) + r"$"), cls="Button", timeout=20)
    type_into(re.compile(r"(^|\s)Modelo \*$"), model[:3])
    press(re.compile(r"^" + re.escape(model) + r"$"), cls="Button", timeout=20)
    hide_keyboard()
    press("Buscar", cls="Button")
    press(re.compile(r"^" + re.escape(f"{brand} {model}") + r" \(2024\)$"), timeout=30)
    wait_for(re.compile(r"^Trajo \d+ datos sin confirmar"), timeout=20,
             what="lo que trajo el modelo")
    # El aro que el modelo copió dice de dónde viene (no del mero vínculo).
    scroll_into_view(re.compile(r"^Aro 29"), timeout=20)
    wait_for(re.compile(r"^Del modelo " + re.escape(f"{brand} {model}") + r" 2024 · sin confirmar$"),
             timeout=10, what="el origen del aro que copió el modelo")
    themed("bici-desde-el-modelo")
    evidence.append("bici=del_modelo")

    press("Siguiente", cls="Button")
    press("Siguiente", cls="Button")
    # Sin familia de pedalier la bici no se guarda: el editor vuelve aquí.
    press(re.compile(r"^Sistema técnico:"), timeout=30)
    press(re.compile(r"^Pedalier / BB Pedalier"), timeout=20)
    press("Familia pedalier / BB", timeout=20)
    press(re.compile(r"^BSA roscado$"), cls="Button", timeout=20)
    press("Siguiente", cls="Button")
    press("Guardar", cls="Button")
    wait_for(re.compile(r"^Bicicleta \* " + re.escape(f"{brand} {model}")), timeout=60,
             what="la bici en el trabajo")
    evidence.append("bici=guardada")


# ── 2. El diagnóstico sale de la ficha (criterios 2 y 4) ────────────────────
def diagnosis_follows_the_bike() -> None:
    press(re.compile(r"^Diagnóstico$"), cls="Button", timeout=30)
    press(re.compile(r"^Sistema\. Cockpit"), timeout=30)
    press(re.compile(r"^Freno delantero"), timeout=20)
    press(re.compile(r"^Componente\. Pastillas"), timeout=20)
    # Freno de disco en la ficha: el freno tiene rotor, y el rotor se mide.
    press(re.compile(r"^Rotor Estado"), timeout=20)
    wait_for("Grosor rotor delantero", timeout=20,
             what="el rotor en el diagnóstico de un freno de disco")
    themed("diagnostico-segun-la-ficha")
    evidence.append("diagnostico=rotor_por_disco")


# ── 3. Servicio y repuestos con lo que la ficha ya sabe ─────────────────────
def search_items(query: str) -> None:
    # El buscador abre su panel después del primer toque: lo tecleado antes
    # de «Motor de compatibilidad» se pierde (2026-09-30).
    press(re.compile(r"^Agregar repuesto o parte"), cls="EditText", timeout=30)
    wait_for("Motor de compatibilidad", timeout=20, what="el buscador de ítems")
    shell(f"input text {query}")
    time.sleep(2)


def set_side(side: str, verdict: re.Pattern[str]) -> None:
    press(re.compile(r"^Sin fijar lado$"), timeout=30)
    press(re.compile(r"^" + side + r"$"), cls="CheckBox", timeout=20)
    # La línea puede quedar sobre el borde (la lista crece hacia abajo): lo
    # que está fuera de la vista no está en el árbol, así que se desplaza.
    scroll_into_view(verdict, timeout=60)


def add_wheel_build(holes: str) -> None:
    press(re.compile(r"^Productos y servicios$"), cls="Button", timeout=30)
    search_items("Enrayado")
    press(re.compile(r"^" + re.escape(SERVICE) + r" SKU"), timeout=30)
    press(re.compile(r"^Falta: Cantidad de rayos"), timeout=30)
    press(re.compile(r"^Trasera$"), cls="Button", timeout=20)
    # El freno lo trae la ficha: el asistente no lo pregunta en blanco.
    wait_for(re.compile(r"^Disco hidráulico$"), cls="Button", timeout=10,
             what="el freno que ya sabe la ficha")
    themed("asistente-con-lo-que-sabe-la-ficha")
    press("Selecciona una opción", timeout=20)
    press(re.compile(r"^" + holes + r"$"), cls="Button", timeout=20)
    press(re.compile(r"^Aplicar$"), cls="Button")
    wait_for(re.compile(r"Cantidad de rayos / hoyos: " + holes), timeout=30,
             what="el Enrayado en las líneas")
    evidence.append(f"enrayado_trasero={holes}H")


def add_fitting_tire() -> None:
    search_items("Ardent")
    press(re.compile(r"^" + re.escape(TIRE_FITS) + r" SKU"), timeout=30)
    hide_keyboard()
    set_side("Trasero", re.compile(r"La ficha lo anota al terminar: rueda trasera 622"))
    evidence.append("neumatico_29=trasero")


def add_wrong_tire() -> None:
    search_items("Kenda")
    # «Solo compatibles» esconde el 27,5; «Mostrar todo» lo muestra marcado.
    # Primero llegan los resultados (siempre ofrece el artículo suelto).
    wait_for(re.compile(r'^Agregar: "Kenda"'), timeout=20, what="los resultados de «Kenda»")
    if find_all(dump(), re.compile(r"^" + re.escape(TIRE_WRONG) + r" SKU")):
        raise JourneyError("«Solo compatibles» mostró el neumático 27,5")
    themed("buscador-solo-compatibles")
    press(re.compile(r"^Mostrar todo$"), cls="RadioButton")
    wait_for(re.compile(r"^" + re.escape(TIRE_WRONG) + r" SKU: No compatible"), timeout=20,
             what="el 27,5 marcado como no compatible")
    themed("buscador-mostrar-todo")
    press(re.compile(r"^" + re.escape(TIRE_WRONG) + r" SKU"), timeout=20)
    hide_keyboard()
    set_side("Delantero", re.compile(r"No calza con el aro 29"))
    scroll_into_view(re.compile(r"No calza con el aro 29"), timeout=20)
    themed("lineas-del-trabajo")
    evidence.append("neumatico_27_5=delantero_no_calza")


def save_job(customer: str) -> str:
    press(re.compile(r"^Guardar$"), cls="Button", timeout=30)
    row = wait_for(re.compile(r"^Abrir cliente " + re.escape(customer) + r" PG-\d+"),
                   timeout=60, what="el trabajo en la lista")
    number = re.search(r"PG-\d+", row.name).group(0)
    evidence.append(f"trabajo={number}")
    return number


# ── 4. Presupuesto aprobado y facturado ─────────────────────────────────────
def let_snackbar_go(text: re.Pattern[str], name: str) -> None:
    """Un aviso con acción ya no queda fijo (Flutter 3.38 lo fijaba; tapaba la
    hoja de vistas en teléfono). Si sigue, se aparta y se anota."""
    deadline = time.monotonic() + 15
    while found := find_all(dump(), text):
        if time.monotonic() > deadline:
            # Se desliza desde el aviso mismo: un gesto que empieza sobre la
            # lista la desplaza y deja el aviso donde estaba.
            x, y = found[0].center
            _, height = screen_size()
            shell(f"input swipe {x} {y} {x} {height - 5} 250")
            time.sleep(1.5)
            if find_all(dump(), text):
                raise JourneyError(f"el aviso «{name}» no se fue ni deslizándolo")
            evidence.append(f"aviso_{name}=apartado_a_mano")
            return
        time.sleep(1.5)
    evidence.append(f"aviso_{name}=se_fue_solo")


def approve_and_invoice() -> None:
    press(STATUS_CHIP, timeout=30)
    press(re.compile(r"^Aprobado$"), timeout=20)
    wait_for(re.compile(r"^Cambiar o abrir estado: .*Presupuesto Aprobado$"), timeout=30,
             what="el presupuesto aprobado")
    let_snackbar_go(re.compile(r"^Presupuesto aprobado\. Puedes facturarlo"), "aprobado")
    press(re.compile(r"^Ver más acciones del trabajo"), timeout=20)
    press(re.compile(r"^Facturar presupuesto$"), timeout=20)
    press("Crear factura", cls="Button", timeout=20)
    wait_for(re.compile(r"^Abrir factura del trabajo"), timeout=60, what="la factura del trabajo")
    let_snackbar_go(re.compile(r"fue facturado conservando"), "facturado")
    evidence.append("presupuesto=aprobado_y_facturado")


# ── 5. El encargo con /tarea, y la foto en la tarea ─────────────────────────
def open_action(command: str) -> None:
    """Una acción «/…» del buscador global. Sin un campo con foco, la primera
    tecla abre el buscador; el resto se escribe ya en su campo y se comprueba.
    Todo de una vez, `input text /tarea` llegó como «/taa» el 2026-09-30: dos
    teclas se perdieron mientras el buscador se abría."""
    focused = [node for node in dump() if node.cls.endswith("EditText") and node.focused]
    if not focused:
        shell("input text /")
        focused = [wait_for(re.compile(r"^/"), cls="EditText", timeout=20, what="el buscador global")]
    field = focused[0]
    shell("input keyevent 123")  # fin del texto
    shell("input keyevent " + " ".join(["67"] * (len(field.text) + 2)))
    shell(f"input text {command}")
    time.sleep(1.2)
    value = [node.text for node in dump() if node.cls.endswith("EditText") and node.focused]
    if value != [command]:
        raise JourneyError(f"el buscador quedó con {value!r} en vez de «{command}»")
    shell("input keyevent 66")


def commission(coworker: str, job_number: str) -> None:
    # Sin un campo con foco, teclear abre el buscador; «/» son acciones.
    open_action("/tarea")
    press(re.compile(r"^\w{1,3} " + re.escape(coworker) + r"\b"), timeout=30)
    press(re.compile(r"^#" + re.escape(job_number) + r"\b"), timeout=30)
    press(re.compile(r"^Hacer el trabajo"), timeout=30)
    # El encargo lleva la línea del Enrayado, con lo que se respondió.
    wait_for(re.compile(r"^" + re.escape(SERVICE) + r" .*Cantidad de rayos / hoyos: 28"),
             timeout=30, what="la línea del Enrayado en el encargo")
    hide_keyboard()
    themed("encargo-sobre-la-linea")
    press(re.compile(r"^Crear tarea$"), timeout=20)
    press(re.compile(r"^Ver la tarea$"), timeout=60)
    wait_for(re.compile(r"^TRABAJO #" + re.escape(job_number) + r" 0 de 1 servicios hechos "
                        + re.escape(SERVICE)), timeout=30, what="la tarea ligada al trabajo")
    themed("tarea-ligada-a-la-linea")
    evidence.append("encargo=a_la_companera_sobre_la_linea")
    # El panel de herramientas cubre la lista, pero la lista sigue en el
    # árbol: se cierra mientras el panel esté, no hasta ver «Vista:».
    for _ in range(3):
        if not find_all(dump(), re.compile(r"^Tareas, herramienta")):
            break
        back = find_all(dump(), "Volver", cls="Button")
        if not back:
            break
        tap(back[0], 2)
    if find_all(dump(), re.compile(r"^Tareas, herramienta")):
        raise JourneyError("el panel de la tarea no se cerró")


def photo_in_the_task() -> None:
    press(re.compile(r"^Vista: "), timeout=30)
    press(re.compile(r"^Tareas Tareas operativas"), timeout=20)
    press(re.compile(r"^Ver detalles de Hacer el trabajo"), timeout=30)
    press(re.compile(r"^Adjuntos Agregar archivos"), timeout=20)
    wait_for("Editar Tarea", timeout=30, what="la tarea en su formulario")
    # Con el teclado arriba, «Actualizar» y «Cancelar» siguen a la vista.
    type_into("Descripción (Opcional)", "Foto de la rueda antes de armar.")
    _, height = screen_size()
    footer = find_all(dump(), re.compile(r"^(Actualizar|Cancelar)$"), cls="Button")
    if not keyboard_shown() or len(footer) != 2 or any(n.bounds[3] > height * 0.65 for n in footer):
        raise JourneyError("con el teclado arriba no se ven «Actualizar» y «Cancelar»")
    themed("tarea-con-teclado")
    hide_keyboard()
    press("Agregar archivo")
    pick_in_documents_ui(list(PHOTO))
    wait_for("Adjuntos (1)", timeout=60)
    press("Actualizar", cls="Button")
    wait_gone("Editar Tarea", timeout=120, what="la tarea tras subir la foto")
    # Reabrir y mirar la foto en el visor oscuro.
    press(re.compile(r"^Adjuntos 1 archivo"), timeout=60)
    wait_for("Actualizar", timeout=60)
    press("Abrir adjunto", timeout=60)
    wait_for(re.compile(r"^rueda-trasera\.png PNG$"), timeout=60, what="el visor")
    time.sleep(1.5)
    themed("visor-de-la-foto")
    close = find_all(dump(), "Cerrar", cls="Button")
    if not close:
        raise JourneyError("el visor no ofrece «Cerrar»")
    tap(close[0], 2)
    press("Cancelar", cls="Button", timeout=30)
    wait_gone("Editar Tarea", timeout=30)
    evidence.append("foto=subida_y_vista")


# ── 6. Cierre rechazado y corregido ─────────────────────────────────────────
def change_status(target: str) -> None:
    press(STATUS_CHIP, timeout=30)
    press(re.compile(r"^Cambiar estado a " + target), timeout=20)


def blocked_close_and_fix() -> None:
    press("Cambiar vista del taller", timeout=30)
    press(re.compile(r"^Lista Lectura rápida"), timeout=20)
    change_status("En Curso")
    wait_for(re.compile(r"^Cambiar o abrir estado: En curso"), timeout=30, what="el trabajo en curso")
    change_status("Finalizado")
    # El 27,5 adelante no calza con el aro 29: el servidor rechaza el cierre
    # entero y dice qué línea corregir (`incompatible`, motor de fichas real).
    wait_for(re.compile(r"sin cerrar$"), timeout=60, what="el cierre rechazado")
    wait_for(re.compile(r"^«" + re.escape(TIRE_WRONG) + r"» dice 584"), timeout=10,
             what="la línea que el cierre pide corregir")
    themed("cierre-rechazado")
    evidence.append("cierre=rechazado_por_neumatico_que_no_calza")
    # «Revisar líneas» cierra también la hoja de estados (2026-09-30).
    press("Revisar líneas", cls="Button")
    press(re.compile(r"^Acciones de Línea \d+, " + re.escape(TIRE_WRONG)), timeout=60)
    press(re.compile(r"^Cambiar por otro artículo$"), timeout=20)
    field = wait_for("Buscar por nombre...", cls="EditText", timeout=20)
    tap(field)
    wait_for("Motor de compatibilidad", timeout=20, what="el buscador del cambio")
    shell("input text Ardent")
    time.sleep(2)
    press(re.compile(r"^" + re.escape(TIRE_FITS) + r" SKU"), timeout=30)
    hide_keyboard()
    set_side("Delantero", re.compile(r"La ficha lo anota al terminar: rueda delantera 622"))
    # El precio es el del artículo nuevo, no el del 27,5 (2026-09-30).
    if find_all(dump(), re.compile(r"^14990 Precio unit"), cls="EditText"):
        raise JourneyError("la línea cambiada quedó con el precio del 27,5")
    themed("linea-corregida")
    press(re.compile(r"^Guardar$"), cls="Button", timeout=20)
    wait_for(STATUS_CHIP, timeout=60, what="la lista tras guardar")
    change_status("Finalizado")
    wait_for(re.compile(r"^Cambiar o abrir estado: Finalizado"), timeout=60,
             what="el trabajo terminado")
    themed("trabajo-terminado")
    evidence.append("cierre=terminado_tras_corregir")


# ── 7. La ficha y el historial (criterios 5, 6 y 7) ─────────────────────────
def bike_record_after_close(customer: str, brand: str) -> None:
    # En el editor de la bici: la rueda trasera instalada en el trabajo, sin
    # confirmar el BSD (la ficha del neumático no está verificada).
    press(re.compile(r"^Abrir Bicicleta: " + re.escape(brand)), timeout=30)
    wait_for(re.compile(r"Sección 1 de 4"), timeout=30, what="el editor de la bici")
    press("Siguiente", cls="Button")
    press("Siguiente", cls="Button")
    press(re.compile(r"^Sistema técnico:"), timeout=30)
    press(re.compile(r"^Rueda trasera Rueda trasera"), timeout=20)
    wait_for("Instalado en un trabajo terminado · sin confirmar", timeout=20,
             what="el BSD trasero instalado y sin confirmar")
    themed("ficha-rueda-trasera")
    evidence.append("ficha=bsd_trasero_del_trabajo_sin_confirmar")
    press("Volver a trabajos", cls="Button")

    press(re.compile(r"^Abrir cliente " + re.escape(customer)), timeout=30)
    press(re.compile(r"^Abrir bicicleta " + re.escape(brand)), timeout=30)
    press(re.compile(r"^Ficha Técnica$"), timeout=30)
    scroll_into_view(re.compile(r"^32 / 28$"), timeout=40)
    scroll_into_view(re.compile(r"^622 \(29″/700c\)$"), timeout=20)
    themed("ficha-tecnica-resumen")
    evidence.append("resumen=rayos_32_28_bsd_622")
    for _ in range(4):
        swipe_down()
    press(re.compile(r"^Historial$"), timeout=30)
    press(re.compile(r"^Rueda trasera$"), timeout=30)
    # El mapa de la rueda trasera con su leyenda, que en oscuro se leía gris
    # sobre blanco (corregida en BikeSystemController, 2026-09-30).
    legend = scroll_into_view(re.compile(r"Rueda trasera — componentes$"), timeout=30)
    _, height = screen_size()
    if legend.bounds[3] >= height * 0.97:
        raise JourneyError("la leyenda del mapa queda bajo el borde")
    themed("mapa-rueda-trasera-con-leyenda")
    evidence.append("leyenda=rueda_trasera_componentes")
    # La memoria de la rueda trasera nombra el Enrayado: sus respuestas
    # («Tipo de freno: Disco hidráulico») ya no lo llevan al freno. La
    # tarjeta es un solo nodo y el servicio es su última fila: se desplaza
    # hasta su final para que la fila (servicio, rueda y trabajo de origen)
    # quede en el frame, no sólo el comienzo de la memoria.
    reveal_end(re.compile(r"Activo: Rueda trasera .*Servicio: " + re.escape(SERVICE)
                          + r" .*Trasero PG-\d+$"), timeout=40)
    themed("historial-rueda-trasera")
    evidence.append("historial=enrayado_en_la_rueda_trasera")


if __name__ == "__main__":
    sys.exit(run(journey, "C1/C4 nativo"))
