# /day0-check — Day-0 Setup Validation

Validate day-0 setup. The only manual steps are two browser logins (gh, claude);
everything else is applied automatically by `scripts/setup-day0.sh` on container
start and on every re-run. This command verifies state and guides the user
through the remaining auth-gated steps only.

## Instructions

1. Run the validation script via Bash:
   ```bash
   bash scripts/check-day0.sh
   ```

2. If the script reports "This is the template repo itself — day-0 checks are not applicable",
   stop and report that: the checks validate repos *derived* from the template. Mention that
   `DAY0_FORCE_FULL=1 bash scripts/check-day0.sh` runs the full checklist anyway.

3. Present results clearly. The script prints auth gates first, then setup state:
   - `OK` — complete ✓
   - `FAIL` — needs action; show the hint verbatim
   - `SKIP` — blocked on an auth gate above; it fixes itself once the user logs in and
     re-runs `bash scripts/setup-day0.sh`. Do NOT treat SKIPs as separate problems.
   - `WARN` — optional feature (Ollama); never blocks a green run

4. Guided remediation — by construction, FAILs are only things Claude cannot do:

   **gh CLI not authenticated:**
   - Explain: "GitHub auth uses browser OAuth so no token is stored in env vars or repo files"
   - Action: interactive — Claude cannot run it. Tell the user to type in this session:
     `! gh auth login --hostname github.com --git-protocol https --web -s project`
     (the `-s project` grants the Kanban/Projects scope in the same login),
     then `! gh auth setup-git`
   - After login: run `bash scripts/setup-day0.sh` — it applies the GitHub ruleset and
     Kanban board bootstraps automatically. Do not run the individual `bootstrap-*` scripts by hand.

   **gh missing Projects scope** (logged in before this template's flow existed):
   - Action: user types `! gh auth refresh -s project`, then re-run `bash scripts/setup-day0.sh`

   **Claude CLI not authenticated:**
   - Action: user types `! claude auth login` (browser OAuth)

   **GitHub token found in environment:**
   - Explain: "Env tokens are readable by every process in the container, including agents — this template's policy is browser OAuth only"
   - Action: remove GITHUB_TOKEN/GH_TOKEN from `.env`, host shell profile, or devcontainer config, then rebuild/restart

   **GitHub settings bootstrapped FAIL while gh is authenticated:**
   - Usually missing repo admin permission — the hint names it. A repo admin must run
     `bash scripts/setup-day0.sh` (or `APPLY=true bash scripts/bootstrap-github-settings.sh`) once.

   **Any setup-file FAIL (CODEOWNERS, .env, .claude/settings.json, plugins):**
   - Run `bash scripts/setup-day0.sh` — it copies configs, fills CODEOWNERS from the
     git remote, and installs plugins. Only debug further if it fails after that.

   **Ollama WARN:**
   - Optional. Install on the host (https://ollama.com, `ollama pull qwen2.5-coder:7b`,
     bind to 0.0.0.0 per docs/TEMPLATE_GUIDE.md) — or set `LOCAL_MODEL_ENABLED=false` in `.env`.

5. After the user reports completing a login, run `bash scripts/setup-day0.sh` (it finishes
   the bootstraps and prints the status), then confirm with `bash scripts/check-day0.sh`.

6. When nothing FAILs: "All day-0 steps complete. Your repo is fully configured."
