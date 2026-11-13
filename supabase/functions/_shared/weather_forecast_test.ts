import { assert, assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  composeWeatherDocument,
  loadShopWeather,
  parseWeatherLocation,
  recordHistory,
  resolveWeatherExpiry,
  tieForecastToObservation,
  type UpstreamAnswer,
  WEATHER_SCHEMA,
  type WeatherCacheRow,
  type WeatherDeps,
  weatherUpstreamUrl,
} from "./weather_forecast.ts";
import type { WeatherHistory, WeatherObservation, WeatherStep } from "./weather_sources.ts";

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
  reports?: unknown | Error;
}) {
  const log: string[] = [];
  const requests: { url: string; ifModifiedSince: string | null }[] = [];
  const boxes: string[] = [];
  const stations: string[] = [];
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
    fetchStationReports: (station) => {
      stations.push(station);
      const reports = options.reports ?? [];
      return reports instanceof Error ? Promise.reject(reports) : Promise.resolve(reports);
    },
  };
  return { deps, log, requests, boxes, stations, saved: () => saved };
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
  // The coldest of the six hours from 05:00 comes late in them, when less of
  // the gap is left: it takes the mean of those hours' corrections.
  assertEquals(tied.steps[3].span_min_temperature, 14.8);
  // What the measured 19° feels like, by the forecast's own reckoning.
  assertEquals(tied.apparent_temperature, 18);
});

Deno.test("a forecast wind that triples the measured one is brought down to it", () => {
  // 10.5 m/s forecast against 3.1 measured: with no days of readings to say
  // what is usual here, every hour keeps that factor.
  const tied = tieForecastToObservation(STEPS, MEASURED);
  assertEquals(tied.adjusted, true);
  assertEquals(tied.steps.map((item) => item.wind_speed), [2.9, 3.1, 2.9, 2.9, 2.9]);
  // Where it blows from is the forecast's.
  assertEquals(tied.steps.every((item) => item.wind_from_direction === 200), true);

  // Light airs are levelled: 0.4 against 1.9 is not «a fifth of the wind».
  const calm = STEPS.map((item) => ({ ...item, wind_speed: 1.9 }));
  const light = tieForecastToObservation(calm, { ...MEASURED, wind_speed: 0.4 });
  assertEquals(light.steps[1].wind_speed, 1.5);
  // One gusty report does not multiply the forecast without bound.
  assertEquals(
    tieForecastToObservation(calm, { ...MEASURED, wind_speed: 9 }).steps[1].wind_speed,
    3.8,
  );
  // No measured wind: nothing to compare, the forecast's stays.
  assertEquals(
    tieForecastToObservation(STEPS, { ...MEASURED, wind_speed: null }).steps[1].wind_speed,
    10.5,
  );
  // A step that has no wind gets none.
  const windless = STEPS.map((item) => ({ ...item, wind_speed: null }));
  assertEquals(tieForecastToObservation(windless, MEASURED).steps[1].wind_speed, null);
});

/// Three days of an aerodrome on a coast: by night the forecast's wind is
/// four times the measured one, in the afternoon a little over it, and its
/// evening temperature reads four degrees high.
function coastalHistory(): WeatherHistory {
  const readings: WeatherHistory["readings"] = [];
  for (let day = 10; day <= 12; day++) {
    for (let hour = 0; hour < 24; hour++) {
      const afternoon = hour >= 14 && hour <= 22;
      const evening = hour >= 21 || hour <= 1;
      readings.push({
        time: `2026-11-${day}T${String(hour).padStart(2, "0")}:00:00.000Z`,
        temperature: 16,
        wind_speed: afternoon ? 5 : 1.5,
        model_temperature: evening ? 20 : 16,
        model_wind_speed: afternoon ? 7 : 6,
      });
    }
  }
  return { station: "SCVM", read_at: "2026-11-12T23:00:00.000Z", readings };
}

function hourly(from: string, count: number, overrides: Partial<WeatherStep> = {}) {
  const start = Date.parse(from);
  return Array.from(
    { length: count },
    (_, index) =>
      step(new Date(start + index * 3600000).toISOString(), 18, {
        wind_speed: 8,
        span_minutes: index + 1 === count ? 0 : 60,
        ...overrides,
      }),
  );
}

