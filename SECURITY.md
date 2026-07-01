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
- Pre-commit hooks with gitleaks and semgrep.
- CI secret scan and semgrep workflows.
- Deny-by-default egress in devcontainer firewall.
- Local bootstrap script to enforce branch protection and required checks.
