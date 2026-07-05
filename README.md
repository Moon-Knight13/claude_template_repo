# Claude Secure Template

[![ci](https://github.com/Moon-Knight13/claude_template_repo/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/Moon-Knight13/claude_template_repo/actions/workflows/ci.yml)
[![semgrep](https://github.com/Moon-Knight13/claude_template_repo/actions/workflows/semgrep.yml/badge.svg?branch=main)](https://github.com/Moon-Knight13/claude_template_repo/actions/workflows/semgrep.yml)
[![secret-scan](https://github.com/Moon-Knight13/claude_template_repo/actions/workflows/secret-scan.yml/badge.svg?branch=main)](https://github.com/Moon-Knight13/claude_template_repo/actions/workflows/secret-scan.yml)

A language-agnostic, production-ready template for Claude-first development. Provides secure defaults, AI task routing, BMAD workflow integration, and deterministic CI gates so you can focus on your project rather than its scaffolding.

## What's Included

- **AI routing** — routes low-risk work to a local Ollama model; escalates to Claude for security, architecture, and cross-cutting changes
- **Security gates** — gitleaks secret scanning, semgrep SAST (including MITRE ATLAS AI/ML rules), Trivy container scanning, all enforced in CI
- **BMAD workflow** — structured product → engineering planning via the `/bmad` skill
- **Kanban orchestration** — a per-repo GitHub Project board where a human orchestrator hands work to Claude sessions or local models; agents claim issues collision-free via `/next-issue` and `/run-epic` (see [docs/KANBAN_WORKFLOW.md](docs/KANBAN_WORKFLOW.md))
- **Devcontainer** — deny-by-default network firewall, pre-installed tooling, Claude CLI with mounted auth volume
- **Branch protection bootstrap** — one-command GitHub branch protection with required status checks
- **Day-0 validation** — `/day0-check` walks you through every setup step with pass/fail output and remediation hints

## How it works

Work comes in as a board card, gets **routed** by risk — to a human, to Claude, or to a
cheaper local model — and every change runs the same security gates before it merges. The
whole loop runs inside a devcontainer whose network is deny-by-default.

📊 **[Open the visual overview →](docs/explainer/index.html)** — a one-page briefing (for
technical and non-technical readers) covering the devcontainer, the two engines, caveman
token compression, and the CI gates. Self-contained HTML; open it locally or host it via
GitHub Pages.

- **Routing** derives from `scripts/route-model.sh`; the same Human/Claude/Local decision
  shows up as the **Route** field on each board card.
- **Gates are required, not advisory** — a red check blocks the merge (see
  [`.github/workflows/`](.github/workflows/)).
- **Caveman** trims Claude's prose to cut output tokens and surfaces a live per-session
  token/cost tally in the statusline (see [docs/TEMPLATE_GUIDE.md](docs/TEMPLATE_GUIDE.md)).

## Prerequisites

- Docker + VS Code Dev Containers extension
- Git with SSH access to GitHub
- Claude Code CLI (authenticated before first session)
- Optional: Ollama on host port 11434 for local model offload

See [docs/TEMPLATE_GUIDE.md](docs/TEMPLATE_GUIDE.md) for the full setup guide including Caveman token compression and PII-Shield.

## Quick Start

1. **Use this template** — click "Use this template" on GitHub, or clone and re-init:
   ```bash
   git clone <this-repo> my-project && cd my-project && rm -rf .git && git init
   ```

2. **Open in devcontainer** — VS Code prompts to reopen; accept. The container installs all tooling automatically on start.

3. **Complete day-0 setup** — two browser logins; everything else is applied automatically on container start:
   ```bash
   gh auth login --hostname github.com --git-protocol https --web -s project && gh auth setup-git
   claude auth login
   bash scripts/setup-day0.sh   # finishes the auth-gated bootstraps, prints status
   ```
   Verify anytime with `bash scripts/check-day0.sh` — or from Claude: `/day0-check`

4. **Validate the template** — confirm all template integrity checks pass:
   ```bash
   bash scripts/validate-template.sh
   ```

## Repository Structure

```
.claude/commands/    Claude Code skills (/bmad, /bmad-to-board, /next-issue, /run-epic, /day0-check, /route-task, /security-audit, /firewall-allow)
.devcontainer/       Dev environment with deny-by-default firewall and pre-installed tooling
.github/             Workflows (CI, secret scan, semgrep, container scan, weekly audit); issue & PR templates
docs/                TEMPLATE_GUIDE.md, AI_ROUTING_POLICY.md, BMAD_WORKFLOW.md, KANBAN_WORKFLOW.md
scripts/             Bootstrap (incl. board), routing, CI helpers, and template validator
```

## Deriving a New Project

When you start a new project from this template:

1. Replace this `README.md` with your project README — use [`docs/README.template.md`](docs/README.template.md) as a starting point.
2. Add `scripts/ci/lint-*.sh` and `scripts/ci/test-*.sh` for your language stack (see `scripts/ci/README.md`).
3. Do the two day-0 logins (quick start step 3) — `scripts/setup-day0.sh` then fills CODEOWNERS, copies configs, applies branch protection, and creates the Kanban board (see [docs/KANBAN_WORKFLOW.md](docs/KANBAN_WORKFLOW.md)).

## License

Apache 2.0 — see [LICENSE](LICENSE).