Deno.test("days of readings teach the usual error of each hour of the day", () => {
  const steps = hourly("2026-11-13T00:00:00.000Z", 48);
  const tied = tieForecastToObservation(steps, null, coastalHistory(), NOW);
  assertEquals(tied.adjusted, true);
  const wind = tied.steps.map((item) => item.wind_speed!);
  const temperature = tied.steps.map((item) => item.temperature);
  // 08:00 UTC, deep in the night: a quarter of the forecast's 8 m/s.
  assert(Math.abs(wind[8] - 2) <= 0.3, `night wind ${wind[8]}`);
  // 18:00 UTC, mid afternoon: five sevenths of it, held a little towards the
  // place's overall factor.
  assert(Math.abs(wind[18] - 5.7) <= 0.5, `afternoon wind ${wind[18]}`);
  // The same hours a day later read the same: the usual error does not fade.
  assertEquals(wind[32], wind[8]);
  assertEquals(wind[42], wind[18]);
  // Between night and afternoon the factor changes by steps a person would
  // not notice, never by a jump.
  for (let index = 1; index < wind.length; index++) {
    assert(Math.abs(wind[index] - wind[index - 1]) <= 1.6, `jump at ${index}`);
  }
  // 23:00 UTC reads four degrees high and noon reads true.
  assert(Math.abs(temperature[23] - 14.2) <= 0.4, `evening ${temperature[23]}`);
  assert(Math.abs(temperature[12] - 18) <= 0.2, `noon ${temperature[12]}`);
  for (let index = 1; index < temperature.length; index++) {
    assert(Math.abs(temperature[index] - temperature[index - 1]) <= 2.2, `jump at ${index}`);
  }
});

Deno.test("how today differs from the usual holds now and fades", () => {
  const steps = hourly("2026-11-12T23:00:00.000Z", 30);
  // At 23:00 UTC the forecast usually reads four degrees and a little wind
  // over the aerodrome. Tonight it reads six degrees and twice the wind over.
  const tonight: WeatherObservation = {
    ...MEASURED,
    temperature: 12,
    wind_speed: 4,
  };
  const tied = tieForecastToObservation(steps, tonight, coastalHistory(), NOW);
  assertEquals(tied.temperature_offset, 6);
  // Now is what was measured.
  assertEquals(tied.steps[0].temperature, 12);
  assertEquals(tied.steps[0].wind_speed, 4);
  // A day later only the usual error of that hour is left.
  const usual = tieForecastToObservation(steps, null, coastalHistory(), NOW);
  assert(Math.abs(tied.steps[24].temperature - usual.steps[24].temperature) <= 0.1);
  assert(Math.abs(tied.steps[24].wind_speed! - usual.steps[24].wind_speed!) <= 0.1);
  // And in between it is in between.
  assert(tied.steps[4].temperature < usual.steps[4].temperature);
});

Deno.test("too few readings, or old ones, teach nothing", () => {
  const steps = hourly("2026-11-13T00:00:00.000Z", 6);
  const few = { ...coastalHistory(), readings: coastalHistory().readings.slice(-2) };
  assertEquals(tieForecastToObservation(steps, null, few, NOW).adjusted, false);
  // The same readings read three weeks later are another season's.
  const later = new Date("2026-12-04T00:00:00.000Z");
  assertEquals(tieForecastToObservation(steps, null, coastalHistory(), later).adjusted, false);
  // Readings no forecast was set next to are only readings.
  const unpaired = {
    ...coastalHistory(),
    readings: coastalHistory().readings.map((reading) => ({
      ...reading,
      model_temperature: null,
      model_wind_speed: null,
    })),
  };
  assertEquals(tieForecastToObservation(steps, null, unpaired, NOW).adjusted, false);
});

