# 05 — Autonomous execution protocol

How I work the project alone, unsupervised, all day — making good engineering decisions,
conserving credit, and never doing anything destructive or host-touching.

## The milestone loop

For each milestone (M0→M7 in `00-master.md`):

```
1. Implement the smallest shippable slice (inline; or a developer agent for a big chunk).
2. Run it under hellish in Docker.
3. Gate:
   - build scripts: conformance.sh = 0 divergences before any long build.
   - hellish changes: 1703 tests + bench geomean ≥1.0 + hard tests + norm (DoD).
4. If hellish diverges from bash → fix-loop (03-hellish.md / .claude/hellish-workflow.md).
5. Commit a checkpoint on `develop` (sole author, no Co-Authored-By).
6. Append a dated entry to PROGRESS.md (what changed, why, results, next).
7. Next slice.
```

Long builds (`make phase-*`, GCC, full `make build`) run in the **background**; I wake on a
sensible cadence (not tight polling) and act on completion. Stamp idempotency means a
failed long build resumes, not restarts.

## Agent team — sparing, credit-aware

Default to **inline** work. Spawn an agent only when it clearly pays off, with full context,
and have it return a **concise artifact** (not a transcript). Cold agents re-derive context
= expensive, so batch related work into *one* well-scoped agent rather than many tiny ones.

| Role | When to spawn | Returns |
|---|---|---|
| **Developer** | a large parallelizable chunk (e.g. draft a B2 batch of ~15 `build_<pkg>()` recipes from the LFS book) | the recipes + packages.sh entries |
| **Auditor/Critic** | a completed batch needs adversarial review (LFS/FHS compliance, hellish-safety, idempotency, security) | a findings list, ranked |
| **Benchmarker** | confirm hellish geomean ≥1.0 after a fix; catch a perf regression | the numbers + verdict |
| **Explore** | locating something across the tree when I'm unsure | file:line pointers |

Cap concurrency (≈1–2 at a time). Prefer background agents so I keep progressing. If an
agent's output is unused or wrong, don't reflexively re-spawn — reconsider inline.

## Checkpoints, branches, commits

- **ft_linux:** integration branch `develop`; risky refactors on `feature/<slug>` →
  merge to `develop` when green. `main` stays stable.
- **vendor/42sh:** hellish fixes on `fix/<slug>` → `develop` (per hellish-workflow.md).
- Commit **after every milestone** (and after each green hellish fix). Messages: concise,
  imperative, **sole author, no `Co-Authored-By` trailer**.
- Bump the submodule pointer in ft_linux whenever hellish advances; commit it (no co-author).

## Hard guardrails (never cross autonomously)

- **No sudo. No host package installs. No host changes outside the repo.** No `make my_shell`.
- **No destructive git:** no force-push, no history rewrite, no branch deletion of shared
  branches. Never commit `build/` or `vendor/42sh/.env`.
- Docker only; `--rm` containers; writes confined to `build/`.
- **Authorized outward action:** republish the `dlesieur/hellish-shell` image to Docker Hub
  (the fix-loop needs it; creds via `vendor/42sh/.env` + `--password-stdin`).
- **User-gated (do NOT do alone):** git pushes to `Univers42/*` remotes; `sudo`/`my_shell`;
  anything that mutates the host or a shared remote's protected branches.

## STOP-and-wait conditions

Pause and leave a clear PROGRESS.md note (rather than guessing) only when:
- the next step *requires* sudo / a host change / a user-gated push;
- an action is destructive or outward-facing and irreversible;
- a genuine ambiguity would risk a large amount of wrong-direction work
  (e.g. the subject and LFS disagree on a mandatory choice with no safe default).

Otherwise: **decide, document the decision + rationale in PROGRESS.md, proceed.**

## Credit / token discipline

- Front-loaded plan docs (this set) so I don't re-derive strategy mid-run.
- Targeted reads (`grep`, line ranges), not whole-file dumps; reuse known context.
- Background long builds; avoid tight polling wake-ups.
- Commit frequently so the conversation can compact without losing progress.
- Edit over rewrite; small diffs.
- Spawn agents only with a clear ROI; one well-scoped agent over many small ones.

## Resumability contract

At any wake-up or new session, I can reconstruct state from: `PROGRESS.md` (latest entry),
the git log on `develop`, the `$LFS/.stamps/` set inside `build/ft_linux.img`, and
`build/logs/`. Nothing critical lives only in conversation context.

## Daily close-out (end of the autonomous session)

Leave: a PROGRESS.md summary (done / in-flight / blocked / decisions), all work committed
on `develop`, suites green (or the single red item clearly flagged with the repro), and the
next concrete step written down.
