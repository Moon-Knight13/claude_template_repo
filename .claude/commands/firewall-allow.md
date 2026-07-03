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
   curl --connect-timeout 5 -sS -v https://<candidate-host> 2>&1 | tail -n 5
   ```
   Firewall-blocked egress shows as `curl: (7) ... No route to host` (the REJECT rule's
   icmp-admin-prohibited maps to EHOSTUNREACH). `Connection refused` means the opposite: the
   host is *allowed* but nothing is listening on that port — do not add it to the allowlist.

2. **Check it isn't already covered** — do not re-add hosts the script already allows:
   - GitHub `web` + `api` + `git` IP ranges are pulled dynamically from `api.github.com/meta`.
   - The local model endpoint is already open on tcp/11434 to the host gateway **and** to the
     resolved `host.docker.internal` / `host.containers.internal` addresses (docker bridge vs
     podman/pasta reach the host differently).
   - DNS (udp/53) and localhost are already open.

3. **Pick the right list in `.devcontainer/init-firewall.sh`.** Locate the two `for domain in \`
   blocks by the comments above them:
   - **Critical domains** — under `# Resolve and add critical allowed domains`. Startup
     **hard-fails** if any of these can't be resolved. Use for hosts required for provisioning
     or core function.
   - **Optional telemetry** — under `# Resolve optional telemetry domains`. Warn-only;
     startup continues if unresolved. Use for non-essential / best-effort hosts.
   Don't go by position or line numbers — confirm the block by its comment and by its body
   (the critical loop `exit 1`s on resolution failure; the optional loop only warns).

4. **Add the entry** to the chosen block as a new backslash-continued line, keeping the existing
   alignment. Every entry ends with ` \` except the last, which ends with `; do`:
   ```bash
   for domain in \
       "existing-host.example" \
       "your-new-host.example.com" \
       "last-existing-host.example"; do
   ```
   Read the real block before editing — don't assume its current contents or ordering. If the
   host sits behind a rotating/shared CDN (e.g. Fastly) rather than stable A records, add a
   short comment explaining which real CDN hostname is being allowed and why — mirror the
   existing comment above the critical block (`raw.githubusercontent.com`, `pypi.org`, etc.).

5. **Caveats** to keep the change working:
   - The firewall matches **resolved IPs**, so only DNS-resolvable A-record hostnames work.
   - **Wildcards and URL paths are not supported** — allow hostnames only, not `*.example.com`
     or `example.com/path`.

6. **Verify.** First syntax-check the edit:
   ```bash
   bash -n .devcontainer/init-firewall.sh
   ```
   Then **rebuild the devcontainer** ("Dev Containers: Rebuild Container"). The rebuild bakes
   the edited script into the image and `postStartCommand` re-runs it from a clean state,
   including its built-in checks (`example.com` blocked, `api.github.com` reachable). After
   the rebuild, confirm the new host connects:
   ```bash
   curl --connect-timeout 5 -sS https://<new-host> >/dev/null && echo OK
   ```
   **Never re-run the firewall script inside a live container.** It is not safe to re-apply:
   the script flushes the rules while the default policies stay DROP from the first run, so
   its own GitHub-ranges fetch is blocked, the script aborts, and the container is left with
   all egress blocked until restarted. (The sudoers rule also only permits the image-baked
   `/usr/local/bin/init-firewall.sh` — which wouldn't contain your edit anyway.)

7. **Security gates before merge** (`CLAUDE.md` guardrails: pre-commit, semgrep, gitleaks, CI
   checks): run `pre-commit run --all-files` (its hooks cover gitleaks and semgrep), confirm no
   secrets/tokens were introduced, and wait for the CI checks on the PR to pass. Keep the diff
   scoped to the allowlist entry.
