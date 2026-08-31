(function () {
  'use strict';

  // Sonda de portal de proveedor.
  //
  // Modos, y el primero existe porque nadie puede escribir la
  // configuración de un portal sin haberlo visto por dentro:
  //
  //   discover  reconoce la página: si la sesión está viva, qué formularios de
  //             búsqueda hay y con qué nombre, y qué se parece a un precio o a
  //             un stock. Su salida es lo que permite escribir la sonda.
  //   probe     busca UN código y devuelve lo que encontró, más la evidencia
  //             cruda con la que se lo puede auditar o corregir después.
  //   search    lee las filas de catálogo que la página ya está mostrando. El
  //             filtro lo hizo el portal en la URL; acá no se filtra nada.
  //   page      lo mismo, pero para UNA página de una enumeración: además de
  //             las filas devuelve con qué terminarla —cuántas filas trajo,
  //             si alguna tabla existía y el esquema no calzó, y si el texto
  //             llegó mal decodificado—.
  //   taxonomy  lee los selectores nativos de clasificación tal como están en
  //             el documento. No sabe qué categoría del ERP le corresponde.
  //
  // Nunca decide. Devuelve hechos y deja que el ERP los interprete: distinguir
  // «no hay stock» de «se cayó la sesión» es una regla de negocio, y en esta
  // página no hay contexto para tomarla.

  const VERSION = '0.5.0';
  const MAX_TEXT = 4000;
  const MAX_ITEMS = 12;
  const MAX_SEARCH_RESULTS = 40;
  // Una enumeración por taxonomía trae varias páginas y varios nodos, así que
  // el tope de filas deja de ser una constante del archivo: lo pone quien
  // llama, que es el único que conoce su presupuesto y el techo del recibo.
  const MAX_PAGE_ROWS = 400;

  function boundedRowLimit(value, fallback) {
    const parsed = Number(value);
    if (!Number.isFinite(parsed) || parsed < 1) return fallback;
    return Math.min(Math.floor(parsed), MAX_PAGE_ROWS);
  }

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
        name: form.getAttribute('name') || '',
        id: form.id || '',
        action: form.getAttribute('action') || '',
        method: (form.getAttribute('method') || 'get').toLowerCase(),
        onsubmit: form.getAttribute('onsubmit') || '',
        near: text(form).slice(0, 240),
        fields: [...form.querySelectorAll('input,select,button')]
          .filter((field) => field.type !== 'password')
          .map((field) => ({
            name: field.name || '',
            type: field.type || '',
            placeholder: field.placeholder || '',
            onchange: field.getAttribute('onchange') || '',
            // Sólo se leen valores de navegación conocidos. Tokens y campos
            // de sesión no forman parte del reconocimiento ni de su log.
            value: field.type === 'hidden' && [
              'url', 'url1', 'folio', 'paginaabsoluta',
            ].includes(field.name || '')
              ? String(field.value || '').slice(0, 120)
              : undefined,
            options: field.tagName === 'SELECT'
              ? [...field.options].map((option) => ({
                value: String(option.value || '').slice(0, 120),
                text: text(option).slice(0, 120),
              })).slice(0, 160)
              : undefined,
          }))
          .slice(0, 16),
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
    // RBX no redirige al login cuando pierde la sesión. Conserva el catálogo,
    // deja el rótulo `Sesion:` vacío y recién después rompe la consulta SQL.
    // Detectarlo en cada marco, antes de concatenar sus textos, evita que el
    // contenido del marco siguiente parezca falsamente el nombre de sesión.
    const hasEmptySessionLabel = list.some((doc) => {
      const body = text(doc.body).trim();
      return /(?:^|\s)sesi[oó]n\s*:\s*$/i.test(body);
    });
    const haystack = list.map((doc) => text(doc.body)).join(' ').toLowerCase();
    const words = [
      'iniciar sesión', 'ingresar al catálogo', 'acceso clientes',
      'tu sesión expiró', 'debe iniciar sesión', 'login',
    ].filter((word) => haystack.includes(word));
    return {
      hasPasswordField: hasPassword,
      hasEmptySessionLabel,
      phrases: words,
    };
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

  function normalized(value) {
    return String(value || '')
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .toLowerCase()
      .replace(/\s+/g, ' ')
      .trim();
  }

  // Extrae filas del catálogo según el esquema del adaptador. La sonda no
  // conoce los encabezados de ningún proveedor: si no están configuradas las
  // columnas de código y nombre, se rehúsa a tratar tablas de navegación como
  // productos.
  function catalogScan(doc, schema, maxRows) {
    const limit = boundedRowLimit(maxRows, MAX_SEARCH_RESULTS);
    const columns = schema && schema.columns ? schema.columns : {};
    const factColumns = schema && schema.factColumns
      ? schema.factColumns
      : {};
    const aliasesFor = (role) => Array.isArray(columns[role])
      ? columns[role].map(normalized).filter(Boolean)
      : [];
    const rows = [];
    // **Una tabla que existe y no calza NO es una página vacía.** Sin este
    // conteo, un encabezado renombrado —o mal decodificado— se lee igual que
    // «este nodo se acabó», y la enumeración terminaría temprano jurando que
    // vio todo. Se cuentan las tablas candidatas y si alguna calzó el esquema.
    let tablesSeen = 0;
    let schemaMatched = false;
    for (const table of [...(doc || document).querySelectorAll('table')]) {
      let headerCells = [...table.querySelectorAll('thead th, thead td')];
      if (!headerCells.length) {
        const firstRow = table.querySelector('tr');
        headerCells = firstRow ? [...firstRow.children] : [];
      }
      const headers = headerCells.map((cell) => normalized(text(cell)));
      const indexOf = (wanted) => headers.findIndex((header) =>
        wanted.some((word) => header === word || header.includes(word)));
      const codeAliases = aliasesFor('code');
      const nameAliases = aliasesFor('name');
      if (!codeAliases.length || !nameAliases.length) continue;
      if (headers.length > 1) tablesSeen++;
      const codeIndex = indexOf(codeAliases);
      const nameIndex = indexOf(nameAliases);
      if (codeIndex < 0 || nameIndex < 0) continue;
      schemaMatched = true;
      const brandIndex = indexOf(aliasesFor('brand'));
      const originIndex = indexOf(aliasesFor('origin'));
      const priceIndex = indexOf(aliasesFor('price'));
      const factIndexes = Object.entries(factColumns).map(([field, aliases]) => ({
        field,
        index: indexOf(Array.isArray(aliases)
          ? aliases.map(normalized).filter(Boolean)
          : []),
      })).filter((entry) => entry.index >= 0);

      for (const row of [...table.querySelectorAll('tr')]) {
        if (row.closest('thead')) continue;
        const cells = [...row.children].filter((cell) =>
          cell.tagName === 'TD' || cell.tagName === 'TH');
        if (cells.length <= Math.max(codeIndex, nameIndex)) continue;
        const code = text(cells[codeIndex]);
        const name = text(cells[nameIndex]);
        if (!code || !name || codeAliases.includes(normalized(code))) continue;
        const priceText = priceIndex >= 0 && cells[priceIndex]
          ? text(cells[priceIndex])
          : '';
        const priceDigits = priceText.replace(/[^0-9]/g, '');
        const technicalFacts = {};
        for (const fact of factIndexes) {
          if (!cells[fact.index]) continue;
          const value = text(cells[fact.index]).slice(0, 160);
          if (value) technicalFacts[fact.field] = value;
        }
        rows.push({
          code: code.slice(0, 80),
          name: name.slice(0, 240),
          brand: brandIndex >= 0 && cells[brandIndex]
            ? text(cells[brandIndex]).slice(0, 120)
            : '',
          origin: originIndex >= 0 && cells[originIndex]
            ? text(cells[originIndex]).slice(0, 120)
            : '',
          priceNet: priceDigits ? Number(priceDigits) : null,
          rowText: text(row).slice(0, 500),
          technicalFacts,
        });
        if (rows.length >= limit) {
          return { rows, tablesSeen, schemaMatched, truncated: true };
        }
      }
    }
    return { rows, tablesSeen, schemaMatched, truncated: false };
  }

  // **Mojibake es un hecho observable, no una teoría.** Un IIS que sirve
  // `text/html` sin `charset` deja que el navegador adivine; cuando adivina
  // UTF-8 sobre bytes Windows-1252, «Código» llega como «CÃ³digo» y NINGÚN
  // alias de columna calza. Sin esta señal, esa página se reporta idéntica a
  // un nodo que se acabó, y la enumeración cierra jurando cobertura completa.
  // Escapes explicitos: este archivo viaja como asset y se inyecta como
  // texto; un literal no-ASCII aca depende de que nadie lo recodifique.
  const MOJIBAKE = /[\u00c3\u00c2][\u0080-\u00bf]|\ufffd/;

  function looksMisdecoded(body) {
    return MOJIBAKE.test(String(body || ''));
  }

  function collectRows(docs, schema, maxRows) {
    const limit = boundedRowLimit(maxRows, MAX_SEARCH_RESULTS);
    const seen = new Set();
    const results = [];
    let tablesSeen = 0;
    let schemaMatched = false;
    let truncated = false;
    for (const doc of docs) {
      let scan;
      try {
        scan = catalogScan(doc, schema, limit - results.length);
      } catch (_) {
        scan = { rows: [], tablesSeen: 0, schemaMatched: false };
      }
      tablesSeen += scan.tablesSeen || 0;
      schemaMatched = schemaMatched || scan.schemaMatched === true;
      for (const row of scan.rows) {
        const key = `${normalized(row.code)}|${normalized(row.name)}`;
        if (seen.has(key)) continue;
        seen.add(key);
        results.push(row);
        if (results.length >= limit) {
          truncated = true;
          break;
        }
      }
      if (results.length >= limit) break;
    }
    return { results, tablesSeen, schemaMatched, truncated };
  }

  function search(query, schema, maxRows) {
    const wanted = String(query || '').trim();
    const docs = documents();
    const body = docs.map((doc) => text(doc.body)).filter(Boolean).join(' ');
    const { results } = collectRows(docs, schema, maxRows);
    return {
      mode: 'search',
      version: VERSION,
      url: String(location.href),
      title: document.title || '',
      query: wanted,
      frameCount: docs.length,
      session: looksLoggedOut(docs),
      results,
      noResults: (schema && Array.isArray(schema.noResultPhrases)
        ? schema.noResultPhrases
        : []).some((phrase) => normalized(body).includes(normalized(phrase))),
      // Metadatos estructurales, sin cookies ni valores de campos. Un portal
      // legacy puede cambiar el formulario o dejar de aceptar un deep link;
      // estos datos permiten demostrar esa deriva sin guardar credenciales.
      frameUrls: docs.map((doc) => {
        try {
          return String(doc.location.href).slice(0, 300);
        } catch (_) {
          return '';
        }
      }),
      searchForms: docs.flatMap((doc, frame) => {
        try {
          return searchForms(doc).map((form) => ({ ...form, frame }));
        } catch (_) {
          return [];
        }
      }).slice(0, 12),
      catalogLinks: docs.flatMap((doc, frame) => {
        try {
          return [...doc.querySelectorAll('a')]
            .filter((link) => /catalog|product|producto|buscar|palabra|codigo/i
              .test(`${link.getAttribute('href') || ''} ${text(link)}`))
            .map((link) => ({
              frame,
              text: text(link).slice(0, 80),
              href: String(link.href || '').slice(0, 300),
            }));
        } catch (_) {
          return [];
        }
      }).slice(0, 20),
      bodySample: body.slice(0, MAX_TEXT),
    };
  }

  // UNA página de una enumeración por taxonomía.
  //
  // Devuelve las filas y, sobre todo, con qué decidir si esa enumeración
  // terminó. La sonda no cuenta páginas ni sabe qué nodo pidió el ERP: informa
  // lo que esta página tiene, y quien enumera decide. El enlace «Siguiente» se
  // reporta pero NO se recomienda: RBX lo dibuja también en una página vacía.
  function page(schema, maxRows) {
    const docs = documents();
    const body = docs.map((doc) => text(doc.body)).filter(Boolean).join(' ');
    const scan = collectRows(docs, schema, maxRows);
    return {
      mode: 'page',
      version: VERSION,
      url: String(location.href),
      title: document.title || '',
      frameCount: docs.length,
      session: looksLoggedOut(docs),
      results: scan.results,
      rowCount: scan.results.length,
      // Tres hechos distintos que antes se confundían en «0 filas»:
      tablesSeen: scan.tablesSeen,
      schemaMatched: scan.schemaMatched,
      misdecoded: looksMisdecoded(body),
      truncated: scan.truncated,
      noResults: (schema && Array.isArray(schema.noResultPhrases)
        ? schema.noResultPhrases
        : []).some((phrase) => normalized(body).includes(normalized(phrase))),
      frameUrls: docs.map((doc) => {
        try {
          return String(doc.location.href).slice(0, 300);
        } catch (_) {
          return '';
        }
      }),
      bodySample: body.slice(0, MAX_TEXT),
    };
  }

  // Lee los selectores de clasificación tal como están AHORA en el documento.
  //
  // No los recorre ni los elige: eso lo decide el ERP, que es el único que
  // conoce la familia canónica pedida. Devolver `value` y texto de cada opción
  // es lo que permite que la taxonomía sea dato descubierto y no una tabla
  // escrita a mano por proveedor.
  function taxonomy(fieldNames) {
    const wanted = (Array.isArray(fieldNames) ? fieldNames : [])
      .map((name) => String(name || '').trim())
      .filter(Boolean);
    if (!wanted.length) return { mode: 'taxonomy', version: VERSION, fields: [] };
    const docs = documents();
    const fields = [];
    for (const name of wanted) {
      for (let frame = 0; frame < docs.length; frame++) {
        let select;
        try {
          select = [...docs[frame].querySelectorAll('select')]
            .find((field) => field.name === name);
        } catch (_) {
          select = null;
        }
        if (!select) continue;
        fields.push({
          field: name,
          frame,
          selected: String(select.value || '').slice(0, 120),
          options: [...select.options]
            .map((option) => ({
              value: String(option.value || '').slice(0, 120),
              text: text(option).slice(0, 160),
            }))
            .filter((option) => option.value && option.text)
            .slice(0, 400),
        });
        break;
      }
    }
    return {
      mode: 'taxonomy',
      version: VERSION,
      url: String(location.href),
      frameCount: docs.length,
      session: looksLoggedOut(docs),
      misdecoded: looksMisdecoded(
        docs.map((doc) => text(doc.body)).filter(Boolean).join(' '),
      ),
      fields,
    };
  }

  // Navega selectores nativos del portal. Se usa sólo cuando el proveedor
  // publica una taxonomía estable y más precisa que su buscador por palabra.
  // No conoce categorías del ERP ni decide cuál elegir: recibe el texto ya
  // resuelto por el adaptador del proveedor y confirma qué opción seleccionó.
  function selectOption(fieldName, optionText) {
    const wanted = normalized(optionText);
    const docs = documents();
    for (let frame = 0; frame < docs.length; frame++) {
      const doc = docs[frame];
      const select = [...doc.querySelectorAll('select')]
        .find((field) => field.name === fieldName);
      if (!select) continue;
      const option = [...select.options].find((candidate) => {
        const label = normalized(text(candidate));
        return label === wanted || label.includes(wanted);
      });
      if (!option) {
        return {
          ok: false,
          frame,
          fieldName,
          options: [...select.options]
            .map((candidate) => text(candidate).slice(0, 120))
            .filter(Boolean)
            .slice(0, 160),
        };
      }
      select.value = option.value;
      option.selected = true;
      select.dispatchEvent(new Event('input', { bubbles: true }));
      select.dispatchEvent(new Event('change', { bubbles: true }));
      const hasChangeHandler = !!(
        select.onchange || select.getAttribute('onchange')
      );
      if (!hasChangeHandler && select.form) select.form.submit();
      return {
        ok: true,
        frame,
        fieldName,
        value: String(option.value || '').slice(0, 120),
        text: text(option).slice(0, 120),
        submittedBy: hasChangeHandler ? 'change' : 'form',
      };
    }
    return { ok: false, fieldName, options: [] };
  }

  const globalScope = globalThis;
  globalScope.__vinabikeSupplierProbe = {
    discover,
    probe,
    search,
    page,
    taxonomy,
    selectOption,
    version: VERSION,
  };
  return { ready: true, version: VERSION };
})();
