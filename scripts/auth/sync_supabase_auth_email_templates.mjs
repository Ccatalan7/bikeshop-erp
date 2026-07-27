#!/usr/bin/env node

import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

import {
  authEmailDefinitions,
  expectedTemplateFiles,
  writeTemplates,
} from "./auth_email_templates.mjs";

const projectRef = "xzdvtzdqjeyqxnkqprtf";
const endpoint = `https://api.supabase.com/v1/projects/${projectRef}/config/auth`;
const scriptPath = fileURLToPath(import.meta.url);
const projectRoot = path.resolve(path.dirname(scriptPath), "..", "..");
const templateRoot = path.join(projectRoot, "supabase", "templates");
const apply = process.argv.includes("--apply");
const expectedArguments = apply ? ["--apply"] : [];

assert.deepEqual(
  process.argv.slice(2),
  expectedArguments,
  "Use no arguments for read-only verification or exactly --apply",
);

function loadAccessToken() {
  const stored = execFileSync(
    "security",
    [
      "find-generic-password",
      "-w",
      "-s",
      "Supabase CLI",
      "-a",
      "supabase",
    ],
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
    throw new Error(`Supabase Auth config ${method} failed with HTTP ${response.status}`);
  }
  return response.json();
}

async function readConfig(accessToken, attempts = 3) {
  let lastError;
  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    try {
      return await request("GET", accessToken);
    } catch (error) {
      lastError = error;
      if (attempt < attempts) {
        await new Promise((resolve) => setTimeout(resolve, attempt * 400));
      }
    }
  }
  throw lastError;
}

function digest(value) {
  return crypto
    .createHash("sha256")
    .update(typeof value === "string" ? value : JSON.stringify(value))
    .digest("hex");
}

function templateField(definition) {
  return definition.category === "notification"
    ? `mailer_templates_${definition.key}_notification_content`
    : `mailer_templates_${definition.key}_content`;
}

function subjectField(definition) {
  return definition.category === "notification"
    ? `mailer_subjects_${definition.key}_notification`
    : `mailer_subjects_${definition.key}`;
}

function enabledField(definition) {
  assert.equal(definition.category, "notification");
  return `mailer_notifications_${definition.key}_enabled`;
}

