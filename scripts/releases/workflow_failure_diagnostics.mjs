function cleanGitHubLogLine(value) {
  const withoutAnsi = String(value ?? "").replace(
    // GitHub may preserve terminal color codes from a nested workflow.
    // eslint-disable-next-line no-control-regex
    /\x1B\[[0-?]*[ -/]*[@-~]/gu,
    "",
  );
  const fields = withoutAnsi.split("\t");
  const message = fields.length >= 3 ? fields.slice(2).join("\t") : withoutAnsi;
  return message.replace(
    /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z\s?/u,
    "",
  );
}

export function formatWorkflowFailureSummary(
  jobsText,
  failedLog,
  { fallbackPrefix = "android-update" } = {},
) {
  let jobs = [];
  try {
    const parsed = JSON.parse(jobsText || "{}");
    jobs = Array.isArray(parsed?.jobs) ? parsed.jobs : [];
  } catch {
    jobs = [];
  }

  const lines = ["Failure summary:"];
  const failedJobs = jobs.filter((job) => job?.conclusion === "failure");
  if (failedJobs.length === 0) {
    lines.push("Failed job: unavailable from GitHub jobs API");
    lines.push("  Failed step: unavailable from GitHub jobs API");
  } else {
    for (const job of failedJobs.slice(0, 12)) {
      lines.push(`Failed job: ${String(job?.name || "Unnamed GitHub job")}`);
      const failedSteps = Array.isArray(job?.steps)
        ? job.steps.filter((step) => step?.conclusion === "failure")
        : [];
      if (failedSteps.length === 0) {
        lines.push("  Failed step: unavailable from GitHub jobs API");
      } else {
        for (const step of failedSteps.slice(0, 12)) {
          lines.push(
            `  Failed step: ${String(step?.name || "Unnamed GitHub step")}`,
          );
        }
      }
    }
  }

  const cleanLogLines = String(failedLog ?? "")
    .split(/\r?\n/u)
    .map(cleanGitHubLogLine);
  const gateStart = cleanLogLines.findIndex((line) =>
    line.startsWith("[flutter-test-gate] Flutter tests failed."),
  );
  if (gateStart >= 0) {
    const gateEnd = cleanLogLines.findIndex(
      (line, index) =>
        index >= gateStart &&
        line.startsWith("[flutter-test-gate] Nothing was published."),
    );
    const boundedEnd =
      gateEnd >= gateStart
        ? gateEnd + 1
        : Math.min(cleanLogLines.length, gateStart + 80);
    lines.push(...cleanLogLines.slice(gateStart, boundedEnd));
  } else {
    lines.push(
      `[${fallbackPrefix}] Nothing was published. ` +
        "Fix the failed step above and run the task again.",
    );
  }

  return lines
    .map((line) => line.slice(0, 1200))
    .slice(0, 120)
    .join("\n")
    .trimEnd();
}
