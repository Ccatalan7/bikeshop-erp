// The places of the weather tab besides the shop: finding one by name, the
// clock it lives on, and the key its kept forecast goes under.
//
// Names are searched in OpenStreetMap's Nominatim. Its usage policy (read on
// 2026-11-13) allows light use that names who asks and forbids searching on
// every keystroke, so the app searches when the person submits. A place's
// zone comes from its coordinates, with the public-domain `tz-lookup` table:
// the app shows every hour on the clock of the place, not of the device.
// @ts-ignore: the package ships no type declarations.
import tzlookupUntyped from "https://esm.sh/tz-lookup@6.1.25";

const tzlookup = tzlookupUntyped as (latitude: number, longitude: number) => string;

export const MAX_PLACES_PER_PERSON = 8;

export type PlaceMatch = {
  name: string;
  region: string | null;
  latitude: number;
  longitude: number;
};

function fourDecimals(value: number): number {
  return Math.round(value * 10000) / 10000;
}

/// The key of a place's kept forecast: the same place added by two people of
/// a shop is asked once.
export function placeKey(latitude: number, longitude: number): string {
  return `${fourDecimals(latitude).toFixed(4)},${fourDecimals(longitude).toFixed(4)}`;
}

/// The IANA zone at a point; null where the table has none.
export function zoneOf(latitude: number, longitude: number): string | null {
  try {
    const zone = tzlookup(latitude, longitude);
    return typeof zone === "string" && zone.length > 0 ? zone : null;
  } catch (_) {
    return null;
  }
}

/// Minutes east of UTC on the clock of [timeZone] at [instant].
export function zoneOffsetMinutes(timeZone: string, instant: Date): number | null {
  try {
    const parts = new Intl.DateTimeFormat("en-US", {
      timeZone,
      hourCycle: "h23",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
    }).formatToParts(instant);
    const read = (type: string) => Number(parts.find((part) => part.type === type)?.value);
    const wall = Date.UTC(
      read("year"),
      read("month") - 1,
      read("day"),
      read("hour"),
      read("minute"),
      read("second"),
    );
    if (!Number.isFinite(wall)) return null;
    return Math.round((wall - Math.floor(instant.getTime() / 1000) * 1000) / 60000);
  } catch (_) {
    return null;
  }
}

/// The offsets of [timeZone] over [instants], as the changes only: one entry
/// while the clock does not change, two across a daylight-saving switch.
export function zoneOffsets(
  timeZone: string | null,
  instants: readonly string[],
): { from: string; minutes: number }[] {
  if (timeZone === null) return [];
  const offsets: { from: string; minutes: number }[] = [];
  for (const instant of instants) {
    const at = new Date(instant);
    if (Number.isNaN(at.getTime())) continue;
    const minutes = zoneOffsetMinutes(timeZone, at);
    if (minutes === null) return [];
    if (offsets.length === 0 || offsets[offsets.length - 1].minutes !== minutes) {
      offsets.push({ from: at.toISOString(), minutes });
    }
  }
  return offsets;
}

export function placeSearchUrl(query: string): string {
  const parameters = new URLSearchParams({
    q: query,
    format: "jsonv2",
    limit: "8",
    addressdetails: "1",
    "accept-language": "es",
  });
  return `https://nominatim.openstreetmap.org/search?${parameters}`;
}

function text(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : null;
}

/// Towns, cities and the like out of Nominatim's answer, without repeats.
export function normalizePlaceMatches(answer: unknown): PlaceMatch[] {
  if (!Array.isArray(answer)) return [];
  const matches: PlaceMatch[] = [];
  const seen = new Set<string>();
  for (const entry of answer) {
    if (entry === null || typeof entry !== "object") continue;
    const record = entry as Record<string, unknown>;
    const category = text(record.category) ?? text(record.class);
    if (category !== "place" && category !== "boundary") continue;
    const latitude = Number(record.lat);
    const longitude = Number(record.lon);
    if (
      !Number.isFinite(latitude) || !Number.isFinite(longitude) ||
      Math.abs(latitude) > 90 || Math.abs(longitude) > 180
    ) continue;
    const address = (record.address ?? {}) as Record<string, unknown>;
    const name = text(record.name) ?? text(address.city) ?? text(address.town) ??
      text(address.village) ?? text(address.municipality);
    if (name === null) continue;
    const region = [text(address.state) ?? text(address.region), text(address.country)]
      .filter((part): part is string => part !== null && part !== name)
      .join(", ");
    const key = `${name.toLowerCase()}|${region.toLowerCase()}`;
    if (seen.has(key)) continue;
    seen.add(key);
    matches.push({
      name: name.slice(0, 80),
      region: region.length > 0 ? region.slice(0, 120) : null,
      latitude: fourDecimals(latitude),
      longitude: fourDecimals(longitude),
    });
    if (matches.length === 6) break;
  }
  return matches;
}

/// A second door to the same OpenStreetMap names: Photon, for when Nominatim
/// turns the server away (it answered 502 to the function's first real
/// search, on 2026-11-13).
export function placeSearchFallbackUrl(query: string): string {
  const parameters = new URLSearchParams({ q: query, limit: "10" });
  return `https://photon.komoot.io/api/?${parameters}`;
}

/// Photon answers GeoJSON; this puts it in Nominatim's shape so one reader
/// serves both.
export function photonAsNominatim(answer: unknown): unknown[] {
  const features = (answer as { features?: unknown } | null)?.features;
  if (!Array.isArray(features)) return [];
  const entries: unknown[] = [];
  for (const feature of features) {
    const record = feature as {
      properties?: Record<string, unknown>;
      geometry?: { coordinates?: unknown };
    } | null;
    const properties = record?.properties;
    const coordinates = record?.geometry?.coordinates;
    if (!properties || !Array.isArray(coordinates) || coordinates.length < 2) continue;
    entries.push({
      category: properties.osm_key,
      name: properties.name,
      lat: String(coordinates[1]),
      lon: String(coordinates[0]),
      address: { state: properties.state, country: properties.country },
    });
  }
  return entries;
}
