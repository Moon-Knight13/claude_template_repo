# /security-audit — Full Security Scan with ATLAS Coverage

Run a comprehensive security audit of the current working tree, map findings to MITRE ATLAS techniques, and produce a prioritized remediation report.

## Instructions

1. Run all pre-commit security gates via Bash:
   ```bash
   pre-commit run --all-files 2>&1
   ```
   Capture and show the full output.

2. Run the project semgrep rules explicitly:
   ```bash
   semgrep scan --config .semgrep.yml --verbose 2>&1
   ```
   Parse findings by severity (ERROR → WARNING → INFO).

3. For each semgrep finding that has an `atlas_technique` metadata field, map it to the MITRE ATLAS technique:
   - AML.T0051 — Prompt Injection
   - AML.T0054 — LLM Output Execution
   - AML.T0049 — Unverified ML Artifact Fetch
   - AML.T0025 — Model Exfiltration
   - AML.T0040 — PII in Prompts

4. Report the results in four sections:

   **Gate Results:**
   | Gate | Status | Finding Count |
   |------|--------|---------------|
   | gitleaks (pre-commit) | PASS/FAIL | N secrets/PII |
   | semgrep custom rules | PASS/FAIL | N findings |
   | file integrity checks | PASS/FAIL | N issues |

   **Findings by Severity:**
   For each ERROR or WARNING finding: file:line, rule ID, ATLAS technique (if applicable), recommended fix.

   **ATLAS Coverage Summary:**
   Which ATLAS techniques are actively scanned, which are not covered, and recommended rules to add for any gaps.

   **PII Coverage:**
   | PII Type | Detection Method | Scope |
   |----------|-----------------|-------|
   | Email addresses | gitleaks `pii-email` | All file types (diff-time) |
   | Credit cards | gitleaks `pii-credit-card` | All file types (diff-time) |
   | US SSN | gitleaks `pii-ssn` | All file types (diff-time) |
   | UK National Insurance | gitleaks `pii-uk-nino` | All file types (diff-time) |
   | Phone (E.164) | gitleaks `pii-phone-e164` | All file types (diff-time) |
   | Hardcoded email literals | semgrep `pii-literal-email-in-code` | Python/JS/TS source |
   | PII in logging calls | semgrep `pii-in-log-call` | Python/JS/TS source |
   | PII in LLM f-string prompts | semgrep `atlas-t0040-pii-in-prompt` | Python source |
   | PII sent to Claude | PII-Shield (manual MCP) | Claude Code session |

   Flag any PII rule that is disabled or has an overly broad allowlist as a finding.

5. For any ERROR-level gitleaks finding (real secret detected):
   - Stop and treat this as a critical incident
   - Direct the user to SECURITY.md for the leak response procedure
   - Do not proceed with other tasks until the secret is rotated and history is cleaned

6. Suggest the next action based on findings — no findings means "run `git add -p` and commit; all security gates will re-run on push via CI."
