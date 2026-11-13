import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  composeWeatherDocument,
  loadShopWeather,
  parseWeatherLocation,
  resolveWeatherExpiry,
  tieForecastToObservation,
  type UpstreamAnswer,
  WEATHER_SCHEMA,
  type WeatherCacheRow,
  type WeatherDeps,
  weatherUpstreamUrl,
} from "./weather_forecast.ts";
import type { WeatherObservation, WeatherStep } from "./weather_sources.ts";

const NOW = new Date("2026-11-12T23:20:00.000Z");
const SETTINGS = {
  seo_geo_latitude: "-33.025195",
  seo_geo_longitude: "-71.562306",
  seo_address_city: "Viña del Mar",
};
const PLACE = { latitude: -33.0252, longitude: -71.5623, name: "Viña del Mar" };

function step(time: string, temperature: number, overrides: Partial<WeatherStep> = {}) {
  return {
    time,
    span_minutes: 60,
    temperature,
    apparent_temperature: temperature - 1,
    wind_speed: 10,
    wind_from_direction: 200,
    humidity: 55,
    uv_index: 0,
    symbol: "clearsky_night",
    precipitation: 0,
    span_min_temperature: null,
    span_max_temperature: null,
    half_day_symbol: null,
    ...overrides,
  } satisfies WeatherStep;
}

// Viña del Mar on the evening of 2026-11-12: MET read 22.9° and 10.5 m/s
// where the aerodrome measured 19° and 3.1 m/s.
const STEPS: WeatherStep[] = [
  step("2026-11-12T22:00:00.000Z", 24.7),
  step("2026-11-12T23:00:00.000Z", 22.9, { wind_speed: 10.5 }),
  step("2026-11-13T00:00:00.000Z", 21.2),
  step("2026-11-13T05:00:00.000Z", 19.9, { span_minutes: 360, span_min_temperature: 16 }),
  step("2026-11-13T11:00:00.000Z", 17.1, { span_minutes: 0 }),
];
const MEASURED: WeatherObservation = {
  time: "2026-11-12T23:00:00.000Z",
  station: "SCVM",
  distance_km: 11.7,
  temperature: 19,
  wind_speed: 3.0867,
  wind_from_direction: 330,
  wind_gust: null,
  humidity: 72.9,
  symbol: "clearsky",
};

function metDocument(times: [string, number][]) {
  return {
    geometry: { type: "Point", coordinates: [-71.5623, -33.0252, 59] },
    properties: {
      meta: { updated_at: "2026-11-12T19:19:40Z" },
      timeseries: times.map(([time, temperature]) => ({
        time,
        data: {
          instant: { details: { air_temperature: temperature, wind_speed: 3 } },
          next_1_hours: { summary: { symbol_code: "fair_night" }, details: {} },
        },
      })),
    },
  };
}

const MET_NOW = metDocument([
  ["2026-11-12T23:00:00Z", 20],
  ["2026-11-13T00:00:00Z", 19],
]);
const METARS = [{
  icaoId: "SCVM",
  reportTime: "2026-11-12T23:00:00.000Z",
  temp: 19,
  dewp: 14,
  wdir: 330,
  wspd: 6,
  clouds: [],
  lat: -32.947,
  lon: -71.479,
  elev: 136,
}];

function cachedRow(overrides: Partial<WeatherCacheRow> = {}): WeatherCacheRow {
  return {
    latitude: -33.0252,
    longitude: -71.5623,
    payload: {
      schema: WEATHER_SCHEMA,
      series: { model_updated_at: "2026-11-12T13:00:00Z", elevation: 59, steps: STEPS },
      observation: null,
    },
    source_last_modified: "Thu, 12 Nov 2026 19:20:00 GMT",
    fetched_at: "2026-11-12T19:20:00.000Z",
    checked_at: "2026-11-12T22:45:00.000Z",
    expires_at: "2026-11-12T23:15:00.000Z",
    ...overrides,
  };
}

