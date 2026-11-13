// The shop's weather for the daily briefing of the ERP: one answer per shop,
// kept between requests, made of a forecast and of the last measurement near
// the place (see `weather_sources.ts` for why it takes both).
//
// MET Norway's terms shape the keeping (api.met.no/doc/TermsOfService, read
// on 2026-11-12): browsers and apps go through a backend, a request is never
// repeated before its `Expires`, a repeat carries `If-Modified-Since`,
// coordinates have at most four decimals, and every request names who asks.
// So one row per shop holds the last readings, and only the caller that
// claims an expired row asks again.
//
// What leaves here is the ERP's own document, not a provider's: the app draws
// `steps` and `observation` whoever they came from, so the sources can change
// without publishing an app.

import {
  HISTORY_HOURS,
  MAX_OBSERVATION_AGE_MS,
  normalizeMetForecast,
  observationBox,
  pickObservation,
  stationReadings,
  type WeatherHistory,
  type WeatherObservation,
  type WeatherSeries,
  type WeatherStep,
} from "./weather_sources.ts";
import { zoneOffsets } from "./weather_places.ts";

export const WEATHER_PROVIDER = "met.no+aviationweather.gov/v1";
export const WEATHER_SCHEMA = 1;

const MET_ENDPOINT = "https://api.met.no/weatherapi/locationforecast/2.0/complete";
const DEFAULT_FRESH_MS = 30 * 60 * 1000;
const MIN_FRESH_MS = 5 * 60 * 1000;
const MAX_FRESH_MS = 3 * 60 * 60 * 1000;
/// After a failed read nobody asks again for this long.
const FAILURE_BACKOFF_MS = 5 * 60 * 1000;
/// A claim older than this belonged to a caller that died mid-refresh.
const CLAIM_TTL_MS = 30 * 1000;
/// What a caller that lost the claim is told to wait before asking again.
const CLAIM_RETRY_MS = 45 * 1000;
/// The measured error of the forecast holds for the first hours and then goes:
/// nearly whole two hours on, half at about seven, a tenth at twelve. A plain
/// exponential let go too soon: on the evening it was measured the corrected
/// curve dipped and then climbed through the night, because the model's error
/// outlasted the correction.
const OFFSET_FADES_HOURS = 8;
/// A gap wider than this is not the model's error: it is another air mass or
/// a broken sensor, and correcting by it would invent weather.
const MAX_TEMPERATURE_OFFSET = 8;
/// The aerodrome's last days are read again after this long: it reports once
/// an hour.
const HISTORY_REFRESH_MS = 50 * 60 * 1000;
const HOUR_MS = 60 * 60 * 1000;
/// Under this, in metres per second, every wind is a light air: the ratio of
/// two light airs says nothing about the place.
const WIND_FLOOR = 1.5;
/// A measured wind this many times the forecast's is one gust in one report.
const MAX_WIND_RATIO = 2.5;
/// The forecast's wind is never stretched or shrunk beyond these.
const MIN_WIND_SCALE = 0.15;
const MAX_WIND_SCALE = 2;
/// How wind differs today from the place's usual error holds for less time
/// than a temperature gap does.
const WIND_FADES_HOURS = 6;
/// Fewer readings than this teach nothing about a place.
const MIN_PAIRED_READINGS = 3;
/// Readings count for the hours of the day next to their own: full at the
/// same hour, a third two hours away, nothing four hours away.
const NEAR_HOURS_OF_DAY = 1.5;
/// What the readings near an hour must outweigh to move it away from the
/// place's overall error, and what all of them must outweigh to say the
/// forecast errs at all.
const NEAR_PRIOR = 1;
const OVERALL_PRIOR = 2;

export type WeatherLocation = {
  latitude: number;
  longitude: number;
  name: string | null;
  /// Set for a place a person added; the shop's own place has none.
  id?: string | null;
  region?: string | null;
  /// IANA zone of the place: its hours are read on that clock.
  time_zone?: string | null;
};

export type WeatherPayload = {
  schema: number;
  series: WeatherSeries;
  observation: WeatherObservation | null;
  /// The aerodrome's last days next to what the forecast had said for them.
  /// Rows kept before 2026-11-13 have none.
  history?: WeatherHistory | null;
};

