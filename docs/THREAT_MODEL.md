# Threat Model

What this template protects, what it does not, and why. Written to be read
before you trust it — including by someone deciding whether it is good enough
for their situation, which means the non-goals matter as much as the controls.

`SECURITY.md` covers reporting and response. This covers design.

## Scope

The subject is **the agent, not just the code it writes**. That distinction
drove most of what follows. The repository's semgrep rules carry MITRE ATLAS
coverage — `AML.T0051` prompt injection, `AML.T0054` LLM output execution,
`AML.T0040` PII in prompts — but read what they scan: they catch
`eval(llm_response)` in *code you write*. They protect the product. Nothing in
them protects the Claude session building the product, which reads issue bodies,
PR comments, package contents and fetched pages, all of which are attacker-
reachable.

## Assets

| Asset | Where it lives | Why an attacker wants it |
| --- | --- | --- |
| Claude OAuth credential | `~/.claude/.credentials.json`, a named volume mounted into the container | Impersonate the developer's subscription |
| GitHub token | `~/.config/gh/hosts.yml`, mounted the same way | Push code, read private repos |
| SSH / signing keys | `~/.ssh` | Commit as the developer |
| Source and history | the working tree | Whatever the repository is worth |
| **The harness itself** | `CLAUDE.md`, `.claude/`, `.devcontainer/`, `scripts/route-model.sh`, gate configs | Widen every other boundary at once |

The last row is the one that is easy to miss. Files that decide what the agent
may do are a higher-value target than the code, because editing them changes the
rules for everything else — and the edit arrives looking like ordinary repo work.

## Adversary model

Ordered by how likely they are to matter here.

1. **Attacker-supplied text reaching an autonomous agent.** Anyone who can open
   an issue, comment on a PR, publish an npm package, or control a fetched page.
   Requires no access to this repository at all. This is the primary adversary
   and the one the original control set did not address.
2. **A compromised upstream.** The template repo, an installer, or a plugin.
3. **A careless developer.** Commits a secret, logs PII. The original control
   set was built almost entirely for this one.
4. **A malicious insider with repo access.** Largely out of scope; see non-goals.

## The lethal trifecta

An agent is exploitable when it has all three of: access to private data,
exposure to untrusted content, and the ability to communicate externally. Any
two are survivable. The mitigation is architectural — break one leg — not
filtering, because prompt injection is unsolved.

This template's devcontainer has **all three**:

| Leg | Present as |
| --- | --- |
| Private data | Mounted credential volumes; the working tree; anything the agent reads |
| Untrusted content | Issue and PR bodies, npm packages, `raw.githubusercontent.com`, fetched pages, local model output |
| External communication | The firewall allowlist — see below |

Design as though the injection lands, because it will.

## Trust boundaries

| Boundary | Enforced by | Holds against |
| --- | --- | --- |
| Host ↔ container | Docker + devcontainer | Host compromise |
| Container ↔ internet | `.devcontainer/init-firewall.sh` (iptables/ipset, deny-by-default, IPv6 denied wholesale) | Egress to hosts outside the allowlist |
| Agent ↔ credentials | `permissions.deny` + `sandbox.credentials` in `.claude/settings.json` | The agent reading tokens and keys |
| Agent ↔ its own rules | `.claude/hooks/guard-harness-files.sh` | A session editing its own guardrails in passing |
| Session ↔ untrusted text | `.claude/hooks/frame-untrusted-input.sh` | Issue/PR content read as instructions |
| Working tree ↔ `main` | Branch protection, required checks, CODEOWNERS | Unreviewed changes landing |

### Why deny rules, and why so few of them

`permissions.deny` is the most durable control Claude Code offers: deny rules
block in **every** permission mode, including `bypassPermissions`, and no
settings scope can remove a deny another scope added. Allow rules, by contrast,
have no effect in `bypassPermissions`, and protected paths do not survive it
either.

That absoluteness is also why the deny list is short. `.claude/settings.json`
syncs to every derived repo, and a deny there cannot be relaxed downstream — so
it may only contain rules true in *every* repo the template produces. Credential
paths qualify. Harness files do not: `/firewall-allow` legitimately edits
`.devcontainer/init-firewall.sh`, and the template repo edits all of them as its
product. Hence the hook, which can be conditional.

### Why the guard hook's escape hatch is still a boundary

`guard-harness-files.sh` yields to `CLAUDE_ALLOW_HARNESS_EDIT=1`. That is not a
formality a model can satisfy: the hook reads the variable from the Claude Code
process environment, and every Bash tool call runs in a fresh shell whose
exports die with it. Only whoever launched the session can set it.