function harness(options: {
  settings?: Record<string, string>;
  cache?: WeatherCacheRow | null;
  claim?: boolean;
  forecast?: UpstreamAnswer | Error;
  observations?: unknown | Error;
}) {
  const log: string[] = [];
  const requests: { url: string; ifModifiedSince: string | null }[] = [];
  const boxes: string[] = [];
  let saved: WeatherCacheRow | null = null;
  const deps: WeatherDeps = {
    now: () => NOW,
    readSettings: () => Promise.resolve(options.settings ?? SETTINGS),
    readCache: () => Promise.resolve(options.cache ?? null),
    claimRefresh: (_tenant, _now, claimsBefore) => {
      log.push(`claim<${claimsBefore.toISOString()}`);
      return Promise.resolve(options.claim ?? true);
    },
    saveCache: (_tenant, row) => {
      saved = row;
      return Promise.resolve();
    },
    fetchForecast: (url, ifModifiedSince) => {
      requests.push({ url, ifModifiedSince });
      const forecast = options.forecast ??
        { status: 200, expires: null, lastModified: null, body: MET_NOW };
      return forecast instanceof Error ? Promise.reject(forecast) : Promise.resolve(forecast);
    },
    fetchObservations: (box) => {
      boxes.push(box);
      const observations = options.observations ?? METARS;
      return observations instanceof Error
        ? Promise.reject(observations)
        : Promise.resolve(observations);
    },
  };
  return { deps, log, requests, boxes, saved: () => saved };
}

function source(body: Record<string, unknown>) {
  return body.source as Record<string, unknown>;
}

function temperatures(body: Record<string, unknown>) {
  return (body.steps as WeatherStep[]).map((item) => item.temperature);
}

Deno.test("the place is the shop's listing, at four decimals", () => {
  assertEquals(parseWeatherLocation(SETTINGS), PLACE);
  assertEquals(
    weatherUpstreamUrl(PLACE),
    "https://api.met.no/weatherapi/locationforecast/2.0/complete?lat=-33.0252&lon=-71.5623",
  );
  assertEquals(parseWeatherLocation({ ...SETTINGS, seo_address_city: "  " })?.name, null);
});

Deno.test("a place that is not a place gives no forecast", async () => {
  for (
    const settings of [
      {},
      { seo_geo_latitude: "-33.02", seo_geo_longitude: "" },
      { seo_geo_latitude: "0", seo_geo_longitude: "0" },
      { seo_geo_latitude: "91", seo_geo_longitude: "10" },
      { seo_geo_latitude: "10", seo_geo_longitude: "181" },
      { seo_geo_latitude: "-33,02", seo_geo_longitude: "-71.56" },
      { seo_geo_latitude: "1e2", seo_geo_longitude: "-71.56" },
    ]
  ) {
    assertEquals(parseWeatherLocation(settings), null);
  }
  const run = harness({ settings: {} });
  const result = await loadShopWeather(run.deps, "tenant");
  assertEquals(result, { status: 200, body: { status: "location_missing" } });
  assertEquals(run.requests.length, 0);
  assertEquals(run.boxes.length, 0);
});

Deno.test("the next request waits for Expires, inside sane bounds", () => {
  assertEquals(
    resolveWeatherExpiry("Thu, 12 Nov 2026 23:51:45 GMT", NOW).toISOString(),
    "2026-11-12T23:51:45.000Z",
  );
  // No header, or one that is not a date: half an hour.
  assertEquals(resolveWeatherExpiry(null, NOW).toISOString(), "2026-11-12T23:50:00.000Z");
  assertEquals(resolveWeatherExpiry("soon", NOW).toISOString(), "2026-11-12T23:50:00.000Z");
  // Already past, or a day away: five minutes and three hours.
  assertEquals(
    resolveWeatherExpiry("Thu, 12 Nov 2026 22:00:00 GMT", NOW).toISOString(),
    "2026-11-12T23:25:00.000Z",
  );
  assertEquals(
    resolveWeatherExpiry("Fri, 13 Nov 2026 23:20:00 GMT", NOW).toISOString(),
    "2026-11-13T02:20:00.000Z",
  );
});

