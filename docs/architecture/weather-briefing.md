# Clima del resumen diario: fuentes, precisión medida y contrato

El «Resumen diario» (campana de la barra derecha) tiene una pestaña «Clima»,
al lado de «Hoy» y «Período»: lo que hay ahora, una frase sobre la próxima
lluvia, un gráfico de las próximas 24 horas o de los próximos seis días y,
debajo, lo mismo fila por fila (hora o día, cielo, temperatura, lluvia y
viento). Este documento dice de dónde sale cada dato, por qué son dos fuentes
y qué reglas salieron de mirar datos reales. Nació el 2026-11-12.

**2026-11-13, corrección del dueño:** el clima partió como una sección dentro
del resumen y duró un día: «sepáralo… agrégalo como un tab más ahí arriba». En
su pestaña tiene el alto del panel para el detalle por hora. Mientras nadie
abre la pestaña no se pregunta nada al servidor. `BriefingWeatherSection`
conserva su forma compacta y plegable (`detailed: false`), que hoy ninguna
pantalla usa.

## Mapa de dueños

| Pieza | Dueño |
|---|---|
| Fuentes y su lectura (MET Norway, METAR) | `supabase/functions/_shared/weather_sources.ts` |
| Documento, caché, amarre pronóstico↔medición | `supabase/functions/_shared/weather_forecast.ts` |
| Entrada HTTP, sesión → tienda | `supabase/functions/weather-forecast/index.ts` (`verify_jwt = true`) |
| Lugares: buscar por nombre, zona horaria, clave del caché | `supabase/functions/_shared/weather_places.ts` |
| Caché, una fila por tienda y lugar | `public.weather_forecast_cache` (`20261112193700`, `20261113093000`; sólo `service_role`) |
| Lugares de cada persona | `public.weather_places` (`20261113093000`; sólo `service_role`) |
| Modelo y derivados (ahora, horas, días, sol) | `lib/shared/models/weather_forecast.dart` |
| La frase del día y los textos | `lib/shared/models/weather_outlook.dart` |
| Lectura desde la app | `lib/shared/services/weather_forecast_service.dart` |
| Amanecer y atardecer | `lib/shared/utils/solar_times.dart` |
| Dibujos del cielo, gráfico y sección | `lib/shared/widgets/weather/` |
| Encabezado común de las secciones del resumen | `lib/shared/widgets/briefing_section_header.dart` |

La app nunca habla con un proveedor: pide `weather-forecast` y dibuja el
documento que vuelve. Cambiar de fuente es desplegar la función, sin publicar
una app.

## Por qué dos fuentes

**Pronóstico: MET Norway, Locationforecast 2.0 `complete`.** Es el modelo
europeo (ECMWF) con licencia CC BY 4.0 y uso comercial permitido. Open-Meteo
quedó fuera porque su nivel gratuito es sólo para uso no comercial, y no hay
estación MOSMIX del servicio alemán cerca (la más próxima, Pudahuel, a 83 km).

**«Ahora»: el último METAR de un aeródromo cercano**, del Aviation Weather
Center de la NOAA (dominio público). Para Viña del Mar es SCVM (Concón, a
11,7 km).

La medición manda porque el pronóstico solo se equivoca en la costa, y se
midió. El 2026-11-12 se compararon cinco días de METAR de SCVM y SCRD contra
los modelos:

- El viento de MET Norway fue entre **2,4 y 3,8 veces** el medido.
- Su temperatura de la tarde quedó hasta **4 °C** arriba.
- De los modelos comparados por Open-Meteo, ICON fue el mejor en la costa
  (error medio de 0,93 °C); el IFS de 9 km quedó entre 1,3 y 3,1 °C arriba.

Por eso la función:

- Muestra en «ahora» la temperatura, el viento, la humedad y el cielo medidos,
  mientras el reporte tenga menos de 100 minutos (`MAX_OBSERVATION_AGE_MS`) y
  la estación esté a menos de 30 km (`MAX_STATION_KM`; la altura cuenta como
  distancia, 25 m por kilómetro).
- **Amarra el pronóstico a la medición**: corre la curva de temperatura por la
  diferencia medida y la suelta de a poco, `diferencia × exp(−(horas/8)²)`. Una
  exponencial simple soltaba demasiado pronto y la curva corregida bajaba y
  volvía a subir en la noche. Una diferencia de más de 8 °C no se corrige: es
  otra masa de aire o un sensor malo.
