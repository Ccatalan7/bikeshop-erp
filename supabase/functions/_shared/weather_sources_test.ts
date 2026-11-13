import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  normalizeMetForecast,
  observationBox,
  pickObservation,
  symbolFromMetar,
} from "./weather_sources.ts";

function metEntry(time: string, temperature: number, extra: Record<string, unknown> = {}) {
  return {
    time,
    data: {
      instant: {
        details: {
          air_temperature: temperature,
          apparent_air_temperature: temperature - 0.5,
          wind_speed: 4,
          wind_from_direction: 200,
          relative_humidity: 60,
          ultraviolet_index_clear_sky: 3.2,
        },
      },
      ...extra,
    },
  };
}

Deno.test("MET's document becomes a series with the summary that fits each step", () => {
  const series = normalizeMetForecast({
    geometry: { type: "Point", coordinates: [-71.5623, -33.0252, 59] },
    properties: {
      meta: { updated_at: "2026-11-12T19:19:40Z" },
      timeseries: [
        // Out of order on purpose: the series is sorted by time.
        metEntry("2026-11-15T18:00:00Z", 20.3, {
          next_6_hours: {
            summary: { symbol_code: "cloudy" },
            details: { precipitation_amount: 0, air_temperature_max: 20.3 },
          },
        }),
        metEntry("2026-11-15T11:00:00Z", 16, {
          next_1_hours: {
            summary: { symbol_code: "lightrainshowers_day" },
            details: { precipitation_amount: 0.4 },
          },
          next_6_hours: {
            summary: { symbol_code: "rain" },
            details: { precipitation_amount: 9 },
          },
          next_12_hours: { summary: { symbol_code: "partlycloudy_day" }, details: {} },
        }),
        metEntry("2026-11-15T12:00:00Z", 17.4, {
          next_6_hours: {
            summary: { symbol_code: "fair_day" },
            details: {
              precipitation_amount: 0.1,
              air_temperature_max: 20.3,
              air_temperature_min: 17.3,
            },
          },
        }),
        { time: "2026-11-15T13:00:00Z", data: { instant: { details: {} } } },
        "noise",
      ],
    },
  });
  assertEquals(series?.model_updated_at, "2026-11-12T19:19:40Z");
  assertEquals(series?.elevation, 59);
  assertEquals(series?.steps.map((step) => [step.time, step.span_minutes]), [
    ["2026-11-15T11:00:00.000Z", 60],
    ["2026-11-15T12:00:00.000Z", 360],
    ["2026-11-15T18:00:00.000Z", 0],
  ]);
  const [hourly, sixHourly] = series!.steps;
  // An hourly step takes the hour's summary, not the six hours'.
  assertEquals(hourly.symbol, "lightrainshowers_day");
  assertEquals(hourly.precipitation, 0.4);
  assertEquals(hourly.half_day_symbol, "partlycloudy_day");
  assertEquals(hourly.apparent_temperature, 15.5);
  assertEquals(sixHourly.symbol, "fair_day");
  assertEquals(sixHourly.precipitation, 0.1);
  assertEquals(sixHourly.span_min_temperature, 17.3);
  assertEquals(sixHourly.span_max_temperature, 20.3);
});

Deno.test("a document without a series is no forecast", () => {
  for (
    const document of [
      null,
      "text",
      {},
      { properties: {} },
      { properties: { timeseries: [] } },
      { properties: { timeseries: [{ time: "2026-11-15T11:00:00Z", data: {} }] } },
    ]
  ) {
    assertEquals(normalizeMetForecast(document), null);
  }
});

