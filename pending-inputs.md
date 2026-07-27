# Pending Inputs - Decisions Required

The template has been scaffolded with sensible defaults and placeholder values. The items below require your input before the site is production-ready.

---

## 1. Site Identity (update `src/_data/site.json`)

| Field         | Current placeholder                          | What you need to provide                                |
| ------------- | -------------------------------------------- | ------------------------------------------------------- |
| `url`         | `https://example.com`                        | Your production domain (e.g., `https://yourdomain.com`) |
| `lang`        | `en-US`                                      | Primary locale if different                             |
| `title`       | `Site Title`                                 | Your actual site title                                  |
| `description` | `A fast, accessible, mostly-static website.` | A real meta description (50-160 chars)                  |
| `author`      | `Your Team`                                  | Team or individual name                                 |
| `socialImage` | `/assets/img/social-card.png`                | Path to your OG image (1200x630px recommended)          |

**Action:** Edit `src/_data/site.json` with your values.

---

## 2. Hosting Provider

The template includes security headers for multiple providers. You need to choose one:

- **GitHub Pages** - simplest, but no custom response headers (CSP/HSTS not supported)
- **Netlify** - supports `_headers` file and `netlify.toml`, preview deploys included
- **Cloudflare Pages** - supports `_headers` file, edge rules, preview deploys
- **AWS (S3 + CloudFront)** - most control, most setup

**Action:** Set `HOSTING_TARGET` env var (e.g., `cloudflare` or `netlify`) and run `scripts/copy-headers.sh` during build, or manually copy from `ops/headers/<provider>/` into `dist/`.

---

## 3. Social Card Image

The OG image at `/assets/img/social-card.png` needs to be created.

**Requirements:** 1200x630px, PNG or JPG, represents your brand/site.

**Action:** Add your image to `src/assets/img/social-card.png`.

---

## 4. Navigation Items

The header partial (`src/_includes/partials/header.njk`) has placeholder navigation links (Home, About).

**Action:** Update navigation items in the header partial to match your site structure.

---

## 5. Visual Regression Tests - Merge Gate?

The spec lists visual regression as "Optional (team choice)" for merge gating.

- **Yes** - catches unintended layout changes, but requires maintaining baseline screenshots
- **No** - less CI friction, rely on manual review for visual changes

**Action:** Decide and configure in your GitHub branch protection rules if desired.

---

## 6. MCP Server Configuration (`.mcp.json`)

The MCP config has a skeleton for an issue tracker integration. If you use one:

**Action:** Replace placeholder values in `.mcp.json` with your actual server command, args, and set the `ISSUE_TRACKER_TOKEN` environment variable.

---

## 7. Node.js Version

Currently pinned to **Node 20** in CI workflows.

**Action:** If you need a different version, update `.github/workflows/*.yml` and optionally add an `.nvmrc` file.

---

## 8. Domain and DNS

For deployment to work with custom domains:

**Action:** Configure DNS with your hosting provider and update `src/_data/site.json` url field.

---

## Priority Order

1. **Site Identity** (#1) - needed before any real content
2. **Hosting Provider** (#2) - needed before first deploy
3. **Social card** (#3) - needed for link previews
4. Everything else - can be deferred