export type WeatherCacheRow = {
  latitude: number;
  longitude: number;
  payload: WeatherPayload;
  source_last_modified: string | null;
  fetched_at: string;
  checked_at: string;
  expires_at: string;
};

export type UpstreamAnswer = {
  status: number;
  expires: string | null;
  lastModified: string | null;
  /// Parsed body of a 200; null otherwise.
  body: unknown;
};

export type WeatherDeps = {
  now: () => Date;
  readSettings: (tenantId: string) => Promise<Record<string, string>>;
  /// The kept forecast of one place of the shop (`shop` is its own).
  readCache: (tenantId: string, placeKey: string) => Promise<WeatherCacheRow | null>;
  /// True for the one caller allowed to refresh an expired row.
  claimRefresh: (
    tenantId: string,
    now: Date,
    claimsBefore: Date,
    placeKey: string,
  ) => Promise<boolean>;
  /// Writes the row and releases its claim.
  saveCache: (tenantId: string, row: WeatherCacheRow, placeKey: string) => Promise<void>;
  fetchForecast: (url: string, ifModifiedSince: string | null) => Promise<UpstreamAnswer>;
  /// The latest METARs inside a `south,west,north,east` box.
  fetchObservations: (box: string) => Promise<unknown>;
  /// One aerodrome's METARs of the last `HISTORY_HOURS`.
  fetchStationReports: (station: string) => Promise<unknown>;
};

export type WeatherResponse = {
  status: number;
  body: Record<string, unknown>;
};

const LATITUDE = /^-?[0-9]{1,2}(\.[0-9]{1,8})?$/;
const LONGITUDE = /^-?[0-9]{1,3}(\.[0-9]{1,8})?$/;

function fourDecimals(value: number): number {
  return Math.round(value * 10000) / 10000;
}

/// The shop's place, from the coordinates its Google listing left in the site
/// settings. Null when they are absent or not a real place.
export function parseWeatherLocation(
  settings: Record<string, string | null | undefined>,
): WeatherLocation | null {
  const rawLatitude = (settings.seo_geo_latitude ?? "").trim();
  const rawLongitude = (settings.seo_geo_longitude ?? "").trim();
  if (!LATITUDE.test(rawLatitude) || !LONGITUDE.test(rawLongitude)) return null;
  const latitude = fourDecimals(Number(rawLatitude));
  const longitude = fourDecimals(Number(rawLongitude));
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return null;
  if (Math.abs(latitude) > 90 || Math.abs(longitude) > 180) return null;
  if (latitude === 0 && longitude === 0) return null;
  const name = (settings.seo_address_city ?? "").trim();
  return { latitude, longitude, name: name.length > 0 ? name.slice(0, 80) : null };
}

export function weatherUpstreamUrl(location: WeatherLocation): string {
  return `${MET_ENDPOINT}?lat=${location.latitude.toFixed(4)}&lon=${location.longitude.toFixed(4)}`;
}

/// When MET allows the next request: its `Expires`, kept inside sane bounds so
/// a missing or absurd header can neither hammer the service nor freeze the
/// forecast for a day.
export function resolveWeatherExpiry(expiresHeader: string | null, now: Date): Date {
  const parsed = expiresHeader ? Date.parse(expiresHeader) : Number.NaN;
  const wanted = Number.isFinite(parsed) ? parsed - now.getTime() : DEFAULT_FRESH_MS;
  const bounded = Math.min(Math.max(wanted, MIN_FRESH_MS), MAX_FRESH_MS);
  return new Date(now.getTime() + bounded);
}

/// A value of the series at an instant, read between the two steps around it.
function valueAt(
  steps: WeatherStep[],
  at: number,
  pick: (step: WeatherStep) => number | null,
): number | null {
  if (steps.length === 0) return null;
  const start = Date.parse(steps[0].time);
  // A measurement taken shortly before the series starts still meets it.
  if (at < start) return start - at <= 90 * 60 * 1000 ? pick(steps[0]) : null;
  for (let index = 0; index < steps.length; index++) {
    const from = Date.parse(steps[index].time);
    if (index + 1 === steps.length) return at === from ? pick(steps[index]) : null;
    const to = Date.parse(steps[index + 1].time);
    if (at > to) continue;
    const first = pick(steps[index]);
    const second = pick(steps[index + 1]);
    if (first === null || second === null || to === from) return first ?? second;
    return first + (second - first) * (at - from) / (to - from);
  }
  return null;
}

