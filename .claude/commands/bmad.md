# /bmad — BMAD Planning Session

Start a structured BMAD planning session for the current task or feature.

## Instructions

1. Read `docs/BMAD_WORKFLOW.md` to understand the stage definitions and current project context.

2. Ask the user: "What task or feature are we planning?" If they've already described it in their message, use that directly.

3. Based on the task, identify the appropriate BMAD starting stage:
   - **Discovery** — new problem, unknown scope, requirements unclear
   - **Requirements** — problem understood, defining what to build
   - **Architecture** — requirements clear, designing how to build it
   - **Task Decomposition** — architecture decided, breaking into implementation tasks
   - **Implementation** — executing a specific task from the decomposition
   - **Security & Release Readiness** — implementation complete, preparing to ship

4. Guide the user through the stage:
   - Ask the stage-appropriate questions
   - Help produce the stage artifact (discovery brief, requirements doc, architecture decision, task list, implementation plan, or security checklist)
   - Identify any escalation triggers (from CLAUDE.md) that require routing to Claude vs. local model

5. At the end of each stage, confirm: "Should we advance to the next BMAD stage, or is there more to clarify here?"

## Output format

Produce a clearly labeled stage artifact that can be committed to the repo as part of the BMAD workflow documentation.
