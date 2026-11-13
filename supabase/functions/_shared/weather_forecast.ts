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
  MAX_OBSERVATION_AGE_MS,
  normalizeMetForecast,
  observationBox,
  pickObservation,
  type WeatherObservation,
  type WeatherSeries,
  type WeatherStep,
} from "./weather_sources.ts";

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

export type WeatherLocation = {
  latitude: number;
  longitude: number;
  name: string | null;
};

export type WeatherPayload = {
  schema: number;
  series: WeatherSeries;
  observation: WeatherObservation | null;
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
  readCache: (tenantId: string) => Promise<WeatherCacheRow | null>;
  /// True for the one caller allowed to refresh an expired row.
  claimRefresh: (tenantId: string, now: Date, claimsBefore: Date) => Promise<boolean>;
  /// Writes the row and releases its claim.
  saveCache: (tenantId: string, row: WeatherCacheRow) => Promise<void>;
  fetchForecast: (url: string, ifModifiedSince: string | null) => Promise<UpstreamAnswer>;
  /// The latest METARs inside a `south,west,north,east` box.
  fetchObservations: (box: string) => Promise<unknown>;
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

export type TiedForecast = {
  steps: WeatherStep[];
  /// How many degrees the forecast read over the measurement.
  temperature_offset: number;
  /// False when the forecast's wind and the measured one are different winds.
  wind_trusted: boolean;
  /// What the measurement feels like, by the forecast's own reckoning.
  apparent_temperature: number | null;
};

/// The forecast, tied to what was just measured.
///
/// The model's error at the place is what it reads against the instrument
/// right now. That error is taken off the temperature in full at the
/// measurement and fades over the next hours, when the model stands alone
/// again. Wind is not a matter of degree: a forecast that doubles or halves
/// the measured wind is describing another wind, and saying nothing about the
/// next hours' wind is better than saying that.
export function tieForecastToObservation(
  steps: WeatherStep[],
  observation: WeatherObservation | null,
): TiedForecast {
  const untouched = {
    steps,
    temperature_offset: 0,
    wind_trusted: true,
    apparent_temperature: null,
  };
  if (observation === null) return untouched;
  const measuredAt = Date.parse(observation.time);
  const modelled = valueAt(steps, measuredAt, (step) => step.temperature);
  if (modelled === null) return untouched;

  const gap = modelled - observation.temperature;
  const offset = Math.abs(gap) > MAX_TEMPERATURE_OFFSET ? 0 : gap;
  const modelledWind = valueAt(steps, measuredAt, (step) => step.wind_speed);
  const measuredWind = observation.wind_speed;
  // Below two metres per second everything is a light air, whatever its ratio.
  const windTrusted = measuredWind === null || modelledWind === null ||
    (modelledWind <= 2 * Math.max(measuredWind, 2) &&
      measuredWind <= 2 * Math.max(modelledWind, 2));
  const modelledApparent = valueAt(steps, measuredAt, (step) => step.apparent_temperature);

  const shift = (value: number | null, by: number) =>
    value === null ? null : Math.round((value - by) * 10) / 10;
  const tied = steps.map((step) => {
    const hours = Math.max(0, (Date.parse(step.time) - measuredAt) / 3600000);
    const by = offset * Math.exp(-((hours / OFFSET_FADES_HOURS) ** 2));
    return {
      ...step,
      temperature: shift(step.temperature, by)!,
      apparent_temperature: shift(step.apparent_temperature, by),
      span_min_temperature: shift(step.span_min_temperature, by),
      span_max_temperature: shift(step.span_max_temperature, by),
      wind_speed: windTrusted ? step.wind_speed : null,
      wind_from_direction: windTrusted ? step.wind_from_direction : null,
    };
  });
  return {
    steps: tied,
    temperature_offset: Math.round(offset * 10) / 10,
    wind_trusted: windTrusted,
    apparent_temperature: modelledApparent === null
      ? null
      : Math.round((observation.temperature + (modelledApparent - modelled)) * 10) / 10,
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
  const tied = tieForecastToObservation(row.payload.series.steps, observation);
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
      name: location.name,
      latitude: location.latitude,
      longitude: location.longitude,
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
    wind_trusted: tied.wind_trusted,
    steps,
  };
}

function sameLocation(row: WeatherCacheRow | null, location: WeatherLocation): boolean {
  return row !== null && row.payload?.schema === WEATHER_SCHEMA &&
    Array.isArray(row.payload.series?.steps) && row.payload.series.steps.length > 0 &&
    Math.abs(Number(row.latitude) - location.latitude) < 0.00005 &&
    Math.abs(Number(row.longitude) - location.longitude) < 0.00005;
}

export async function loadShopWeather(
  deps: WeatherDeps,
  tenantId: string,
): Promise<WeatherResponse> {
  const location = parseWeatherLocation(await deps.readSettings(tenantId));
  if (location === null) {
    return { status: 200, body: { status: "location_missing" } };
  }

  const now = deps.now();
  const cached = await deps.readCache(tenantId);
  const known = sameLocation(cached, location) ? cached : null;

  if (known !== null && Date.parse(known.expires_at) > now.getTime()) {
    return { status: 200, body: composeWeatherDocument(location, known, now, { stale: false }) };
  }

  if (known !== null) {
    const claimed = await deps.claimRefresh(
      tenantId,
      now,
      new Date(now.getTime() - CLAIM_TTL_MS),
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

  const row: WeatherCacheRow = {
    latitude: location.latitude,
    longitude: location.longitude,
    payload: { schema: WEATHER_SCHEMA, series, observation },
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
  await deps.saveCache(tenantId, row);
  return {
    status: 200,
    body: composeWeatherDocument(location, row, now, { stale: !confirmed }),
  };
}