Deno.test("the forecast starts at what was measured, and the gap fades", () => {
  const tied = tieForecastToObservation(STEPS, MEASURED);
  assertEquals(tied.temperature_offset, 3.9);
  // Whole at the measurement and before it, 98 % an hour later, 57 % six
  // hours later and 11 % twelve hours later.
  assertEquals(tied.steps.map((item) => item.temperature), [20.8, 19, 17.4, 17.7, 16.7]);
  assertEquals(tied.steps[1].apparent_temperature, 18);
  assertEquals(tied.steps[3].span_min_temperature, 13.8);
  // What the measured 19° feels like, by the forecast's own reckoning.
  assertEquals(tied.apparent_temperature, 18);
});

Deno.test("a forecast wind that triples the measured one is not shown", () => {
  const tied = tieForecastToObservation(STEPS, MEASURED);
  assertEquals(tied.wind_trusted, false);
  assertEquals(tied.steps.every((item) => item.wind_speed === null), true);
  assertEquals(tied.steps.every((item) => item.wind_from_direction === null), true);

  // Light airs agree with each other, whatever their ratio.
  const calm = STEPS.map((item) => ({ ...item, wind_speed: 1.9 }));
  const light = tieForecastToObservation(calm, { ...MEASURED, wind_speed: 0.4 });
  assertEquals(light.wind_trusted, true);
  assertEquals(light.steps[1].wind_speed, 1.9);
  // And a measured gale against a calm forecast is the same mistake.
  assertEquals(
    tieForecastToObservation(calm, { ...MEASURED, wind_speed: 9 }).wind_trusted,
    false,
  );
  // No measured wind: nothing to compare, the forecast's stays.
  assertEquals(
    tieForecastToObservation(STEPS, { ...MEASURED, wind_speed: null }).wind_trusted,
    true,
  );
});

Deno.test("a measurement that is not from this air leaves the forecast alone", () => {
  for (
    const observation of [
      null,
      // Twelve degrees apart is not the model's error.
      { ...MEASURED, temperature: 10.9, wind_speed: null },
      // Measured outside the series.
      { ...MEASURED, time: "2026-11-12T20:00:00.000Z", wind_speed: null },
      { ...MEASURED, time: "2026-11-14T20:00:00.000Z", wind_speed: null },
    ]
  ) {
    const tied = tieForecastToObservation(STEPS, observation);
    assertEquals(tied.temperature_offset, 0);
    assertEquals(tied.steps.map((item) => item.temperature), [24.7, 22.9, 21.2, 19.9, 17.1]);
  }
});

Deno.test("the document drops what ended and a measurement that grew old", () => {
  const row = cachedRow({
    payload: {
      schema: WEATHER_SCHEMA,
      series: { model_updated_at: "2026-11-12T13:00:00Z", elevation: 59, steps: STEPS },
      observation: MEASURED,
    },
  });
  const fresh = composeWeatherDocument(PLACE, row, NOW, { stale: false });
  // 22:00–23:00 ended twenty minutes ago and still holds the hour before now.
  assertEquals(temperatures(fresh), [20.8, 19, 17.4, 17.7, 16.7]);
  assertEquals(fresh.wind_trusted, false);
  assertEquals(fresh.observation, {
    ...MEASURED,
    wind_speed: 3.1,
    humidity: 73,
    apparent_temperature: 18,
  });
  assertEquals(
    (source(fresh).credits as { name: string }[]).map((credit) => credit.name),
    ["MET Norway", "NOAA Aviation Weather Center"],
  );

  // Two hours on, the 23:00 report no longer says what «now» is.
  const later = composeWeatherDocument(
    PLACE,
    row,
    new Date("2026-11-13T01:10:00.000Z"),
    { stale: false },
  );
  assertEquals(later.observation, null);
  assertEquals(later.wind_trusted, true);
  assertEquals(temperatures(later), [21.2, 19.9, 17.1]);
  assertEquals(
    (source(later).credits as { name: string }[]).map((credit) => credit.name),
    ["MET Norway"],
  );
});

