# /next-issue — Claim and build the next ready card

Pick up the top ready card from the board without colliding with anyone else,
implement it, and open a PR. This is how an agent session "picks up an issue."

## Preconditions

- The board exists (`.ai/project.env` present) and you are on a clean working tree.

## Instructions

1. Find the next card:
   `bash scripts/board.sh next`
   If nothing is returned, report that the queue is empty and stop. The user may
   pass a specific issue number instead — if so, use that.

2. **Claim it (collision-safe):**
   `bash scripts/board.sh claim <n>`
   - Exit code 3 means it was already assigned or was claimed concurrently — do
     NOT proceed. Run `bash scripts/board.sh next` again for a different card.
   - Success means you now hold it (assigned + `wip` + Status=In Progress).

3. Read the issue in full (`gh issue view <n>`). Note the acceptance criteria and
   the board **Route**:
   - `Route=Human` should not reach you via `next`; if the user forced such an
     issue, confirm they want an agent to proceed.
   - `Route=Local` — prefer routing generation through `scripts/ask-local.sh`
     per the model-routing protocol in CLAUDE.md.
   - `Route=Claude` — proceed in this session.

4. Create an isolated branch: `git checkout -b issue-<n>-<short-slug>`.

5. Implement the story so it satisfies every acceptance criterion. Run the
   repo's checks (pre-commit, tests, `bash scripts/validate-template.sh` if
   relevant) before opening the PR.

6. Open a PR that closes the issue:
   `gh pr create --fill --body "Closes #<n>\n\n<what changed + which AC are met>"`
   Fill in the BMAD Stage checkbox in the PR template.

7. Move the card: `bash scripts/board.sh move <n> in-review`.

8. Report the PR URL. If you could not finish, run
   `bash scripts/board.sh release <n>` so the card returns to Ready for someone
   else, and explain what is blocking.

**Golden rule:** never touch a card that is already assigned or In Progress.