/// A value of the hourly part of a series at an instant. Null where the
/// series has thinned out to six-hour steps or does not reach: a reading is
/// only set next to a forecast made for its own hour.
function hourlyValueAt(
  steps: WeatherStep[],
  at: number,
  pick: (step: WeatherStep) => number | null,
): number | null {
  if (steps.length === 0) return null;
  const start = Date.parse(steps[0].time);
  // A report sent a few minutes before the hour belongs to that hour.
  if (at < start) return start - at <= 30 * 60 * 1000 ? pick(steps[0]) : null;
  for (let index = 0; index + 1 < steps.length; index++) {
    const from = Date.parse(steps[index].time);
    const to = Date.parse(steps[index + 1].time);
    if (at > to) continue;
    if (to - from > HOUR_MS) return null;
    const first = pick(steps[index]);
    const second = pick(steps[index + 1]);
    if (first === null || second === null || to === from) return first ?? second;
    return first + (second - first) * (at - from) / (to - from);
  }
  return null;
}

/// The aerodrome's last days, each reading next to what the forecast had said
/// for it.
///
/// A reading keeps the first forecast it was set next to. A new reading takes
/// the first of [series] that covers its hour: the one kept before this read
/// (made hours before the reading, as the forecasts shown to people are), and
/// only then the one just fetched.
export function recordHistory(
  previous: WeatherHistory | null | undefined,
  station: string,
  readings: { time: string; temperature: number; wind_speed: number | null }[],
  series: (WeatherSeries | null)[],
  now: Date,
): WeatherHistory {
  const known = new Map<string, WeatherHistory["readings"][number]>();
  if (previous && previous.station === station && Array.isArray(previous.readings)) {
    for (const reading of previous.readings) known.set(reading.time, reading);
  }
  const modelled = (at: number, pick: (step: WeatherStep) => number | null) => {
    for (const item of series) {
      const value = item === null ? null : hourlyValueAt(item.steps, at, pick);
      if (value !== null) return Math.round(value * 10) / 10;
    }
    return null;
  };
  return {
    station,
    read_at: now.toISOString(),
    readings: readings.map((reading) => {
      const kept = known.get(reading.time);
      const at = Date.parse(reading.time);
      return {
        ...reading,
        model_temperature: kept?.model_temperature ??
          modelled(at, (step) => step.temperature),
        model_wind_speed: kept?.model_wind_speed ?? modelled(at, (step) => step.wind_speed),
      };
    }),
  };
}

/// The natural logarithm of how the measured wind compares with the
/// forecast's, with light airs levelled and one-off extremes held in.
function windRatioLog(measured: number, modelled: number): number {
  const ratio = Math.max(measured, WIND_FLOOR) / Math.max(modelled, WIND_FLOOR);
  return Math.log(Math.min(Math.max(ratio, MIN_WIND_SCALE), MAX_WIND_RATIO));
}

/// What a set of readings says around each hour of the day: their mean, each
/// counting for the hours next to its own, pulled towards the mean of all of
/// them where few are near and towards zero when there are few at all. Null
/// when there are too few to say anything.
function usualByHour(
  samples: { hour: number; value: number }[],
): ((hour: number) => number) | null {
  if (samples.length < MIN_PAIRED_READINGS) return null;
  const overall = samples.reduce((sum, sample) => sum + sample.value, 0) /
    (samples.length + OVERALL_PRIOR);
  return (hour) => {
    let weight = NEAR_PRIOR;
    let total = NEAR_PRIOR * overall;
    for (const sample of samples) {
      const apart = Math.abs(sample.hour - hour);
      const share = Math.exp(-((Math.min(apart, 24 - apart) / NEAR_HOURS_OF_DAY) ** 2));
      weight += share;
      total += share * sample.value;
    }
    return total / weight;
  };
}

function hourOfDay(at: number): number {
  return ((at / HOUR_MS) % 24 + 24) % 24;
}

