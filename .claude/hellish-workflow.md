# hellish workflow — fixing the shell so it runs the ft_linux build

This is the runbook for the core loop of this project: **every ft_linux build script
runs under hellish (our 42sh, `vendor/42sh`), and each script hellish has to run is an
opportunity to harden hellish.** When hellish can't run something, we fix *hellish* —
with a solution that **scales better and performs better** — not the script.

Read this together with the "Fixing hellish" section of `CLAUDE.md`.

---

## 1. Triage: is it the interpreter or the script?

Run the same script under **bash** as the oracle (`RUNNER=bash`, or
`bash -c '<repro>'`).

- **Works under bash, fails under hellish → interpreter bug → fix hellish.**
  Never rewrite the ft_linux script to dodge the construct.
- **Fails under bash too → genuine script bug → fix the script.**
  (Examples seen: `info()` writing to stdout polluting a command-sub return; a
  non-idempotent `extract()`.)

The fix must be **root-cause, scalable, and faster** — no patches, no hardcoding,
covering the edge cases (not just the one input that failed).

---

## 2. Work on a dedicated branch

Do all of it on a **separate branch** in `vendor/42sh` (e.g. `fix/<slug>` or the
current campaign branch). Never validate on `main`/`develop` directly.

```
cd vendor/42sh
git checkout -b fix/<slug>        # off the integration branch
make                              # debug+ASan build → build/bin/hellish
build/bin/hellish -c '<minimal repro>'   # reproduce; ASan gives the crash site
# ... root-cause fix in src/ ...
```

---

## 3. Definition of Done — validate hellish is functional

A fix is **not done** until ALL of the following pass. Run them every time; never skip one.

1. **Full functional suite — all `tests/*` pass.**
   `make -C vendor/42sh test` (it runs the curated default list incl.
   `regress_hellish`). For thoroughness also run the broad set of test-list files.
   Output must match bash for every case.

2. **Benchmark with `OPT=1` — hellish still faster than bash.**
   `make -C vendor/42sh bench` (this builds `OPT=1` and races vs `bash --posix`).
   The geomean must stay **≥ ~1.0** (faster/at-parity), wall-clock faster, and **zero
   output MISMATCH**. Note: libft must be built `-O3` (its Makefile shipped `-O0`,
   which made hellish far slower) — keep it that way.

3. **Hard tests pass, faster, same output.**
   The `bench` `hard` class runs `tests/hard/*.sh` (100–500-line real programs). They
   must produce **identical output to bash** (no MISMATCH) **and run faster** in hellish.

4. **Norminette clean on all C.**
   `make -C vendor/42sh norm` — every `.c`/`.h` touched must pass norminette
   (25 lines/func, ≤5 funcs/file, 80 cols, valid 42 header). No exceptions.

5. **New tests cover the new logic — so we never regress it.**
   For every construct fixed or added, add a deterministic case to
   `tests/regress_hellish` AND `scripts/conformance.sh`. These run again and again on
   every future iteration. A fix without a test does not count as done.

6. **Special syntax / sugar from the ft_linux scripts becomes a permanent test.**
   When a specific pattern or command from the ft_linux build scripts misbehaves under
   hellish, write a small test that exercises *that exact pattern* (the real shape the
   build uses — sourcing-with-comment, `exec > >(tee …)`, `comm <(…) <(…)` with shell
   vars, `"$VAR"/{a,b}` brace, `[[ … ]]`, pushd/popd, `set -euo pipefail`, …) and add it
   to the tests, so the build's needs are continuously regression-tested.

---

## 4. Commit, merge, publish

- **Commit as sole author — NO `Co-Authored-By` trailer** (both `vendor/42sh` and the
  ft_linux superproject).
- Once everything in §3 is green on the branch, **merge into `develop`**.
  (Promote `develop → main` when it's solid / when capable.)
- Then **rebuild + republish** the hellish image and **rebuild the builder** so the
  build uses the fixed hellish, **bump the submodule pointer**, and **re-run the phase**:
  ```
  make -C vendor/42sh fclean && make -C vendor/42sh OPT=1 all
  docker build -t dlesieur/hellish-shell:latest -t dlesieur/hellish-shell:<sha> \
      -f vendor/42sh/Dockerfile vendor/42sh
  # push (creds in vendor/42sh/.env, --password-stdin); then:
  make image && make phase-<x>          # re-run under hellish
  ```
- `make my_shell` (sudo, installs `/usr/bin/hellish`) and pushes to `Univers42/*` are
  user-gated unless told otherwise.
- Only **file an issue** on `Univers42/42sh` if a bug is genuinely unfixable in the loop.

---

## 5. The conformance gate runs *before* a long build

`scripts/conformance.sh` (host) and `make check-hellish` diff every construct the build
scripts use under hellish vs bash. **Keep it green before kicking off a 30–60 min phase**
— that's what catches a missing construct before the phase deadlocks on it.

---

## 6. Known gaps tracker (add a test + fix each)

- `set -e` does not abort a failing *multi-stage pipeline* (simple commands do).
- `[[ … && … ]]` internal logic (the shell splits on `&&` before `[[` sees it).
- Arrays `a=(…)` (only `vm-run.sh` uses them, host/bash — out of the in-container path).

When any of these is hit by the build, fix it via §1–§4 and add its `regress_hellish`
+ `conformance.sh` cases.