Deno.test("what has not expired is answered without asking anyone", async () => {
  const row = cachedRow({ expires_at: "2026-11-12T23:40:00.000Z" });
  const run = harness({ cache: row });
  const result = await loadShopWeather(run.deps, "tenant");
  assertEquals(result.status, 200);
  assertEquals(result.body.place, PLACE);
  assertEquals(source(result.body).expires_at, row.expires_at);
  assertEquals(run.requests.length, 0);
  assertEquals(run.boxes.length, 0);
  assertEquals(run.log, []);
});

Deno.test("the first read asks both sources and keeps their answers", async () => {
  const run = harness({
    cache: null,
    forecast: {
      status: 200,
      expires: "Thu, 12 Nov 2026 23:51:45 GMT",
      lastModified: "Thu, 12 Nov 2026 23:20:12 GMT",
      body: MET_NOW,
    },
  });
  const result = await loadShopWeather(run.deps, "tenant");
  assertEquals(result.status, 200);
  assertEquals(run.requests, [{
    url: "https://api.met.no/weatherapi/locationforecast/2.0/complete?lat=-33.0252&lon=-71.5623",
    ifModifiedSince: null,
  }]);
  assertEquals(run.boxes, ["-33.29,-71.88,-32.76,-71.24"]);
  // Nobody holds a row yet, so there is nothing to claim.
  assertEquals(run.log, []);
  const saved = run.saved()!;
  assertEquals(saved.source_last_modified, "Thu, 12 Nov 2026 23:20:12 GMT");
  assertEquals(saved.fetched_at, NOW.toISOString());
  assertEquals(saved.checked_at, NOW.toISOString());
  assertEquals(saved.expires_at, "2026-11-12T23:51:45.000Z");
  assertEquals(saved.payload.series.steps.length, 2);
  assertEquals(saved.payload.observation?.station, "SCVM");
  // The row keeps the forecast as MET gave it; the tie is made on the way out.
  assertEquals(saved.payload.series.steps[0].temperature, 20);
  assertEquals(temperatures(result.body), [19, 18]);
  assertEquals((result.body.observation as WeatherObservation).temperature, 19);
});

Deno.test("an expired row is refreshed by the caller that claims it", async () => {
  const run = harness({ cache: cachedRow(), claim: true });
  const result = await loadShopWeather(run.deps, "tenant");
  assertEquals(source(result.body).stale, false);
  assertEquals(run.log, ["claim<2026-11-12T23:19:30.000Z"]);
  assertEquals(run.requests[0].ifModifiedSince, "Thu, 12 Nov 2026 19:20:00 GMT");
  assertEquals(run.saved()?.payload.series.steps.length, 2);
});

Deno.test("whoever loses the claim gets what is in hand and asks nobody", async () => {
  const run = harness({ cache: cachedRow(), claim: false });
  const result = await loadShopWeather(run.deps, "tenant");
  assertEquals(result.status, 200);
  assertEquals(source(result.body).expires_at, "2026-11-12T23:20:45.000Z");
  assertEquals(run.requests.length, 0);
  assertEquals(run.boxes.length, 0);
  assertEquals(run.saved(), null);
});