function readTemplate(definition) {
  const target = path.join(templateRoot, definition.file);
  const html = fs.readFileSync(target, "utf8");
  assert.equal(
    html,
    expectedTemplateFiles().get(definition.file),
    `${definition.file} is not generated from the canonical renderer`,
  );
  assert.ok(html.startsWith("<!doctype html>"), `${definition.file} is not HTML`);
  assert.ok(!/<script/i.test(html), `${definition.file} contains a script`);
  assert.ok(
    !/(?:src|href)\s*=\s*["']https?:\/\//i.test(html),
    `${definition.file} loads a remote resource`,
  );
  assert.ok(
    html.includes("overflow-wrap:anywhere"),
    `${definition.file} does not protect long identities on compact clients`,
  );
  return html;
}

function buildPatch(current) {
  const patch = {
    rate_limit_email_sent: 30,
    mailer_secure_email_change_enabled: true,
    security_update_password_require_reauthentication: true,
  };

  for (const definition of authEmailDefinitions) {
    patch[subjectField(definition)] = definition.subject;
    patch[templateField(definition)] = readTemplate(definition);
    if (definition.category === "notification") {
      patch[enabledField(definition)] = true;
    }
  }

  assert.ok(
    Object.keys(patch).every(
      (key) =>
        key.startsWith("mailer_") ||
        key === "rate_limit_email_sent" ||
        key === "security_update_password_require_reauthentication",
    ),
    "Patch escaped the Auth email allowlist",
  );
  assert.equal(current.site_url, "https://vinabike.cl");
  assert.equal(current.disable_signup, false);
  assert.equal(current.mailer_autoconfirm, false);
  assert.equal(current.external_email_enabled, true);
  assert.equal(current.external_google_enabled, true);
  assert.equal(current.mailer_otp_exp, 3600);
  assert.equal(current.mailer_otp_length, 6);
  return patch;
}

function providerSnapshot(config) {
  return {
    site_url: config.site_url,
    disable_signup: config.disable_signup,
    mailer_autoconfirm: config.mailer_autoconfirm,
    external_email_enabled: config.external_email_enabled,
    external_google_enabled: config.external_google_enabled,
    external_google_client_id: config.external_google_client_id,
    external_google_secret: config.external_google_secret,
    external_google_additional_client_ids:
      config.external_google_additional_client_ids,
    smtp_host: config.smtp_host,
    smtp_port: config.smtp_port,
    smtp_user: config.smtp_user,
    smtp_pass: config.smtp_pass,
    smtp_admin_email: config.smtp_admin_email,
    smtp_sender_name: config.smtp_sender_name,
  };
}

function selected(config, keys) {
  return Object.fromEntries(keys.map((key) => [key, config[key]]));
}

function mismatches(config, expected) {
  return Object.entries(expected)
    .filter(([key, value]) => config[key] !== value)
    .map(([key]) => key)
    .sort();
}

async function applyWithReconciliation(accessToken, before, patch) {
  let patchError = null;
  try {
    await request("PATCH", accessToken, patch);
  } catch (error) {
    patchError = error;
  }

  let after;
  try {
    after = await readConfig(accessToken);
  } catch (readError) {
    throw new Error(
      `Auth config write outcome is unknown; post-write read-back failed: ${
        readError instanceof Error ? readError.message : String(readError)
      }`,
    );
  }

  const remaining = mismatches(after, patch);
  if (remaining.length === 0) return after;

  const rollback = selected(before, Object.keys(patch));
  await request("PATCH", accessToken, rollback);
  const rolledBack = await readConfig(accessToken);
  assert.deepEqual(
    selected(rolledBack, Object.keys(rollback)),
    rollback,
    "Auth email rollback did not round-trip",
  );

  const reason = patchError instanceof Error
    ? patchError.message
    : `read-back mismatch: ${remaining.join(", ")}`;
  throw new Error(`Auth email configuration was rolled back: ${reason}`);
}

async function main() {
  writeTemplates({ check: true });
  const accessToken = loadAccessToken();
  const before = await readConfig(accessToken);
  const patch = buildPatch(before);
  const keys = Object.keys(patch).sort();
  const changedKeys = mismatches(before, patch);

  console.log(
    JSON.stringify({
      mode: apply ? "apply" : "check",
      projectRef,
      templateCount: authEmailDefinitions.length,
      changedKeys,
      templateDigests: Object.fromEntries(
        authEmailDefinitions.map((definition) => [
          definition.key,
          digest(patch[templateField(definition)]),
        ]),
      ),
      emailRateLimitPerHour: {
        current: before.rate_limit_email_sent,
        expected: patch.rate_limit_email_sent,
      },
      providerPreservationRequired: true,
    }),
  );

  if (!apply || changedKeys.length === 0) return;

  const justBefore = await readConfig(accessToken);
  assert.deepEqual(
    selected(justBefore, keys),
    selected(before, keys),
    "Auth email configuration changed concurrently",
  );
  assert.deepEqual(
    providerSnapshot(justBefore),
    providerSnapshot(before),
    "Google, SMTP, signup, or Site URL changed concurrently",
  );

  const after = await applyWithReconciliation(accessToken, before, patch);
  assert.deepEqual(
    providerSnapshot(after),
    providerSnapshot(before),
    "Google, SMTP, signup, or Site URL changed unexpectedly",
  );
  assert.deepEqual(
    selected(after, keys),
    patch,
    "Auth email patch did not round-trip exactly",
  );

  console.log(
    JSON.stringify({
      projectRef,
      appliedKeys: keys,
      templateCount: authEmailDefinitions.length,
      emailRateLimitPerHour: after.rate_limit_email_sent,
      readbackDigest: digest(selected(after, keys)),
      googlePreserved: true,
      smtpPreserved: true,
    }),
  );
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
});
