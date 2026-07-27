#!/usr/bin/env node

import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";

const projectRef = "xzdvtzdqjeyqxnkqprtf";
const projectUrl = `https://${projectRef}.supabase.co`;
const legacySuffix = "@worker-login.vinabike.app";
const safeSuffix = "@worker-login.invalid";
const apply = process.argv.includes("--apply");
const expectedArguments = apply ? ["--apply"] : [];

assert.deepEqual(
  process.argv.slice(2),
  expectedArguments,
  "Use no arguments for read-only verification or exactly --apply",
);

function loadSecretKey() {
  const value = execFileSync(
    "security",
    [
      "find-generic-password",
      "-w",
      "-s",
      "Vinabike ERP Supabase secret key",
      "-a",
      "supabase",
    ],
    { encoding: "utf8" },
  ).trim();
  assert.match(value, /^sb_secret_[A-Za-z0-9_-]+$/);
  return value;
}

async function request(secretKey, path, {
  method = "GET",
  body,
  prefer,
} = {}) {
  const response = await fetch(`${projectUrl}${path}`, {
    method,
    headers: {
      apikey: secretKey,
      Authorization: `Bearer ${secretKey}`,
      Accept: "application/json",
      ...(body ? { "Content-Type": "application/json" } : {}),
      ...(prefer ? { Prefer: prefer } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  if (!response.ok) {
    throw new Error(`${method} ${path.split("?")[0]} failed with HTTP ${response.status}`);
  }
  if (response.status === 204) return null;
  return response.json();
}

async function listPortalAccounts(secretKey) {
  const select = [
    "id",
    "tenant_id",
    "employee_id",
    "auth_user_id",
    "login_email",
  ].join(",");
  const rows = await request(
    secretKey,
    `/rest/v1/employee_portal_accounts?select=${select}&order=id.asc`,
  );
  assert.ok(Array.isArray(rows));
  return rows;
}

async function getAuthUser(secretKey, userId) {
  const user = await request(secretKey, `/auth/v1/admin/users/${userId}`);
  assert.equal(user?.id, userId);
  return user;
}

async function listAllAuthUsers(secretKey) {
  const users = [];
  for (let page = 1; page <= 100; page += 1) {
    const payload = await request(
      secretKey,
      `/auth/v1/admin/users?page=${page}&per_page=1000`,
    );
    const batch = Array.isArray(payload?.users) ? payload.users : [];
    users.push(...batch);
    if (batch.length < 1000) return users;
  }
  throw new Error("Auth user enumeration exceeded the guarded page limit");
}

function expectedSafeEmail(loginEmail) {
  assert.equal(typeof loginEmail, "string");
  assert.ok(loginEmail.endsWith(legacySuffix));
  const safeEmail = `${loginEmail.slice(0, -legacySuffix.length)}${safeSuffix}`;
  assert.ok(safeEmail.length <= 254);
  return safeEmail;
}

function assertAuthoritativeWorker(row, user) {
  assert.equal(typeof row.id, "string");
  assert.equal(typeof row.tenant_id, "string");
  assert.equal(typeof row.employee_id, "string");
  assert.equal(typeof row.auth_user_id, "string");
  assert.equal(user.id, row.auth_user_id);
  assert.equal(user.email?.toLowerCase(), row.login_email.toLowerCase());
  assert.equal(user.app_metadata?.account_type, "worker_portal");
  assert.equal(user.app_metadata?.tenant_id, row.tenant_id);
  assert.equal(user.app_metadata?.employee_id, row.employee_id);
  assert.equal(user.app_metadata?.role, "worker");
}

async function updateAuthEmail(secretKey, userId, email) {
  const user = await request(secretKey, `/auth/v1/admin/users/${userId}`, {
    method: "PUT",
    body: { email, email_confirm: true },
  });
  assert.equal(user?.id, userId);
  assert.equal(user?.email?.toLowerCase(), email.toLowerCase());
  return user;
}

async function updatePortalEmail(secretKey, row, fromEmail, toEmail) {
  const query = new URLSearchParams({
    id: `eq.${row.id}`,
    tenant_id: `eq.${row.tenant_id}`,
    login_email: `eq.${fromEmail}`,
    select: "id,tenant_id,employee_id,auth_user_id,login_email",
  });
  const updated = await request(
    secretKey,
    `/rest/v1/employee_portal_accounts?${query}`,
    {
      method: "PATCH",
      body: { login_email: toEmail },
      prefer: "return=representation",
    },
  );
  assert.ok(Array.isArray(updated));
  assert.equal(updated.length, 1);
  assert.equal(updated[0].login_email, toEmail);
  return updated[0];
}

async function reconcileOne(secretKey, row, knownAuthEmails) {
  const beforeUser = await getAuthUser(secretKey, row.auth_user_id);
  assertAuthoritativeWorker(row, beforeUser);
  const safeEmail = expectedSafeEmail(row.login_email);
  assert.ok(!knownAuthEmails.has(safeEmail.toLowerCase()));

  const justBeforeRows = await listPortalAccounts(secretKey);
  const justBefore = justBeforeRows.find((candidate) => candidate.id === row.id);
  assert.deepEqual(justBefore, row, "Worker portal state changed concurrently");

  await updateAuthEmail(secretKey, row.auth_user_id, safeEmail);
  try {
    await updatePortalEmail(secretKey, row, row.login_email, safeEmail);
  } catch (databaseError) {
    try {
      await updateAuthEmail(secretKey, row.auth_user_id, row.login_email);
    } catch {
      throw new Error(
        "Worker email migration outcome is unknown; Auth rollback failed",
      );
    }
    const rolledBackUser = await getAuthUser(secretKey, row.auth_user_id);
    assert.equal(
      rolledBackUser.email?.toLowerCase(),
      row.login_email.toLowerCase(),
      "Worker Auth email rollback did not round-trip",
    );
    throw databaseError;
  }

  const afterRows = await listPortalAccounts(secretKey);
  const afterRow = afterRows.find((candidate) => candidate.id === row.id);
  assert.ok(afterRow);
  assert.equal(afterRow.login_email, safeEmail);
  const afterUser = await getAuthUser(secretKey, row.auth_user_id);
  assertAuthoritativeWorker(afterRow, afterUser);
  knownAuthEmails.add(safeEmail.toLowerCase());
}

async function main() {
  const secretKey = loadSecretKey();
  const rows = await listPortalAccounts(secretKey);
  const legacyRows = rows.filter((row) => row.login_email?.endsWith(legacySuffix));
  const safeRows = rows.filter((row) => row.login_email?.endsWith(safeSuffix));
  assert.equal(
    legacyRows.length + safeRows.length,
    rows.length,
    "A worker portal account uses an unrecognized login-email domain",
  );

  for (const row of rows) {
    assertAuthoritativeWorker(row, await getAuthUser(secretKey, row.auth_user_id));
  }

  console.log(JSON.stringify({
    mode: apply ? "apply" : "check",
    projectRef,
    workerPortalAccounts: rows.length,
    legacyDomainAccounts: legacyRows.length,
    safeDomainAccounts: safeRows.length,
    targetDomain: "worker-login.invalid",
    authorityAligned: true,
  }));

  if (!apply || legacyRows.length === 0) return;

  const authUsers = await listAllAuthUsers(secretKey);
  const knownAuthEmails = new Set(
    authUsers
      .map((user) => user.email?.trim().toLowerCase())
      .filter(Boolean),
  );
  for (const row of legacyRows) {
    await reconcileOne(secretKey, row, knownAuthEmails);
  }

  const finalRows = await listPortalAccounts(secretKey);
  assert.equal(
    finalRows.filter((row) => row.login_email?.endsWith(legacySuffix)).length,
    0,
  );
  for (const row of finalRows) {
    assert.ok(row.login_email?.endsWith(safeSuffix));
    assertAuthoritativeWorker(row, await getAuthUser(secretKey, row.auth_user_id));
  }
  console.log(JSON.stringify({
    mode: "read-back",
    projectRef,
    migratedAccounts: legacyRows.length,
    legacyDomainAccounts: 0,
    authorityAligned: true,
  }));
}

await main();
