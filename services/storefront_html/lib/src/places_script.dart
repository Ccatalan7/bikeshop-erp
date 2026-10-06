/// Google Places on the HTML pages, through the store's
/// `google-places-proxy` (the key stays in Supabase), as Flutter's
/// `AddressAutocompleteService` asks it: `status`, `autocomplete` and
/// `details`, one session token per pick. [resolve] reads a place into the
/// address fields the way `resolvePlace` does; the checkout and the
/// portal's address form share it (`window.vinabikePlaces`).
const placesScript = r'''
(function () {
  var body = document.body.dataset;
  var sbUrl = (body.sbUrl || '').replace(/\/+$/, ''), sbKey = body.sbKey || '', tenant = body.tenant || '';
  function call(payload) {
    return fetch(sbUrl + '/functions/v1/google-places-proxy', {
      method: 'POST',
      headers: { apikey: sbKey, authorization: 'Bearer ' + sbKey, 'content-type': 'application/json' },
      body: JSON.stringify(Object.assign({ tenantId: tenant }, payload))
    }).then(function (r) { if (!r.ok) throw new Error('http ' + r.status); return r.json(); });
  }
  function token() {
    if (window.crypto && crypto.randomUUID) return crypto.randomUUID();
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function (c) {
      var r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3 | 8)).toString(16);
    });
  }
  function component(components, type) {
    for (var i = 0; i < components.length; i++) if ((components[i].types || []).indexOf(type) >= 0) return components[i].long_name == null ? null : String(components[i].long_name);
    return null;
  }
  // `AddressAutocompleteService.resolvePlace`.
  function resolve(result) {
    var c = result.address_components || [];
    var locality = component(c, 'locality'), province = component(c, 'administrative_area_level_2');
    var region = component(c, 'administrative_area_level_1') || '';
    var comuna = component(c, 'administrative_area_level_3') || locality || component(c, 'sublocality_level_1') || component(c, 'sublocality') || '';
    var city = locality || (comuna ? comuna : null) || (province !== region ? province : null) || region;
    var loc = result.geometry && result.geometry.location;
    return {
      formatted: result.formatted_address || '',
      street: component(c, 'route') || '', number: component(c, 'street_number'),
      apartment: component(c, 'subpremise') || component(c, 'premise'), comuna: comuna, city: city, region: region,
      postal: component(c, 'postal_code'), lat: loc && loc.lat, lng: loc && loc.lng
    };
  }
  var enabled = null;
  window.vinabikePlaces = {
    token: token,
    resolve: resolve,
    // Whether the store has Places on (`initialize`): asked once per page.
    status: function () {
      if (!enabled) enabled = call({ action: 'status' }).then(function (r) { return !!(r && r.enabled === true); }, function () { return false; });
      return enabled;
    },
    suggest: function (input, session) {
      return call({ action: 'autocomplete', input: input, sessionToken: session }).then(function (r) {
        return r && r.status === 'OK' && Array.isArray(r.predictions) ? r.predictions.map(function (p) { return { placeId: p.place_id, description: p.description }; }) : [];
      });
    },
    details: function (placeId, session) {
      return call({ action: 'details', placeId: placeId, sessionToken: session }).then(function (r) {
        return r && r.status === 'OK' && r.result ? resolve(r.result) : null;
      });
    }
  };
})();
''';