/// How the forecast has erred at the place, hour of the day by hour of the
/// day, over the aerodrome's last days.
function learnFromHistory(history: WeatherHistory | null | undefined, now: Date) {
  const temperature: { hour: number; value: number }[] = [];
  const wind: { hour: number; value: number }[] = [];
  for (const reading of history?.readings ?? []) {
    const at = Date.parse(reading.time);
    if (!Number.isFinite(at) || now.getTime() - at > HISTORY_HOURS * HOUR_MS) continue;
    const hour = hourOfDay(at);
    if (reading.model_temperature !== null) {
      const gap = reading.model_temperature - reading.temperature;
      if (Math.abs(gap) <= MAX_TEMPERATURE_OFFSET) temperature.push({ hour, value: gap });
    }
    if (reading.wind_speed !== null && reading.model_wind_speed !== null) {
      wind.push({ hour, value: windRatioLog(reading.wind_speed, reading.model_wind_speed) });
    }
  }
  return { temperature: usualByHour(temperature), wind: usualByHour(wind) };
}

export type TiedForecast = {
  steps: WeatherStep[];
  /// How many degrees the forecast read over the measurement.
  temperature_offset: number;
  /// Whether the aerodrome's readings changed anything.
  adjusted: boolean;
  /// What the measurement feels like, by the forecast's own reckoning.
  apparent_temperature: number | null;
};

/// The forecast, tied to what the aerodrome measures.
///
/// Two things are known about the model's error at a place: what it reads
/// against the instrument right now, and what it has read against it at each
/// hour of the day over the last days ([history]). The usual error of each
/// hour is taken off that hour for as far as the series goes; how today
/// differs from the usual is taken off in full at the measurement and fades
/// over the next hours.
///
/// Temperature errs by degrees and wind by a factor: on a coast the model's
/// grid point is over open water, and its wind was two to five times the
/// measured one, differently by night and in the afternoon (Viña del Mar,
/// five days of reports, 2026-11-13). Without days of readings the wind keeps
/// the factor measured now: it is all that is known about the place.
export function tieForecastToObservation(
  steps: WeatherStep[],
  observation: WeatherObservation | null,
  history: WeatherHistory | null = null,
  now: Date = new Date(observation?.time ?? steps[0]?.time ?? 0),
): TiedForecast {
  const usual = learnFromHistory(history, now);
  const measuredAt = observation === null ? Number.NaN : Date.parse(observation.time);
  const modelled = observation === null
    ? null
    : valueAt(steps, measuredAt, (step) => step.temperature);
  if (modelled === null && usual.temperature === null && usual.wind === null) {
    return { steps, temperature_offset: 0, adjusted: false, apparent_temperature: null };
  }

  const usualGap = (at: number) => usual.temperature?.(hourOfDay(at)) ?? 0;
  const usualWind = (at: number) => usual.wind?.(hourOfDay(at)) ?? 0;

  const gap = modelled === null ? null : modelled - observation!.temperature;
  const measuredGap = gap !== null && Math.abs(gap) <= MAX_TEMPERATURE_OFFSET ? gap : null;
  const unusualGap = measuredGap === null ? 0 : measuredGap - usualGap(measuredAt);

  const modelledWind = modelled === null
    ? null
    : valueAt(steps, measuredAt, (step) => step.wind_speed);
  const measuredWind = observation?.wind_speed ?? null;
  const measuredRatio = measuredWind === null || modelledWind === null
    ? null
    : windRatioLog(measuredWind, modelledWind);
  const unusualWind = measuredRatio === null ? 0 : measuredRatio - usualWind(measuredAt);

  const modelledApparent = modelled === null
    ? null
    : valueAt(steps, measuredAt, (step) => step.apparent_temperature);

  const shift = (value: number | null, by: number) =>
    value === null ? null : Math.round((value - by) * 10) / 10;
  const sinceMeasured = (at: number) =>
    modelled === null ? 0 : Math.max(0, (at - measuredAt) / HOUR_MS);
  const offsetAt = (at: number) =>
    Math.min(
      MAX_TEMPERATURE_OFFSET,
      Math.max(
        -MAX_TEMPERATURE_OFFSET,
        usualGap(at) +
          unusualGap * Math.exp(-((sinceMeasured(at) / OFFSET_FADES_HOURS) ** 2)),
      ),
    );
  const tied = steps.map((step) => {
    const at = Date.parse(step.time);
    const by = offsetAt(at);
    // The extremes of a six-hour step fall somewhere inside it: they take the
    // mean offset of its hours, not the one of its first instant.
    const spanHours = Math.round(step.span_minutes / 60);
    let across = by;
    if (spanHours > 1) {
      across = 0;
      for (let hour = 0; hour <= spanHours; hour++) across += offsetAt(at + hour * HOUR_MS);
      across /= spanHours + 1;
    }
    const windFade = usual.wind === null
      ? 1
      : Math.exp(-((sinceMeasured(at) / WIND_FADES_HOURS) ** 2));
    const scale = Math.min(
      MAX_WIND_SCALE,
      Math.max(MIN_WIND_SCALE, Math.exp(usualWind(at) + unusualWind * windFade)),
    );
    return {
      ...step,
      temperature: shift(step.temperature, by)!,
      apparent_temperature: shift(step.apparent_temperature, by),
      span_min_temperature: shift(step.span_min_temperature, across),
      span_max_temperature: shift(step.span_max_temperature, across),
      wind_speed: step.wind_speed === null ? null : Math.round(step.wind_speed * scale * 10) / 10,
    };
  });
  return {
    steps: tied,
    temperature_offset: Math.round((measuredGap ?? 0) * 10) / 10,
    adjusted: true,
    apparent_temperature: modelledApparent === null || modelled === null
      ? null
      : Math.round((observation!.temperature + (modelledApparent - modelled)) * 10) / 10,
  };
}

