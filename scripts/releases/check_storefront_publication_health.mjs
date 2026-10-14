#!/usr/bin/env node
// Stops a release while vinabike.cl is not publishing from main.
//
// 2026-10-14: the store workflow had failed on 21 builds in a row over 20
// hours (first its post-deploy check, then its bundle budget) while ERP
// releases kept going out; the site stayed on the 13 October build and nobody
// looked. The last finished run of the store workflow on main has to be green
// before a release is prepared.
//
// Exit 0: the store publishes. 1: the last finished run failed. 2: GitHub
// could not be read. STOREFRONT_FAILURE_ACKNOWLEDGED="<reason>" lets a
// release through with the failure printed, for an emergency only.
import { spawnSync } from "node:child_process";

const WORKFLOW = "firebase-hosting-store.yml";

const result = spawnSync(
  "gh",
  [
    "run",
    "list",
    "--workflow",
    WORKFLOW,
    "--branch",
    "main",
    "--limit",
    "30",
    "--json",
    "status,conclusion,headSha,createdAt,url,event",
  ],
  { encoding: "utf8" },
);
if (result.status !== 0) {
  console.error(
    `No se pudo leer el workflow de la tienda en GitHub: ${result.stderr.trim()}`,
  );
  process.exit(2);
}

const runs = JSON.parse(result.stdout);
const finished = runs.filter((run) => run.status === "completed");
const last = finished[0];
if (!last) {
  console.error("GitHub no devolvió ninguna publicación terminada de la tienda.");
  process.exit(2);
}
if (last.conclusion === "success") {
  console.log(
    `La tienda publica: ${last.headSha.slice(0, 8)} (${last.event}, ${last.createdAt}).`,
  );
  process.exit(0);
}

const lastGood = finished.find((run) => run.conclusion === "success");
const failing = lastGood
  ? finished.slice(0, finished.indexOf(lastGood))
  : finished;
const since = failing[failing.length - 1];
const running = runs.find((run) => run.status !== "completed");
const lines = [
  `vinabike.cl no se publica desde ${since.createdAt}: ${failing.length} ` +
    `${failing.length === 1 ? "build falló" : "builds fallaron"} seguidos ` +
    "en main.",
  `Último: ${last.headSha.slice(0, 8)} → ${last.url}`,
  lastGood
    ? `Último bueno: ${lastGood.headSha.slice(0, 8)} (${lastGood.createdAt}).`
    : "Ninguno de los últimos 30 terminó bien.",
  running
    ? `Hay uno en curso (${running.headSha.slice(0, 8)}): si trae el arreglo, espera a que termine.`
    : "Lee el paso que falla (gh run view <id> --log-failed) y arréglalo antes de lanzar.",
];
const acknowledged = process.env.STOREFRONT_FAILURE_ACKNOWLEDGED?.trim();
if (acknowledged) {
  console.warn(lines.join("\n"));
  console.warn(`Se lanza igual: ${acknowledged}`);
  process.exit(0);
}
console.error(lines.join("\n"));
process.exit(1);