- **Calla el viento del pronóstico cuando la medición lo contradice** (el doble
  o la mitad, con piso de 2 m/s): `wind_trusted: false` y cada paso lleva
  `wind_speed: null`. La app no dibuja un viento que no tiene.

Para volver a medir: `https://aviationweather.gov/api/data/metar?ids=SCVM,SCRD&format=json&hours=120`
contra el `complete` de MET para las mismas horas.

## Lo que exige MET Norway

Sus condiciones (`api.met.no/doc/TermsOfService`, leídas el 2026-11-12) dan la
forma del caché:

- Una app o un navegador pasa por un servidor propio: por eso existe la
  función.
- Una petición no se repite antes de su `Expires`, y la repetición lleva
  `If-Modified-Since`: por eso hay una fila por tienda con `expires_at` y
  `source_last_modified`.
- Coordenadas con cuatro decimales como máximo.
- Cada petición dice quién pregunta: `User-Agent` con el sitio de la tienda
  (`WEATHER_USER_AGENT` lo cambia sin desplegar).
- Atribución: el documento trae `source.credits` y la sección los muestra como
  enlaces.

## Caché y refresco

- Una fila por tienda en `weather_forecast_cache`, con lo último leído
  (`payload = {schema, series, observation}`).
- Vigencia: el `Expires` del proveedor, acotado entre 5 minutos y 3 horas;
  30 minutos si no viene.
- **Un solo refresco a la vez**: quien encuentra la fila vencida la reclama con
  una actualización condicional de `refresh_claimed_at`. Quien pierde recibe lo
  guardado y la indicación de volver en 45 s. Un reclamo de más de 30 s era de
  un llamador que murió.
- Si el proveedor falla y hay algo guardado, se entrega con `stale: true` y
  nadie vuelve a preguntar por 5 minutos. Si no hay nada guardado, 502 con
  `status: "unavailable"`.
- Sin coordenadas, 200 con `status: "location_missing"`: no es un error.

En la app, `WeatherForecastService` guarda la respuesta por persona con sesión
y vuelve a preguntar sólo después de `expires_at`, y sólo mientras alguien
mira: la sección llama `ensureFresh()` al montarse y en cada minuto del reloj
del resumen. Otra cuenta que entra en el mismo equipo nunca ve el clima de la
anterior.

## Más lugares que el local (2026-11-13)

El dueño pidió poder agregar otros («para poder agregar Seattle también»).
Cada persona tiene su lista, hasta ocho, en `weather_places`; el local va
siempre primero y no se quita. En la pestaña son pestañas de texto junto al
título, y «+» abre un buscador en el mismo sitio (nada flotante: ver «Elegir
no abre un bloque flotante» en `.github/GUI_DESIGN_PRINCIPLES.md`). El equipo
recuerda cuál quedó elegido.

- **La función es la única puerta.** Cuerpo `{}` o
  `{action: "forecast", place_id?}` para el pronóstico;
  `{action: "search", query}`; `{action: "add_place", name, region, latitude,
  longitude}`; `{action: "remove_place", place_id}`. Toda respuesta de
  pronóstico trae `places` (la lista de la persona) y `shop_place` (el nombre
  del local), así la pestaña se arma con una sola llamada.
- **Un pronóstico guardado por lugar.** La clave del caché es `shop` para el
  local y `latitud,longitud` con cuatro decimales para lo demás: el mismo
  lugar agregado por dos personas de una tienda se pregunta una vez.
- **Cada lugar en su reloj.** La zona sale de las coordenadas (tabla
  `tz-lookup`, de dominio público) y la función manda `place.offsets`: los
  minutos respecto de UTC y cuándo cambian dentro del pronóstico. La app no
  carga la tabla de zonas del mundo; `WeatherZone` lee horas y días con eso, y
  sin `offsets` usa el reloj del local. Fuera del local la pestaña dice «Hora
  local 0:43».
- **La búsqueda sale por Photon.** Nominatim rechazó a la función en su
  primera búsqueda real (502 desde los servidores de Supabase, aunque desde un
  computador respondía): se pregunta primero a Photon, que lee los mismos
  nombres de OpenStreetMap, y Nominatim queda de respaldo. Se busca al enviar,
  nunca tecla a tecla: las reglas de uso de Nominatim prohíben el
  autocompletado. Los nombres de región llegan en inglés.
- **Un lugar que ya no existe** (se quitó en otro equipo) responde
  `place_missing` y la app vuelve al local.

