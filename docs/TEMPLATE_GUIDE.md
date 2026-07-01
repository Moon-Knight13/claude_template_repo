# Claude Secure Template — Reference Guide

[![CI Configured](https://img.shields.io/badge/CI-configured-brightgreen.svg)](#ci-and-quality-gates)
[![Secret Scan Configured](https://img.shields.io/badge/Secret%20Scan-configured-brightgreen.svg)](#ci-and-quality-gates)
[![Semgrep Configured](https://img.shields.io/badge/Semgrep-configured-brightgreen.svg)](#ci-and-quality-gates)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](../LICENSE)

Public, language-agnostic template for secure and repeatable Claude-first development with BMAD workflow, Caveman token compression, and optional local model offload.

## Referenced Projects

- BMAD Method: https://github.com/bmad-code-org/BMAD-METHOD
- Caveman: https://github.com/JuliusBrussee/caveman
- Semgrep: https://github.com/semgrep/semgrep
- Gitleaks: https://github.com/gitleaks/gitleaks
- Ollama: https://github.com/ollama/ollama
- PII-Shield: https://github.com/gregmos/PII-Shield

## Who This Template Is For

- Teams that want secure defaults for new repositories.
- Projects that need language-agnostic CI and policy enforcement.
- Claude-led development that routes simple work to local models and complex work to Claude.

## Requirements

- Git with SSH access to GitHub.
- Docker with Dev Containers support.
- VS Code with Dev Containers extension.
- Access to GitHub Actions in target repositories.
- Optional local model endpoint on host port 11434.
- Claude CLI authentication available before first coding session.
- Caveman installer checksum configured for deterministic startup verification.

### Local AI Prerequisite (Ollama on host:11434)

If you want local-model offload, install and run Ollama on your host machine (not inside the container).

Linux quick path:

```bash
curl -fsSL https://ollama.com/install.sh | sh
ollama serve
```

Pull at least one model:

```bash
ollama pull qwen2.5-coder:7b
```

Verify host endpoint before opening devcontainer:

```bash
curl http://localhost:11434/api/tags
```

This template maps container access to host via host.docker.internal and firewall rules allow only host gateway tcp/11434.

### Claude Credential Prerequisite

Claude auth is stored in a mounted user config volume and persists across container restarts.

Before first coding session inside devcontainer:

1. Open terminal in container.
2. Run `claude login`.
3. Complete auth flow.
4. Verify with `claude --version` and a simple Claude command.

The mounted path is `/home/node/.claude` and is intentionally outside repository files to prevent accidental credential commits.

### Caveman Installer Verification Prerequisite

This template verifies the pinned Caveman installer script checksum before executing it.

- Default env var used by startup: `CAVEMAN_INSTALL_SHA256`
- Update this value when bumping `CAVEMAN_VERSION` in `scripts/install-caveman.sh`
- If checksum does not match, startup aborts Caveman installation by design

## Quick Start

1. Create a new repository from this template.
2. Clone with SSH and open in VS Code.
3. Reopen in devcontainer.
4. Let post-start bootstrap run automatically:
   - firewall setup (IPv4 + IPv6 deny-by-default)
   - Caveman token compression install
   - BMAD workflow install
   - pre-commit hooks install
   - Claude Code official plugins install (skill-creator, frontend-design, code-review, superpowers, github, commit-commands, semgrep)

Note: startup is intentionally deterministic; pre-commit hook versions are not auto-updated unless `PRECOMMIT_AUTOUPDATE=1` is set.

5. Complete the manual day-0 steps below — then verify:

```bash
bash scripts/check-day0.sh
```

6. Push initial commit so CI checks exist.

## Day 0 Setup

After the devcontainer starts, these steps require human input and cannot be automated:

| Step | Command | Why it's manual |
|------|---------|-----------------|
| Populate CODEOWNERS | Edit `.github/CODEOWNERS` | Requires your real GitHub username or team |
| Apply GitHub branch protection | `APPLY=true bash scripts/bootstrap-github-settings.sh` | Requires `gh auth login` with repo admin scope |
| Copy env config | `cp .env.example .env` | Per-developer preferences and optional secrets |
| Copy Claude MCP config | `cp .claude/settings.json.example .claude/settings.json` | Endpoint and model may differ per machine |
| Set GITHUB_TOKEN | Add to `.env` or host shell profile | Required for the github plugin to access repos/PRs/issues |
| Install Ollama (optional) | See [Ollama docs](https://ollama.com) | Only needed if you want local model routing |

Run `bash scripts/check-day0.sh` at any time to see which steps are still pending.

`bootstrap-github-settings.sh` configures a repository **ruleset**
(`Main_Branch_Protections`, targeting the default branch), not legacy branch
protection. It is idempotent — creates the ruleset if absent, updates it in place
otherwise. The ruleset requires a pull request with approving review(s), passing
status checks (`validate-template`, `semgrep`, `gitleaks`), linear history, and
blocks force-pushes / deletions / direct pushes to the branch.

Bootstrap safety defaults:
- dry-run unless `APPLY=true` (prints the exact ruleset payload)
- only the default branch is targeted unless `REQUIRE_DEFAULT_BRANCH=false`
- refuses to require code-owner reviews while `.github/CODEOWNERS` is unset or still
  the shipped placeholder owner (override with `REQUIRE_CODEOWNERS=false`)
- repo admins may bypass by default; set `ADMIN_BYPASS=false` for a multi-maintainer
  repo that wants no bypass
- pre-change snapshots are saved under `.ai/bootstrap-snapshots` for rollback

## Security Model

- Deny-by-default egress firewall in devcontainer (IPv4 + IPv6).
- Host access limited to local model endpoint on TCP 11434.
- Secrets blocked locally by pre-commit and in CI by gitleaks workflow.
- Semgrep policy checks in local and CI workflows with SARIF upload to GitHub Security tab.
- Default-branch ruleset (required PR reviews + required status checks, no force-push/deletion) configured by the bootstrap script.

See [SECURITY.md](../SECURITY.md) for leak response guidance.

## PII & Privacy Controls

Protection is layered across two surfaces: **repo commits** and **Claude context**.

### Commit-time PII detection (gitleaks)

The following PII types are blocked at pre-commit and re-checked in CI:

| PII Type | Rule ID | Notes |
|----------|---------|-------|
| Email addresses | `pii-email` | Test domains (example.com, localhost) are allowlisted |
| Credit card numbers | `pii-credit-card` | Common test card numbers (Stripe, PayPal) are allowlisted |
| US Social Security Numbers | `pii-ssn` | Invalid SSN prefix ranges excluded to reduce false positives |
| UK National Insurance Numbers | `pii-uk-nino` | Specific format; low false positive rate |
| Phone numbers (E.164) | `pii-phone-e164` | Only structured international format; TV placeholder numbers allowlisted |

In addition, the built-in gitleaks ruleset (100+ rules) covers all common API keys and tokens: AWS, GitHub, Stripe, Slack, Google, Azure, Twilio, Sendgrid, Shopify, and more.

All PII rules skip `tests/` and `docs/` paths by default. To add a custom allowlist for your project, add entries to `.gitleaks.toml`.

### Code-time PII detection (semgrep)

| Rule ID | What it catches | Languages |
|---------|----------------|-----------|
| `pii-literal-email-in-code` | Hardcoded real email addresses in string literals | Python, JS, TS |
| `pii-in-log-call` | PII-named variables passed to logging/print calls | Python, JS, TS |
| `atlas-t0040-pii-in-prompt` | PII field names interpolated into LLM f-string prompts | Python |

### Claude context protection (PII-Shield)

[PII-Shield](https://github.com/gregmos/PII-Shield) anonymizes content *before it reaches Claude* — replacing names, emails, phone numbers, and other PII with reversible placeholders that are restored in Claude's response. This is complementary to git hooks (which protect the repo), not a substitute.

PII-Shield cannot be installed via `claude plugin install` — it uses a `.mcpb` bundle format. Manual setup:
1. Download the `.mcpb` file from [gregmos/PII-Shield](https://github.com/gregmos/PII-Shield)
2. In Claude Code: **Settings → Extensions → drag in the `.mcpb` file**
3. First run downloads a ~634 MB NER model (one-time)
4. Mappings expire after 7 days by default

## CI and Quality Gates

- Universal checks:
   - secret-scan workflow (gitleaks full history scan)
   - semgrep workflow (custom rules + `p/secrets` + `p/security-audit` community packs, SARIF output)
   - container-scan workflow (Trivy CVE scan, weekly + on devcontainer changes).
     The devcontainer is a local dev sandbox behind a deny-by-default firewall,
     not a shipped artifact, so the gate **blocks only on CRITICAL** findings
     while CRITICAL+HIGH are still reported to the Security tab for visibility.
     Base-image OS CVEs are kept clear by `apt-get upgrade` in the Dockerfile;
     the base digest is refreshed via Dependabot.
   - repository-audit workflow (validates required files and CODEOWNERS customisation)
- Project marker detection for language-specific checks.
- If a stack marker exists and expected scripts are missing under `scripts/ci`, CI fails by design.

## BMAD Workflow

BMAD is the default delivery framework for planning and execution.

BMAD bootstrap is validation-only. It does not auto-generate workflow docs at startup.
Keep `docs/BMAD_WORKFLOW.md` authored in-repo and update it per project via normal commits.

Stage flow:
1. discovery
2. requirements
3. architecture
4. task decomposition
5. implementation
6. security and release readiness

See [docs/BMAD_WORKFLOW.md](BMAD_WORKFLOW.md).

## Claude Code Skills and Plugins

### Official plugins (auto-installed at startup)

| Plugin | Source | Purpose |
|--------|--------|---------|
| `skill-creator` | `claude-plugins-official` | Create new custom skills for this repo |
| `frontend-design` | `claude-plugins-official` | UI/UX design assistance with a11y and performance focus |
| `code-review` | `claude-plugins-official` | Code review workflow |
| `superpowers` | `claude-plugins-official` | Enhanced capabilities and full-context mode |
| `github` | `claude-plugins-official` | GitHub operations (PRs, issues, code search) — requires GITHUB_TOKEN |
| `commit-commands` | `claude-plugins-official` | Git commit workflow assistance |
| `semgrep` | `claude-plugins-official` | Security scanning integrated into Claude Code session |

Plugins are installed by `scripts/install-claude-plugins.sh` at container startup. They persist in the Claude Code config volume across rebuilds. Re-run `bash scripts/install-claude-plugins.sh` manually if a plugin is missing.

### Project-specific custom skills

These slash commands are defined in `.claude/commands/` and are specific to this template's tooling:

| Command | Purpose |
|---------|---------|
| `/bmad` | Start a BMAD planning session for the current task |
| `/route-task` | Invoke the model routing protocol explicitly |
| `/day0-check` | Validate day-0 setup and get guided remediation |
| `/security-audit` | Full security scan with MITRE ATLAS + PII coverage mapping |

## Caveman and Token Controls

Caveman installs automatically in `lite` mode on first devcontainer start, verified against a pinned SHA256 checksum.

### Activating Caveman in a Claude Code session

Caveman is installed into `/home/node/.claude` and activates automatically with the configured default mode. To change mode within a session:

- `/caveman lite` — enable lite compression (default; minimal prompt restructuring)
- `/caveman full` — enable full compression (maximum savings; more aggressive reformatting)
- `/caveman off` — disable for the current session

To verify the installed version and mode:

```bash
cat ~/.claude/.caveman-default-mode
cat ~/.claude/.template-caveman-version
```

To update the version, change `CAVEMAN_VERSION` in `scripts/install-caveman.sh` and update `CAVEMAN_INSTALL_SHA256` in `devcontainer.json`, then rebuild the container.

### Model routing and cost controls

- Model routing policy uses local endpoint for low-risk tasks and Claude for high-risk tasks.
- Disable local routing with `CAVEMAN_ENABLED=0` or `LOCAL_MODEL_ENABLED=false`.
- Recommended local defaults:
   - `qwen2.5-coder:7b` for normal coding tasks
   - `qwen2.5-coder:1.5b-base` for fast/simple edits
   - escalate to Claude for high-risk or ambiguous changes
- Optional fast-path env controls:
   - `LOCAL_MODEL_FAST_MODEL=qwen2.5-coder:1.5b-base`
   - `LOCAL_MODEL_FAST_TASK_TYPES=format,docs,tiny-refactor,rename,simple-test`

See [docs/AI_ROUTING_POLICY.md](AI_ROUTING_POLICY.md) and `scripts/route-model.sh`.

## Secrets Handling

- Never commit credentials or API keys.
- Keep Claude auth in mounted config outside workspace files.
- Use `.env.example` as a template only — never commit `.env`.
- Store CI secrets in GitHub Secrets or Environments.

## What Propagates vs Manual Setup

Propagates from template files:
- workflows, scripts, docs, pre-commit config

Manual per new repository:
- run bootstrap script for branch protections and required checks
- enable or verify repository-level security settings in GitHub if org rulesets are not centrally managed

## Compatibility Matrix

| Component | Default Pin |
|-----------|------------|
| BMAD | 6.9.0 (`scripts/install-bmad.sh`) |
| Caveman | v1.9.0 (`scripts/install-caveman.sh`) |
| Semgrep | pinned by image digest in `semgrep.yml`, tracked by Dependabot |
| Gitleaks | pinned by image digest in `secret-scan.yml`, tracked by Dependabot |
| Trivy | pinned by action SHA in `container-scan.yml`, tracked by Dependabot |

## Version and Upgrade Policy

- Use semantic tags for template releases.
- Keep tool pins explicit in scripts and workflows.
- Accept upgrades through reviewed pull requests (Dependabot or manual).

## Troubleshooting

- Local model unreachable: verify host service and port 11434.
- Local model unreachable from container: verify host endpoint with `curl http://localhost:11434/api/tags` on host, then check devcontainer firewall output.
- Claude auth missing in container: run `claude login` inside container and confirm `/home/node/.claude` is populated.
- Bootstrap permission error: ensure gh auth user is repo admin.
- CI missing script failure: add matching scripts under `scripts/ci` for detected stack.
- Gitleaks false positive on a test file: add the file path to the rule's `paths` allowlist in `.gitleaks.toml`.
- Semgrep PII false positive: add the file pattern to the rule's `paths.exclude` list in `.semgrep.yml`.

## FAQ

**Q: Template or fork?**
A: Use template for new projects. Fork only when contributing back to this repository.

**Q: Can I disable optional layers?**
A: Yes. Use `CAVEMAN_ENABLED=0` or `BMAD_ENABLED=0` in environment.

**Q: The gitleaks PII rules are flagging test data — what do I do?**
A: Either move test data to `tests/` (already allowlisted) or use placeholder values (`test@example.com`, `000-00-0000`). For custom allowlists, add entries to `.gitleaks.toml`.

**Q: Does PII-Shield work offline?**
A: The NER model runs locally after the initial download, but PII-Shield still sends the anonymized content to Claude via the Anthropic API.
