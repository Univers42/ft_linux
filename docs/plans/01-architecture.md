# 01 — Architecture & DSA: the build orchestrator

The interesting computer-science of an LFS build is **dependency-ordered, idempotent,
resource-bounded, reproducible orchestration** of ~90 source builds inside one container,
driven by a shell (hellish) that doesn't yet have every bash convenience. This doc fixes
the data structures and algorithms before any code is written.

## Design goals (ranked)

1. **Correct & reproducible** — same inputs ⇒ same build, every time, on any host.
2. **Resumable** — an unsupervised multi-hour run must resume after a failure, not restart.
3. **Fast within resource limits** — saturate cores per package without OOM.
4. **hellish-safe** — use only constructs hellish supports (or harden hellish first).
5. **Production-grade & legible** — small functions, one job each, matching existing style.

## 1. Package model — a declarative record per package

Mirror the proven toolchain pattern ([build-toolchain-lib.sh](../../scripts/build-toolchain-lib.sh)):
each package is a `build_<pkg>()` function (configure flags + post-install fixups encoded
verbatim from the LFS book) plus pinned metadata in [packages.sh](../../scripts/packages.sh):

```
<PKG>_VERSION=...
<PKG>_URL=...
<PKG>_SHA256=...      # NEW: integrity + reproducibility
<PKG>_DEPS="a b c"    # NEW: names that MUST appear earlier in the order (validation only)
```

**Why functions, not a table?** hellish lacks robust `arr=(...)` arrays (a documented gap).
A function-per-package + a flat ordered name-list sidesteps arrays entirely and matches the
working toolchain code. Arrays get implemented in hellish as *hardening* (`03-hellish.md`),
but **the build never depends on them**.

## 2. Build order — the LFS topological sort, validated (not recomputed)

The LFS book's Ch.8 order is a hand-tuned topological sort that also encodes *bootstrap*
subtleties (e.g. packages built against temp tools then rebuilt) that a naive
dependency-graph topo-sort gets wrong. So:

- **Source of order:** an explicit newline-delimited `ORDER` string (the book's order).
- **Validator (cheap DSA):** before building, walk `ORDER` once; for each package assert
  every name in `<PKG>_DEPS` already appeared. O(N + E) over a built-set (a shell
  associative check via stamp-style marker files / a `case` membership test). This catches
  an accidental reorder without us re-deriving the fragile bootstrap ordering.
- Iterate with `for pkg in $ORDER; do step "$pkg-$ver" build_$pkg; done` — array-free.

## 3. Idempotency & resumability — stamp memoization

Reuse `step`/`is_done`/`stamp_done` ([lib.sh:152-174](../../scripts/lib.sh#L152-L174)).
Stamp key = `<pkg>-<version>` under `$LFS/.stamps/` **inside the image** (survives
container `--rm`). Properties:

- A completed package is skipped on re-run ⇒ failure resumes from the first incomplete
  package. This is the backbone of unsupervised operation.
- To force a rebuild: delete the stamp inside the mounted image.
- *Future option:* key on `<pkg>-<version>-<recipe-hash>` so editing a recipe auto-invalidates;
  deferred (adds in-shell hashing) — manual stamp deletion is fine for now.

## 4. Source cache — content-addressed + integrity-checked

`fetch()` ([lib.sh:111-126](../../scripts/lib.sh#L111-L126)) already caches by filename
(which carries the version) in `build/sources`. Add:

- **sha256 verification** against `<PKG>_SHA256` *before* extract — fail closed on mismatch.
  Reproducibility + supply-chain integrity, near-zero cost.
- **Mirror fallback:** try the pinned URL, then a GNU/LFS mirror, before failing.
- `extract()` is already idempotent (derives top dir from the tarball, clears stale copy).

## 5. Parallelism & resource model

- **Within a package:** `make -j N` — the dominant speedup.
- **Across packages:** **none.** Ch.8 is a near-linear chain; cross-package parallelism is
  unsafe (shared `$LFS`, ordering), low-value (one VM), and breaks idempotent stamping.
- **N is computed at runtime, in-script** (hellish-evaluated), not in compose:
  `N = min(nproc, max(1, MemAvailableGB / 2))`. gcc/glibc/binutils are RAM-hungry; halving
  by memory prevents OOM on small hosts. This **replaces the dead literal**
  `MAKEFLAGS: "-j$(nproc)"` in [docker-compose.yml:30](../../docker/docker-compose.yml#L30)
  (compose never expands `$()`). Set `MAKEFLAGS="-j$N"` in `lib.sh` / entrypoint instead.
- **Disk:** every `build_<pkg>` ends with `rm -rf "$src"` (already the toolchain habit) to
  bound the 20 GB image; sources stay in the cache, not the image.

## 6. Reproducibility & pinning

- Debian base **by digest** (`debian:12-slim@sha256:…`) in the Dockerfile.
- Every package `VERSION` + `SHA256` pinned in `packages.sh`.
- Committed `configs/kernel/.config` (no `defconfig` drift).
- Submodule commits pinned in `.gitmodules` (hellish + libft, incl. the `-O3` libft).
- `SOURCE_DATE_EPOCH` exported where build systems honor it.
- **Scope:** we target *reproducible inputs + an idempotent process* (practical
  reproducibility). Full bit-identical output (build paths, timestamps, parallel
  nondeterminism) is a research goal beyond the subject — explicitly out of scope.

## 7. hellish in the chroot (decision + fallback)

Phase 2 builds inside `chroot $LFS`, which has only the *target* system's tools — hellish
is not there by default. To honor "hellish runs the scripts" inside the chroot:

- **Stage a script-mode hellish into the chroot** (`/tools/bin/hellish`): a no-readline /
  statically-linkable build (script mode never needs line-editing). The Ch.8 `build-all`
  then runs under hellish in the chroot — the ultimate hardening test (a 90-package build
  driven by our shell).
- **Autonomy-safe fallback (per package):** if one package deadlocks hellish and isn't
  quickly fixable, build *that package* under the chroot's bash, **record the gap + add a
  `conformance.sh` + `regress_hellish` case**, and keep the subject moving. Never silent.
- **Precedence:** hellish-first; subject progress is never fully blocked by one shell bug.

## 8. Module boundaries (files)

| File | Role |
|---|---|
| `scripts/packages.sh` | pinned `VERSION`/`URL`/`SHA256`/`DEPS` per package (data only). |
| `scripts/build-system-lib.sh` (NEW) | `build_<pkg>()` recipes for Ch.8 (mirrors toolchain lib). |
| `scripts/02-build-system.sh` | chroot setup, hellish staging, sources `build-system-lib.sh`, runs `ORDER`. |
| `scripts/lib.sh` | add sha256 verify in `fetch`, runtime `-j` `MAKEFLAGS`, order validator. |
| `scripts/conformance.sh` | one case per construct any recipe uses (gate before long builds). |

Keep functions ≤ ~30 lines, files focused; match the existing toolchain-lib idiom.

## Complexity summary

- Order validation: **O(N + E)** one pass (N≈90, E small).
- Build: **O(N)** package builds, each `make -j N`; cache lookups **O(1)**; stamp checks **O(1)**.
- Memory: bounded by the `-j` heuristic. Disk: bounded by post-install cleanup.