/// The document the ERP draws, as of [now].
export function composeWeatherDocument(
  location: WeatherLocation,
  row: WeatherCacheRow,
  now: Date,
  flags: { stale: boolean; expiresAt?: string },
): Record<string, unknown> {
  const kept = row.payload.observation;
  const age = kept === null ? Number.NaN : now.getTime() - Date.parse(kept.time);
  const observation = kept !== null && age <= MAX_OBSERVATION_AGE_MS ? kept : null;
  const history = row.payload.history ?? null;
  const tied = tieForecastToObservation(row.payload.series.steps, observation, history, now);
  // What already ended is not forecast; the step that holds «now» stays.
  const from = now.getTime() - 60 * 60 * 1000;
  const steps = tied.steps.filter((step, index) =>
    index === tied.steps.length - 1 ||
    Date.parse(step.time) + step.span_minutes * 60000 > from
  );
  return {
    status: "ok",
    schema: WEATHER_SCHEMA,
    place: {
      id: location.id ?? null,
      name: location.name,
      region: location.region ?? null,
      latitude: location.latitude,
      longitude: location.longitude,
      time_zone: location.time_zone ?? null,
      // The clock of the place over these steps, so the app needs no zone
      // table of its own.
      offsets: zoneOffsets(location.time_zone ?? null, [
        now.toISOString(),
        ...steps.map((step) => step.time),
      ]),
    },
    source: {
      model_updated_at: row.payload.series.model_updated_at,
      checked_at: row.checked_at,
      expires_at: flags.expiresAt ?? row.expires_at,
      stale: flags.stale,
      credits: [
        { name: "MET Norway", url: "https://www.met.no/en" },
        ...(observation === null
          ? []
          : [{ name: "NOAA Aviation Weather Center", url: "https://aviationweather.gov/" }]),
      ],
    },
    observation: observation === null ? null : {
      ...observation,
      wind_speed: observation.wind_speed === null
        ? null
        : Math.round(observation.wind_speed * 10) / 10,
      wind_gust: observation.wind_gust === null
        ? null
        : Math.round(observation.wind_gust * 10) / 10,
      humidity: observation.humidity === null ? null : Math.round(observation.humidity),
      apparent_temperature: tied.apparent_temperature,
    },
    // The aerodrome whose readings corrected the forecast, when any did.
    adjusted_with: tied.adjusted ? (observation?.station ?? history?.station ?? null) : null,
    steps,
  };
}

function sameLocation(row: WeatherCacheRow | null, location: WeatherLocation): boolean {
  return row !== null && row.payload?.schema === WEATHER_SCHEMA &&
    Array.isArray(row.payload.series?.steps) && row.payload.series.steps.length > 0 &&
    Math.abs(Number(row.latitude) - location.latitude) < 0.00005 &&
    Math.abs(Number(row.longitude) - location.longitude) < 0.00005;
}

export const SHOP_PLACE_KEY = "shop";

export async function loadShopWeather(
  deps: WeatherDeps,
  tenantId: string,
): Promise<WeatherResponse> {
  return await loadPlaceWeather(
    deps,
    tenantId,
    SHOP_PLACE_KEY,
    parseWeatherLocation(await deps.readSettings(tenantId)),
  );
}

