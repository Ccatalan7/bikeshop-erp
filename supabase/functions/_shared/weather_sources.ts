// The two readings the shop's weather is made of, each turned into the
// provider-neutral shapes the ERP draws:
//
// - the forecast of MET Norway's Locationforecast (ECMWF's model), and
// - what the nearest aerodrome measured in its last METAR, from NOAA's
//   Aviation Weather Center.
//
// Why two (measured for Viña del Mar on 2026-11-12, against five days of
// METARs): on a coast the model's grid point is not the town. MET's wind was
// about three times the measured one, hour after hour, and its evening
// temperature up to four degrees over. A measurement is the truth of «now»,
// so it leads, and `weather_forecast.ts` ties the first hours of the forecast
// to it.

export type WeatherStep = {
  /// ISO instant, UTC.
  time: string;
  /// Until the next step; 0 on the last one.
  span_minutes: number;
  temperature: number;
  apparent_temperature: number | null;
  /// Metres per second.
  wind_speed: number | null;
  wind_from_direction: number | null;
  humidity: number | null;
  uv_index: number | null;
  /// The sky over the span, in MET's composable symbol names.
  symbol: string | null;
  /// Millimetres over the span.
  precipitation: number;
  span_min_temperature: number | null;
  span_max_temperature: number | null;
  /// The sky over the twelve hours from `time`.
  half_day_symbol: string | null;
};

export type WeatherSeries = {
  model_updated_at: string | null;
  /// Metres above sea level the provider assumes for the place.
  elevation: number | null;
  steps: WeatherStep[];
};

export type WeatherObservation = {
  time: string;
  /// ICAO code of the aerodrome.
  station: string;
  distance_km: number;
  temperature: number;
  wind_speed: number | null;
  wind_from_direction: number | null;
  wind_gust: number | null;
  humidity: number | null;
  /// As a MET symbol name without its day or night ending.
  symbol: string;
};

/// What an aerodrome measured at one instant of the last days, next to what
/// the forecast had said for that instant when one covered it.
export type WeatherPastReading = {
  /// ISO instant of the report, UTC.
  time: string;
  temperature: number;
  /// Metres per second.
  wind_speed: number | null;
  model_temperature: number | null;
  model_wind_speed: number | null;
};

/// The last days of one aerodrome: how the forecast errs at the place is
/// learned from them (`weather_forecast.ts`).
export type WeatherHistory = {
  station: string;
  /// When the aerodrome's reports were last read.
  read_at: string;
  readings: WeatherPastReading[];
};

/// How far back an aerodrome's reports are read: five days show every hour of
/// the day several times.
export const HISTORY_HOURS = 120;
/// Aerodromes that report every few minutes are not kept report by report.
const MAX_READINGS = 400;

const KNOT = 0.514444;
/// An aerodrome farther than this is another place.
export const MAX_STATION_KM = 30;
/// A report older than this no longer says what «now» is.
export const MAX_OBSERVATION_AGE_MS = 100 * 60 * 1000;
/// A hundred metres of height weigh like four kilometres of distance: the
/// hilltop field next door is a worse witness than the one down the coast.
const METRES_PER_KM_OF_DISTANCE = 25;

