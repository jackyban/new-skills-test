# 04: Rebuild the interactive flow on top of the shared verdict

**What to build:** The human-facing wizard becomes a presenter over the verdict the earlier tickets produce. It logs in only when the verdict says a login is needed, walks the device-code flow, lets the user move to a different cached account, treats an interruption as "not completed" rather than a permanent failure, and closes with a summary naming the host, the account, the protocol, the proxy requirement, and which files it touched.

**Blocked by:** 02 — Judge the session by asking one host and by using the API; 03 — Detect the proxy requirement, record it, never inherit it silently

**Status:** ready-for-agent

- [ ] A machine whose session is already correct finishes without opening a browser and without a login, and still prints the summary
- [ ] A login happens only when the verdict demands one, and the stages presented match what will actually happen
- [ ] Being logged in as a different account shows the current account and offers a switch against the explicit host
- [ ] Without a usable terminal the wizard prints a clear message and the exact command to re-run under, instead of hanging silently mid-flow
- [ ] The final gate is a live authenticated call, and the summary cannot claim success without naming an account
- [ ] Ctrl-C or end-of-input at any prompt is reported as "authorisation not completed", with re-running as the obvious next action
- [ ] The summary always reports host, account, protocol, proxy requirement, and the files touched or explicitly "none"
- [ ] User-facing strings stay in the same language and tone as the existing script
- [ ] Interactive and check mode share one code path for detection, judgement, and verification — no duplicated branching, and a fix in one cannot drift from the other
- [ ] Re-running after success is a harmless no-op that still summarises
