# 02: Judge the session by asking one host and by using the API

**What to build:** Check mode answers the real question — can this machine, right now, talk to GitHub as a usable account — scoped to one explicit host. It distinguishes: host unreachable, not logged in, logged in, logged in as a different account than the one expected, and token rejected. An optional expected account turns "somebody is logged in" into pass or fail.

**Blocked by:** 01 — Make check mode answer where gh is and which version it is

**Status:** ready-for-agent

- [x] Every auth question is asked about one explicit host held in a single constant, never "whatever hosts happen to be configured"
- [x] A stale or broken credential for any other host never changes the verdict for the host under test
- [x] The authoritative signal for a usable session is an authenticated API call returning the login name; the status command is used only for diagnosis — which accounts are cached, what scopes the token carries
- [x] The status command reporting success while the API rejects the token yields a token-rejected outcome with its own exit code, never success
- [x] An expected account that does not match yields a wrong-account outcome with its own exit code, and the actual account is visible in the status line
- [x] An unreachable host is distinguishable from a missing login: network failure and credential failure never collapse into one verdict
- [x] Stdout stays exactly one line in every outcome; all diagnosis goes to stderr
- [x] The outcomes form one closed set with a single owner in the code; no branch invents a new string or a second dispatch path
- [x] Fake-CLI cases exist for every outcome in the set, including the two cross-checks: other host broken while this one is fine, and status claims success while the API rejects

## Progress

**Implemented.** The verdict is one closed set — `logged-in`, `gh-missing`,
`gh-too-old`, `host-unreachable`, `not-logged-in`, `logged-in-other-account`,
`token-rejected` — with exit codes 0/10/11/12/13/14/15 and a single mapping
function as the only way to turn a verdict into a code. Every question is asked
about one host, pinned in one constant and applied to every invocation.

Two questions are kept apart on purpose: whether a credential is *stored*
(`auth token`) and whether the host *accepts* it (an authenticated API call).
That separation is what lets a rejected token and an unreachable host land on
different verdicts even though both make the API call fail.

`--expect-user` turns "somebody is signed in" into a pass/fail condition.

**Verified.** Green run on Git Bash, 2026-11-02: `24 passed, 0 failed, 1 skipped`.
Both cross-checks are among the green ones — the status command claiming success
while the API refuses, and a cached credential surviving a dead network without
being mislabelled as rejected. The fixture is itself checked for hostility when
unscoped, so "another host is broken" cannot pass by accident.

**One correction worth recording.** `logged-in-other-account` only exists
relative to an expectation. With no `--expect-user`, a working session as any
account is `logged-in`; the first version of the test asserted the opposite and
was wrong, not the implementation.

**Landed contract change.** Ticket 01's provisional terminal state `gh-ready`
("resolution passed, auth deliberately not judged") is gone: now that the auth
is judged, a successful check reports `logged-in`, and the status line gained
`user` and `scopes` fields. 01's tests were updated with it.

**Still open, carried from 01.** Exit code 10 has never been produced on a host
that has no CLI, and the interactive stages still gate on an unscoped status
command — both belong to tickets that can actually exercise them.
