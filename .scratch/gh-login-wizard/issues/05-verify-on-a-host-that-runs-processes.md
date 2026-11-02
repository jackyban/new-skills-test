# 05: Prove it on a host where bash and gh actually start

**What to build:** The feature is verified rather than merely written. The full test suite is executed green on a machine that can spawn processes, the interactive path is walked once end-to-end against a real network and a real account, and the test entry point is wired into CI if a remote exists.

**Blocked by:** 01, 02, 03, 04 — every ticket above must be complete first

**Status:** ready-for-agent

- [x] The full test suite is executed on a host where bash and the CLI actually start, and the command plus its result are pasted on this ticket
- [x] The interactive path is walked once end-to-end for real, and the summary it printed matches reality — host, account, protocol, and whether a proxy was needed
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

## Found by the first real run

The first human run printed one line:

```
✓ Setup complete
```

and nothing else. That is a defect, and the tests could not see it.

`finish()` — the frozen library's closing frame — calls `_clear` as its first
act, wiping the terminal. The summary was printed immediately before it, so it
was cleared off the screen the same instant it appeared. A captured stdout still
contains text that a terminal has scrolled away, so every assertion about the
summary stayed green while the human saw nothing.

Fixed by printing the summary *after* the closing frame, at both call sites. A
new assertion now encodes the invariant that the old ones could not: the account
line must come after the last `Setup complete`, not merely exist somewhere in
the output.

This is the whole argument for having this ticket. Every prior ticket was
verified at the seam, the seam was honest about exit codes and status lines, and
the thing the seam cannot see is whether a person is looking at anything.

## How to capture a transcript

`_clear` is a no-op when stdout is not a terminal, so piping keeps every line
while prompts still read from the terminal:

```
bash gh-login-wizard.sh | cat
```

## First successful walkthrough

Branch A — a machine that was already logged in — walked end to end on
2026-11-02:

```
▸ Stage 1/1 · 检查 · 已经可用
  已经是登录状态，不需要重复登录。
  ? 要改用另一个账号吗？ [y/N] n

  ✓ Setup complete

  主机:      github.com
  账号:      jackyban
  协议:      https
  代理:      http://127.0.0.1:7890（默认值）
  写入文件:  无
```

One stage, no browser, no login, and a summary that names the account. The
proxy line is the interesting one: the direct probe to the host timed out and
the documented default answered, so the run went through it. That is the
verdict doing its job on a network where it actually matters.

### The question it surfaced, and the answer

On this machine the proxy is needed for every future shell, yet the
already-logged-in path writes nothing (`写入文件: 无`), because the value-file
upsert only happens inside the login stage. Whether that path should record it
was a product call, now made: **it should not**. An already-good run changes
nothing, and that stays true. The accepted cost is that a fresh shell without
the proxy will fail with no note from the wizard — the operator knows, because
the summary printed the proxy line.

The login path still records it, and a test now drives exactly that case.
## Suite, final

```
bash tests/run.sh
46 passed, 0 failed, 0 skipped
```

The skip that had survived every previous run is gone: the "no CLI at all" case
is now exercised through a simulated platform, so exit code 10 is produced for
the first time.

One criterion remains on this ticket, and it needs a person: the not-logged-in
branch has never run against the real service.
