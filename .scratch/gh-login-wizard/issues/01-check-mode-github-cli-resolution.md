# 01: Make check mode answer where gh is and which version it is

**What to build:** Running the wizard's check mode on any machine returns, without a single prompt, one machine-readable status line on stdout and one exit code describing whether the GitHub CLI was found, which executable won, and at what version. Failures explain themselves on stderr. Nothing is written to disk. This same run establishes the test seam every later ticket is verified through.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [x] Check mode never reads stdin, never opens a browser, never prompts
- [x] A usable CLI produces exactly one stdout line of space-separated key=value fields in a fixed order, always including the state, the resolved executable, and the version
- [ ] Three distinct exit codes: CLI missing, CLI too old, CLI usable
- [x] Resolution order — explicit environment variable, then PATH, then conventional per-platform install locations — is observable in the status line; a wrongly-set explicit variable is reported as the reason rather than silently skipped
- [x] An unparseable version is treated as too old, never as usable
- [x] The minimum version is pinned to one constant, and the reason the flow needs it is recorded next to it
- [x] Check mode leaves the persisted value file and the credential store byte-identical
- [x] A test harness exists: a fake CLI whose behaviour is selected by an environment variable, placed ahead on PATH, driven by a single bash entry point that exits non-zero on the first failed assertion
- [x] One invariant test asserts the frozen library section is byte-identical to the wizard template's
- [x] The frozen library section is not modified
- [ ] No account, org, host-owner, or proxy address is hard-coded

## Progress

**Implemented.** Check mode exists and resolves the CLI in a fixed order (explicit
environment variable, PATH, then conventional per-platform install locations),
pins the version floor to one constant, treats an unparseable banner as too old,
and emits one fixed-order status line on stdout with all diagnosis on stderr.
Exit codes 0 / 2 / 10 / 11 are allocated; 12+ are deliberately left unused
because auth judgement is not this ticket. The fake CLI and the single bash
test entry point are in place, including the frozen-library invariant.

**Established without running anything.** The library section above the STAGES
marker is byte-identical to the wizard template's (compared programmatically,
7476 characters, same marker line). Every function definition in the script has
a matching column-0 closer (21/21). The check-mode region contains no prompt,
browser, or write primitive; its only stdin reads are a herestring and a process
substitution, never the terminal. No account, org, or address was introduced by
this work.

**Not established — needs a host that can start a process.** Nothing in this
ticket has been executed. On the machine this was written on, every child
process dies with STATUS_DLL_INIT_FAILED (0xC0000142), so `bash -n`,
the test suite, and the fake CLI have never run. Treat the exit codes, the
status line, and the harness as written-but-unverified. Run:

```
bash tests/run.sh --fail-fast
```

**Known tension, deliberately not resolved here.** The no-hard-coded-address
criterion is met by the code this ticket added, but the interactive stage that
predates it still carries a literal `http://127.0.0.1:7890` proxy default. That
literal is the proxy decision's business, which belongs to the ticket that
detects and records the proxy requirement; rewriting it here would be a
different change in a different ticket's area.

## First real run

Ran on Git Bash (2026-11-02). It failed immediately, and the failure was a design
error in the harness, not in the wizard:

```
FAIL  exits 0
      got 127; stderr: .../tools/bash: error while loading shared libraries: ?: cannot open shared object file
```

The harness had been isolating PATH by symlinking `bash`, `sed`, `head` and
`uname` into a temp directory. On MSYS that breaks: the loader looks for its
runtime next to the invoked path, not next to the real executable. `env -i`
compounded it by stripping the platform variables MSYS needs to resolve paths.

Fixed by removing the isolation layer: the harness keeps the real PATH and puts
the fake CLI first, which is the thing the wizard actually consults. The
"not installed anywhere" case is now skipped whenever any real `gh` is
reachable, rather than pretending an isolated PATH exists.
Second run failed too, one layer deeper: `${extra[@]}` pushes
`FAKE_GH_MODE=ready` into the command position, and bash only honours
`NAME=value` as an assignment when it appears literally in the source — words
produced by expansion are never assignments. The harness now routes through
`env` explicitly, without `-i`, which both fixes the expansion problem and
keeps the platform environment MSYS needs.

## Verified state

Green run on Git Bash, 2026-11-02:

```
13 passed, 0 failed, 1 skipped
```

All three rungs of the resolution order are now demonstrated at the seam
(environment variable, PATH, and conventional location), as are the too-old and
unparseable outcomes, the untouched value file, an untouched credential-store
home, the argument rejection, and the frozen-library invariant.

## Remaining before this ticket closes

1. **Exit code 10 has never been produced.** The "not installed anywhere" case
   skips itself on this machine because a real `gh` lives at
   `/c/Program Files/GitHub CLI`, and an absolute candidate path cannot be
   hidden by filtering PATH. It needs a host with no CLI at all, which is what
   the verification ticket exists for.
2. **The no-hard-coded-address criterion is only true of the new code.** The
   interactive stage still carries a literal proxy address; that is the proxy
   ticket's decision to make.

Worth recording: the seam earned its keep immediately. Driving check mode
through the harness caught two real defects in the harness itself — a PATH
isolation layer that broke MSYS's loader, and an array expansion that bash would
never treat as an assignment — and one genuine gap in the wizard's tests, the
untested `located` rung.
## Contract update (from ticket 02)

`gh-ready` was provisional — "resolution passed, auth deliberately not judged
yet". Now that the auth verdict exists, a successful check reports
`logged-in`, and the status line gained `user` and `scopes` fields. The exit
codes this ticket allocated (0, 2, 10, 11) are unchanged.
