# slides.py <asset-base-url> <out.json> — the seven approved slides as the
# editor stores them: every text, button, product photo and accent a layer of
# its own, measured from the approved frames (meas/*.json); the ground art an
# image under them. Desktop layers show from 900 up; the phone's on a phone
# and a tablet.
import json, os, sys, re
# The working folder: meas/ and out/ live in it.
S = os.environ.get('CAMPAIGN_WORK') or os.getcwd()
BASE = sys.argv[1]  # a folder with its slash, or a name prefix
OUT = sys.argv[2]
WA = 'https://wa.me/56998357797?text='
from urllib.parse import quote

def wa(text):
    return WA + quote(text, safe='')

CAT = '/productos?category='
SITE = 'https://vinabike.cl'
# Where each button of the approved frames goes on the real site.
DEST = {
    SITE + '/productos/categoria/bicicletas': CAT + '29f464d8-8290-5d99-8782-efc8aae20c60',
    SITE + '/productos/categoria/horquillas': CAT + '85c21c7e-3791-4795-9aba-ef30f9b5a236',
    SITE + '/guias/en-bici-a-lo-vasquez': '/guias/en-bici-a-lo-vasquez',
    SITE + '/servicios': '/servicios',
    SITE + '/productos/bicicleta-royal-baby-freestyle-7-aro-16-rojo/6975531562089': '/productos/bicicleta-royal-baby-freestyle-7-aro-16-rojo/6975531562089',
    SITE + '/productos/horquilla-rockshox-lyrik-ultimate-rc2-charger-3-1-debonair-27-5-boost-160-mm-off/710845916991': '/productos/horquilla-rockshox-lyrik-ultimate-rc2-charger-3-1-debonair-27-5-boost-160-mm-off/710845916991',
}
# What the frames only sketched (`/productos`, `/contacto`): by slide and label.
BY_LABEL = {
    ('ninos', '¿Cuál le queda? Dinos cuánto mide'): wa('Hola Viñabike, quiero saber qué bicicleta le queda a un niño. Mide '),
    ('horquillas', '¿Cuál le sirve a tu bici? Escríbenos'): wa('Hola Viñabike, quiero saber qué horquilla le sirve a mi bici'),
    ('maxxis', '¿No sabes cuál lleva tu bici? Escríbenos'): wa('Hola Viñabike, quiero saber qué neumático Maxxis lleva mi bici'),
    ('maxxis', 'Ver neumáticos Maxxis'): '/productos?brand=aae19bd2-257d-47b0-8175-fc259939233e',
    ('servicios', 'Agenda por WhatsApp'): wa('Hola Viñabike, quiero agendar un servicio para mi bici'),
    ('servicios', 'Ver qué incluye cada uno'): '/servicios',
    ('cassette', 'Comprar'): '/productos/cassette-sram-eagle-t-type-xs-1270-12v-10-52t-nucleo-hg/710845904684',
    ('accesorios', 'Ver accesorios'): CAT + '164e46a9-3bfc-47d9-85ff-e911d96adacd',
}
IMG = {
    'ROB00005-1.jpg': ('bici-freestyle-16-roja-{v}.webp', 'bici'),
    'mkr-srm00315.png': ('cassette-xs-1270-{v}.webp', 'cassette'),
    'mx-assegai.jpg': ('neumatico-assegai-{v}.webp', 'neumatico'),
    'coil-yellow.jpg': ('candado-espiral-onguard.webp', 'candado'),
    'AE0253.png': ('luz-trasera.webp', 'luz'),
    '180GP46L.png': ('bombin-giyo.webp', 'bombin'),
    'fork.png': ('horquilla-lyrik-ultimate.webp', 'horquilla'),
    'mx-logo.png': ('maxxis-logo.webp', 'logo_maxxis'),
}
NAMES = {'eye': 'antetitulo', 'ttl': 'titulo', 'sub': 'bajada', 'fine': 'nota', 'tag': 'etiqueta', 'spec': 'dato',
         'sign': 'cartel', 'pn': 'plan', 'pp': 'precio', 'pd': 'detalle', 'price': 'precio'}
SLIDES = [
    # name, title, subtitle, slide ground, counter ink desktop / phone, plate
    ('lovasquez', 'En bici a Lo Vásquez', 'Desde Viña del Mar, con 530 m de subida.', '#29172D', 'light', 'light', False),
    ('ninos', 'Bicicletas para niños', 'De 2 a 11 años, en aro 12 al 24.', '#0E2A1F', 'light', 'dark', False),
    ('servicios', 'Servicios', 'Para dejar la bici al día de una vez.', '#252D35', 'light', 'dark', False),
    ('maxxis', 'Neumáticos Maxxis', 'Assegai, High Roller II, Forekaster, Rekon, Ardent y más.', '#3B2214', 'dark', 'dark', True),
    ('horquillas', 'Horquillas RockShox', 'Recon, Reba, SID, Lyrik, Domain y BoXXer.', '#071A1E', 'light', 'light', False),
    ('cassette', 'Cassette SRAM XS-1270', '12 velocidades · 10-52T · núcleo HG', '#E7E9EB', 'dark', 'dark', False),
    ('accesorios', 'Luces, candados y bombines', 'Lo básico para tu bici.', '#2A1C58', 'light', 'dark', False),
]
ART_ALT = {'lovasquez': 'Perfil de la ruta de Viña del Mar al santuario de Lo Vásquez: 36 km, con el punto más alto a 416 m'}
R1 = lambda v: round(float(v), 1)


