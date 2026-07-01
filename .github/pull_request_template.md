## What does this PR do?

<!-- One or two sentences. Link to the relevant issue or BMAD stage if applicable. -->

## BMAD Stage

<!-- Which BMAD stage does this complete or advance? -->
- [ ] Discovery
- [ ] Requirements
- [ ] Architecture
- [ ] Task Decomposition
- [ ] Implementation
- [ ] Security & Release Readiness

## Pre-merge checklist

- [ ] `pre-commit run --all-files` passes locally
- [ ] No new secrets introduced (gitleaks pre-commit passed)
- [ ] No new ERROR-level semgrep findings
- [ ] For new repos: `.github/CODEOWNERS` is populated with real owners (not placeholder)
- [ ] For new repos: `scripts/bootstrap-github-settings.sh` has been run (verify with `scripts/check-day0.sh`)
