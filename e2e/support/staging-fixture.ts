import { execFileSync } from "node:child_process";

const fixtureProductId = "e2e00000-0000-4000-8000-000000000101";

function runDatabaseCommand(args: string[]) {
  return execFileSync("bash", ["scripts/db/query.sh", "staging", ...args], {
    cwd: process.cwd(),
    encoding: "utf8",
    env: {
      ...process.env,
      VINABIKE_DB_WRITE_CONFIRM: "staging",
    },
    stdio: ["ignore", "pipe", "pipe"],
  });
}

export function resetStagingInventoryFixture() {
  runDatabaseCommand([
    "--file",
    "scripts/e2e/reset_staging_fixture.sql",
    "--write",
  ]);
}

export function readStagingFixtureStock() {
  const output = runDatabaseCommand([
    "--sql",
    `select inventory_qty::integer as stock from public.products where id = '${fixtureProductId}'`,
    "--format",
    "json",
  ]);
  const rows = JSON.parse(output) as Array<{ stock: number }>;
  if (rows.length !== 1) {
    throw new Error(
      `Expected one staging fixture product, found ${rows.length}`,
    );
  }
  return Number(rows[0].stock);
}
