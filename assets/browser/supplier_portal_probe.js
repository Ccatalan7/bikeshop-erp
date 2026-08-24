(function () {
  'use strict';

  // Sonda de portal de proveedor.
  //
  // Dos modos, y el primero existe porque nadie puede escribir la
  // configuración de un portal sin haberlo visto por dentro:
  //
  //   discover  reconoce la página: si la sesión está viva, qué formularios de
  //             búsqueda hay y con qué nombre, y qué se parece a un precio o a
  //             un stock. Su salida es lo que permite escribir la sonda.
  //   probe     busca UN código y devuelve lo que encontró, más la evidencia
  //             cruda con la que se lo puede auditar o corregir después.
  //
  // Nunca decide. Devuelve hechos y deja que el ERP los interprete: distinguir
  // «no hay stock» de «se cayó la sesión» es una regla de negocio, y en esta
  // página no hay contexto para tomarla.

  const VERSION = '0.1.0';
  const MAX_TEXT = 4000;
  const MAX_ITEMS = 12;

  // **Un portal viejo vive en marcos.** El catálogo de RBX es un frameset:
  // el documento de arriba no tiene ni texto ni formularios, así que leer sólo
  // `document.body` devolvía un informe vacío con la página llena a la vista.
  // Lo encontró el propio reconocimiento en su primera corrida.
  //
  // Se recorren el documento y todos los marcos del MISMO origen. Los de otro
  // origen el navegador no los deja leer, y eso está bien: no son del portal.
  function documents() {
    const found = [document];
    const walk = (win, depth) => {
      if (depth > 3) return;
      let frames;
      try {
        frames = win.frames;
      } catch (_) {
        return;
      }
      for (let index = 0; index < frames.length; index++) {
        let doc;
        try {
          doc = frames[index].document;
        } catch (_) {
          continue; // otro origen: no es asunto nuestro
        }
        if (!doc || found.includes(doc)) continue;
        found.push(doc);
        walk(frames[index], depth + 1);
      }
    };
    walk(window, 0);
    return found;
  }

  // **El texto de una página NO es `textContent`.**
  //
  // `textContent` incluye el código fuente de los `<script>` inline. El
  // catálogo de RBX imprime el precio con un script en la propia celda, así que
  // la página se leía como:
  //
  //     ... CHINA $document.write(formatear_numero("2240",0));2.240 1
  //
  // El `$` quedaba pegado a «document» y ningún patrón de precio calzaba: las
  // doce consultas del primer chequeo real salieron «ilegible» con las páginas
  // perfectamente dibujadas. Se ve en la evidencia guardada, no en la pantalla.
  const HIDDEN_TAGS = new Set(['SCRIPT', 'STYLE', 'NOSCRIPT', 'TEMPLATE']);

  function text(node) {
    if (!node) return '';
    if (node.nodeType === 3) {
      return String(node.nodeValue || '').replace(/\s+/g, ' ').trim();
    }
    const doc = node.ownerDocument || document;
    let walker;
    try {
      walker = doc.createTreeWalker(node, NodeFilter.SHOW_TEXT, {
        acceptNode(candidate) {
          let parent = candidate.parentElement;
          while (parent) {
            if (HIDDEN_TAGS.has(parent.tagName)) return NodeFilter.FILTER_REJECT;
            parent = parent.parentElement;
          }
          return NodeFilter.FILTER_ACCEPT;
        },
      });
    } catch (_) {
      return String(node.textContent || '').replace(/\s+/g, ' ').trim();
    }
    const parts = [];
    let current = walker.nextNode();
    while (current) {
      const value = String(current.nodeValue || '').replace(/\s+/g, ' ').trim();
      if (value) parts.push(value);
      current = walker.nextNode();
    }
    return parts.join(' ');
  }

  function insideHiddenTag(node) {
    let parent = node && node.parentElement;
    while (parent) {
      if (HIDDEN_TAGS.has(parent.tagName)) return true;
      parent = parent.parentElement;
    }
    return false;
  }

  function visible(node) {
    if (!node || !node.getBoundingClientRect) return false;
    const box = node.getBoundingClientRect();
    return box.width > 0 && box.height > 0;
  }

  // Un precio chileno se escribe de varias formas y ninguna es un decimal
  // inglés: $12.990, 12.990, 12990. Se recogen CANDIDATOS, no se elige uno:
  // elegir sin saber la maqueta es adivinar.
  function priceCandidates(doc) {
    const found = [];
    const seen = new Set();
    const pattern = /\$\s?\d{1,3}(?:[.\s]\d{3})+|\$\s?\d{3,7}\b/g;
    const scope = (doc || document).body;
    if (!scope) return found;
    const walker = (doc || document).createTreeWalker(
      scope,
      NodeFilter.SHOW_TEXT,
      null,
    );
    let node = walker.nextNode();
    while (node && found.length < MAX_ITEMS) {
      const value = String(node.nodeValue || '');
      const matches = value.match(pattern);
      if (matches && !insideHiddenTag(node) && visible(node.parentElement)) {
        for (const match of matches) {
          const clean = match.replace(/\s+/g, '');
          if (seen.has(clean)) continue;
          seen.add(clean);
          found.push({
            value: clean,
            near: text(node.parentElement).slice(0, 120),
          });
          if (found.length >= MAX_ITEMS) break;
        }
      }
      node = walker.nextNode();
    }
    return found;
  }

  // Las palabras con las que un portal chileno dice si hay o no hay. Se
  // reportan las que APARECEN; no se concluye nada con ellas acá.
  const STOCK_WORDS = [
    'sin stock', 'agotado', 'no disponible', 'sin existencias',
    'stock', 'disponible', 'disponibilidad', 'en bodega', 'unidades',
  ];

  function stockSignals(doc) {
    const haystack = text((doc || document).body).toLowerCase();
    return STOCK_WORDS.filter((word) => haystack.includes(word));
  }

  function searchForms(doc) {
    return [...(doc || document).querySelectorAll('form')]
      .map((form) => ({
        action: form.getAttribute('action') || '',
        method: (form.getAttribute('method') || 'get').toLowerCase(),
        fields: [...form.querySelectorAll('input,select')]
          .filter((field) => field.type !== 'hidden')
          .map((field) => ({
            name: field.name || '',
            type: field.type || '',
            placeholder: field.placeholder || '',
          }))
          .slice(0, 8),
      }))
      // Un formulario de login no es un buscador, y confundirlos hace que la
      // sonda "busque" mandando credenciales vacías.
      .filter((form) => !form.fields.some((field) => field.type === 'password'))
      .slice(0, 6);
  }

  function looksLoggedOut(docs) {
    const list = docs || [document];
    const hasPassword = list.some(
      (doc) => !!doc.querySelector('input[type="password"]'),
    );
    const haystack = list.map((doc) => text(doc.body)).join(' ').toLowerCase();
    const words = [
      'iniciar sesión', 'ingresar al catálogo', 'acceso clientes',
      'tu sesión expiró', 'debe iniciar sesión', 'login',
    ].filter((word) => haystack.includes(word));
    return { hasPasswordField: hasPassword, phrases: words };
  }

  function discover() {
    const docs = documents();
    const merge = (fn) => docs.flatMap((doc, index) => {
      try {
        return fn(doc).map((item) => ({ ...item, frame: index }));
      } catch (_) {
        return [];
      }
    }).slice(0, MAX_ITEMS * 2);
    return {
      mode: 'discover',
      version: VERSION,
      url: String(location.href),
      title: document.title || '',
      frameCount: docs.length,
      // La URL de cada marco: en un frameset es lo que dice DÓNDE está de
      // verdad el buscador y dónde los resultados.
      frameUrls: docs.map((doc) => {
        try {
          return String(doc.location.href).slice(0, 200);
        } catch (_) {
          return '';
        }
      }),
      session: looksLoggedOut(docs),
      searchForms: merge((doc) => searchForms(doc)),
      // Los enlaces que suenan a catálogo: en varios portales el buscador no
      // está en la portada sino un nivel adentro.
      catalogLinks: docs.flatMap((doc) => [...doc.querySelectorAll('a')])
        .filter((link) => /catalog|product|producto|tienda|buscar|search/i
          .test(`${link.getAttribute('href') || ''} ${text(link)}`))
        .map((link) => ({ text: text(link).slice(0, 40), href: link.href }))
        .slice(0, 10),
      priceCandidates: merge((doc) => priceCandidates(doc)),
      stockSignals: [...new Set(docs.flatMap((doc) => stockSignals(doc)))],
      bodySample: docs.map((doc) => text(doc.body))
        .filter(Boolean).join(' ⟦marco⟧ ').slice(0, MAX_TEXT),
    };
  }

  function probe(code) {
    const wanted = String(code || '').trim();
    const docs = documents();
    const body = docs.map((doc) => text(doc.body)).filter(Boolean).join(' ');
    // La coincidencia del código se busca como palabra, no como trozo: «1128»
    // dentro de «11285» respondería por un producto que no es.
    const codeSeen = wanted
      ? new RegExp(`(^|[^0-9A-Za-z])${wanted.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}([^0-9A-Za-z]|$)`)
        .test(body)
      : false;
    return {
      mode: 'probe',
      version: VERSION,
      url: String(location.href),
      title: document.title || '',
      code: wanted,
      codeSeen,
      frameCount: docs.length,
      session: looksLoggedOut(docs),
      priceCandidates: docs.flatMap((doc) => {
        try {
          return priceCandidates(doc);
        } catch (_) {
          return [];
        }
      }).slice(0, MAX_ITEMS),
      stockSignals: [...new Set(docs.flatMap((doc) => stockSignals(doc)))],
      bodySample: body.slice(0, MAX_TEXT),
    };
  }

  const globalScope = globalThis;
  globalScope.__vinabikeSupplierProbe = { discover, probe, version: VERSION };
  return { ready: true, version: VERSION };
})();