function record(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function finite(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function text(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : null;
}

/// MET's Locationforecast 2.0 document as a series. Null when it holds none.
export function normalizeMetForecast(document: unknown): WeatherSeries | null {
  const properties = record(record(document)?.properties);
  const timeseries = properties?.timeseries;
  if (!Array.isArray(timeseries)) return null;

  const raw: { at: number; instant: Record<string, unknown>; data: Record<string, unknown> }[] = [];
  for (const entry of timeseries) {
    const item = record(entry);
    const at = Date.parse(text(item?.time) ?? "");
    const data = record(item?.data);
    const instant = record(record(data?.instant)?.details);
    if (!Number.isFinite(at) || data === null || instant === null) continue;
    if (finite(instant.air_temperature) === null) continue;
    raw.push({ at, instant, data });
  }
  if (raw.length === 0) return null;
  raw.sort((a, b) => a.at - b.at);

  const steps: WeatherStep[] = raw.map((current, index) => {
    const span = index + 1 < raw.length ? Math.round((raw[index + 1].at - current.at) / 60000) : 0;
    const hourly = record(current.data.next_1_hours);
    const sixHourly = record(current.data.next_6_hours);
    // The summary that matches the step: the hour while the series is hourly,
    // the six hours once it thins out.
    const summary = span <= 60 && hourly !== null ? hourly : (sixHourly ?? hourly);
    const details = record(summary?.details);
    return {
      time: new Date(current.at).toISOString(),
      span_minutes: span,
      temperature: finite(current.instant.air_temperature)!,
      apparent_temperature: finite(current.instant.apparent_air_temperature),
      wind_speed: finite(current.instant.wind_speed),
      wind_from_direction: finite(current.instant.wind_from_direction),
      humidity: finite(current.instant.relative_humidity),
      uv_index: finite(current.instant.ultraviolet_index_clear_sky),
      symbol: text(record(summary?.summary)?.symbol_code),
      precipitation: Math.max(0, finite(details?.precipitation_amount) ?? 0),
      span_min_temperature: finite(details?.air_temperature_min),
      span_max_temperature: finite(details?.air_temperature_max),
      half_day_symbol: text(record(record(current.data.next_12_hours)?.summary)?.symbol_code),
    };
  });

  const coordinates = record(record(document)?.geometry)?.coordinates;
  return {
    model_updated_at: text(record(properties?.meta)?.updated_at),
    elevation: Array.isArray(coordinates) ? finite(coordinates[2]) : null,
    steps,
  };
}

/// The box of aerodromes worth asking about around a place, as the Aviation
/// Weather Center takes it: south, west, north, east.
export function observationBox(latitude: number, longitude: number): string {
  const latitudeSpan = MAX_STATION_KM / 111.2;
  const longitudeSpan = latitudeSpan /
    Math.max(0.2, Math.cos(latitude * Math.PI / 180));
  return [
    latitude - latitudeSpan,
    longitude - longitudeSpan,
    latitude + latitudeSpan,
    longitude + longitudeSpan,
  ].map((value) => value.toFixed(2)).join(",");
}

function kilometresBetween(
  latitudeA: number,
  longitudeA: number,
  latitudeB: number,
  longitudeB: number,
): number {
  const radians = Math.PI / 180;
  const a = Math.sin((latitudeB - latitudeA) * radians / 2) ** 2 +
    Math.cos(latitudeA * radians) * Math.cos(latitudeB * radians) *
      Math.sin((longitudeB - longitudeA) * radians / 2) ** 2;
  return 2 * 6371 * Math.asin(Math.sqrt(a));
}

/// Relative humidity from the air and dew point temperatures (Magnus).
function humidityFrom(temperature: number, dewPoint: number): number {
  const saturation = (value: number) => Math.exp(17.625 * value / (243.04 + value));
  return Math.min(100, Math.max(0, 100 * saturation(dewPoint) / saturation(temperature)));
}

/// What a METAR says about the sky, in MET's symbol names. The words of the
/// report decide: its weather group first, then its densest cloud layer.
export function symbolFromMetar(report: Record<string, unknown>): string {
  const weather = (text(report.wxString) ?? "").toUpperCase().split(/\s+/).filter(Boolean);
  const said = (code: string) => weather.some((token) => token.includes(code));
  const thunder = said("TS") ? "andthunder" : "";
  const showers = said("SH") ? "showers" : "";
  const kind = said("SN") && said("RA") || said("PL") || said("GR") || said("GS")
    ? "sleet"
    : said("SN") || said("SG")
    ? "snow"
    : said("RA") || said("DZ")
    ? "rain"
    : "";
  if (kind !== "") {
    const wet = weather.filter((token) => /RA|DZ|SN|SG|PL|GR|GS/.test(token));
    const strength = wet.some((token) => token.startsWith("+"))
      ? "heavy"
      : wet.every((token) => token.startsWith("-") || token.includes("DZ"))
      ? "light"
      : "";
    return `${strength}${kind}${showers}${thunder}`;
  }
  if (thunder !== "") return "rainandthunder";
  if (said("FG") || said("BR")) return "fog";

  const covers = Array.isArray(report.clouds)
    ? report.clouds.map((layer) => (text(record(layer)?.cover) ?? "").toUpperCase())
    : [];
  if (covers.some((cover) => cover === "OVC" || cover === "BKN" || cover === "VV")) {
    return "cloudy";
  }
  if (covers.includes("SCT")) return "partlycloudy";
  if (covers.includes("FEW")) return "fair";
  return "clearsky";
}

/// The measurement that best says what «now» is at the place: among the
/// aerodromes around it that reported lately, the nearest one, with height
/// counted as distance.
export function pickObservation(
  reports: unknown,
  place: { latitude: number; longitude: number; elevation: number | null },
  now: Date,
): WeatherObservation | null {
  if (!Array.isArray(reports)) return null;
  let best: { score: number; at: number; observation: WeatherObservation } | null = null;
  for (const entry of reports) {
    const report = record(entry);
    const station = text(report?.icaoId);
    const at = Date.parse(text(report?.reportTime) ?? "");
    const temperature = finite(report?.temp);
    const latitude = finite(report?.lat);
    const longitude = finite(report?.lon);
    if (
      report === null || station === null || !Number.isFinite(at) || temperature === null ||
      latitude === null || longitude === null
    ) continue;
    const age = now.getTime() - at;
    if (age < -10 * 60 * 1000 || age > MAX_OBSERVATION_AGE_MS) continue;
    const distance = kilometresBetween(place.latitude, place.longitude, latitude, longitude);
    if (distance > MAX_STATION_KM) continue;
    const height = finite(report.elev);
    const score = distance +
      (height === null || place.elevation === null
        ? 0
        : Math.abs(height - place.elevation) / METRES_PER_KM_OF_DISTANCE);
    // The latest report of the best-placed aerodrome.
    if (
      best !== null &&
      (score > best.score + 0.001 || (Math.abs(score - best.score) <= 0.001 && at <= best.at))
    ) continue;
    const dewPoint = finite(report.dewp);
    const speed = finite(report.wspd);
    const gust = finite(report.wgst);
    best = {
      score,
      at,
      observation: {
        time: new Date(at).toISOString(),
        station,
        distance_km: Math.round(distance * 10) / 10,
        temperature,
        wind_speed: speed === null ? null : speed * KNOT,
        // A calm or variable wind comes from nowhere in particular.
        wind_from_direction: speed === null || speed === 0 ? null : finite(report.wdir),
        wind_gust: gust === null ? null : gust * KNOT,
        humidity: dewPoint === null ? null : humidityFrom(temperature, dewPoint),
        symbol: symbolFromMetar(report),
      },
    };
  }
  return best?.observation ?? null;
}

/// One aerodrome's reports of the last days as plain readings, oldest first
/// and one per instant.
export function stationReadings(
  reports: unknown,
  station: string,
  now: Date,
): { time: string; temperature: number; wind_speed: number | null }[] {
  if (!Array.isArray(reports)) return [];
  const byInstant = new Map<number, { temperature: number; wind_speed: number | null }>();
  for (const entry of reports) {
    const report = record(entry);
    if (report === null || text(report.icaoId) !== station) continue;
    const at = Date.parse(text(report.reportTime) ?? "");
    const temperature = finite(report.temp);
    if (!Number.isFinite(at) || temperature === null) continue;
    const age = now.getTime() - at;
    if (age < -10 * 60 * 1000 || age > HISTORY_HOURS * 60 * 60 * 1000) continue;
    const speed = finite(report.wspd);
    byInstant.set(at, {
      temperature,
      wind_speed: speed === null ? null : Math.round(speed * KNOT * 10) / 10,
    });
  }
  return [...byInstant.entries()]
    .sort((first, second) => first[0] - second[0])
    .slice(-MAX_READINGS)
    .map(([at, reading]) => ({ time: new Date(at).toISOString(), ...reading }));
}
