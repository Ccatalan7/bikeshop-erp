/// Where the project's database lives. Edge functions run wherever the
/// caller is nearest unless the invocation pins them; from Chile that put
/// `whatsapp-send` on a far edge and cost ~650 ms per database hop — eight
/// hops per message. Pinning the function next to the database turns each
/// hop into tens of milliseconds. The value matches the pooler host in
/// `scripts/db/lib.sh` (`aws-1-sa-east-1`).
const String kSupabaseFunctionsRegion = 'sa-east-1';

const Map<String, String> kSupabaseFunctionsRegionHeaders = {
  'x-region': kSupabaseFunctionsRegion,
};
