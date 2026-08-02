---
name: vinabike-erp-continuity
description: Resume Vinabike ERP work without retraining a new chat. Use at the start or resumption of a task in this repository, especially after compaction or handoff, and whenever work depends on the canonical Flutter debug session, real-app visual verification, DesignSync, or Codex-Claude collaboration.
---

# Vinabike ERP Continuity

Recover the live technical state first, then continue the product work. This skill is a bootstrap layer; `AGENTS.md` and the documents it routes to remain the product and process authorities.

## Resume in this order

1. Read the repository `AGENTS.md`, then only the task-relevant documents it requires. For non-trivial Claude collaboration, include `docs/development/CODEX_CLAUDE_COLLABORATION.md`.
2. Read relevant Codex memory and the current module handoff or completion plan. Verify live facts rather than trusting stale process IDs, SHAs, URLs, or test counts.
3. Establish repository state without changing it:

   ```bash
   git branch --show-current
   git rev-parse --short HEAD
   git status --short
   scripts/dev/native_session.sh status
   screen -ls
   ```

4. Identify file ownership before editing. Codex and Claude are independent reviewers and must not write the same files concurrently.
5. Continue from the next unresolved acceptance criterion. Do not spend a round restating information already available in repository documents.

## Route capabilities deliberately

- Use shell and repository wrappers for code, tests, Git state, logs, and deterministic app control.
- Use Browser or Chrome for browser-only verification; use Computer Use for Claude Desktop, Design windows, and native macOS UI.
- Claude owns visual and interaction direction. Every literal visual value comes from Claude's DesignSync output; screenshots are for comparison and evidence, never for estimating values.
- Test the real running application with real production-backed data in read-only paths. Capture exact rendered frames, not placeholder mockups.
- Keep production mutations, final OCR application, publication, deployment, commits, and pushes outside scope unless the user explicitly authorizes them.

## Reuse the canonical native session

`scripts/dev/native_session.sh` owns the single Flutter macOS session. Never launch a second matching Flutter process or app.

```bash
scripts/dev/native_session.sh status
scripts/dev/native_session.sh reload
scripts/dev/native_session.sh restart
scripts/dev/native_session.sh doctor
```

When the app opens a native macOS file picker, do not navigate its folders by
hand and do not send shortcuts without first resolving the exact debug app.
Use the versioned owner, then verify the loaded filename/result through the
app semantics tree:

```bash
scripts/dev/app_control.sh tap --label "Elegir archivo"
scripts/dev/app_control.sh choose-file /absolute/path/to/the/file
scripts/dev/app_control.sh read --filter "movimientos"
```

The default screen session is `payroll`. The status word `viva` means the session is alive; it is not a session name. If `screen -ls` reports `payroll` as attached, share it with:

```bash
screen -x payroll
```

Inside screen, `r` hot reloads, `R` hot restarts, and `Ctrl-A` then `D` detaches without stopping Flutter. Prefer the wrapper commands when terminal attachment is unnecessary.

## Continue Claude without retraining

Reuse the current Claude chat and allow compaction while it remains operational. Before every first prompt in a newly opened chat, visibly verify the repository's required Code mode, accepted model, Effort: Ultracode, intended title or URL, and that workflows/subagents remain disabled when the current task requires that suspension.

A new chat is exceptional: use one only after an actual context/tool failure or a clean task boundary. Before switching, update the owning repository documents and leave a compact handoff containing:

- objective, completed and open acceptance criteria;
- current SHA, dirty-worktree warning, file ownership, and forbidden actions;
- Design project/page/turn/component IDs and unreadable values;
- canonical debug status and control commands, never stale process IDs;
- exact test/analyzer results, real screenshot paths, defects, and next action.

Ask Claude for concise evidence-backed checkpoints at meaningful boundaries, not narration for every click. Independently inspect diffs, tests, domain contracts, and real rendered behavior before accepting its work.

## Close a round

Before declaring a slice complete, run proportionate focused tests and analysis, verify its real desktop/phone behavior where applicable, and record reusable tool/domain lessons in the owning guide during the same task. Report unresolved blockers by name; do not hide them behind a green focused test.
