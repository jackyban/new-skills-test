# GitHub CLI Login Wizard: Complete the Login Flow

Status: ready-for-agent
Type: spec

## Problem Statement

A developer sits down on a Windows machine to do repo work that needs the GitHub CLI. The login wizard already in this repo gets them started — it finds the `gh` executable, walks them through the device-code browser dance, and then says it worked. But the wizard cannot answer the only question that actually matters: **is this machine, right now, able to talk to GitHub as the right account?**

The places where the current flow breaks, from the user's side:

- They are told to "set `DSH_GH_PATH` to point at the exe" when `gh` is missing, but nothing in the script ever reads `DSH_GH_PATH`. Following the advice changes nothing.
- They have a perfectly good `gh` installed somewhere other than the one hard-coded Windows folder, and the wizard declares it missing.
- They are already logged in on `github.com`, but some unrelated host in their credential store is stale, so the wizard's login check fails and it marches them through a device-code flow they did not need.
- They are logged in as the wrong account — a work account, a bot token, somebody else's session — and the wizard reports "already logged in, no need to log in again" and exits successfully. Every subsequent issue write lands in the wrong place.
- They need a proxy to reach `github.com`. The wizard exports one into its own process, logs in, exits — and five minutes later in a fresh shell `gh` hangs, because the proxy decision died with the wizard.
- `gh auth status` says okay, but the token cannot read the org, so the first real command fails. The wizard's verification never touched the API.
- The final summary says "Setup complete" and lists nothing: not the host, not the account, not the protocol, not whether a proxy is now required.

And one meta-problem: because the wizard is a blocking interactive script, neither the user's agent nor CI can answer "is `gh` set up on this box?" without a human watching a terminal. The wizard's own success cannot be checked cheaply.

## Solution

Finish the login flow so it establishes and *proves* a known-good GitHub CLI session, and can be checked without a human.

1. **Find `gh` properly.** Honour `DSH_GH_PATH` first, then `PATH`, then the standard install locations for the platform. Check the version against a pinned minimum. When nothing works, say precisely what was looked for.
2. **Report the real auth state.** Ask `github.com` specifically, not "any configured host". Distinguish: not logged in, logged in as the account we want, logged in as a *different* account (offer to switch), token present but rejected by the API.
3. **Log in only when needed, and leave a trail.** Run the device-code flow against `github.com` with HTTPS. If a proxy is required to make any of this work, record that decision where the next shell can pick it up, and print the exact line to source — never edit the user's shell profile behind their back.
4. **Verify by using the API, not by trusting a status command.** Make one authenticated call as the final gate; report the account and the token's scopes.
5. **Summarise the end state.** Host, account, protocol, proxy requirement, and what is still missing.
6. **Add a non-interactive check mode.** `--check` does the detection, judgement, and verification without prompts or browser, prints exactly one machine-readable status line to stdout, explains failures on stderr, and exits with a code that distinguishes the failure kinds. This is the single seam the whole feature is tested at.

## User Stories

