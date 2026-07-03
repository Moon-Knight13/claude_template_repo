#!/usr/bin/env bash
# Deterministic tests for scripts/check-day0.sh — auth-first ordering, SKIP
# gating, WARN semantics, and exit codes — using PATH shims for gh/claude and a
# sandbox repo. No network, no real auth needed.
#
# Usage: bash scripts/tests/test-day0.sh
# Exit: 0 all pass, 1 otherwise.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(dirname "$HERE")"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0

ok()  { echo "PASS $1"; pass=$((pass + 1)); }
bad() { echo "FAIL $1: $2"; fail=$((fail + 1)); }

# ── PATH shims ────────────────────────────────────────────────────────────────
# Fake gh/claude driven by MOCK_* env vars; fake curl so the Ollama probe never
# leaves the sandbox.
SHIMS="$TMP/shims"
mkdir -p "$SHIMS"

cat > "$SHIMS/gh" <<'EOF'
#!/usr/bin/env bash
case "$1 ${2:-}" in
  "auth status")
    if [[ "${MOCK_GH_AUTHED:-false}" == "true" ]]; then
      echo "Logged in to github.com"
      [[ "${MOCK_GH_SCOPE:-false}" == "true" ]] && echo "Token scopes: 'project', 'repo'"
      exit 0
    fi
    exit 1
    ;;
  "repo view")
    # Template detection asks isTemplate. Like real gh, this fails when
    # unauthenticated, which routes detection to the offline fallback.
    [[ "${MOCK_GH_AUTHED:-false}" == "true" ]] || exit 1
    echo "${MOCK_IS_TEMPLATE:-false}"
    exit 0
    ;;
  "api user")
    echo "${MOCK_GH_LOGIN:-mockuser}"
    exit 0
    ;;
esac
exit 0
EOF

cat > "$SHIMS/claude" <<'EOF'
#!/usr/bin/env bash
case "$1 ${2:-}" in
  "auth status")
    echo "{\"loggedIn\": ${MOCK_CLAUDE_LOGGEDIN:-false}}"
    exit 0
    ;;
  "plugin list")
    if [[ "${MOCK_PLUGINS:-true}" == "true" ]]; then
      printf '%s\n' skill-creator frontend-design code-review superpowers commit-commands
    fi
    exit 0
    ;;
esac
exit 0
EOF

cat > "$SHIMS/curl" <<'EOF'
#!/usr/bin/env bash
[[ "${MOCK_OLLAMA_UP:-false}" == "true" ]] && exit 0
exit 7
EOF

chmod +x "$SHIMS/gh" "$SHIMS/claude" "$SHIMS/curl"

# ── Sandbox repo ──────────────────────────────────────────────────────────────
make_sandbox() { # writes a derived-repo sandbox into $1
    local sb="$1"
    mkdir -p "$sb/scripts/lib" "$sb/.github" "$sb/.claude" "$sb/.ai"
    cp "$SCRIPTS/check-day0.sh" "$sb/scripts/"
    cp "$SCRIPTS/lib/template-detect.sh" "$sb/scripts/lib/"
    git -C "$sb" init -q
    git -C "$sb" remote add origin https://github.com/mockuser/derived_repo.git
    # Fixture: fully configured unless a test removes something.
    echo "* @mockuser" > "$sb/.github/CODEOWNERS"
    echo "LOCAL_MODEL_ENABLED=true" > "$sb/.env"
    echo "{}" > "$sb/.claude/settings.json"
    touch "$sb/.ai/bootstrap-completed" "$sb/.ai/project-bootstrap-completed"
}

run_check() { # sandbox [K=V ...] — runs check-day0 with shims, captures output
    local sb="$1"; shift
    (
        cd "$sb" || exit 99
        env PATH="$SHIMS:$PATH" GITHUB_TOKEN="" GH_TOKEN="" \
            LOCAL_MODEL_ENABLED="${LOCAL_MODEL_ENABLED:-true}" "$@" \
            bash scripts/check-day0.sh
    ) > "$TMP/out" 2>&1
    echo $?
}

# ── Case 1: fully green ───────────────────────────────────────────────────────
SB="$TMP/green"; make_sandbox "$SB"
rc=$(run_check "$SB" MOCK_GH_AUTHED=true MOCK_GH_SCOPE=true MOCK_CLAUDE_LOGGEDIN=true MOCK_OLLAMA_UP=true)
if [[ "$rc" == "0" ]] && grep -q "All day-0 steps complete." "$TMP/out" \
    && ! grep -qE '^ (FAIL|SKIP|WARN)' "$TMP/out"; then
    ok "all green -> exit 0, no FAIL/SKIP/WARN"
else
    bad "all green" "exit=$rc; $(grep -E '^ (FAIL|SKIP|WARN)' "$TMP/out" | head -3)"
fi