## Non-goals

Stated plainly, because a control believed to do more than it does is worse than
no control.

**The container is not a data-containment boundary.** It is a host-protection
boundary. `init-firewall.sh` builds its allowlist from `api.github.com/meta`,
admitting the entire GitHub CIDR range — every repository, not only yours — plus
npm and the Anthropic API. `git push` to an arbitrary destination is therefore an
**accepted exfiltration path**, not a closed one. No allowlist can distinguish
your commit from an exfil payload while still supporting `git push`. Only branch
protection and human review catch that, and only after the data has reached
GitHub.

**Egress policy is per-container, not per-binary.** `curl`, `git` and `node` all
inherit the same allowlist. Tooling that scopes network policy per binary by
verified process identity, so `api.github.com` can be allowed for the agent
runtime and denied to `curl`, exists — NVIDIA's OpenShell is one, with Red Hat
maintaining and integrating it — but is out of scope at this template's scale.

**TLS is not inspected.** The allow decision is made on the client-supplied
hostname. Domain fronting is live. Terminating TLS would need a CA certificate
inside the container and a proxy holding plaintext; that trade was deliberately
declined here.

**Subagents are not a security boundary.** They run in the same process as the
parent and share its sandbox configuration. `local-worker` is a context and
routing boundary only.

**Prompt injection is not solved.** Every control here reduces blast radius.
None prevents it.

**A malicious maintainer is out of scope.** Where a repository has one
maintainer, branch protection is self-review and admins can bypass it. The
template cannot ship a second reviewer.

## Findings

From the adversarial review that produced this document. Severity reflects
impact on a derived repository.

| # | Finding | Severity | Status |
| --- | --- | --- | --- |
| A1 | `validate-template.sh` verified structure and syntax only, while README presented it as the integrity gate — a green run implied working controls | High | **Fixed** — section 9 exercises controls and is negative-tested |
| A2 | Local inference endpoint (`:11434`) is unauthenticated and firewall-permitted; `delegate-local.sh` rung 5 validates output by word count, which is a quality check, not a security one | High | **Open** — see below |
| A3 | `template-sync` merges `-X theirs` on a weekly cron with optional `workflows: write`. A compromised upstream reverts downstream security rules via a PR that looks routine. This has already happened by accident | High | **Documented** — mechanism unchanged |
| A5 | `board.sh` gates cards on Status, label and assignee — all metadata. The body, which the agent implements, can be edited after labelling | High | **Mitigated** — `frame-untrusted-input.sh` |
| A4 | `.claude/skills/bmad-*` is gitignored, installed at container start, never reviewed, varies per machine — model-invoked instructions outside the review boundary | Medium | **Open** |
| A6 | `init-firewall.sh:63` fetches its own allowlist over the network it is about to control, unpinned and unverified, with `curl -s` swallowing errors | Medium | **Open** — bootstrap chicken-and-egg |
| A9 | Single-maintainer repos make required review self-review | Medium | **Won't fix** — organisational |
| A7 | PII-Shield needed a manual per-machine install but was presented as a shipped control | Low | **Fixed** — documented as opt-in |
| A8 | `install-caveman.sh` writes to user-level `~/.claude/settings.json`, outside the repo's review gates, with a globbed hook path | Low | **Open** |

### A2 in detail

Three facts compose badly: `LOCAL_MODEL_ENABLED=true`; `init-firewall.sh`
explicitly ACCEPTs `:11434` to the host gateway; Ollama has no authentication.
Anything able to reach that gateway can serve model output that
`delegate-local.sh` will accept, because rung 5 checks `empty_output` and
`degenerate_output:unique_words` — fluent, non-degenerate, backdoored code passes
every rung with `VERDICT: OK`. `/run-epic` then fans that across parallel
subagents.

The fix is an authenticating gateway in front of the endpoint so the agent never
reaches raw inference, plus an output rail replacing the word-count heuristic.
Until then, treat local model output as unreviewed third-party code.

## What a green build actually means

`bash scripts/validate-template.sh` passing means: the files are present and
well-formed, the credential deny rules exist, every wired hook is executable, the
harness guard both denies governing files and leaves ordinary ones alone, and
routing refuses to send a high-risk security task to the local model.

It does **not** mean the firewall is currently up (that is asserted by
`init-firewall.sh` itself at container start), that the Bash sandbox initialised
(reported, not enforced — see `sandbox._failIfUnavailable_note`), or that the
open findings above are closed.
