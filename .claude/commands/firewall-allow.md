# /firewall-allow — Add an egress host to the dev container firewall

Use this whenever a change (new dependency, tool, installer, or service) needs the dev
container to reach a **new external host** and you are hitting — or anticipating — a blocked
outbound connection. The container runs a deny-by-default egress firewall
(`.devcontainer/init-firewall.sh`); anything not in the `allowed-domains` ipset is `REJECT`ed,
so a new egress requirement must be added to the allowlist before it will work.

## Escalation gate

Per `CLAUDE.md`, changes that touch **firewall/networking** are a hard escalation trigger: this
is **always a Claude task and must never be routed to the local model**. Do not delegate it.

## Instructions

1. **Identify the exact host(s)** the new dependency must reach. Use the real hostname that is
   contacted (registry, API, CDN, package host) — not a vanity/redirect URL. If unsure, reproduce
   the failure and read the rejected destination, e.g.:
   ```bash
   curl -sS -v https://<candidate-host> 2>&1 | head -n 20   # "Connection refused"/icmp-admin-prohibited => blocked
   ```

2. **Check it isn't already covered** — do not re-add hosts the script already allows:
   - GitHub `web` + `api` + `git` IP ranges are pulled dynamically from `api.github.com/meta`.
   - The local model endpoint is the host gateway on tcp/11434.
   - DNS (udp/53) and localhost are already open.

3. **Pick the right list in `.devcontainer/init-firewall.sh`:**
   - **Critical domains** — the `for domain in \` block (~lines 95–103). Startup **hard-fails**
     if any of these can't be resolved. Use for hosts required for provisioning or core function.
   - **Optional telemetry** — the second `for domain in \` block (~lines 122–141). Warn-only;
     startup continues if unresolved. Use for non-essential / best-effort hosts.

4. **Add the entry** to the chosen block as a new backslash-continued line, keeping the existing
   alignment. Every entry ends with ` \` except the last, which ends with `; do`:
   ```bash
   for domain in \
       "registry.npmjs.org" \
       "api.anthropic.com" \
       "your-new-host.example.com" \
       ...
       "update.code.visualstudio.com"; do
   ```
   If the host sits behind a rotating/shared CDN (e.g. Fastly) rather than stable A records,
   add a short comment explaining which real CDN hostname is being allowed and why — mirror the
   existing `raw.githubusercontent.com` / `objects.githubusercontent.com` comment (~lines 91–94).

5. **Caveats** to keep the change working:
   - The firewall matches **resolved IPs**, so only DNS-resolvable A-record hostnames work.
   - **Wildcards and URL paths are not supported** — allow hostnames only, not `*.example.com`
     or `example.com/path`.

6. **Verify** by re-running the script and its built-in checks:
   ```bash
   sudo bash .devcontainer/init-firewall.sh
   ```
   Its verification block already asserts `example.com` is blocked and `api.github.com` is
   reachable. Then confirm the new host now connects:
   ```bash
   curl --connect-timeout 5 -sS https://<new-host> >/dev/null && echo OK
   ```
   Note: `postStartCommand` runs the image-baked `/usr/local/bin/init-firewall.sh`, so a full
   **devcontainer rebuild** is the authoritative end-to-end test.

7. **Security gates before merge** (`CLAUDE.md` guardrails): run `pre-commit run --all-files`
   and confirm no secrets/tokens were introduced. Keep the diff scoped to the allowlist entry.