1. As a developer running the wizard for the first time, I want it to find my `gh` installation without me telling it where, so that I can get to the login step instead of debugging PATH.
2. As a developer whose `gh` lives outside `PATH`, I want to point at it once via `DSH_GH_PATH`, so that the environment variable the script advertises actually works.
3. As a developer on a machine with no `gh` at all, I want a message that lists every location that was checked and the exact install step, so that I know what to do next without guessing.
4. As a developer with an old `gh`, I want to be told the version I have, the version required, and why it is required, so that I upgrade instead of watching the device flow misbehave.
5. As a developer who is already logged into `github.com` as the right account, I want the wizard to say so and finish in one step, so that I do not re-authorise for nothing.
6. As a developer with a stale credential for some other GitHub host, I want the `github.com` check to be independent of that host, so that an unrelated mess does not send me through a login I did not need.
7. As a developer logged in as the wrong account, I want to be shown the current account and offered a switch, so that my subsequent work does not go to the wrong owner.
8. As a developer with several accounts cached, I want the wizard to list them and let me choose, so that I can pick work or personal deliberately.
9. As a developer on a network that needs a proxy, I want the wizard to detect that and route the login through it, so that authorisation completes on the first try.
10. As a developer on a network that needs a proxy, I want the proxy requirement recorded and the exact export line printed, so that later shells and later tools keep working.
11. As a developer who does not use a proxy, I want the wizard to never inherit a stale proxy setting silently, so that a leftover environment variable cannot poison the run.
12. As a developer whose proxy guess is wrong, I want to be told which proxy was tried and how to override it, so that I can correct it and re-run.
13. As a developer whose network is simply down, I want that distinguished from "credentials rejected", so that I stop re-authorising a problem that is not authorisation.
14. As a developer mid-device-code, I want the verification code and the URL repeated where I can see them, so that I do not lose them to terminal scroll.
15. As a developer whose code expired, I want the wizard to say so and offer another attempt, so that I do not have to re-read the instructions from the top.
16. As a developer who cancels in the browser, I want the wizard to report "authorisation not completed" without pretending it failed permanently, so that re-running is the obvious next action.
17. As a developer, I want re-running the wizard after success to be a harmless no-op, so that I can run it out of habit.
18. As a developer, I want the closing summary to name the host, the account, the protocol, and any proxy requirement, so that I can paste the result into a handoff.
19. As a developer with a token that authenticates but cannot read an organisation, I want the wizard to surface the token's scopes, so that the first real command does not fail mysteriously.
20. As a developer in a Terminal without a full TTY (or under a Windows shim), I want a clear message and the exact command to re-run under, so that the login prompt does not hang unexplained.
21. As an agent or CI job, I want a `--check` mode that never prompts, never opens a browser, and returns a distinct exit code per outcome, so that I can gate work on "gh is ready" without a human.
22. As an agent or CI job, I want `--check` to print one stable, parseable status line on stdout and put all human chatter on stderr, so that I can read it with a single field-splitting step.
23. As an agent or CI job, I want `--check` to be able to assert a specific expected account, so that "logged in as somebody" is not mistaken for "logged in as the right body".
24. As a maintainer of this script, I want every judgement (missing, too old, not logged in, wrong account, network, unauthorised) to be reachable through the single seam, so that I can test the flow without a network, a browser, or a real `gh`.
25. As a maintainer, I want the frozen wizard library section untouched, so that the script stays consistent with every other wizard.
26. As a developer, I want the wizard to keep working when I re-run it after fixing a typo in a proxy setting, so that recovery does not require manual cleanup of credential state.
27. As a developer, I want to know whether the wizard wrote anything to disk at all, and where, so that I am never surprised by a config change.

## Implementation Decisions

**Shape and modes**

- One bash script, still: a frozen library section followed by an authored stages section. The library section is not modified — it is identical in every wizard and that identity is the point.
- Two entry modes off the same code path: interactive (default, current behaviour) and non-interactive check. The check mode runs the same detection, judgement, and verification functions; only the prompting and browser-opening are skipped. This is what keeps the seam single.
- `--help` documents both the interactive flow and the exit-code table.

**Finding `gh`**

- Resolution order is explicit and reported: `DSH_GH_PATH`, then `PATH`, then a per-platform list of conventional install locations. The first hit wins and the wizard says which one won.
- `DSH_GH_PATH` is the environment-variable name already promised in the script's own error text; keeping it means the existing message stops being a lie rather than introducing a new name.
- A minimum version is pinned to a single constant, chosen because the flow depends on behaviour introduced together (device flow with `--web`, `--skip-ssh-key`, and `auth status` scoped to one host). The version is reported on failure alongside the version found.
- Version parsing handles the `gh version X.Y.Z (YYYY-MM-DD)` shape and treats an unparseable version as "too old, cannot confirm".

**Judging auth state**

- All auth questions are asked about one explicit host, never "whatever hosts happen to be configured". The host is a single constant, defaulting to `github.com`.
- The authoritative signal for "usable session" is a successful authenticated API call returning the login name — not the exit status of the status command. The status command is used for *diagnosis* (which accounts are cached, what scopes the token carries), and its output is parsed only for that.
- The resulting state is one of a small closed set: `gh-missing`, `gh-too-old`, `host-unreachable`, `not-logged-in`, `logged-in`, `logged-in-other-account`, `token-rejected`. Every decision in the flow keys off this set, so the interactive and check modes cannot drift apart.
- When the account is not the one the user wants, switching uses the CLI's own account-switch facility against the explicit host rather than editing credential storage.

**Proxy**

- Network reachability is probed before login. Direct first. If direct fails, a proxy is taken from the environment if present, otherwise from a documented default, and that choice is *stated*, never silent.
- A run that only succeeds through a proxy records the requirement and prints the exact export line. Where it is recorded: through the library's existing `.env` upsert, so re-runs read it back as an already-known value instead of re-asking.
- The wizard never edits shell profiles, and never writes proxy settings into git's own configuration. Explicitly declined: a persistent global proxy mutation on the user's behalf.

**Verification and summary**

- The final gate is a live authenticated call; the account name and token scopes come from that response, not from cached text.
- The closing summary reports host, account, protocol, proxy requirement, files touched, and anything still outstanding. A summary with no account in it is a bug, not a cosmetic gap.

**Non-interactive contract**