def responsive(visible_on):
    """A desktop layer hides on phone and tablet; a phone layer shows only there."""
    if visible_on == 'd':
        return True, {'mobile': {'visible': False}, 'tablet': {'visible': False}, 'version': 2}
    return False, {'mobile': {'visible': True}, 'tablet': {'visible': True}, 'version': 2}


def base(lid, kind, x, y, w, h, v, **extra):
    visible, resp = responsive(v)
    return {'id': lid, 'type': kind, 'x': R1(x), 'y': R1(y), 'w': R1(w), 'h': R1(h), 'rotation': extra.pop('rotation', 0),
            'locked': False, 'visible': visible, 'anim': 'none', **extra, 'responsive': resp}


def merge_texts(texts):
    """Lines of one paragraph (same style, same left, one line apart) join in one layer."""
    blocks = []
    for t in texts:
        lh = t['fontSize'] * t['lineHeight']
        key = (t['container'], t['parent'], t['fontSize'], t['weight'], t['color'], t['uppercase'])
        prev = blocks[-1] if blocks else None
        if prev and prev['key'] == key and abs(prev['x'] - t['x']) < 2 and abs((t['y'] - prev['lasty']) - lh) < 3:
            prev['lines'].append(t['text']); prev['lasty'] = t['y']; prev['right'] = max(prev['right'], t['x'] + t['w'])
            continue
        # a full stop left alone after a run in another style joins that run
        if prev and re.fullmatch(r'[\.,;:!?]+', t['text']) and abs(prev['lasty'] - t['y']) < 6:
            prev['lines'][-1] += t['text']; prev['right'] = max(prev['right'], t['x'] + t['w'])
            continue
        blocks.append({'key': key, 'x': t['x'], 'y0': t['y'], 'lasty': t['y'], 'h0': t['h'], 'right': t['x'] + t['w'], 'lines': [t['text']], 't': t})
    return blocks


