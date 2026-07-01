# BMAD Workflow

This template uses BMAD as the default project workflow for Claude-led delivery.

## Stages
1. Discovery and scope
2. Requirements and PRD
3. Architecture and risk review
4. Task decomposition and plan
5. Implementation and validation
6. Security hardening and release readiness

## Usage
- Install BMAD through template bootstrap scripts.
- Use BMAD guidance in planning and delivery phases.
- Use bmad-help in Claude sessions when next steps are unclear.

## From decomposition to the board
Once the Task Decomposition stage produces a task list, `/bmad-to-board` turns it
into an epic plus story issues on the Kanban board (with BMAD Stage and a
suggested Route set on each), where they can be claimed and built. See
[KANBAN_WORKFLOW.md](KANBAN_WORKFLOW.md).
