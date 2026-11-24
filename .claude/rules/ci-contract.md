---
paths:
  - "src/**"
  - ".github/**"
  - "Makefile"
  - "package.json"
---

# CI contract rules

- Run `make setup` to activate the committed Git hooks and `make restore` to install the locked Node dependencies.
- Run `make ci` locally before opening a PR. It runs the same portable verification gate as the CI workflow.
- Keep workflow YAML a thin wrapper around the corresponding Make targets. Put check logic in the Makefile, package scripts, or pre-commit configuration.
- A required status check's `context` in `.github/rulesets/main-protection.json`
  is a workflow job id. Never rename one without the other: an unreported
  required check leaves pull requests waiting indefinitely.
- Do not make a job required if its own `if:` excludes pull requests — GitHub
  reports such a job as successful, producing a check that is always green.
- Do not disable, skip, or weaken CI quality gates without explicit team approval.
- All required checks (lint, test, build, security scans) must be green before merge.
- Do not add `--no-verify`, `continue-on-error: true`, or `if: always()` to bypass failing steps.
- Workflow permissions must follow least-privilege: `contents: read` by default, escalate per-job only as needed.
- New CI jobs should use the same `make` targets to keep local and CI behavior identical.
