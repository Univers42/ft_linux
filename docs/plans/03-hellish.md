# 03 — hellish compliance: gate, frontier, gaps, fix-loop

Every build script runs under hellish. This doc tracks the conformance gate, the live
binutils-`configure` frontier, the known gaps, and the publish loop. The **Definition of
Done** for any hellish fix is in `.claude/hellish-workflow.md` — follow it verbatim
(1703 tests + bench geomean ≥1.0 + hard tests faster/same-output + norm + a new regress
case). Commit **sole author, no `Co-Authored-By`**; merge to `develop`.

## The conformance gate (`scripts/conformance.sh`)

Run **before any long build**: `HELLISH=vendor/42sh/build/bin/hellish bash
scripts/conformance.sh` → must report `0 divergence(s)`. It diffs each construct hellish
vs bash. Current coverage is good but **missing cases to add in M0**:

- `exec > >(tee -a f) 2>&1` — the redirect every phase runs through ([lib.sh:43](../../scripts/lib.sh#L43)).
  This is the highest-value missing case.
- `set -e` aborting a **multi-stage** pipeline (`set -e; false | true | true; echo NO`).
- `[[ a && b ]]` internal logic (`dbracket-logic` is present but documented-failing — keep
  it red until fixed, don't delete).
- `MAKEFLAGS`/`-j` propagation sanity (a recipe-shaped `make -jN` no-op).
- The `lib.sh` helpers as black-box snippets: `fetch`-style `$(...)` capture, `step`/stamp,
  `with_clean_build`, the `unpack` command-sub chain.

Mirror every NEW case into `vendor/42sh/tests/regress_hellish` so the shell suite locks it.

## Live frontier — binutils `configure` under hellish

**Symptom** (hellish only; bash passes): `configure: WARNING: invalid host type:` (empty),
`checking build system type... config.sub: missing argument`, `configure: error:
.../config.sub failed`, `cache variable ac_cv_env_build_alias_value contains a newline`.

**What we know:** `configure` and `config.guess`/`config.sub` carry `#!/bin/sh` shebangs, so
they execute under the builder's `/bin/sh` (dash/bash), **not** hellish — the divergence is
therefore in *what hellish hands to / sets around* that invocation, not inside configure.
binutils-pass1 passes **no** `--build=$(...)` arg, yet `build_alias` ends up holding a
newline ⇒ the value is coming from the **environment** hellish exports to the child.

**Top hypotheses (diagnose in order):**
1. **hellish exports an env var whose value carries a trailing `\n`** (e.g. a var set from
   `$(...)` upstream that wasn't newline-stripped, then exported). configure caches env vars
   and rejects newlines → exact error. *Check:* in the builder, under hellish, dump
   `env | cat -A` right before the failing configure and diff vs bash.
2. **Command substitution `$(...)` not stripping all trailing newlines** somewhere in
   `lib.sh`/`build-toolchain-lib.sh` (`config.guess` capture, `fetch` return). POSIX
   requires stripping trailing newlines. *Check:* `x="$(printf 'a\n\n')"; printf '[%s]' "$x"`
   under hellish vs bash.
3. **A var with embedded newline propagated via `get_envp`/`get_envp_all`** (the procsub env
   path touched this session) — verify exported set matches bash exactly (names+values),
   `cat -A` to reveal control chars.

**Method:** reproduce in isolation in the builder (`make shell`, then run a single
`build_binutils_pass1`-shaped configure under hellish), bisect with `env -i` + minimal vars,
`cat -A` everything. Root-cause → fix in `vendor/42sh/src/…` → regress case (`env`-export
newline / `$(...)` trailing-newline) → DoD gates → republish.

## Known gaps (fix + test each as the build hits it)

| Gap | Effect on build | Plan |
|---|---|---|
| `set -e` on **multi-stage** pipeline doesn't abort | a failing mid-pipeline stage may be missed | fix exit-status propagation; regress + conformance case |
| `[[ a && b ]]` internal `&&` | shell splits on `&&` before `[[` | parse `&&`/`\|\|` inside `[[ ]]`; case already in conformance (red) |
| arrays `arr=(…)` | not used by build (only host `vm-run.sh`) | implement as hardening; **build must not depend on it** |
| command-sub newline stripping (if confirmed by frontier) | autotools build-type detection | POSIX trailing-newline strip; regress case |

## hellish-in-chroot (script-mode build)

Phase 2 needs hellish inside the chroot (§01.7). Provide a **script-mode hellish**:
- Prefer a `--without-readline` / static-ish build (script mode never line-edits), so it
  drops the `libreadline`/`libtinfo` runtime dependency that may not exist early in Ch.8.
- If we keep the dynamic binary, stage `libreadline.so*`/`libtinfo.so*` into the chroot
  before chrooting (they exist in the builder image).
- Verify with a chroot smoke test (`hellish -c 'echo ok'`) before driving `build-all.sh`.

## The publish loop (after a green hellish fix)

```
cd vendor/42sh
make fclean && make OPT=1 all          # optimized binary
make test && make bench && make norm   # DoD gates (see hellish-workflow.md)
# commit (sole author, no co-author), merge -> develop
docker build -t dlesieur/hellish-shell:latest -t dlesieur/hellish-shell:<sha> \
    -f Dockerfile .                    # vendor/42sh/Dockerfile packages the binary
echo "$DOCKER_PAS" | docker login -u "$DOCKER_LOGIN" --password-stdin   # .env, gitignored
docker push dlesieur/hellish-shell:latest && docker push …:<sha>
cd ../.. && make image                 # builder COPYs the fresh hellish
# bump submodule pointer in ft_linux, commit (no co-author), then re-run the phase
```

`make my_shell` (sudo, host `/usr/bin/hellish`) and pushes to `Univers42/*` git remotes are
**user-gated** — do not run them autonomously. Docker Hub image republish **is** authorized
(the fix-loop needs it).

## hellish fixes already landed (each has a regress case)

assignment-only NULL-argv crash · bare-`for` crash · `source`/`eval` leading-comment ·
`exec > >(tee)` exit hang (procsub detach) · `pushd`/`popd` · `set -o pipefail` · single
`[[ … ]]` test · brace expansion with `$var`/quoted prefix · procsub inheriting
non-exported vars (`get_envp_all`). Perf: libft built `-O3` (was `-O0`).
