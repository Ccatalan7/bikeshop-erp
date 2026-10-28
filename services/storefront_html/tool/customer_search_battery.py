"""Busca como un cliente: cada búsqueda contra /buscar en vivo, compacta.

El 2026-10-28 el dueño: «tenéis que probarla tú directamente, probar ser como
que tú fueras un cliente». Estas son las búsquedas que un cliente chileno
escribe (palabras de taller, errores de tipeo, plurales, medidas a medio
escribir, marcas, modelos y servicios). Se corren antes y después de tocar la
búsqueda y se lee cada diferencia: más resultados no es mejor si son ruido.

Uso:
  python3 -I tool/customer_search_battery.py > antes.txt
  python3 -I tool/customer_search_battery.py --compare antes.txt
  python3 -I tool/customer_search_battery.py "neumatico 27" "kasco"

--api cambia el origen (por defecto el Cloud Run de la tienda, sin el relevo
de Hosting). Sólo lee: no deja búsquedas sin resultados registradas.
"""
import argparse
import json
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor

API = "https://storefront-html-c6c5ju6mca-rj.a.run.app"

QUERIES = [
    # Neumáticos, cámaras, llantas, ruedas
    "neumatico", "neumatico 29", "neumatico 27", "neumatico 27.5", "neumatico 27,5",
    "neumatico 27 5", "neumatico 26", "neumatico 700x25", "neumatico 2", "neumatico 27.5 x 2",
    "neumatico 2.2", "neumatico 29x2.10", "neumatico mtb", "neumatico ruta", "neumatico tubeless",
    "maxxis", "kenda", "chaoyang", "camara", "camara 29", "camara 27", "camara 20", "camara 2",
    "camara presta", "camara valvula fina", "camara auto", "llanta 27", "llanta 29", "aro 27",
    "rueda", "rueda 29", "rayos", "maza", "maza trasera",
    # Frenos
    "pastillas", "pastiyas", "pastillas fremo", "pastillas b01s", "pastillas shimano",
    "freno", "freno disco", "freno hidraulico", "freno v brake", "zapatas", "patines",
    "disco freno", "rotor 160", "rotor 180", "manilla freno", "liquido de frenos", "sangrado",
    # Transmisión
    "cadena", "cadena 9v", "cadena 9 velocidades", "cadena 11v", "kmc x9", "cassette",
    "cassette 11-3", "cassette 11-42", "piñon", "pinon", "cambio", "cambio trasero",
    "cambio delantero", "desviador", "shifter", "manilla de cambio", "pata de cambio",
    "postiza", "motor", "pedalier", "eje pedalier cuadrado", "eje cuadrado", "biela", "bielas",
    "plato", "corona 36", "missing link", "piola", "funda de cambio", "shimano", "deore",
    "altus", "rd m310", "bb-un300",
    # Manubrio, asiento, suspensión
    "manubrio", "volante", "potencia", "potencia 31.8", "tee", "puños", "sillin", "asiento",
    "tija", "tija de 27.2", "direccion", "horquilla", "horquilla 29", "suspension",
    # Accesorios
    "casco", "cascos", "kasco", "guantes", "guantes largos", "guantes cortos", "luz",
    "luz trasera", "luz para bici", "candado", "bombin", "bonbin", "inflador", "caramagiola",
    "porta caramagiola", "porta celular", "soporte celular", "timbre", "parrilla", "canasto",
    "tapabarro", "pedales", "pedal", "pedales plataforma", "mochila", "lentes", "polera",
    # Cuidado y herramientas
    "lubricante", "aceite cadena", "desengrasante", "grasa", "liquido tubeless", "sellante",
    "valvula tubeless", "cinta tubeless", "parches", "kit de parches", "herramientas",
    "llave allen", "desmontador", "corta cadena", "cono",
    # Servicios
    "taller", "servicio", "arreglo", "arreglo frenos", "mantencion", "mantención",
    "mantencion full", "lavado", "armado", "ajuste frenos", "centrado rueda", "cambio de cadena",
    # Errores de tipeo
    "nuematico", "neumatco", "camra", "cadna", "shimamo", "candao", "maxis", "deraillleur",
]


def ask(api, q, stock_all=False):
    params = {"q": q}
    if stock_all:
        params["stock"] = "all"
    with urllib.request.urlopen(api + "/buscar?" + urllib.parse.urlencode(params), timeout=30) as r:
        return json.load(r)


def line(api, q):
    d = ask(api, q)
    head = f"{q!r:28} {d['total']:>3}"
    if d.get("fixed"):
        head += f" «{d['fixed']}»"
    if d.get("agotados"):
        head += f" [+agot: {d['agotados']}]"
    prods = " | ".join(p["name"][:42] for p in d["products"][:4])
    cats = ", ".join(f'{c["name"]} {c["count"]}' for c in d["categories"][:3])
    servs = " | ".join(s["name"][:30] for s in d["services"][:2])
    return q, f"{head}\n    P: {prods}\n    C: {cats}\n    S: {servs}"


def parse(path):
    out, cur = {}, None
    for text in open(path, encoding="utf-8"):
        if text.startswith("'"):
            cur = text.split("'")[1]
            out[cur] = [text.rstrip("\n")]
        elif cur:
            out[cur].append(text.rstrip("\n"))
    return {q: "\n".join(v) for q, v in out.items()}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("queries", nargs="*")
    parser.add_argument("--api", default=API)
    parser.add_argument("--compare", help="una corrida anterior: sólo imprime lo que cambió")
    args = parser.parse_args()
    queries = args.queries or QUERIES
    with ThreadPoolExecutor(max_workers=4) as pool:
        results = list(pool.map(lambda q: line(args.api, q), queries))
    if not args.compare:
        for _, text in results:
            print(text)
        return
    before = parse(args.compare)
    for q, text in results:
        if before.get(q) != text:
            print(text)
            print("    ANTES: " + (before.get(q, "(no estaba)").split("\n")[0][29:].strip()))


main()
