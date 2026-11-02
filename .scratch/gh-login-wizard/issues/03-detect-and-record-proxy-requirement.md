# 03: Detect the proxy requirement, record it, never inherit it silently

**What to build:** When the host is not directly reachable, the flow tries the environment's proxy and then a documented default, states which one it used, and — on an interactive run that only succeeded through a proxy — records the requirement so a later shell can pick it up, along with the exact line to source. Check mode reports the requirement and writes nothing.

**Blocked by:** 02 — Judge the session by asking one host and by using the API

**Status:** ready-for-agent

- [ ] Direct reachability is probed first; a proxy is used only after direct fails
- [ ] The proxy source — inherited from the environment, or the documented default — is named in the output, so a leftover environment variable can never be used silently
- [ ] When both direct and proxy attempts fail, the message names the proxy that was tried and how to override it
- [ ] The proxy requirement appears as its own field in the status line, with a fixed vocabulary and no free text
- [ ] An interactive run that needed a proxy persists the requirement through the library's existing value-file upsert and prints the exact line to source; check mode persists nothing
- [ ] The user's shell profile is never edited, and git's own proxy configuration is never written
- [ ] A re-run reads the persisted requirement back as an already-known value instead of asking again or re-deriving it as an error
- [ ] Cases encoded for: direct reachable, direct unreachable but proxy works, both unreachable — each asserted at the seam, not by inspecting internals
