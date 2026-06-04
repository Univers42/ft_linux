# PROGRESS — ft_linux autonomous run log

Append-only, newest at top. One entry per milestone or significant decision. This + the
git log on `develop` + `$LFS/.stamps/` + `build/logs/` are the source of truth for
resuming. Format per entry:

```
## YYYY-MM-DD HH:MM — <milestone/topic>
- did: …
- result: … (tests/conformance/build status)
- decided: … (+ why)
- next: …
```

---

## 2026-06-04 — Planning complete (pre-journey)
- did: wrote the plan set under `docs/plans/` (00 master, 01 architecture/DSA, 02 Ch.8
  manifest, 03 hellish, 04 kernel/boot/net, 05 autonomy) + this log. Master strategy in
  `.claude/plans/snuggly-soaring-hanrahan.md`; hellish DoD in `.claude/hellish-workflow.md`.
- result: docs only; no code/build changes yet. Awaiting user go-ahead to start the journey.
- decided: hellish-in-chroot with per-package bash fallback; no cross-package parallelism +
  runtime-tuned `-j`; static network to QEMU user-net defaults; ship `wget` for the network
  requirement; practical (not bit-identical) reproducibility; no ccache. (See 01/04 for why.)
- open items found while planning: `MAKEFLAGS: "-j$(nproc)"` literal in docker-compose
  (compose won't expand `$()`); `conformance.sh` lacks an `exec > >(tee)` case; binutils
  `configure` fails under hellish only (frontier — see 03).
- next: on go-ahead, start **M0** (conformance cases + MAKEFLAGS fix + binutils-configure
  root-cause/fix + republish image), then M1.