## De dónde sale el lugar del local

De `website_settings`, leído por claves: `seo_geo_latitude`,
`seo_geo_longitude` y `seo_address_city`. Las escribe la conexión con la ficha
de Google del local (Sitio web › Integraciones). Sin ellas la sección dice que
falta conectar la ficha y lleva ahí.

## El documento

```json
{ "status": "ok", "schema": 1,
  "place": { "name": "Viña del Mar", "latitude": -33.0252, "longitude": -71.5623 },
  "source": { "model_updated_at": "…", "checked_at": "…", "expires_at": "…",
              "stale": false, "credits": [{ "name": "MET Norway", "url": "…" }] },
  "observation": null,
  "wind_trusted": true,
  "steps": [ { "time": "…", "span_minutes": 60, "temperature": 19.0,
               "apparent_temperature": 19.0, "wind_speed": null,
               "wind_from_direction": null, "humidity": 57.1, "uv_index": 0,
               "symbol": "clearsky_night", "precipitation": 0 } ] }
```

`observation`, cuando hay, lleva `time`, `station`, `distance_km`,
`temperature`, `apparent_temperature`, `wind_speed`, `wind_from_direction`,
`wind_gust`, `humidity` y `symbol`. Los símbolos son los de MET Norway; la app
los lee por composición (cielo, lo que cae, intensidad, chubascos, tormenta),
así cualquier combinación tiene dibujo y palabra.

`test/fixtures/weather/shop_weather_vina_del_mar_20261112.json` es una
respuesta real de la función.

## Reglas que salieron de datos reales

- **Una sola vara para «llueve».** `WeatherOutlook.rainPerHour` (0,2 mm) y
  `rainPerDay` (1 mm) deciden la frase, las barras del gráfico, la lectura al
  tocar y el texto para lector de pantalla. Con varas distintas el gráfico
  mostraba «<1 mm» bajo un sol despejado mientras la frase decía que no llovía.
- **El primer cielo del gráfico es el medido.** A las 4:00 del 2026-11-13 el
  modelo decía neblina y el aeródromo, despejado: «ahora» y el primer punto del
  gráfico se contradecían.
- **`NSC` y `NCD` se leen como despejado.** El aeródromo dice «sin nube
  significativa», que no descarta nube alta. Es la lectura habitual y la mejor
  evidencia a mano, pero no una certeza.
- **La sensación térmica sólo cuando cambia el número.** «15°, sensación 15°»
  no dice nada.
- **El viento por hora es el del pronóstico.** Sale cuando calza con la
  medición de la hora; si no, la columna desaparece y una línea lo dice. Que
  calce a las 5:00 no prueba el de las 14:00: en la costa el modelo midió alto.
- **Un cuerpo de pestaña más corto que el panel se centra solo.** El
  `AnimatedSwitcher` del resumen apila a sus hijos centrados y un
  `SingleChildScrollView` se encoge a su contenido: la vista por días quedaba
  en medio del panel con un hueco arriba. Va en un `ListView`, que ocupa todo
  el alto.
- **Abre en «Días»** (dueño, 2026-11-13); «Horas» cuando la persona lo eligió.
- **Los días empiezan mañana.** «Hoy» ya está en las 24 horas; un «hoy» a
  medias (lo que queda del día) daría máximas y mínimas engañosas.
- **Las horas son las del local** (`shopTime`), no las del equipo.

## Mejoras que necesitan una decisión del dueño

- Open-Meteo de pago (uso comercial): permitiría elegir el modelo que mejor
  midió en la costa (ICON).
- Google Weather API: hay que habilitarla en la consola de Google Cloud de la
  tienda.

Las dos se enchufan en `weather_sources.ts` sin tocar la app.

## Pruebas

- Función: `supabase/functions/_shared/weather_forecast_test.ts`,
  `weather_sources_test.ts` y `weather_places_test.ts` (Deno).
- Base: `supabase/tests/weather_forecast_cache.sql` y `weather_places.sql`
  (pgTAP), con sus read-backs en `supabase/manual_checks/verification/`.
- App: `test/unit/weather_forecast_test.dart`,
  `weather_forecast_service_test.dart`, `solar_times_test.dart`,
  `test/widget/briefing_weather_section_test.dart` y
  `notification_weather_briefing_test.dart` (la sección dentro del resumen:
  aparece en «Hoy», no en «Ayer»).
