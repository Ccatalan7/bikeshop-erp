import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  normalizePlaceMatches,
  photonAsNominatim,
  placeKey,
  zoneOf,
  zoneOffsets,
} from "./weather_places.ts";

Deno.test("a place is kept under its coordinates, four decimals", () => {
  assertEquals(placeKey(47.60383, -122.33006), "47.6038,-122.3301");
  assertEquals(placeKey(-33.0252, -71.5623), "-33.0252,-71.5623");
});

Deno.test("the zone of a place comes from where it is", () => {
  assertEquals(zoneOf(47.6038, -122.3301), "America/Los_Angeles");
  assertEquals(zoneOf(-33.0252, -71.5623), "America/Santiago");
});

Deno.test("offsets list only the changes of the place's clock", () => {
  assertEquals(
    zoneOffsets("America/Los_Angeles", ["2026-11-13T08:00:00Z", "2026-11-14T08:00:00Z"]),
    [{ from: "2026-11-13T08:00:00.000Z", minutes: -480 }],
  );
  // Seattle moves its clocks forward on 2027-03-14 at 10:00 UTC.
  assertEquals(
    zoneOffsets("America/Los_Angeles", [
      "2027-03-14T09:00:00Z",
      "2027-03-14T10:00:00Z",
      "2027-03-14T11:00:00Z",
    ]),
    [
      { from: "2027-03-14T09:00:00.000Z", minutes: -480 },
      { from: "2027-03-14T10:00:00.000Z", minutes: -420 },
    ],
  );
  assertEquals(zoneOffsets(null, ["2026-11-13T08:00:00Z"]), []);
  assertEquals(zoneOffsets("Not/AZone", ["2026-11-13T08:00:00Z"]), []);
});

Deno.test("a search keeps towns and cities, once each, in the app's shape", () => {
  const answer = [
    {
      category: "boundary",
      name: "Seattle",
      lat: "47.6038321",
      lon: "-122.330062",
      address: { city: "Seattle", state: "Washington", country: "Estados Unidos de América" },
    },
    // The same city again, as another kind of record.
    {
      category: "place",
      name: "Seattle",
      lat: "47.6062",
      lon: "-122.3321",
      address: { state: "Washington", country: "Estados Unidos de América" },
    },
    { category: "amenity", name: "Seattle Coffee", lat: "1", lon: "1", address: {} },
    { category: "place", name: "Nowhere", lat: "95", lon: "0", address: {} },
  ];
  assertEquals(normalizePlaceMatches(answer), [{
    name: "Seattle",
    region: "Washington, Estados Unidos de América",
    latitude: 47.6038,
    longitude: -122.3301,
  }]);
  assertEquals(normalizePlaceMatches({ error: "x" }), []);
});

Deno.test("the second search source is read with the same reader", () => {
  const answer = {
    features: [
      {
        geometry: { coordinates: [-122.330062, 47.6038321] },
        properties: {
          osm_key: "place",
          name: "Seattle",
          state: "Washington",
          country: "United States",
        },
      },
      { geometry: { coordinates: [1, 1] }, properties: { osm_key: "shop", name: "Seattle Cafe" } },
    ],
  };
  assertEquals(normalizePlaceMatches(photonAsNominatim(answer)), [{
    name: "Seattle",
    region: "Washington, United States",
    latitude: 47.6038,
    longitude: -122.3301,
  }]);
  assertEquals(photonAsNominatim(null), []);
});
