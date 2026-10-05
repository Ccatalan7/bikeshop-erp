#!/usr/bin/env python3
"""Compares the HTML storefront with the Flutter store's published pages.

For every product and category URL in the live sitemap, it fetches the page the
Flutter store publishes (the SEO snapshot the build writes from the Flutter
data path) and the same path from the HTML server, and compares what Google and
a visitor read: title, description, robots, canonical, h1, the Product node
(name, SKU, photos, brand, category, price, availability, technical sheet,
GTIN, model), the breadcrumbs, the collection nodes and the BikeStore node.

The snapshot is as old as the last store build; the HTML is read now, so a
price or stock change since the build shows as a difference to re-check.

With `--skus FILE` it checks instead that every published SKU renders at its
canonical path (the sitemap leaves out products without photos).

    python3 services/storefront_html/tool/parity.py \
        --html http://localhost:4325 [--flutter https://vinabike.cl] \
        [--limit N] [--workers 8] [--out report.json] [--skus skus.txt]

Exit code 1 when any page differs or any SKU fails.
Stdlib only.
"""

import argparse
import html as htmllib
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor

UA = "vinabike-parity/1 (+storefront_html/tool/parity.py)"


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):  # noqa: D401
        return None


OPENER = urllib.request.build_opener(NoRedirect)


def fetch(url, attempts=4):
    request = urllib.request.Request(url, headers={"user-agent": UA})
    for attempt in range(attempts):
        try:
            with OPENER.open(request, timeout=40) as response:
                return response.status, response.read().decode("utf-8", "replace"), dict(response.headers)
        except urllib.error.HTTPError as error:
            body = error.read().decode("utf-8", "replace") if error.fp else ""
            return error.code, body, dict(error.headers or {})
        except (urllib.error.URLError, ConnectionError, TimeoutError):
            # A reset from the CDN is not a difference: try again.
            if attempt == attempts - 1:
                raise
            time.sleep(1 + attempt * 2)


def head_fields(page):
    def first(pattern):
        match = re.search(pattern, page, re.S | re.I)
        return htmllib.unescape(match.group(1).strip()) if match else None

    return {
        "title": first(r"<title>(.*?)</title>"),
        "description": first(r'<meta[^>]*name="description"[^>]*content="([^"]*)"')
        or first(r'<meta[^>]*content="([^"]*)"[^>]*name="description"'),
        "robots": first(r'<meta[^>]*name="robots"[^>]*content="([^"]*)"')
        or first(r'<meta[^>]*content="([^"]*)"[^>]*name="robots"'),
        "canonical": first(r'<link[^>]*rel="canonical"[^>]*href="([^"]*)"')
        or first(r'<link[^>]*href="([^"]*)"[^>]*rel="canonical"'),
        "h1": strip_tags(first(r"<h1[^>]*>(.*?)</h1>")) or None,
    }


def nodes(page):
    found = []
    for match in re.finditer(
        r'<script[^>]*type="application/ld\+json"[^>]*>(.*?)</script>', page, re.S
    ):
        try:
            data = json.loads(match.group(1))
        except ValueError:
            found.append({"@type": "INVALID_JSON"})
            continue
        for item in data if isinstance(data, list) else [data]:
            graph = item.get("@graph") if isinstance(item, dict) else None
            found.extend(graph if isinstance(graph, list) else [item])
    return found


def by_type(found, kind):
    return [n for n in found if isinstance(n, dict) and n.get("@type") == kind]


def strip_tags(text):
    return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", text or "")).strip()


def product_view(found):
    products = by_type(found, "Product")
    if not products:
        return None
    p = products[0]
    offers = p.get("offers") or {}
    if isinstance(offers, list):
        offers = offers[0] if offers else {}
    return {
        "name": p.get("name"),
        "sku": p.get("sku"),
        "image": p.get("image"),
        "brand": (p.get("brand") or {}).get("name") if isinstance(p.get("brand"), dict) else p.get("brand"),
        "category": p.get("category"),
        "gtin": p.get("gtin13") or p.get("gtin") or p.get("gtin12") or p.get("gtin8"),
        "model": p.get("model"),
        "price": str(offers.get("price")) if offers.get("price") is not None else None,
        "availability": offers.get("availability"),
        "description": strip_tags(p.get("description")),
        "sheet": sorted(
            (a.get("name"), str(a.get("value")))
            for a in (p.get("additionalProperty") or [])
            if isinstance(a, dict)
        ),
    }


def crumbs(found):
    lists = by_type(found, "BreadcrumbList")
    if not lists:
        return None
    return [
        (item.get("name"), item.get("item"))
        for item in lists[0].get("itemListElement", [])
    ]


def collection_view(found):
    page = by_type(found, "CollectionPage")
    items = by_type(found, "ItemList")
    return {
        "collection": {k: page[0].get(k) for k in ("name", "url", "description", "image")} if page else None,
        "items": {
            "name": items[0].get("name"),
            "numberOfItems": items[0].get("numberOfItems"),
            "elements": [
                (element.get("url"), element.get("name"))
                for element in items[0].get("itemListElement", [])
            ],
        } if items else None,
    }


def business(found):
    stores = by_type(found, "BikeStore")
    return stores[0] if stores else None