def build(name, v):
    m = json.load(open(f'{S}/meas/{name}-{v}.json'))
    W = 1440 if v == 'd' else 390
    B = 560 if v == 'd' else 255
    pre = f'{name}_{v}'
    out = []
    # ---- the ground: a bleed each side, the composition's own art over them
    art = lambda part: f'{BASE}{name}-{v}-{part}.webp'
    # the composition's own art first: it is the image the page fetches ahead
    out.append(base(f'{pre}_fondo', 'image', 0, 0, W, 780, v, imageUrl=art('center'), fit='cover', focalPointX=0.5, focalPointY=0.5, radius=0, altText=ART_ALT.get(name, ''), locked=True))
    out.append(base(f'{pre}_fondo_izq', 'image', -B, 0, B, 780, v, imageUrl=art('left'), fit='cover', focalPointX=0.5, focalPointY=0.5, radius=0, altText='', locked=True))
    out.append(base(f'{pre}_fondo_der', 'image', W, 0, B, 780, v, imageUrl=art('right'), fit='cover', focalPointX=0.5, focalPointY=0.5, radius=0, altText='', locked=True))
    for layer in out:
        layer['locked'] = True
    # ---- accents
    n = {}
    def num(k):
        n[k] = n.get(k, 0) + 1
        return f'{pre}_{k}' + (f'_{n[k]}' if n[k] > 1 else '')
    for s in m['shapes']:
        if s['kind'] == 'sign':
            out.append(base(num('cartel_fondo'), 'shape', s['x'], s['y'], s['w'], s['h'], v, shape='rectangle', fillColor='#0A6B47', borderColor='#DBFFFFFF', borderWidth=1.5, radius=5))
        elif s['kind'] == 'bar':
            out.append(base(num('barra'), 'shape', s['x'], s['y'], s['w'], s['h'], v, shape='rectangle', fillColor=s['fill'], borderColor=s['fill'], borderWidth=0, radius=0))
        elif s['kind'] == 'marker':
            out.append(base(num('destacador'), 'shape', s['x'], s['y'], s['w'], s['h'], v, shape='rectangle', fillColor=s['fill'], borderColor=s['fill'], borderWidth=0, radius=0))
        elif s['kind'] == 'rule':
            out.append(base(num('linea'), 'shape', s['x'], s['y'], s['w'], 1, v, shape='rectangle', fillColor=s['fill'], borderColor=s['fill'], borderWidth=0, radius=0))
    # ---- product photos and marks
    for im in m['images']:
        file, label = IMG[im['src'].split('/')[-1]]
        out.append(base(num(label), 'image', im['x'], im['y'], im['w'], im['h'], v, rotation=im['rotation'], imageUrl=BASE + file.format(v=v),
                        fit='contain', focalPointX=0.5, focalPointY=0.5, radius=0, altText=im['alt'] or ''))
    # ---- text
    for b in merge_texts(m['texts']):
        t = b['t']
        cls = t['container'].split()[0]
        lh = t['fontSize'] * t['lineHeight']
        lines = b['lines']
        y = b['y0'] - (lh - b['h0']) / 2
        h = lh * len(lines)
        role = NAMES.get(cls, cls)
        if t['parent'] in ('k', 'from', 'b', 'hl') or (cls == 'tag' and t['parent'] == 'b'):
            role += {'k': '_linea', 'from': '_desde', 'b': '_fuerte', 'hl': '_fuerte'}[t['parent'] if t['parent'] in ('k', 'from', 'hl') else 'b']
        heading = t['heading']
        weight = t['weight']
        layer = base(num(role), 'text', b['x'], y, b['right'] - b['x'] + 6, h, v,
                     text='\n'.join(lines), fontRole='heading' if heading else 'body', fontSize=R1(t['fontSize']),
                     fontWeight='w700' if weight >= 700 else 'w600' if weight >= 600 else 'w500' if weight >= 500 else 'w400',
                     color=t['color'], align='left', letterSpacing=round(t['letterSpacing'], 2), lineHeight=round(t['lineHeight'], 3),
                     uppercase=bool(t['uppercase']))
        if t['skew']:
            layer['skew'] = t['skew']
        if cls == 'ttl' and t['parent'] != 'k':
            layer['heading'] = True
        out.append(layer)
    # ---- buttons and links
    for bt in m['buttons']:
        href = BY_LABEL.get((name, bt['label'])) or DEST.get(bt['href'])
        assert href, (name, bt['label'], bt['href'])
        if bt['kind'] == 'button':
            layer = base(num('boton'), 'button', bt['x'], bt['y'], bt['w'], bt['h'], v, label=bt['label'], link=href, style='filled',
                         actions=[{'to': href, 'type': 'navigate', 'label': bt['label'], 'variant': 'filled'}], inheritTheme=False,
                         bgColor=bt['bg'], fgColor=bt['fg'], radius=bt['radius'], shadow=False, fontSize=bt['fontSize'], uppercase=False, letterSpacing=0)
        else:
            tall = 32 if v == 'd' else 40
            grow = max(0, tall - bt['h'])
            layer = base(num('enlace'), 'button', bt['x'], bt['y'] - grow / 2, bt['w'] + 6, bt['h'] + grow, v, label=bt['label'], link=href, style='text',
                         actions=[{'to': href, 'type': 'navigate', 'label': bt['label'], 'variant': 'text'}], inheritTheme=False,
                         bgColor=bt['fg'], fgColor=bt['fg'], radius=4, shadow=False, fontSize=bt['fontSize'], uppercase=False, letterSpacing=0,
                         fontWeight='w500', underline=True)
        if bt['icon']:
            layer['icon'] = bt['icon']
        out.append(layer)
    return out


slides = []
for name, title, subtitle, ground, tone_d, tone_m, plate in SLIDES:
    elements = build(name, 'd') + build(name, 'm')
    ids = [e['id'] for e in elements]
    assert len(ids) == len(set(ids)), [i for i in ids if ids.count(i) > 1]
    main = next(e for e in elements if e['type'] == 'button' and e['style'] == 'filled')
    over = {'designWidth': 390}
    if tone_m != tone_d:
        over['navTone'] = tone_m
    slide = {
        'title': title, 'subtitle': subtitle,
        'actions': [{'to': main['link'], 'type': 'navigate', 'label': main['label'], 'variant': 'filled'}],
        'ctaLink': main['link'], 'ctaText': main['label'], 'buttonLink': main['link'], 'buttonText': main['label'], 'actionVariant': 'filled',
        'imageUrl': '', 'altText': '', 'videoUrl': '', 'videoFileUrl': '', 'showOverlay': False, 'overlayOpacity': 0,
        'style': {'backgroundType': 'solid', 'backgroundColor': ground},
        'campaignKey': f'inicio-2026-11-{name}',
        'useComposition': True, 'canvasResponsiveVersion': 2, 'designWidth': 1440, 'designHeight': 750,
        'constrainElementsToSafeArea': False, 'scaleText': True, 'navTone': tone_d, 'navPlate': plate,
        'responsive': {'mobile': dict(over), 'tablet': dict(over), 'version': 2},
        'elements': elements,
    }
    slides.append(slide)

block = {
    'slides': slides, 'autoPlay': True, 'animation': 'fade', 'showArrows': False, 'showIndicators': True,
    'indicatorStyle': 'bars', 'indicatorBottomCompact': 88, 'scaleHeight': True,
    'accessibleTitle': 'Tienda y taller de bicicletas en Viña del Mar',
    'blockHeight': 750, 'spacingAfter': 36, 'schemaVersion': 1, 'intervalSeconds': 8, 'transitionDuration': 1600, 'animationDurationMs': 1600,
}
json.dump(block, open(OUT, 'w'), ensure_ascii=False, indent=1)
print(len(slides), 'slides;', [len(s['elements']) for s in slides], 'layers;', len(json.dumps(block, ensure_ascii=False)), 'bytes')