# ── Case 2: gh unauthed — first FAIL is the login command, gh items SKIP ─────
SB="$TMP/unauthed"; make_sandbox "$SB"
rm -f "$SB/.ai/bootstrap-completed" "$SB/.ai/project-bootstrap-completed"
rc=$(run_check "$SB" MOCK_GH_AUTHED=false MOCK_CLAUDE_LOGGEDIN=true MOCK_OLLAMA_UP=true)
first_fail=$(grep -m1 '^ FAIL' "$TMP/out")
if [[ "$rc" == "1" ]] && [[ "$first_fail" == *"gh CLI authenticated"* ]] \
    && grep -A1 "gh CLI authenticated" "$TMP/out" | grep -q -- "--web -s project" \
    && grep -q "^ SKIP gh has Projects scope" "$TMP/out" \
    && grep -q "^ SKIP GitHub settings bootstrapped" "$TMP/out" \
    && grep -q "^ SKIP Kanban board bootstrapped" "$TMP/out"; then
    ok "gh unauthed -> first FAIL is gh login (with -s project), downstream SKIPs"
else
    bad "gh unauthed" "exit=$rc; first FAIL: $first_fail"
fi

# ── Case 3: token in env — reported first, fails the run ─────────────────────
SB="$TMP/token"; make_sandbox "$SB"
rc=$(run_check "$SB" GH_TOKEN=dummy MOCK_GH_AUTHED=true MOCK_GH_SCOPE=true MOCK_CLAUDE_LOGGEDIN=true MOCK_OLLAMA_UP=true)
first_fail=$(grep -m1 '^ FAIL' "$TMP/out")
if [[ "$rc" == "1" ]] && [[ "$first_fail" == *"No GitHub token in environment"* ]]; then
    ok "env token -> first FAIL is the token check, exit 1"
else
    bad "env token" "exit=$rc; first FAIL: $first_fail"
fi

# ── Case 4: claude unauthed — its own FAIL, gates nothing ────────────────────
SB="$TMP/claude"; make_sandbox "$SB"
rc=$(run_check "$SB" MOCK_GH_AUTHED=true MOCK_GH_SCOPE=true MOCK_CLAUDE_LOGGEDIN=false MOCK_OLLAMA_UP=true)
if [[ "$rc" == "1" ]] && grep -q "^ FAIL Claude CLI authenticated" "$TMP/out" \
    && grep -A1 "Claude CLI authenticated" "$TMP/out" | grep -q "claude auth login" \
    && grep -q "^  OK  All Claude plugins installed" "$TMP/out"; then
    ok "claude unauthed -> FAIL with claude auth login; plugins check unaffected"
else
    bad "claude unauthed" "exit=$rc"
fi

# ── Case 5: missing project scope — scope FAIL, board SKIP ───────────────────
SB="$TMP/scope"; make_sandbox "$SB"
rm -f "$SB/.ai/project-bootstrap-completed"
rc=$(run_check "$SB" MOCK_GH_AUTHED=true MOCK_GH_SCOPE=false MOCK_CLAUDE_LOGGEDIN=true MOCK_OLLAMA_UP=true)
if [[ "$rc" == "1" ]] && grep -q "^ FAIL gh has Projects scope" "$TMP/out" \
    && grep -A1 "gh has Projects scope" "$TMP/out" | grep -q "gh auth refresh -s project" \
    && grep -q "^ SKIP Kanban board bootstrapped" "$TMP/out"; then
    ok "no project scope -> scope FAIL, board SKIP"
else
    bad "no project scope" "exit=$rc"
fi

# ── Case 6: Ollama down — WARN only, run still green ─────────────────────────
SB="$TMP/ollama"; make_sandbox "$SB"
rc=$(run_check "$SB" MOCK_GH_AUTHED=true MOCK_GH_SCOPE=true MOCK_CLAUDE_LOGGEDIN=true MOCK_OLLAMA_UP=false)
if [[ "$rc" == "0" ]] && grep -q "^ WARN Ollama reachable" "$TMP/out" \
    && grep -q "All day-0 steps complete." "$TMP/out"; then
    ok "Ollama down -> WARN, exit stays 0"
else
    bad "Ollama down" "exit=$rc; $(grep -E 'Ollama|Results' "$TMP/out")"
fi

# ── Case 7: template repo self-detection still short-circuits ────────────────
SB="$TMP/template"; make_sandbox "$SB"
git -C "$SB" remote set-url origin https://github.com/Moon-Knight13/claude_template_repo.git
sed -i 's/@mockuser/@your-org\/your-team/' "$SB/.github/CODEOWNERS"
rc=$(run_check "$SB" MOCK_GH_AUTHED=false)
if [[ "$rc" == "0" ]] && grep -q "template repo itself" "$TMP/out"; then
    ok "template repo -> early exit 0"
else
    bad "template repo" "exit=$rc"
fi

echo ""
echo "test-day0: $pass passed, $fail failed"
[[ $fail -eq 0 ]] || exit 1
