<!--
Shared pipeline for the review-wc / review-diff / review-pr skills.

Lives outside ~/.claude/skills/ on purpose: a bare .md in that tree gets scanned as a
malformed skill. Each skill Reads this file and supplies the parts marked "caller
supplies": the diff, the slim target, and any per-context overrides.
-->

# Review pipeline

Stages below run in order: prune, size gate, triage, agent selection, review, validation,
aggregation. The calling skill has already captured the diff and defines two things this
file refers to:

- **Slim target**: what the size gate hands small diffs to.
- **Overrides**: per-context rules (for example, which tree to read from) that win over
  anything here.

## Prune skip-noise

Before the size gate and triage, remove these from the diff and list them in triage as
`Skipped: <path>`:

- `vendor/`, `node_modules/`, `dist/`, `build/`, `.next/`
- Generated: `*.pb.go`, `*_generated.*`, `*.gen.go`
- Lockfiles: `go.sum`, `yarn.lock`, `package-lock.json`, `pnpm-lock.yaml`, `Cargo.lock`, `Gemfile.lock`, `Podfile.lock`
- Minified assets and binary files

Sub-agents receive the pruned diff only.

## Size gate

Decide slim vs full by scope, not line count alone. Every count below is measured on the
**pruned** diff: exclude anything Prune skip-noise removed.

- **<50 changed lines**: always take the **Slim target**.
- **>200 changed lines**: always continue with the full pipeline.
- **50–200 changed lines**: Slim target if localized (≤3 files, single subsystem, one type
  of change: refactor, rename, isolated bug fix, doc/comment). Otherwise full pipeline.
  Escalate to full if the diff touches multiple subsystems, mixes concerns (logic +
  security + tests), adds new business logic or public APIs, or modifies auth,
  data-mutation, or validation paths.

## Triage

Before fanning out, compile a one-paragraph diff summary: files touched, their
subsystems/dirs, whether tests changed, approximate size. If the caller supplied a change
description (a pull request body, for example), say how the changes relate to it. Pass this
summary to every sub-agent.

Also compute a **comment-noise signal** and record it in the summary as
`Comment-noise signal: tripped|clear`, with the reason. It trips when any of these holds on
the pruned diff:

- Added comment lines exceed roughly 25% of added non-blank lines, ignoring documentation
  on exported symbols.
- Any added comment line contains an em dash, restates the line immediately below it, or
  addresses the reviewer rather than a future reader.
- The same rationale is explained in more than one place in the diff: at two layers, or in
  a comment and again in a test. One site owns the decision; the others should name it and
  point at it. Repeating a fact is fine, repeating the reasoning is the trip.
- Any added comment asserts how a symbol outside its own package works inside, rather than
  naming it and pointing at its comment. Naming another package's function and saying what
  the call is for is fine; describing its internals is the trip.

The signal is advisory input to the Generalist's machine-authored-tells lens. It gates how
hard that lens is applied, never which agents run.

## Agent selection

Apply these heuristics to the pruned diff. Record the decision and the matching signals
(or their absence) in triage so reviewers see what was skipped and why. A caller may
override this stage and run every agent unconditionally.

**Always run**: Bugs & Logic, Generalist.

**Run Security if any of**:

- Path matches `auth|authn|authz|crypto|session|token|password|secret|sql|exec|sanitize|validate|cors|csrf|jwt|oauth|webhook|cookie|tls|x509`.
- Added lines touch `os/exec`, `database/sql`, raw SQL, `eval`, `unsafe`, template rendering with user input, deserialization, file path joins from request data, or new HTTP/RPC handlers.
- New external input surface (request body, query param, header, env var from untrusted source).
- Size-gate escalation mentions auth, validation, or data mutation. Security is forced on regardless of keyword match.

**Run Test Coverage if any of**:

- Net-new function, method, or public API in non-test, non-doc files.
- New or modified branching, business logic, error handling, or validation in production code.
- Critical path touched (auth, data mutation, validation, money/billing, migration).
- Size gate chose full because the diff mixes concerns or adds business logic.

**Skip Test Coverage when**: comment/doc-only, pure rename/move, formatting, dependency
bump with no call-site change, or refactor with no new branches where existing tests still
cover.

**Skip Security when**: nothing above matches and the diff is confined to internal data
structures, logging, telemetry, build/CI config without secret handling, or docs.

## Review process

Launch the selected sub-agents **in parallel** via the Agent tool. Use these
`subagent_type` values so each role runs on its intended model:

| Role | `subagent_type` | When |
|---|---|---|
| Bugs & Logic | `review-bugs-logic` | always |
| Generalist | `review-generalist` | always |
| Security | `review-security` | per Agent selection |
| Test Coverage | `review-tests` | per Agent selection |

Each agent's scope and reporting rules live in its own agent definition, the single source
of truth. Don't restate them here or in the calling skill.

Pass every agent:

- the pruned diff,
- the triage summary, including which agents were skipped and why,
- any change description the caller supplied,
- the caller's Overrides.

## Validation

After the selected agents complete, launch the validator (`subagent_type:
review-validator`). Pass it the pruned diff, the triage summary (including skipped agents
and the signals or absence behind each skip), every finding, any change description, and
the caller's Overrides.

The validator owns its full process: dedupe, verify against source, score each finding
inline as `[c:NN s:LVL]` (confidence 0–100, severity `low`|`med`|`high`), filter
pre-existing findings, run the coverage check for categories that returned "None." and for
any skipped by Agent selection, apply broader subsumption, and tag likely Suggestions
`do`/`opportunistic`/`skip`. It returns every surviving finding tagged, with any
pre-existing, subsumption, or verdict notes. The step-by-step rubric is the
`review-validator` agent definition, the single source of truth. Don't restate it here.

## Aggregation

After the validator completes, aggregate into one review. Map each `[c:NN s:LVL]` to a
bucket:

| Confidence | Severity | Bucket |
|------------|----------|--------|
| 76+ | high | **Critical** |
| 76+ | med | Important |
| 76+ | low | Suggestions |
| 51–75 | high | Important |
| 51–75 | med | Important |
| 51–75 | low | Suggestions |
| 26–50 | any | Suggestions |
| 0–25 | any | suppressed (unless `[pre-existing]` high → Important) |

Then present:

1. **Critical** (must fix)
2. **Important** (should fix)
3. **Suggestions** (nice to have), each with its `do`/`opportunistic`/`skip` verdict
4. **Positive observations**

End with a brief overall assessment. If the caller supplied a change description, say
whether the diff delivers what it claims.
