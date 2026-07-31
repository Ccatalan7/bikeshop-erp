#!/usr/bin/env node

import assert from "node:assert/strict";
import test from "node:test";

import {
  PairedReleaseBaseError,
  androidBaselineFromManifest,
  chooseCommonReleaseNotesBase,
  selectLatestAndroidRun,
  validateAndroidPublicationManifest,
} from "./resolve_paired_release_notes_base.mjs";

const HEAD = "f".repeat(40);
const DESKTOP = "d".repeat(40);
const ANDROID = "a".repeat(40);
const COMMON = "c".repeat(40);

function chooser(ancestors, bases = [COMMON]) {
  return {
    isAncestor(left, right) {
      return ancestors.has(`${left}:${right}`);
    },
    mergeBases() {
      return bases;
    },
  };
}

test("uses the older desktop commit when it already covers Android", () => {
  const base = chooseCommonReleaseNotesBase(
    { desktopCommit: DESKTOP, androidCommit: ANDROID, headSha: HEAD },
    chooser(
      new Set([
        `${DESKTOP}:${HEAD}`,
        `${ANDROID}:${HEAD}`,
        `${DESKTOP}:${ANDROID}`,
      ]),
    ),
  );
  assert.equal(base, DESKTOP);
});

test("uses the older Android commit when it already covers desktop", () => {
  const base = chooseCommonReleaseNotesBase(
    { desktopCommit: DESKTOP, androidCommit: ANDROID, headSha: HEAD },
    chooser(
      new Set([
        `${DESKTOP}:${HEAD}`,
        `${ANDROID}:${HEAD}`,
        `${ANDROID}:${DESKTOP}`,
      ]),
    ),
  );
  assert.equal(base, ANDROID);
});

test("uses one safe merge base when prior platform commits diverged", () => {
  const base = chooseCommonReleaseNotesBase(
    { desktopCommit: DESKTOP, androidCommit: ANDROID, headSha: HEAD },
    chooser(
      new Set([
        `${DESKTOP}:${HEAD}`,
        `${ANDROID}:${HEAD}`,
        `${COMMON}:${HEAD}`,
      ]),
    ),
  );
  assert.equal(base, COMMON);
});

test("fails closed when there is no unique safe common baseline", () => {
  assert.throws(
    () =>
      chooseCommonReleaseNotesBase(
        { desktopCommit: DESKTOP, androidCommit: ANDROID, headSha: HEAD },
        chooser(new Set([`${DESKTOP}:${HEAD}`, `${ANDROID}:${HEAD}`]), [
          COMMON,
          "b".repeat(40),
        ]),
      ),
    PairedReleaseBaseError,
  );
});

test("same-head Android retries use the current manifest's prior base", () => {
  const selected = selectLatestAndroidRun(
    [
      {
        databaseId: 30,
        headSha: HEAD,
        status: "completed",
        conclusion: "success",
        event: "workflow_dispatch",
        createdAt: "2026-07-31T18:30:00Z",
        displayTitle: `Android publish · ${HEAD}`,
      },
      {
        databaseId: 20,
        headSha: ANDROID,
        status: "completed",
        conclusion: "success",
        event: "workflow_dispatch",
        createdAt: "2026-07-30T18:30:00Z",
        displayTitle: `Android publish · ${ANDROID}`,
      },
      {
        databaseId: 10,
        headSha: DESKTOP,
        status: "completed",
        conclusion: "success",
        event: "workflow_dispatch",
        createdAt: "2026-07-29T18:30:00Z",
        displayTitle: `Android publish · ${DESKTOP}`,
      },
    ],
    { headSha: HEAD, branch: "smartpegas1.0" },
  );
  assert.equal(selected.databaseId, 30);
  const currentManifest = {
    schema_version: 1,
    package_name: "com.vinabike.erp",
    commit: HEAD,
    release_notes: {
      schema_version: 1,
      from_commit: COMMON,
      to_commit: HEAD,
    },
  };
  assert.equal(androidBaselineFromManifest(currentManifest, HEAD), COMMON);
});

test("Android baseline evidence is exact-commit and exact-range", () => {
  const manifest = {
    schema_version: 1,
    package_name: "com.vinabike.erp",
    commit: ANDROID,
    release_notes: {
      schema_version: 1,
      from_commit: COMMON,
      to_commit: ANDROID,
    },
  };
  assert.equal(validateAndroidPublicationManifest(manifest, ANDROID), manifest);
  manifest.release_notes.to_commit = DESKTOP;
  assert.throws(
    () => validateAndroidPublicationManifest(manifest, ANDROID),
    /inconsistent/u,
  );
});
