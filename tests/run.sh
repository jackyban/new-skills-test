#!/usr/bin/env bash
# Behaviour tests for the login wizard.
#
# Ticket 01: check-mode resolution (which gh, which version, how it was found).
# Ticket 02: the auth verdict (can this host be used, and as whom).
#
# Only external behaviour is asserted: the exit code and the single status line
# that --check puts on stdout. Nothing here reaches into the script's internals,
# and nothing here needs a network or a browser. One case deliberately uses the
# real CLI — the conventional-install-location rung — and says so.
#
# Usage: bash tests/run.sh [--fail-fast]
#
# WIZARD_TEMPLATE may point at the wizard template, for the frozen-library
# invariant. When it cannot be found that one check is skipped loudly rather
# than passed silently.
set -u

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$here/.." && pwd)
wizard="$repo/gh-login-wizard.sh"
fake_dir="$here/fake"
REAL_PATH="$PATH"

fail_fast=0
[[ "${1:-}" == "--fail-fast" ]] && fail_fast=1
finished=0

passed=0
failed=0
skipped=0

pass() { passed=$((passed + 1)); printf '  ok    %s\n' "$1"; }
fail() {
  failed=$((failed + 1))
  printf '  FAIL  %s\n' "$1"
  [[ $# -gt 1 ]] && printf '        %s\n' "$2"
  if (( fail_fast )); then finish; fi
}
skip() { skipped=$((skipped + 1)); printf '  skip  %s\n' "$1"; }
finish() {
  (( finished )) && return
  finished=1
  printf '\n%d passed, %d failed, %d skipped\n' "$passed" "$failed" "$skipped"
  (( failed == 0 ))
  exit $?
}
trap 'finish' EXIT

SANDBOX=$(mktemp -d) || { printf 'mktemp failed\n' >&2; failed=1; exit 1; }
mkdir -p "$SANDBOX/home" "$SANDBOX/work"
printf 'MARKER=seeded\n' >"$SANDBOX/work/.env"
env_before=$(cat "$SANDBOX/work/.env")

# A PATH lookup finds an executable, so the fake needs its executable bit. On
# NTFS there is no such bit and Git Bash decides by shebang instead, so a chmod
# that appears to do nothing is expected there; on a POSIX checkout it is load
# bearing, and a harness that cannot get it should say so instead of reporting
# the fake as "not installed".
if [[ ! -x "$fake_dir/gh" ]]; then
  chmod +x "$fake_dir/gh" 2>/dev/null || true
fi
if [[ ! -x "$fake_dir/gh" ]] && [[ "$(uname -s 2>/dev/null)" != MINGW* ]] && [[ "$(uname -s 2>/dev/null)" != MSYS* ]]; then
  printf 'tests/fake/gh is not executable and chmod did not help; run: chmod +x %s\n' "$fake_dir/gh" >&2
  failed=1
  exit 1
fi

# No isolated tool sandbox. Symlinking bash out of its install directory breaks
# MSYS (its loader cannot find the runtime beside a symlink), and wiping the
# environment strips the platform variables MSYS needs to resolve paths at all.
# So the harness keeps the real PATH and steers resolution by putting the fake
# first — which is the thing the wizard actually consults.

OUT=""
ERR=""
RC=0

# run_check PATH_PREFIX WORKDIR [VAR=VAL ...] -- [ARGS ...]
run_check() {
  local path_prefix="$1" workdir="$2"
  shift 2
  local -a extra=()
  while [[ $# -gt 0 && "$1" != "--" ]]; do extra+=("$1"); shift; done
  [[ "${1:-}" == "--" ]] && shift
  local -a args=("$@")
  local errf="$SANDBOX/stderr"
  local out
  # env, not assignment prefixes: words produced by an expansion are never
  # treated as assignments, so "VAR=VAL" coming out of an array would be taken
  # as the command name. env also keeps the platform variables intact.
  out=$( cd "$workdir" && env PATH="$path_prefix" HOME="$SANDBOX/home" \
           ${extra[@]+"${extra[@]}"} bash "$wizard" --check ${args[@]+"${args[@]}"} </dev/null 2>"$errf" )
  RC=$?
  OUT="$out"
  ERR=$(cat "$errf")
}

# Absolute locations the wizard falls back to. If one of these exists on this
# machine, a "not installed anywhere" case cannot be simulated honestly, so the
# case is skipped by name instead of faked green.
existing_candidates() {
  local c
  for c in "/c/Program Files/GitHub CLI/gh.exe" /usr/bin/gh /usr/local/bin/gh \
           /snap/bin/gh /opt/homebrew/bin/gh /home/linuxbrew/.linuxbrew/bin/gh \
           "${LOCALAPPDATA:-}/GitHubCLI/gh.exe" "${LOCALAPPDATA:-}/Microsoft/WinGet/Links/gh.exe" \
           "${HOME:-}/scoop/shims/gh.exe" "${HOME:-}/.local/bin/gh"; do
    [[ -e "$c" ]] && printf '%s\n' "$c"
  done
}

section() { printf '\n%s\n' "$1"; }

HEAD="host=github.com minimum=2.40.0"

# ── A usable CLI, judged by the API ─────────────────────────────────────────
section "a usable CLI"
run_check "$fake_dir:$REAL_PATH" "$SANDBOX/work" FAKE_GH_MODE=ready --
expected="state=logged-in exe=$fake_dir/gh version=2.79.0 source=path $HEAD user=octocat scopes=gist,read:org,repo"
if [[ $RC -eq 0 ]]; then pass "exits 0"; else fail "exits 0" "got $RC; stderr: $ERR"; fi
if [[ "$OUT" == "$expected" ]]; then pass "one status line, fixed field order"; else fail "one status line, fixed field order" "expected: $expected / got: $OUT"; fi

run_check "$fake_dir:$REAL_PATH" "$SANDBOX/work" FAKE_GH_MODE=ready -- --expect-user octocat
if [[ $RC -eq 0 && "$OUT" == *" user=octocat "* ]]; then
  pass "--expect-user matching the actual account passes"
else
  fail "--expect-user matching the actual account passes" "rc=$RC out=$OUT"
fi

# ── A CLI that is too old ───────────────────────────────────────────────────
section "too old / unparseable"
run_check "$fake_dir:$REAL_PATH" "$SANDBOX/work" FAKE_GH_MODE=old --
if [[ $RC -eq 11 ]]; then pass "old version exits 11"; else fail "old version exits 11" "got $RC"; fi
if [[ "$OUT" == "state=gh-too-old exe=$fake_dir/gh version=2.1.0 source=path $HEAD user= scopes=" ]]; then
  pass "old version reported in the status line"
else
  fail "old version reported in the status line" "got: $OUT"
fi

run_check "$fake_dir:$REAL_PATH" "$SANDBOX/work" FAKE_GH_MODE=garbled --
if [[ $RC -eq 11 && "$OUT" == "state=gh-too-old exe=$fake_dir/gh version= source=path $HEAD user= scopes=" ]]; then
  pass "unparseable version is too old, never usable"
else
  fail "unparseable version is too old, never usable" "rc=$RC out=$OUT"
fi

if [[ "$ERR" == *"parseable"* ]]; then
  pass "an unparseable banner is explained on stderr"
else
  fail "an unparseable banner is explained on stderr" "stderr: $ERR"
fi

# ── The explicit environment variable wins ──────────────────────────────────
section "resolution order"
cp "$fake_dir/gh" "$SANDBOX/custom-gh"
chmod +x "$SANDBOX/custom-gh"
run_check "$REAL_PATH" "$SANDBOX/work" "DSH_GH_PATH=$SANDBOX/custom-gh" FAKE_GH_MODE=ready --
if [[ $RC -eq 0 && "$OUT" == "state=logged-in exe=$SANDBOX/custom-gh version=2.79.0 source=env:DSH_GH_PATH $HEAD user=octocat scopes=gist,read:org,repo" ]]; then
  pass "DSH_GH_PATH is used, and says so"
else
  fail "DSH_GH_PATH is used, and says so" "rc=$RC out=$OUT"
fi

printf 'not executable\n' >"$SANDBOX/broken-gh"
run_check "$fake_dir:$REAL_PATH" "$SANDBOX/work" "DSH_GH_PATH=$SANDBOX/broken-gh" FAKE_GH_MODE=ready --
if [[ $RC -eq 0 && "$OUT" == "state=logged-in exe=$fake_dir/gh version=2.79.0 source=path $HEAD user=octocat scopes=gist,read:org,repo" ]]; then
  pass "a broken DSH_GH_PATH falls through to PATH"
else
  fail "a broken DSH_GH_PATH falls through to PATH" "rc=$RC out=$OUT"
fi
if [[ "$ERR" == *"DSH_GH_PATH"* ]]; then
  pass "a broken DSH_GH_PATH is named, not swallowed"
else
  fail "a broken DSH_GH_PATH is named, not swallowed" "stderr: $ERR"
fi

# ── Found where it is installed, not on PATH ────────────────────────────────
# The third rung. This case deliberately runs the real CLI, because the only
# way to reach a conventional location is a real one being there; it therefore
# makes one authenticated read-only call. Only the rung is asserted, so any
# verdict it reaches — including "unreachable" on an offline machine — is fine.
section "found at a conventional location"
path_gh=$(command -v gh 2>/dev/null || true)
ghdir=""
[[ -n "$path_gh" ]] && ghdir=$(dirname "$path_gh")

if [[ -z "$ghdir" ]]; then
  skip "conventional location (no gh on PATH to hide)"
else
  filtered=$(printf '%s' "$REAL_PATH" | tr ':' '\n' | grep -vxF "$ghdir" | paste -sd ':' -)
  if PATH="$filtered" command -v bash >/dev/null 2>&1 && PATH="$filtered" command -v uname >/dev/null 2>&1; then
    run_check "$filtered" "$SANDBOX/work" --
    if [[ "$OUT" == state=*" source=located "* ]]; then
      pass "a CLI off PATH is found and reported as located"
    else
      fail "a CLI off PATH is found and reported as located" "rc=$RC out=$OUT"
    fi
  else
    skip "conventional location (hiding $ghdir would also hide bash or uname)"
  fi
fi

# ── The auth verdict ────────────────────────────────────────────────────────
section "auth verdict"

# "another account" only means anything relative to an expectation. With no
# expectation, a session that works is a session that works — whoever it is.
run_check "$fake_dir:$REAL_PATH" "$SANDBOX/work" FAKE_GH_MODE=other-account --
if [[ $RC -eq 0 && "$OUT" == "state=logged-in exe=$fake_dir/gh version=2.79.0 source=path $HEAD user=monalisa scopes=gist,read:org,repo" ]]; then
  pass "a usable session as any account is logged-in when nothing was expected"
else
  fail "a usable session as any account is logged-in when nothing was expected" "rc=$RC out=$OUT"
fi

run_check "$fake_dir:$REAL_PATH" "$SANDBOX/work" FAKE_GH_MODE=other-account -- --expect-user octocat
if [[ $RC -eq 14 && "$OUT" == *" user=monalisa "* ]]; then
  pass "the wrong expected account exits 14 and names the real one"
else
  fail "the wrong expected account exits 14 and names the real one" "rc=$RC out=$OUT"
fi

run_check "$fake_dir:$REAL_PATH" "$SANDBOX/work" FAKE_GH_MODE=other-account -- --expect-user monalisa
if [[ $RC -eq 0 && "$OUT" == state=logged-in* ]]; then
  pass "--expect-user matching the other account passes"
else
  fail "--expect-user matching the other account passes" "rc=$RC out=$OUT"
fi

# The cross-check: the status command claims success while the API refuses.
run_check "$fake_dir:$REAL_PATH" "$SANDBOX/work" FAKE_GH_MODE=token-rejected --
if [[ $RC -eq 15 && "$OUT" == "state=token-rejected exe=$fake_dir/gh version=2.79.0 source=path $HEAD user= scopes=" ]]; then
  pass "a rejected token is never reported as success"
else
  fail "a rejected token is never reported as success" "rc=$RC out=$OUT"
fi

run_check "$fake_dir:$REAL_PATH" "$SANDBOX/work" FAKE_GH_MODE=not-logged-in --
if [[ $RC -eq 13 && "$OUT" == state=not-logged-in* ]]; then
  pass "no stored credential is not-logged-in, not rejected"
else
  fail "no stored credential is not-logged-in, not rejected" "rc=$RC out=$OUT"
fi

# The other cross-check: a cached credential plus a dead network must not be
# mistaken for a rejected credential.
run_check "$fake_dir:$REAL_PATH" "$SANDBOX/work" FAKE_GH_MODE=unreachable --
if [[ $RC -eq 12 && "$OUT" == state=host-unreachable* ]]; then
  pass "an unanswered call is a network problem, not a credential problem"
else
  fail "an unanswered call is a network problem, not a credential problem" "rc=$RC out=$OUT"
fi

# A second host with a broken credential must not affect this one. The fixture
# is hostile when unscoped, so this is only green if the wizard always scopes.
run_check "$fake_dir:$REAL_PATH" "$SANDBOX/work" FAKE_GH_MODE=multi-host-broken --
if [[ $RC -eq 0 && "$OUT" == state=logged-in*" user=octocat "* ]]; then
  pass "another host's broken credential does not leak into the verdict"
else
  fail "another host's broken credential does not leak into the verdict" "rc=$RC out=$OUT"
fi
if env FAKE_GH_MODE=multi-host-broken "$fake_dir/gh" auth status >/dev/null 2>&1; then
  fail "the fixture is hostile when unscoped" "unscoped auth status unexpectedly succeeded"
else
  pass "the fixture is hostile when unscoped"
fi

# ── Nothing installed anywhere ──────────────────────────────────────────────
section "no CLI at all"
leaks=$(existing_candidates)
path_gh=$(command -v gh 2>/dev/null || true)
if [[ -n "$leaks" || -n "$path_gh" ]]; then
  skip "gh missing (a real CLI is reachable at ${path_gh:-${leaks:-unknown}})"
else
  run_check "$REAL_PATH" "$SANDBOX/work" FAKE_GH_MODE=ready --
  if [[ $RC -eq 10 ]]; then pass "missing CLI exits 10"; else fail "missing CLI exits 10" "got $RC"; fi
  if [[ "$OUT" == "state=gh-missing exe= version= source=none $HEAD user= scopes=" ]]; then
    pass "missing CLI status line keeps the field order"
  else
    fail "missing CLI status line keeps the field order" "got: $OUT"
  fi

  run_check "$REAL_PATH" "$SANDBOX/work" "DSH_GH_PATH=$SANDBOX/broken-gh" FAKE_GH_MODE=ready --
  if [[ $RC -eq 10 && "$ERR" == *"DSH_GH_PATH"* ]]; then
    pass "with nothing found, the broken DSH_GH_PATH is the named reason"
  else
    fail "with nothing found, the broken DSH_GH_PATH is the named reason" "rc=$RC stderr=$ERR"
  fi
fi

# ── Arguments ───────────────────────────────────────────────────────────────
section "arguments"
run_check "$fake_dir:$REAL_PATH" "$SANDBOX/work" FAKE_GH_MODE=ready -- unexpected
if [[ $RC -eq 2 && -z "$OUT" ]]; then
  pass "an unexpected argument exits 2 without polluting stdout"
else
  fail "an unexpected argument exits 2 without polluting stdout" "rc=$RC out=$OUT"
fi

run_check "$fake_dir:$REAL_PATH" "$SANDBOX/work" FAKE_GH_MODE=ready -- --expect-user
if [[ $RC -eq 2 && -z "$OUT" ]]; then
  pass "--expect-user without a value exits 2 without polluting stdout"
else
  fail "--expect-user without a value exits 2 without polluting stdout" "rc=$RC out=$OUT"
fi

# ── Nothing is written ──────────────────────────────────────────────────────
section "writes nothing"
for m in ready token-rejected unreachable; do
  run_check "$fake_dir:$REAL_PATH" "$SANDBOX/work" "FAKE_GH_MODE=$m" --
done
env_after=$(cat "$SANDBOX/work/.env")
if [[ "$env_after" == "$env_before" ]]; then
  pass "the persisted value file is untouched"
else
  fail "the persisted value file is untouched" "before: $env_before / after: $env_after"
fi
if [[ -z "$(ls -A "$SANDBOX/home")" ]]; then
  pass "the credential-store home stays empty"
else
  fail "the credential-store home stays empty" "found: $(ls -A "$SANDBOX/home")"
fi

# ── The frozen library is still the template's ──────────────────────────────
section "frozen library"
library_of() { sed -n '1,/^#[[:space:]]*STAGES:/p' "$1" | sed '$d'; }

template_path() {
  if [[ -n "${WIZARD_TEMPLATE:-}" ]]; then
    printf '%s' "$WIZARD_TEMPLATE"
    return 0
  fi
  local c
  for c in "$HOME"/.dsh/profiles/*/node_modules/dsh-mattpocock-skills-deck/bundled-skills/wizard/template.sh \
           /usr/local/lib/node_modules/dsh-mattpocock-skills-deck/bundled-skills/wizard/template.sh; do
    if [[ -f "$c" ]]; then printf '%s' "$c"; return 0; fi
  done
  return 1
}

if tpl=$(template_path); then
  if [[ "$(library_of "$wizard")" == "$(library_of "$tpl")" ]]; then
    pass "library section is byte-identical to the wizard template"
  else
    fail "library section is byte-identical to the wizard template" "diff against $tpl"
  fi
else
  skip "library invariant (no template found; set WIZARD_TEMPLATE)"
fi
