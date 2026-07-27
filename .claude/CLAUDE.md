# Project constitution (static template)

## Non-negotiables

- Site must work without JavaScript (progressive enhancement is mandatory).
- Any new interactive behavior must have an accessible baseline (keyboard + screen readers).
- Keep JS minimal; prefer HTML/CSS first.
- No regressions allowed in: Lighthouse budgets, a11y tests, HTML validation, and security scans.

## Local contract

- Always run: `make ci` before opening a PR.
- If CI fails, fix the root cause (do not disable gates without explicit approval).

## Architecture

- Eleventy builds from `src/` to `dist/`.
- `scripts/generate-sitemap.mjs` writes `dist/sitemap.xml`.

## References

- See @.claude/rules/performance.md
- See @.claude/rules/a11y.md
- See @.claude/rules/security.md
- See @.claude/rules/seo.md
- See @.claude/rules/ci-contract.md