Deno.test("the sky of a METAR: its weather first, then its densest layer", () => {
  const cases: [Record<string, unknown>, string][] = [
    [{ clouds: [] }, "clearsky"],
    [{ clouds: [{ cover: "CAVOK" }] }, "clearsky"],
    [{ clouds: [{ cover: "FEW", base: 3000 }] }, "fair"],
    [{ clouds: [{ cover: "FEW" }, { cover: "SCT" }] }, "partlycloudy"],
    [{ clouds: [{ cover: "SCT" }, { cover: "BKN" }] }, "cloudy"],
    [{ clouds: [{ cover: "OVC" }] }, "cloudy"],
    [{ wxString: "BR", clouds: [{ cover: "OVC" }] }, "fog"],
    [{ wxString: "FG" }, "fog"],
    [{ wxString: "-RA", clouds: [{ cover: "BKN" }] }, "lightrain"],
    [{ wxString: "RA BR" }, "rain"],
    [{ wxString: "+RA" }, "heavyrain"],
    [{ wxString: "DZ" }, "lightrain"],
    [{ wxString: "-SHRA" }, "lightrainshowers"],
    [{ wxString: "SHRA" }, "rainshowers"],
    [{ wxString: "TSRA" }, "rainandthunder"],
    [{ wxString: "+TSRA" }, "heavyrainandthunder"],
    [{ wxString: "TS" }, "rainandthunder"],
    [{ wxString: "-SN" }, "lightsnow"],
    [{ wxString: "RASN" }, "sleet"],
    [{ wxString: "-SHSN" }, "lightsnowshowers"],
  ];
  for (const [report, symbol] of cases) {
    assertEquals(symbolFromMetar(report), symbol, JSON.stringify(report));
  }
});

const NOW = new Date("2026-11-12T23:20:00.000Z");
const SHOP = { latitude: -33.0252, longitude: -71.5623, elevation: 59 };
// The two aerodromes of Viña del Mar, as the Aviation Weather Center gave
// them on 2026-11-12.
const CONCON = {
  icaoId: "SCVM",
  reportTime: "2026-11-12T23:00:00.000Z",
  temp: 19,
  dewp: 14,
  wdir: 330,
  wspd: 6,
  wgst: null,
  wxString: null,
  clouds: [],
  lat: -32.947,
  lon: -71.479,
  elev: 136,
};
const RODELILLO = {
  icaoId: "SCRD",
  reportTime: "2026-11-12T23:00:00.000Z",
  temp: 22,
  dewp: 13,
  wdir: 210,
  wspd: 7,
  wgst: null,
  wxString: null,
  clouds: [],
  lat: -33.068,
  lon: -71.557,
  elev: 342,
};

Deno.test("the box holds every aerodrome within reach", () => {
  assertEquals(observationBox(-33.0252, -71.5623), "-33.29,-71.88,-32.76,-71.24");
});

Deno.test("height counts as distance: the field down the coast beats the hilltop", () => {
  const observation = pickObservation(
    [
      RODELILLO,
      { ...CONCON, reportTime: "2026-11-12T22:00:00.000Z", temp: 20 },
      CONCON,
    ],
    SHOP,
    NOW,
  );
  assertEquals(observation?.station, "SCVM");
  // The latest report of that field, not the first one listed.
  assertEquals(observation?.time, "2026-11-12T23:00:00.000Z");
  assertEquals(observation?.temperature, 19);
  assertEquals(observation?.distance_km, 11.7);
  assertEquals(Math.round(observation!.wind_speed! * 10) / 10, 3.1);
  assertEquals(observation?.wind_from_direction, 330);
  assertEquals(Math.round(observation!.humidity!), 73);
  assertEquals(observation?.symbol, "clearsky");
  // Without the shop's height, distance alone decides.
  assertEquals(
    pickObservation([RODELILLO, CONCON], { ...SHOP, elevation: null }, NOW)?.station,
    "SCRD",
  );
});

Deno.test("a calm or shifting wind comes from nowhere", () => {
  assertEquals(
    pickObservation([{ ...CONCON, wspd: 0, wdir: 0 }], SHOP, NOW)?.wind_from_direction,
    null,
  );
  const shifting = pickObservation([{ ...CONCON, wdir: "VRB", wspd: 3 }], SHOP, NOW);
  assertEquals(shifting?.wind_from_direction, null);
  assertEquals(Math.round(shifting!.wind_speed! * 10) / 10, 1.5);
});

Deno.test("an old report, a far field or a report without temperature says nothing", () => {
  assertEquals(
    pickObservation([{ ...CONCON, reportTime: "2026-11-12T21:30:00.000Z" }], SHOP, NOW),
    null,
  );
  assertEquals(
    pickObservation([{ ...CONCON, lat: -33.393, lon: -70.786 }], SHOP, NOW),
    null,
  );
  assertEquals(pickObservation([{ ...CONCON, temp: null }], SHOP, NOW), null);
  assertEquals(pickObservation([], SHOP, NOW), null);
  assertEquals(pickObservation({ error: "x" }, SHOP, NOW), null);
});
