#!/usr/bin/env bash
# Differentially run our scripts under hellish vs bash on the host and report
# where hellish diverges (crash, hellish-only syntax error, different exit).
# Our phase scripts self-guard (require_in_container / arg checks) so they exit
# early and harmlessly off-container — safe to execute here.
# A divergence is a hellish bug to fix in vendor/42sh (see project memory).
set -uo pipefail

SHELL_BIN="${HELLISH:-hellish}"
TIMEOUT="${TIMEOUT:-20}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

FILES=()
for f in "$ROOT"/scripts/*.sh "$ROOT"/docker/entrypoint.sh; do
    [[ "$f" == *"/check-hellish.sh" ]] && continue
    [[ -f "$f" ]] && FILES+=("$f")
done

run_pair() {
    local abs="$1"
    HOUT="$(cd "$(mktemp -d)" && timeout "$TIMEOUT" "$SHELL_BIN" "$abs" 2>&1)"
    HRC=$?
    BOUT="$(cd "$(mktemp -d)" && timeout "$TIMEOUT" bash "$abs" 2>&1)"
    BRC=$?
}

verdict() {
    REASON=""
    if [[ "$HRC" -ge 128 ]]; then
        REASON="hellish crashed: signal $((HRC - 128)) (exit $HRC)"
    elif grep -qi 'syntax error' <<<"$HOUT" && ! grep -qi 'syntax error' <<<"$BOUT"; then
        REASON="hellish reports a syntax error bash accepts"
    elif [[ "$HRC" -ne "$BRC" ]]; then
        REASON="hellish exit $HRC != bash exit $BRC"
    fi
}

main() {
    local f rel fail=0
    echo "==> check-hellish: $SHELL_BIN vs bash over ${#FILES[@]} scripts"
    for f in "${FILES[@]}"; do
        rel="${f#"$ROOT"/}"
        run_pair "$f"
        verdict
        if [[ -n "$REASON" ]]; then
            fail=$((fail + 1))
            printf 'FAIL  %-32s %s\n' "$rel" "$REASON"
            printf '%s\n' "$HOUT" | sed 's/^/        | /' | head -5
        else
            printf 'ok    %-32s (exit %s)\n' "$rel" "$HRC"
        fi
    done
    echo "==> $fail divergence(s). Fix each in vendor/42sh."
    [[ "$fail" -eq 0 ]]
}

main
