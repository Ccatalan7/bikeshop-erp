#!/usr/bin/env node

import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";

const projectRef = "xzdvtzdqjeyqxnkqprtf";
const endpoint = `https://api.supabase.com/v1/projects/${projectRef}/postgrest`;
const expectedBefore = "public, graphql_public";
const expectedAfter = "public, graphql_public, assistant_runtime";
const apply = process.argv.includes("--apply");

assert.deepEqual(
  process.argv.slice(2),
  apply ? ["--apply"] : [],
  "Use no arguments for read-only verification or exactly --apply",
);

function loadAccessToken() {
  const stored = execFileSync(
    "security",
    ["find-generic-password", "-w", "-s", "Supabase CLI", "-a", "supabase"],
    { encoding: "utf8" },
  ).trim();
  const prefix = "go-keyring-base64:";
  return stored.startsWith(prefix)
    ? Buffer.from(stored.slice(prefix.length), "base64").toString("utf8")
    : stored;
}

async function request(method, accessToken, body) {
  const response = await fetch(endpoint, {
    method,
    headers: {
      Authorization: `Bearer ${accessToken}`,
      ...(body ? { "Content-Type": "application/json" } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  if (!response.ok) {
    throw new Error(`Supabase PostgREST config ${method} failed with HTTP ${response.status}`);
  }
  return response.json();
}

const accessToken = loadAccessToken();
const before = await request("GET", accessToken);
assert.ok(
  before.db_schema === expectedBefore || before.db_schema === expectedAfter,
  `Unexpected hosted db_schema: ${before.db_schema}`,
);

if (apply && before.db_schema !== expectedAfter) {
  await request("PATCH", accessToken, { db_schema: expectedAfter });
}

const after = await request("GET", accessToken);
if (apply) assert.equal(after.db_schema, expectedAfter);
assert.equal(after.db_extra_search_path, before.db_extra_search_path);
assert.equal(after.max_rows, before.max_rows);

console.log(JSON.stringify({
  projectRef,
  dbSchema: after.db_schema,
  dbExtraSearchPath: after.db_extra_search_path,
  maxRows: after.max_rows,
  changed: before.db_schema !== after.db_schema,
}));