Deno.test("an unchanged forecast keeps its series and takes the new measurement", async () => {
  const row = cachedRow();
  const run = harness({
    cache: row,
    forecast: {
      status: 304,
      expires: "Thu, 12 Nov 2026 23:55:00 GMT",
      lastModified: null,
      body: null,
    },
  });
  const result = await loadShopWeather(run.deps, "tenant");
  const saved = run.saved()!;
  assertEquals(saved.payload.series.steps, STEPS);
  assertEquals(saved.payload.observation?.station, "SCVM");
  assertEquals(saved.fetched_at, row.fetched_at);
  assertEquals(saved.source_last_modified, row.source_last_modified);
  assertEquals(saved.checked_at, NOW.toISOString());
  assertEquals(saved.expires_at, "2026-11-12T23:55:00.000Z");
  assertEquals(source(result.body).stale, false);
  assertEquals(temperatures(result.body)[1], 19);
});

Deno.test("when MET fails the last forecast stays, marked, and MET rests", async () => {
  for (
    const forecast of [
      new Error("network"),
      { status: 429, expires: null, lastModified: null, body: null },
      { status: 200, expires: null, lastModified: null, body: { properties: {} } },
    ]
  ) {
    const row = cachedRow();
    const run = harness({ cache: row, forecast });
    const result = await loadShopWeather(run.deps, "tenant");
    assertEquals(result.status, 200);
    assertEquals(source(result.body).stale, true);
    const saved = run.saved()!;
    assertEquals(saved.payload.series.steps, STEPS);
    // The age the app shows is the last time MET confirmed it, untouched.
    assertEquals(saved.checked_at, row.checked_at);
    assertEquals(saved.fetched_at, row.fetched_at);
    assertEquals(saved.expires_at, "2026-11-12T23:25:00.000Z");
    // The measurement does not depend on MET.
    assertEquals(saved.payload.observation?.station, "SCVM");
  }
});

Deno.test("without a measurement the forecast stands alone", async () => {
  for (const observations of [new Error("network"), [], { status: "error" }]) {
    const run = harness({ cache: null, observations });
    const result = await loadShopWeather(run.deps, "tenant");
    assertEquals(result.status, 200);
    assertEquals(result.body.observation, null);
    assertEquals(result.body.wind_trusted, true);
    assertEquals(temperatures(result.body), [20, 19]);
    assertEquals(run.saved()?.payload.observation, null);
  }
});

Deno.test("a failed read of the aerodrome keeps the last measurement while it is recent", async () => {
  const row = cachedRow({
    payload: {
      schema: WEATHER_SCHEMA,
      series: { model_updated_at: null, elevation: 59, steps: STEPS },
      observation: MEASURED,
    },
  });
  const run = harness({ cache: row, observations: new Error("network") });
  const result = await loadShopWeather(run.deps, "tenant");
  assertEquals(run.saved()?.payload.observation, MEASURED);
  assertEquals((result.body.observation as WeatherObservation).station, "SCVM");
});

Deno.test("with nothing kept, a failure says so instead of inventing weather", async () => {
  const run = harness({ cache: null, forecast: new Error("network") });
  const result = await loadShopWeather(run.deps, "tenant");
  assertEquals(result, {
    status: 502,
    body: { status: "unavailable", retry_at: "2026-11-12T23:25:00.000Z" },
  });
  assertEquals(run.saved(), null);
});

Deno.test("a shop that moved, or a row of another shape, is read anew", async () => {
  const elsewhere = cachedRow({
    latitude: -33.4489,
    longitude: -70.6693,
    expires_at: "2026-11-13T02:00:00.000Z",
  });
  const moved = harness({ cache: elsewhere });
  const result = await loadShopWeather(moved.deps, "tenant");
  assertEquals(moved.requests[0].ifModifiedSince, null);
  assertEquals(moved.log, []);
  assertEquals(moved.saved()?.latitude, -33.0252);
  assertEquals(temperatures(result.body), [19, 18]);

  const older = cachedRow({ expires_at: "2026-11-13T02:00:00.000Z" });
  (older.payload as { schema: number }).schema = 0;
  const reshaped = harness({ cache: older });
  await loadShopWeather(reshaped.deps, "tenant");
  assertEquals(reshaped.requests.length, 1);
  assertEquals(reshaped.saved()?.payload.schema, WEATHER_SCHEMA);
});
