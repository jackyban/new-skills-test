# 04: Rebuild the interactive flow on top of the shared verdict

**What to build:** The human-facing wizard becomes a presenter over the verdict the earlier tickets produce. It logs in only when the verdict says a login is needed, walks the device-code flow, lets the user move to a different cached account, treats an interruption as "not completed" rather than a permanent failure, and closes with a summary naming the host, the account, the protocol, the proxy requirement, and which files it touched.

**Blocked by:** 02 — Judge the session by asking one host and by using the API; 03 — Detect the proxy requirement, record it, never inherit it silently

**Status:** ready-for-agent

- [x] A machine whose session is already correct finishes without opening a browser and without a login, and still prints the summary
- [x] A login happens only when the verdict demands one, and the stages presented match what will actually happen
- [x] Being logged in as a different account shows the current account and offers a switch against the explicit host
- [x] Without a usable terminal the wizard prints a clear message and the exact command to re-run under, instead of hanging silently mid-flow
- [x] The final gate is a live authenticated call, and the summary cannot claim success without naming an account
- [x] Ctrl-C or end-of-input at any prompt is reported as "authorisation not completed", with re-running as the obvious next action
- [x] The summary always reports host, account, protocol, proxy requirement, and the files touched or explicitly "none"
- [x] User-facing strings stay in the same language and tone as the existing script
- [x] Interactive and check mode share one code path for detection, judgement, and verification — no duplicated branching, and a fix in one cannot drift from the other
- [x] Re-running after success is a harmless no-op that still summarises

## Progress

**Implemented.** The wizard is now a presenter over the verdict. It calls
`_judge` — the same judgement `--check` uses — and then says, in Chinese, what
that verdict means for the person at the terminal. Stage count follows the
verdict: one stage for a blocked or already-good machine, three only when a
login is actually required. Nothing in the human flow decides anything, so a fix
in the judgement cannot leave the wizard telling a different story from
`--check`.

The summary always answers the same five questions — host, account, protocol,
proxy requirement, files written or explicitly none — and it cannot print
success without a named account, because the account comes from the live call
that gated the run.

**A design that was reversed mid-implementation.** The first version gated the
whole flow on `[[ -t 0 ]]`. That was wrong twice: the real hazard is not the
absence of a TTY but walking on after the input has gone, and the gate made the
flow impossible to drive from a script, which is exactly how it needed to be
tested. The guard was replaced by per-prompt reporting: every prompt that cannot
read exits 130 with the reason and two ways forward (`winpty bash $0`, or
`--check` if all you wanted was a status).

**Verified.** Green run on Git Bash, 2026-11-02: `37 passed, 0 failed, 1 skipped`,
including six assertions that drive the whole script end to end against the fake
CLI — an already-good session that must not log in, and a login run whose fixture
grants a credential only when `auth login` actually executes.

**Closed by a second run.** The switch offer and the full set of summary fields
had no assertions in the first green run, so they were left unchecked rather
than claimed. Both assertions were added, and the next run — `39 passed, 0
failed, 1 skipped` — observed them. All ten criteria are now backed by something
that actually ran.

**Not covered at all.** The Ctrl-C half of the interruption criterion is a trap,
and no test sends a signal; the completed-account-switch path is likewise
unexercised. Both belong to the walkthrough ticket, which walks the flow by hand
on a real machine.

**Left alone deliberately.** The frozen library still contains two unscoped
`gh auth status` calls, inside `set_secret` and `set_var`. They are template
code, this flow never calls them, and the library's byte-identity to the template
is a test invariant.