Deno.test("each reading is set next to the forecast made for its hour", () => {
  const earlier = { model_updated_at: null, elevation: 59, steps: STEPS };
  const fresh = {
    model_updated_at: null,
    elevation: 59,
    steps: [step("2026-11-13T00:00:00.000Z", 30, { wind_speed: 1 })],
  };
  const readings = [
    // Before any kept forecast.
    { time: "2026-11-12T20:00:00.000Z", temperature: 21, wind_speed: 2 },
    // Sent seven minutes before the hour the kept forecast starts at.
    { time: "2026-11-12T21:53:00.000Z", temperature: 20, wind_speed: 2.1 },
    { time: "2026-11-12T23:30:00.000Z", temperature: 19, wind_speed: 3.1 },
    // Inside the six-hour stretch: no forecast was made for that hour.
    { time: "2026-11-13T07:00:00.000Z", temperature: 15, wind_speed: 1 },
  ];
  const history = recordHistory(null, "SCVM", readings, [earlier, fresh], NOW);
  assertEquals(history.station, "SCVM");
  assertEquals(history.read_at, NOW.toISOString());
  assertEquals(
    history.readings.map((item) => [item.model_temperature, item.model_wind_speed]),
    [[null, null], [24.7, 10], [22, 10.3], [null, null]],
  );

  // A reading keeps the first forecast it was set next to, and another
  // aerodrome starts from nothing.
  const again = recordHistory(history, "SCVM", readings, [fresh], NOW);
  assertEquals(again.readings[1].model_temperature, 24.7);
  const moved = recordHistory(history, "SCRD", readings, [fresh], NOW);
  assertEquals(moved.readings[1].model_temperature, null);
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
  assertEquals(fresh.adjusted_with, "SCVM");
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
  assertEquals(later.adjusted_with, null);
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
  // The shop's place read from settings alone carries no zone of its own.
  assertEquals(result.body.place, {
    id: null,
    region: null,
    time_zone: null,
    offsets: [],
    ...PLACE,
  });
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
    assertEquals(result.body.adjusted_with, null);
    // No aerodrome, no days of readings to ask for.
    assertEquals(run.stations, []);
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

const REPORTS = [
  { icaoId: "SCVM", reportTime: "2026-11-12T22:00:00.000Z", temp: 20, wspd: 4 },
  { icaoId: "SCVM", reportTime: "2026-11-12T23:00:00.000Z", temp: 19, wspd: 6 },
  // Sent twice, a calm one, another aerodrome's, one without a temperature
  // and one from a week ago.
  { icaoId: "SCVM", reportTime: "2026-11-12T23:00:00.000Z", temp: 19, wspd: 6 },
  { icaoId: "SCVM", reportTime: "2026-11-12T21:00:00.000Z", temp: 21, wspd: 0 },
  { icaoId: "SCRD", reportTime: "2026-11-12T23:00:00.000Z", temp: 17, wspd: 9 },
  { icaoId: "SCVM", reportTime: "2026-11-12T20:00:00.000Z", wspd: 5 },
  { icaoId: "SCVM", reportTime: "2026-11-05T23:00:00.000Z", temp: 18, wspd: 5 },
];

Deno.test("a refresh reads the aerodrome's last days and sets them next to the kept forecast", async () => {
  const run = harness({ cache: cachedRow(), reports: REPORTS });
  await loadShopWeather(run.deps, "tenant");
  assertEquals(run.stations, ["SCVM"]);
  assertEquals(run.saved()?.payload.history, {
    station: "SCVM",
    read_at: NOW.toISOString(),
    readings: [
      // 21:00 is before the kept forecast starts.
      {
        time: "2026-11-12T21:00:00.000Z",
        temperature: 21,
        wind_speed: 0,
        model_temperature: null,
        model_wind_speed: null,
      },
      {
        time: "2026-11-12T22:00:00.000Z",
        temperature: 20,
        wind_speed: 2.1,
        model_temperature: 24.7,
        model_wind_speed: 10,
      },
      {
        time: "2026-11-12T23:00:00.000Z",
        temperature: 19,
        wind_speed: 3.1,
        model_temperature: 22.9,
        model_wind_speed: 10.5,
      },
    ],
  });
});

Deno.test("the aerodrome's days are read once an hour, and a failed read keeps what was known", async () => {
  const history: WeatherHistory = {
    station: "SCVM",
    read_at: "2026-11-12T22:50:00.000Z",
    readings: [],
  };
  const kept = (readAt: string) =>
    cachedRow({
      payload: {
        schema: WEATHER_SCHEMA,
        series: { model_updated_at: null, elevation: 59, steps: STEPS },
        observation: null,
        history: { ...history, read_at: readAt },
      },
    });

  // Read half an hour ago: not yet.
  const soon = harness({ cache: kept("2026-11-12T22:50:00.000Z"), reports: REPORTS });
  await loadShopWeather(soon.deps, "tenant");
  assertEquals(soon.stations, []);
  assertEquals(soon.saved()?.payload.history, history);

  // Read an hour ago: again.
  const due = harness({ cache: kept("2026-11-12T22:20:00.000Z"), reports: REPORTS });
  await loadShopWeather(due.deps, "tenant");
  assertEquals(due.stations, ["SCVM"]);
  assertEquals(due.saved()?.payload.history?.readings.length, 3);

  // The aerodrome does not answer: the forecast is still served and saved.
  const failed = harness({
    cache: kept("2026-11-12T22:20:00.000Z"),
    reports: new Error("network"),
  });
  const result = await loadShopWeather(failed.deps, "tenant");
  assertEquals(result.status, 200);
  assertEquals(failed.saved()?.payload.history?.read_at, "2026-11-12T22:20:00.000Z");

  // Another aerodrome became the nearest one that reports: its days, anew.
  const other = harness({
    cache: kept("2026-11-12T23:10:00.000Z"),
    observations: [{ ...METARS[0], icaoId: "SCRD" }],
    reports: REPORTS,
  });
  await loadShopWeather(other.deps, "tenant");
  assertEquals(other.stations, ["SCRD"]);
  assertEquals(other.saved()?.payload.history?.station, "SCRD");
  assertEquals(other.saved()?.payload.history?.readings.length, 1);
});
