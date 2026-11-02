# 05: Prove it on a host where bash and gh actually start

**What to build:** The feature is verified rather than merely written. The full test suite is executed green on a machine that can spawn processes, the interactive path is walked once end-to-end against a real network and a real account, and the test entry point is wired into CI if a remote exists.

**Blocked by:** 01, 02, 03, 04 — every ticket above must be complete first

**Status:** ready-for-agent

- [ ] The full test suite is executed on a host where bash and the CLI actually start, and the command plus its result are pasted on this ticket
- [ ] The interactive path is walked once end-to-end for real, and the summary it printed matches reality — host, account, protocol, and whether a proxy was needed
- [ ] Both real-world branches are exercised at least once: a machine that was not logged in (login completes) and a machine that already was (no login, no browser)
- [x] No green run is claimed from any session where subprocesses cannot start; if verification is partial, the ticket names exactly which cases remain unverified and why
- [x] CI wiring is either done and observable, or explicitly deferred with the reason and the exact command to add later
- [x] Any account, org, or proxy address observed during verification is kept out of the committed script

## Progress

**The suite runs on a real host.** This is the machine, and the evidence is real
rather than promised: `bash tests/run.sh` on Git Bash.

```
37 passed, 0 failed, 1 skipped      (before the switch/summary assertions)
39 passed, 0 failed, 1 skipped      (after adding them)
```

The skip was the "no CLI at all" case, because a real `gh` lives in
`/c/Program Files/GitHub CLI`. That has since been **removed as a skip**: the
branch under test is platform-independent, so the harness now drops the
directory holding the real CLI from PATH and shadows `uname` so the wizard
searches the macOS locations, none of which exist here. Same assertions, an
honest route to "nothing is there". Expect no skips on the next run — that run
is what closes the remaining suite criterion.

**What is still unverified, precisely.** Two criteria need a human at a
terminal, and this session cannot spawn a process, let alone a browser:

1. **The interactive path against the real service.** Every interactive assertion
   so far drives the script with a fake CLI. The real `gh auth login` device
   flow has never run.
2. **Both real-world branches on a real machine**: one that is not logged in
   (login completes) and one that already is (no login, no browser).

Neither is claimed as done. The walkthrough below is the script for them.

**CI: deferred, with the reason.** There is no remote yet, and no CI can run
without one. When a remote exists, add this file and nothing else:

```yaml
# .github/workflows/tests.yml
name: tests
on: [push, pull_request]
jobs:
  tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: bash tests/run.sh --fail-fast
```

Two things to know about that run: the fake CLI files must be executable in the
index (`git update-index --chmod=+x tests/fake/*`), and the frozen-library
invariant will skip there because the wizard template only exists in a local
profile — set `WIZARD_TEMPLATE` if a copy is ever vendored into the repo.

**Nothing personal shipped.** The script contains no account name, org, owner or
machine-specific proxy beyond the single documented default constant; the
fixtures use invented names (`octocat`, `monalisa`), which is what they are for.

## Walkthrough (for the human)

Run these on a machine with a terminal, and paste the output back here.

```
cd /j/skills

# 1. The already-logged-in branch. Expect one stage, no browser, and a summary
#    naming host, account, protocol, proxy and files written.
bash gh-login-wizard.sh

# 2. The not-logged-in branch. This really does revoke the credential, so run it
#    when you are willing to log in again — which is the thing being tested.
gh auth logout --hostname github.com
bash gh-login-wizard.sh      # device code, browser, verification, summary
```

If the summary says `账号: 未确认` the final gate did not run, and the run is a
failure no matter how the earlier stages looked.
