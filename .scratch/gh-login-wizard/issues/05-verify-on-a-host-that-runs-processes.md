# 05: Prove it on a host where bash and gh actually start

**What to build:** The feature is verified rather than merely written. The full test suite is executed green on a machine that can spawn processes, the interactive path is walked once end-to-end against a real network and a real account, and the test entry point is wired into CI if a remote exists.

**Blocked by:** 01, 02, 03, 04 — every ticket above must be complete first

**Status:** ready-for-agent

- [ ] The full test suite is executed on a host where bash and the CLI actually start, and the command plus its result are pasted on this ticket
- [ ] The interactive path is walked once end-to-end for real, and the summary it printed matches reality — host, account, protocol, and whether a proxy was needed
- [ ] Both real-world branches are exercised at least once: a machine that was not logged in (login completes) and a machine that already was (no login, no browser)
- [ ] No green run is claimed from any session where subprocesses cannot start; if verification is partial, the ticket names exactly which cases remain unverified and why
- [ ] CI wiring is either done and observable, or explicitly deferred with the reason and the exact command to add later
- [ ] Any account, org, or proxy address observed during verification is kept out of the committed script
