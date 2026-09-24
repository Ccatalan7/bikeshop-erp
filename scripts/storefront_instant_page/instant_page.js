// Página instantánea (docs/architecture/storefront-instant-page.md).
// Una ruta generada trae su ficha o categoría en #instant-page-template:
// se muestra con el primer paint, mientras bajan el motor y el programa
// de la tienda, y la tienda la retira con release() cuando su propia
// página ya está dibujada.
//
// El generador de snapshots pega este script justo después de la plantilla
// y antes del splash (#app-shell todavía no existe). No vive en
// web/index.html: scripts/sync_seo_index.sh reescribe ese archivo entero en
// CI. Sin este script (el resto de las rutas, el ERP) la tienda recibe
// `undefined` en window.vinabikeInstantPage y no hace nada.
(function () {
  var api = { active: false, release: function () {}, arm: function () {} };
  window.vinabikeInstantPage = api;
  var template = document.getElementById('instant-page-template');
  if (!template || !('content' in template)) return;

  var page = document.createElement('div');
  page.id = 'instant-page';
  page.appendChild(template.content.cloneNode(true));
  document.body.appendChild(page);
  var root = document.documentElement;
  root.classList.add('ip-covered');
  api.active = true;
  // Si el primer logo no carga, no queda una imagen rota: el encabezado
  // de la tienda prueba después el logo del tenant y el empaquetado.
  var logo = page.querySelector('.ip-logo');
  if (logo) {
    var hideLogo = function () { logo.style.visibility = 'hidden'; };
    logo.addEventListener('error', hideLogo);
    if (logo.complete && logo.naturalWidth === 0) hideLogo();
  }

  var released = false;
  var armed = false;
  api.release = function (reason) {
    if (released) return;
    released = true;
    api.active = false;
    window.vinabikeInstantPageReleased = {
      reason: String(reason || 'content'),
      at: Math.round(performance.now())
    };
    page.setAttribute('aria-hidden', 'true');
    page.classList.add('ip-leaving');
    // Retirada temprana (ficha retirada, error de arranque): vuelve el
    // splash con su logo mientras la tienda sigue cargando.
    root.classList.remove('ip-covered');
    setTimeout(function () {
      if (page.parentNode) page.parentNode.removeChild(page);
    }, 220);
  };
  // La tienda ya ocultó su splash. Si su página no avisa (un error, una
  // ruta que redirige a otra), la instantánea no queda encima.
  api.arm = function () {
    if (armed || released) return;
    armed = true;
    setTimeout(function () { api.release('timeout'); }, 8000);
  };

  // Frescura: el snapshot se generó en el último build. El precio nace
  // neutro (data-ip-state="pending") y sólo se muestra si una lectura
  // pública de los campos que lo deciden coincide con la firma del build.
  // Sin respuesta, con error o distinto, queda neutro hasta que la tienda
  // dibuja el vigente. Misma normalización que
  // seoInstantFreshnessSignature en el generador. El stock no se muestra:
  // lo descuentan reservas que la fila no refleja.
  var product = page.querySelector('[data-ip-sku][data-ip-sig]');
  var sku = product && product.getAttribute('data-ip-sku');
  var base = template.getAttribute('data-ip-api');
  var key = template.getAttribute('data-ip-key');
  var tenant = template.getAttribute('data-ip-tenant');
  if (!sku || !base || !key || !tenant || !window.fetch) return;
  var fields = ['website_price', 'price'];
  function norm(value) {
    if (value === null || value === undefined) return '';
    if (typeof value === 'boolean') return value ? 'true' : 'false';
    if (typeof value === 'number') return value.toFixed(2);
    var text = String(value).trim();
    return /^-?\d+(\.\d+)?$/.test(text) ? Number(text).toFixed(2) : text;
  }
  fetch(base + '/rest/v1/products?select=' + fields.join(',') +
      '&tenant_id=eq.' + encodeURIComponent(tenant) +
      '&sku=eq.' + encodeURIComponent(sku) + '&limit=1', {
    headers: { apikey: key, Authorization: 'Bearer ' + key },
    credentials: 'omit'
  }).then(function (response) {
    return response.ok ? response.json() : null;
  }).then(function (rows) {
    var row = rows && rows[0];
    // La lectura anónima sólo ve fichas activas, publicadas y en la web:
    // una respuesta vacía es una ficha retirada después del build, y su
    // nombre y foto no deben seguir a la vista.
    if (Array.isArray(rows) && !row) {
      api.release('withdrawn');
      return;
    }
    if (!row) return;
    var signature = fields.map(function (field) {
      return norm(row[field]);
    }).join('|');
    if (signature === product.getAttribute('data-ip-sig')) {
      product.setAttribute('data-ip-state', 'verified');
    }
  }).catch(function () {});
})();
