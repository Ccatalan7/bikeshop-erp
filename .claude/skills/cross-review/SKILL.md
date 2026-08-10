---
name: cross-review
description: Coordinate independent Codex-Claude review only when the owner explicitly requested Claude collaboration.
disable-model-invocation: false
---

# Cross-review gate

Use this gate only after the owner explicitly requested Claude collaboration.
Ordinary cross-review uses an independent Codex subagent instead.

1. Capture the current branch, HEAD, and relevant dirty paths. Existing changes
   are evidence and ownership boundaries, never cleanup targets.
2. Build a neutral evidence packet for each new non-trivial problem: symptom,
   reproduction, boundary and relevant files. Do not include either agent's
   diagnosis or preferred fix.
3. Require both Codex and Claude to respond independently with reproduced fact
   versus hypothesis, root cause, severity/blast radius, proposed correction,
   alternatives/trade-offs, minimum regression and uncertainty before
   implementation. Batch related findings into one bounded response per agent.
4. Reconcile both proposals against canonical contracts and observed evidence.
   Record why the selected or synthesized correction wins and preserve material
   dissent as an explicit risk.
5. Identify authorship and file ownership. Never let two agents edit the same
   files concurrently.
6. Start with one reviewer for the highest-risk seam: use
   `ui-cross-reviewer` for predominantly visual work and
   `logic-cross-reviewer` for logic, data, auth, accounting, inventory, or
   concurrency. Let that reviewer inspect every relevant path and focused test;
   do not stop it at an arbitrary low call count. Mixed work may use a second
   sequential specialist when the first pass exposes a distinct uncovered
   seam and the main agent records the evidence gap and cost checkpoint. Never
   run them as an agent team.
7. Do not reveal one reviewer's conclusion to the other before its first pass;
   independent disagreement is useful evidence.
8. Reconcile findings by reproducing them. The implementation author fixes
   confirmed issues, then the other agent rechecks the changed seam.
9. Run focused format/analyzer/tests and the canonical real-app verification.
   Separate pre-existing suite failures from regressions with evidence.
10. Produce one handoff packet:
   - requested outcome and current status;
   - exact files and ownership;
   - behavior changed and invariants preserved;
   - commands and real results;
   - responsive/app states observed;
   - unresolved risks and decisions;
   - actions deliberately not taken, including deploy, production writes,
     commit, and push.

No agent's confidence is a completion signal. Completion requires independent
review plus evidence.

## Cost boundary

- Never start a Workflow or an experimental agent team without the owner's
  explicit approval after stating the estimated agent count and purpose.
- Never nest agents. Begin with one coherent reviewer; add a sequential
  specialist only for a concrete domain or evidence gap. Workflows and agent
  teams require explicit owner approval because their fan-out is unpredictable.
- Give each reviewer a coherent evidence packet and enough tool access to
  inspect the app, relevant source/data flow and focused regressions. Budget by
  unresolved risk, not a small fixed number of calls; avoid only repetitive or
  unfocused exploration.
- Once evidence is sufficient or investigation starts repeating itself, ask the
  active reviewer to conclude with what it has. Do not interrupt an agent that
  is already composing its final conclusion.
- Final synthesis is local and tool-free. Report uncertainty instead of
  spending another review round by default.
