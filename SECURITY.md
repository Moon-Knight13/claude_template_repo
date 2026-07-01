# Security Policy

## Supported Use
This template is intended for secure-by-default project bootstrapping.

## Reporting
If you discover a vulnerability in a derived project, report it to that project maintainer.

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
