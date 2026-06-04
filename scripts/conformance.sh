#!/usr/bin/env bash
# Conformance gate: every shell construct the ft_linux build scripts use, run
# under hellish vs bash and diffed. Must be green before building under hellish
# (pure-hellish: no bash fallback). Point at a specific build with HELLISH=/path.
#
# The chk snippets are passed verbatim to the shell under test; they must stay
# single-quoted (the outer shell must not expand them).
# shellcheck disable=SC2016
set -uo pipefail

HS="${HELLISH:-hellish}"
fail=0

chk() {
    local name="$1" prog="$2" hd bd h b
    hd="$(mktemp -d)"
    bd="$(mktemp -d)"
    h="$(
        cd "$hd" && ASAN_OPTIONS=detect_leaks=0 timeout 10 "$HS" -c "$prog" 2>&1
        printf '[%s]' "$?"
    )"
    b="$(
        cd "$bd" && timeout 10 bash -c "$prog" 2>&1
        printf '[%s]' "$?"
    )"
    rm -rf "$hd" "$bd"
    if [[ "$h" == "$b" ]]; then
        printf '  ok   %s\n' "$name"
    else
        fail=$((fail + 1))
        printf '  FAIL %s\n       hellish: %s\n       bash:    %s\n' "$name" \
            "$(printf '%s' "$h" | tr '\n' '|')" "$(printf '%s' "$b" | tr '\n' '|')"
    fi
}

echo "==> hellish conformance: $HS vs bash"
chk 'source+leading-comment' 'printf "#c\nf(){ echo F; }\n" >l; . ./l; f'
chk 'heredoc-expand' 'X=hi; cat <<E
[$X]
E'
chk 'heredoc-quoted' 'cat <<"E"
[$X]
E'
chk 'procsub-input' 'comm -13 <(printf "a\nb\n") <(printf "b\nc\n")'
chk 'multiline-continuation' 'echo a \
b \
c'
chk 'arith-in-arg' 'B=512; echo $((3 + B))MiB'
chk 'trap-exit' 'trap "echo bye" EXIT; echo hi'
chk 'case' 'x=5; case $x in 5) echo five ;; *) echo no ;; esac'
chk 'func-positional' 'f(){ echo "[$1:$2]"; }; for i in a b; do f "$i" z; done'
chk 'pushd-popd' 'mkdir -p a/b; cd a; pushd b >/dev/null; basename "$PWD"; popd >/dev/null; basename "$PWD"'
chk 'dbracket-file' '[[ -f /etc/hostname ]] && echo yes || echo no'
chk 'dbracket-arith' '[[ "$(id -u)" -eq 0 ]] && echo root || echo nonroot'
chk 'dbracket-logic' '[[ -n abc && -z "" ]] && echo combo'
chk 'dbracket-string' 'v=abc; [[ "$v" != xyz ]] && echo ne'
chk 'brace-literal' 'echo /tmp/{a,b,c}'
chk 'brace-var-prefix' 'X=/tmp; echo "$X"/{etc,var}/x "$X"/usr/{bin,lib}'
chk 'brace-quoted-noexpand' 'echo "{a,b}"'
chk 'pipefail' 'set -o pipefail; false | true; echo $?'
chk 'set-e-simple' 'set -e; false; echo NOPE'
chk 'param-default' 'echo "${z:-def}"; z=set; echo "${z:-def}"'
echo "==> $fail divergence(s)."
[[ "$fail" -eq 0 ]]