/// The weather of one place of a shop: its own (`shop`) or one a person
/// added. Each keeps its forecast under its own key.
export async function loadPlaceWeather(
  deps: WeatherDeps,
  tenantId: string,
  placeKey: string,
  location: WeatherLocation | null,
): Promise<WeatherResponse> {
  if (location === null) {
    return { status: 200, body: { status: "location_missing" } };
  }

  const now = deps.now();
  const cached = await deps.readCache(tenantId, placeKey);
  const known = sameLocation(cached, location) ? cached : null;

  if (known !== null && Date.parse(known.expires_at) > now.getTime()) {
    return { status: 200, body: composeWeatherDocument(location, known, now, { stale: false }) };
  }

  if (known !== null) {
    const claimed = await deps.claimRefresh(
      tenantId,
      now,
      new Date(now.getTime() - CLAIM_TTL_MS),
      placeKey,
    );
    if (!claimed) {
      // Someone else is asking right now: what is in hand is minutes old at
      // worst, and the caller comes back for the new one.
      return {
        status: 200,
        body: composeWeatherDocument(location, known, now, {
          stale: false,
          expiresAt: new Date(now.getTime() + CLAIM_RETRY_MS).toISOString(),
        }),
      };
    }
  }

  let upstream: UpstreamAnswer | null = null;
  try {
    upstream = await deps.fetchForecast(
      weatherUpstreamUrl(location),
      known?.source_last_modified ?? null,
    );
  } catch (error) {
    console.error("[weather-forecast] forecast request failed", error);
  }

  const fresh = upstream !== null && upstream.status === 200
    ? normalizeMetForecast(upstream.body)
    : null;
  const unchanged = upstream !== null && upstream.status === 304 && known !== null;
  const series = fresh ?? known?.payload.series ?? null;
  if (series === null) {
    if (upstream !== null) console.error("[weather-forecast] forecast answered", upstream.status);
    const retryAt = new Date(now.getTime() + FAILURE_BACKOFF_MS).toISOString();
    return { status: 502, body: { status: "unavailable", retry_at: retryAt } };
  }
  const confirmed = fresh !== null || unchanged;
  if (!confirmed && upstream !== null) {
    console.error("[weather-forecast] forecast answered", upstream.status);
  }

  // The measurement is a courtesy to the forecast: without it the forecast
  // still stands, and the last one kept serves while it is recent.
  let observation = known?.payload.observation ?? null;
  try {
    const picked = pickObservation(
      await deps.fetchObservations(observationBox(location.latitude, location.longitude)),
      { latitude: location.latitude, longitude: location.longitude, elevation: series.elevation },
      now,
    );
    if (picked !== null) observation = picked;
  } catch (error) {
    console.error("[weather-forecast] observation request failed", error);
  }

  // The aerodrome's last days teach how the forecast errs at this place.
  let history = known?.payload.history ?? null;
  const station = observation?.station ?? history?.station ?? null;
  if (
    station !== null &&
    (history === null || history.station !== station ||
      now.getTime() - Date.parse(history.read_at) >= HISTORY_REFRESH_MS)
  ) {
    try {
      history = recordHistory(
        history,
        station,
        stationReadings(await deps.fetchStationReports(station), station, now),
        [known?.payload.series ?? null, series],
        now,
      );
    } catch (error) {
      console.error("[weather-forecast] history request failed", error);
    }
  }

  const row: WeatherCacheRow = {
    latitude: location.latitude,
    longitude: location.longitude,
    payload: { schema: WEATHER_SCHEMA, series, observation, history },
    source_last_modified: fresh !== null
      ? upstream!.lastModified
      : (known?.source_last_modified ?? null),
    fetched_at: fresh !== null ? now.toISOString() : known!.fetched_at,
    // The last time MET confirmed the forecast: a failed read leaves it
    // alone, so the app can say how old the forecast really is.
    checked_at: confirmed ? now.toISOString() : known!.checked_at,
    expires_at: confirmed
      ? resolveWeatherExpiry(upstream!.expires, now).toISOString()
      : new Date(now.getTime() + FAILURE_BACKOFF_MS).toISOString(),
  };
  await deps.saveCache(tenantId, row, placeKey);
  return {
    status: 200,
    body: composeWeatherDocument(location, row, now, { stale: !confirmed }),
  };
}
