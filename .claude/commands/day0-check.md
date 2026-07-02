# /day0-check — Day-0 Setup Validation

Validate that all required day-0 setup steps are complete and guide through any that are missing.

## Instructions

1. Run the validation script via Bash:
   ```bash
   bash scripts/check-day0.sh
   ```

2. If the script reports "This is the template repo itself — day-0 checks are not applicable",
   stop and report that: the checks validate repos *derived* from the template. Mention that
   `DAY0_FORCE_FULL=1 bash scripts/check-day0.sh` runs the full checklist anyway.

3. Parse the output and present results clearly:
   - Show each `OK` step as complete ✓
   - Show each `FAIL` step with its reason and the exact fix command

4. For each failing step, provide guided remediation:

   **CODEOWNERS not customized:**
   - Explain: "Branch protection requires real GitHub owners — the placeholder blocks all PRs until updated"
   - Action: Open `.github/CODEOWNERS`, replace `@your-org/your-team` with your GitHub username (e.g., `@MoonKnight13`)

   **.env file missing:**
   - Action: `cp .env.example .env`
   - Remind: "Review the values. Do not add GitHub tokens — auth is via `gh auth login --web`"

   **gh CLI not authenticated:**
   - Explain: "GitHub auth uses browser OAuth so no token is stored in env vars or repo files"
   - Action: user runs `gh auth login --hostname github.com --git-protocol https --web` in their terminal
     (interactive — Claude cannot run it; in a Claude Code session type `! gh auth login --web`),
     then `gh auth setup-git` so git push/pull uses gh as credential helper

   **GitHub token found in environment:**
   - Explain: "Env tokens are readable by every process in the container, including agents — this template's policy is browser OAuth only"
   - Action: remove GITHUB_TOKEN/GH_TOKEN from `.env`, host shell profile, or devcontainer config, then rebuild/restart

   **.claude/settings.json missing:**
   - Action: `cp .claude/settings.json.example .claude/settings.json`
   - Explain: "This enables the local Ollama MCP tool for routing simple tasks to the local model"

   **GitHub bootstrap not run:**
   - Action: First `APPLY=false bash scripts/bootstrap-github-settings.sh` (dry run), then `APPLY=true bash scripts/bootstrap-github-settings.sh`
   - Prerequisite: `gh auth login` with repo admin scope

   **Ollama not reachable:**
   - Explain: "Optional — only needed if LOCAL_MODEL_ENABLED=true. Install from https://ollama.com, then `ollama pull qwen2.5-coder:7b`"
   - If they don't want local models: `LOCAL_MODEL_ENABLED=false` in `.env`

5. After the user reports completing a fix, re-run `bash scripts/check-day0.sh` to confirm.

6. When all steps pass: "All day-0 steps complete. Your template repo is fully configured."
