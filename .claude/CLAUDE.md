# Project constitution (static template)

## Non-negotiables

- Site must work without JavaScript (progressive enhancement is mandatory).
- Any new interactive behavior must have an accessible baseline (keyboard + screen readers).
- Keep JS minimal; prefer HTML/CSS first.
- No regressions allowed in: Lighthouse budgets, a11y tests, HTML validation, and security scans.

## Local contract

- Run `make setup` once per clone or worktree. It creates `.venv/` and activates
  the committed git hooks; `make ci` fails without it.
- Always run: `make ci` before opening a PR.
- If CI fails, fix the root cause (do not disable gates without explicit approval).
- Commit messages must follow Conventional Commits; the `commit-msg` hook enforces it.
- `main` is protected. Changes reach it only through a pull request, merged with a
  merge commit. Never push to `main` directly and never use `--no-verify`.

## Architecture

- Eleventy builds from `src/` to `dist/`.
- `scripts/generate-sitemap.mjs` writes `dist/sitemap.xml`.
- `make ci` is the single gate (hooks + lint + build + test); the workflows in
  `.github/workflows/` are thin wrappers around it. Change what CI does in the
  `Makefile`, `package.json` or `.pre-commit-config.yaml`, not in workflow YAML.
- Branch protection is code: `.github/rulesets/*.json`, applied with
  `make rulesets-apply`. A required check's `context` is a workflow job id —
  renaming one without the other makes PRs hang forever.

## References

- See @.claude/rules/performance.md
- See @.claude/rules/a11y.md
- See @.claude/rules/security.md
- See @.claude/rules/seo.md
- See @.claude/rules/ci-contract.md
