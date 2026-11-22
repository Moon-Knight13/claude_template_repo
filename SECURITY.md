# Security Policy

## Supported Use
This template is intended for secure-by-default project bootstrapping.

## Reporting a Vulnerability

**Do not open a public issue for a security vulnerability.**

- **In this template:** report privately via GitHub's
  [Private Vulnerability Reporting](https://docs.github.com/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability)
  — open the repository's **Security** tab and click **Report a vulnerability**.
  (Repo maintainers: enable this under *Settings → Security → Private vulnerability reporting*.)
  Low-severity findings (weak defaults, misconfiguration, documentation gaps) that are
  safe to discuss in the open may instead use the *Security Vulnerability* issue template.
- **In a project derived from this template:** report to that project's maintainer using
  their disclosure process.

Please include reproduction steps and an impact assessment. We aim to acknowledge reports
within a few business days.

## Secret Leak Response
1. Revoke and rotate exposed credentials immediately.
2. Remove secrets from code and git history.
3. Re-scan repository history with gitleaks.
4. Re-run CI secret and semgrep checks.
5. Document incident and remediation in project notes.

## Baseline Security Controls

Protecting the repository:
- Pre-commit hooks with gitleaks and semgrep.
- CI secret scan and semgrep workflows.
- Local bootstrap script to enforce branch protection and required checks.

Protecting the agent itself (see [docs/THREAT_MODEL.md](docs/THREAT_MODEL.md)):
- `permissions.deny` rules in `.claude/settings.json` over credential and key
  material. Deny rules hold in every permission mode, including
  `bypassPermissions`, and no settings scope can remove one.
- Bash sandbox with credential deny entries for the mounted credential volumes.
- A `PreToolUse` guard over the files that govern the agent — `.claude/`,
  `.devcontainer/`, `CLAUDE.md`, the routing scripts, the gate configs — so a
  session cannot widen its own boundary in passing.
- A `PostToolUse` rail that labels issue and PR text as untrusted data, because
  the board gates cards on metadata while the agent acts on the body.
- gitleaks run as a file is written, not only at commit time.

Deny-by-default egress in the devcontainer firewall bounds **where** data can go.
It does not bound **whether** data leaves: the allowlist admits the whole GitHub
CIDR range, so `git push` is an accepted exfiltration path. The container is a
host-protection boundary, not a data-containment one.

## Non-Goals

The threat model states these in full. In short: prompt injection is not solved,
only blast-radius-reduced; TLS is not inspected, so domain fronting is live;
egress policy is per-container, not per-binary; subagents share the parent
process and are not a security boundary; and in a single-maintainer repository,
required review is self-review.
