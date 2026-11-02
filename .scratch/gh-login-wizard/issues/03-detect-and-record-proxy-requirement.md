# 03: Detect the proxy requirement, record it, never inherit it silently

**What to build:** When the host is not directly reachable, the flow tries the environment's proxy and then a documented default, states which one it used, and — on an interactive run that only succeeded through a proxy — records the requirement so a later shell can pick it up, along with the exact line to source. Check mode reports the requirement and writes nothing.

**Blocked by:** 02 — Judge the session by asking one host and by using the API

**Status:** ready-for-agent

- [x] Direct reachability is probed first; a proxy is used only after direct fails
- [x] The proxy source — inherited from the environment, or the documented default — is named in the output, so a leftover environment variable can never be used silently
- [x] When both direct and proxy attempts fail, the message names the proxy that was tried and how to override it
- [x] The proxy requirement appears as its own field in the status line, with a fixed vocabulary and no free text
- [x] An interactive run that needed a proxy persists the requirement through the library's existing value-file upsert and prints the exact line to source; check mode persists nothing
- [x] The user's shell profile is never edited, and git's own proxy configuration is never written
- [x] A re-run reads the persisted requirement back as an already-known value instead of asking again or re-deriving it as an error
- [x] Cases encoded for: direct reachable, direct unreachable but proxy works, both unreachable — each asserted at the seam, not by inspecting internals

## Progress

**Implemented.** Reachability is asked with `curl`, not inferred from the CLI's
error text. That choice is load-bearing: when nobody is logged in the CLI may
refuse *locally*, without dialling, which would make a dead network and a missing
login indistinguishable — and separating those two is the entire point of check
mode. A 4xx counts as an answer; only silence counts as unreachable.

The proxy is consulted only after the direct route produced no answer, and its
source is named: `env`, `persisted`, `default`, or `failed`, each a closed
vocabulary term rather than prose. The documented default is one constant, so a
machine-local port is no longer spelled inline in the middle of a stage.

Direct attempts clear the proxy variables explicitly, so a machine whose shell
exports a proxy still gets a genuinely direct first attempt, and a leftover
variable can never be used without being named.

**Verified.** Green run on Git Bash, 2026-11-02: `30 passed, 0 failed, 1 skipped`.
The five proxy outcomes are asserted at the seam — direct reachable, environment
proxy, documented default, recorded proxy, and both routes dead — plus the
message that names what was tried and how to override it.

Checked by inspection, not by a test: no shell profile is written, and git's own
proxy configuration is untouched. The only `export` statements are in-process.

**Was not verified, then was.** The interactive half of the persistence
criterion was argued from the code on the grounds that driving it would open a
browser. That was too pessimistic: once the flow became a presenter, it turned
out to be drivable from a pipe with a fake CLI, and the browser is shadowed by a
no-op shim. The case now exists — a proxied login run that must print the export
line and record `DSH_GH_PROXY` — and is waiting on its first run.

**Scoped by decision.** A real walkthrough showed the already-logged-in path
finding the machine needs a proxy but writing nothing. That is deliberate: the
requirement is recorded only during a login, so a run that changes nothing writes
nothing. The criterion above is therefore read as "a run that *logs in* and
needs a proxy". Recording it was offered and declined, with the consequence
accepted: a fresh shell with no proxy will fail without the wizard having left a
note.
## Closed

Green run: `46 passed, 0 failed, 0 skipped`. The persistence case drives a login
run with a dead direct route, and observes both halves — the export line printed
for the next shell, and `DSH_GH_PROXY` actually present in the value file — while
check mode is separately asserted to write nothing at all.