- Exit codes are distinct and stable per outcome, and are documented in `--help`: success; `gh` missing; `gh` too old; host unreachable; not logged in; logged in as a different account than the one expected; token rejected by the API.
- Exactly one line goes to stdout, as space-separated `key=value` fields in a fixed order, always containing at least the state, the resolved executable, the version, the host, and the account when known. Everything a human needs to read goes to stderr.
- An optional expected-account argument turns "somebody is logged in" into a pass/fail condition, so a CI job can assert identity.
- Check mode performs no writes: no `.env` upsert, no credential changes, no browser. Read-only by construction is what makes it safe to gate work on.

**Behaviour under bad conditions**

- No-TTY detection is explicit, with a message and the exact command to re-run under, because the device flow needs a real terminal and silently hanging is the current worst outcome.
- Interruptions (Ctrl-C, EOF at any prompt) are recognised and reported as "not completed" rather than as a failure of the environment.
- Re-running after success is a no-op that still prints the summary.

## Testing Decisions

**What a good test means here**

Test the script's external behaviour at its single seam: the exit code and the one machine-readable status line of the check mode. Never assert on which function was called, on intermediate `say`/`note` chatter, or on the wording of human diagnostics — those are free to change. A test that needs a real `gh`, a real network, or a browser is not a test of this feature; it is a manual walkthrough, and belongs in a handoff note instead.

**The one seam**

The whole script boundary, exercised through check mode, with the `PATH` the script resolves `gh` from pointing at a fake `gh` executable. The fake is a small script that answers `--version`, `auth status`, and the API call according to canned responses; its own behaviour is selected by an environment variable so one fake covers every case. `DSH_GH_PATH` gets a variant that points at a deliberately broken file, to prove precedence and error reporting.

**Modules under test**

Only the script. No new modules are introduced by this spec, and that is deliberate: the seam exists to avoid inventing a testable abstraction for a 300-line bash file.

**Cases worth encoding**

- `gh` absent everywhere → missing, distinct exit code, no prompts.
- `DSH_GH_PATH` set to garbage while a working `gh` sits on `PATH` → the resolution order is observable in the status line.
- old version, unparseable version, current version.
- already logged in as the expected account → success, and check mode made no writes (assert `.env` is byte-identical afterwards).
- logged in as a different account, with and without an expected account supplied.
- another host in the credential store broken while `github.com` is fine → must still report success for `github.com`.
- API rejects the token while the status command claims success → token-rejected, not success.
- host unreachable without a proxy, and with one.
- Interactive mode's stage count and early-exit path, asserted cheaply: that a run against a fake successful session performs no login and reaches the summary.

**Prior art**

There is none in this repo — this is its first feature, and this is its first test. The nearest existing check is the wizard skill's own static pair, `bash -n` and `shellcheck`, which stays in place and is joined by, not replaced by, behaviour tests. Because there is no test runner to inherit, the tests ship as plain bash driven from a single entry point that exits non-zero on the first failed assertion, so they run anywhere a bash exists. One extra invariant is cheap and worth keeping: the frozen library section must be byte-identical to the wizard template's, asserted by comparison rather than trusted.

## Out of Scope

- Making this workspace's host able to execute processes. The current session cannot spawn `bash`, `gh`, or `git` at all (every child process dies with STATUS_DLL_INIT_FAILED). That is an environment defect, not this feature; it only means the tests here cannot be *run* from this session.
- GitHub Enterprise and any host other than `github.com`. The host is a single constant precisely so a second host is a later, separate decision.
- SSH protocol, and SSH key generation for `gh`. The flow pins HTTPS for exactly this reason.
- Providing a Windows terminal shim. Detecting that one is needed and saying which command to re-run under is in scope; shipping or invoking the shim is not.
- Writing CI secrets or repo variables. The library's secret and variable helpers stay unused by this flow; login produces no secret.
- Repairing or pruning other hosts' credentials in the CLI's credential store. The wizard reads that state to decide, and never cleans up someone else's mess.
- A general proxy manager for the machine. The wizard records what *it* needed and prints the line; it does not become the source of truth for the user's shell environment.
- Choosing or documenting an issue tracker; already settled elsewhere in this repo's agent docs.

## Further Notes

- The script is currently committed at the repo root and is the only wizard here, so this spec's references to "the wizard script" are unambiguous. `/wizard` treats wizards as ephemeral by default; this one is being kept as a repeatable setup path, which is why it earns tests at all.
- The repo has no git remote and no CI, so nothing runs these tests automatically yet. Wire the single test entry point into CI when a remote exists; until then it is a command a human or agent runs.
- Because this session cannot execute a subprocess, an agent picking this up should treat the test suite as written-but-unverified here, and say so plainly rather than reporting a green run it never saw. The first verification has to happen on a machine where `bash` and `gh` actually start.
- Any account name, org name, or proxy address in the implementation must come from the environment or the user at runtime; hard-coded personal values in a committed script are a defect.