def compare(path, flutter_base, html_base):
    f_status, f_page, _ = fetch(flutter_base + path)
    h_status, h_page, h_headers = fetch(html_base + path)
    result = {"path": path, "flutter": f_status, "html": h_status, "diffs": []}
    if h_status != 200:
        result["diffs"].append(("status", f_status, h_status, h_headers.get("Location") or h_headers.get("location")))
        return result
    if f_status != 200:
        result["diffs"].append(("flutter_status", f_status, None, None))
        return result
    f_head, h_head = head_fields(f_page), head_fields(h_page)
    for key in f_head:
        if f_head[key] != h_head[key]:
            result["diffs"].append((key, f_head[key], h_head[key], None))
    f_nodes, h_nodes = nodes(f_page), nodes(h_page)
    if business(f_nodes) != business(h_nodes):
        result["diffs"].append(("BikeStore", business(f_nodes), business(h_nodes), None))
    if crumbs(f_nodes) != crumbs(h_nodes):
        result["diffs"].append(("breadcrumbs", crumbs(f_nodes), crumbs(h_nodes), None))
    if "/productos/categoria/" in path or path == "/productos":
        fv, hv = collection_view(f_nodes), collection_view(h_nodes)
        for key in fv:
            if fv[key] != hv[key]:
                result["diffs"].append((key, fv[key], hv[key], None))
    else:
        fv, hv = product_view(f_nodes), product_view(h_nodes)
        if fv is None or hv is None:
            result["diffs"].append(("Product", fv is not None, hv is not None, None))
        else:
            for key in fv:
                if fv[key] != hv[key]:
                    result["diffs"].append((key, fv[key], hv[key], None))
            result["sku"] = hv.get("sku")
    return result


def check_sku(sku, html_base):
    """Every published SKU answers: `/productos/x/<sku>` redirects once to its
    canonical path, which answers 200 and declares itself canonical."""
    quoted = urllib.parse.quote(sku, safe="")
    status, _, headers = fetch(f"{html_base}/productos/x/{quoted}")
    location = headers.get("Location") or headers.get("location")
    if status != 301 or not location:
        return {"sku": sku, "error": f"first answer {status}"}
    status, page, _ = fetch(html_base + location)
    canonical = head_fields(page).get("canonical") or ""
    if status != 200:
        return {"sku": sku, "error": f"{location} answered {status}"}
    if not canonical.endswith(location):
        return {"sku": sku, "error": f"{location} declares {canonical}"}
    if not product_view(nodes(page)):
        return {"sku": sku, "error": f"{location} has no Product node"}
    return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--html", default="http://localhost:4325")
    parser.add_argument("--flutter", default="https://vinabike.cl")
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument(
        "--only-collections",
        action="store_true",
        help="compare only /productos and the category pages",
    )
    parser.add_argument("--workers", type=int, default=8)
    parser.add_argument("--out")
    parser.add_argument(
        "--skus",
        help="file with one published SKU per line: checks that each one renders "
        "at its canonical path instead of comparing with the sitemap",
    )
    args = parser.parse_args()

    if args.skus:
        with open(args.skus, encoding="utf-8") as handle:
            skus = [line.strip() for line in handle if line.strip()]
        with ThreadPoolExecutor(max_workers=args.workers) as pool:
            failures = [f for f in pool.map(lambda s: check_sku(s, args.html), skus) if f]
        print(json.dumps({"skus": len(skus), "failures": len(failures)}, indent=2))
        for failure in failures[:40]:
            print(failure)
        sys.exit(1 if failures else 0)

    _, sitemap, _ = fetch(args.flutter + "/sitemap.xml")
    origin = args.flutter.rstrip("/")
    paths = []
    for loc in re.findall(r"<loc>(.*?)</loc>", sitemap):
        path = loc.replace(origin, "") or "/"
        if path == "/productos" or path.startswith("/productos/"):
            paths.append(path)
    if args.only_collections:
        paths = [p for p in paths if p == "/productos" or "/categoria/" in p]
    if args.limit:
        paths = paths[: args.limit]

    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        results = list(pool.map(lambda p: compare(p, args.flutter, args.html), paths))

    differing = [r for r in results if r["diffs"]]
    by_field = {}
    for r in differing:
        for diff in r["diffs"]:
            by_field.setdefault(diff[0], []).append(r["path"])
    summary = {
        "pages": len(results),
        "products": sum(1 for p in paths if "/categoria/" not in p and p != "/productos"),
        "categories": sum(1 for p in paths if "/categoria/" in p or p == "/productos"),
        "identical": len(results) - len(differing),
        "by_field": {k: len(v) for k, v in sorted(by_field.items())},
    }
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    for r in differing[:40]:
        print(r["path"])
        for field, old, new, extra in r["diffs"]:
            print(f"   {field}: flutter={json.dumps(old, ensure_ascii=False)[:300]}")
            print(f"   {' ' * len(field)}  html   ={json.dumps(new, ensure_ascii=False)[:300]}{'  → ' + extra if extra else ''}")
    if args.out:
        with open(args.out, "w", encoding="utf-8") as handle:
            json.dump({"summary": summary, "results": results}, handle, ensure_ascii=False, indent=1)
    sys.exit(1 if differing else 0)


if __name__ == "__main__":
    main()
