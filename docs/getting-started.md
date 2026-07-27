# Getting Started Guide

A step-by-step guide to building and publishing your own site with this template — from first edit to live deployment.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Initial setup](#2-initial-setup)
3. [Configure your site metadata](#3-configure-your-site-metadata)
4. [Understand the project structure](#4-understand-the-project-structure)
5. [Templating mechanism](#5-templating-mechanism)
6. [Customise the header and footer](#6-customise-the-header-and-footer)
7. [Add and edit pages](#7-add-and-edit-pages)
8. [Add global data](#8-add-global-data)
9. [Add styles and assets](#9-add-styles-and-assets)
10. [Run diagnostics and checks](#10-run-diagnostics-and-checks)
11. [Publish your site](#11-publish-your-site)

---

## 1. Prerequisites

- **Node.js** v18 or later (`node --version` to check)
- **npm** v9 or later (`npm --version` to check)
- **Git**
- A hosting account: [GitHub Pages](https://pages.github.com/), [Cloudflare Pages](https://pages.cloudflare.com/), or [Netlify](https://netlify.com/)

---

## 2. Initial setup

```bash
# Clone the template
git clone https://github.com/your-org/webpage-static-template my-site
cd my-site

# Install dependencies
npm install

# Start the dev server
npm run dev
```

Visit `http://localhost:8080` — you should see the default homepage.

---

## 3. Configure your site metadata

All global site metadata lives in one file:

**`src/_data/site.json`**

```json
{
  "url": "https://your-domain.com",
  "lang": "en-US",
  "title": "My Site",
  "description": "A short description of what this site is about.",
  "author": "Your Name or Team",
  "socialImage": "/assets/img/social-card.png"
}
```

| Field         | Used for                                             |
| ------------- | ---------------------------------------------------- |
| `url`         | Canonical URLs and Open Graph meta tags              |
| `lang`        | `<html lang="...">` attribute                        |
| `title`       | Browser tab, page titles, OG title fallback          |
| `description` | `<meta name="description">`, OG description fallback |
| `author`      | Footer copyright line                                |
| `socialImage` | OG image for rich link previews                      |

Every value in this file is available in any template as `{{ site.fieldName }}`. Update this file before publishing — the defaults (`example.com`, `Site Title`) will appear in production if you don't.

---

## 4. Understand the project structure

```
src/
├── _data/          # Global data files (JSON) — available in all templates
├── _includes/
│   ├── layouts/    # Full-page HTML wrappers
│   └── partials/   # Reusable HTML fragments (header, footer, etc.)
├── pages/          # Your site's pages (.njk files)
├── assets/
│   ├── css/        # Stylesheets
│   ├── js/         # JavaScript
│   ├── img/        # Images
│   └── vendor/     # Third-party JS (self-hosted)
└── robots.txt.njk  # Generates /robots.txt
```

**Build output** — everything compiles to `dist/`, which is what gets deployed. Never edit files in `dist/` directly; they are overwritten on every build.

---

## 5. Templating mechanism

This template uses [Nunjucks](https://mozilla.github.io/nunjucks/) (`.njk` files) as its templating language, processed by [Eleventy](https://www.11ty.dev/).

### How a page is rendered

1. A page file (e.g. `src/pages/about.njk`) declares its **layout** in front matter
2. Eleventy wraps the page's content inside that layout
3. The layout includes partials (header, footer)
4. The result is written as a static `.html` file in `dist/`

### Front matter

Every page starts with a YAML front matter block delimited by `---`:

```njk
---
title: About
description: Learn more about this project.
permalink: /about/
---

<h1>About</h1>
<p>Page content goes here.</p>
```

| Front matter key | Purpose                                                   |
| ---------------- | --------------------------------------------------------- |
| `title`          | Page title — used in `<title>` tag and OG tags            |
| `description`    | Overrides the site-level description for this page        |
| `permalink`      | Output URL. Always set this explicitly (see below)        |
| `layout`         | Which layout to use. Omit if set in a directory data file |

### Permalinks

The `permalink` value controls the output path. **Always set it explicitly** to avoid the page URL mirroring the source file path.

```yaml
permalink: /          # → dist/index.html  (homepage)
permalink: /about/    # → dist/about/index.html
permalink: /blog/     # → dist/blog/index.html
permalink: /404.html  # → dist/404.html  (error page)
```

### Outputting content in a layout

Inside a layout, `{{ content | safe }}` is where the page's body is injected:

```njk
<main id="content">
  {{ content | safe }}
</main>
```

The `| safe` filter tells Nunjucks not to escape the HTML.

### Variables and expressions

```njk
{# Print a variable #}
{{ site.title }}

{# Conditional #}
{% if page.url == "/" %}active{% endif %}

{# Include a partial #}
{% include "partials/header.njk" %}

{# Comment (not rendered in output) #}
{# This is a Nunjucks comment #}
```

### Directory data files

A `*.json` file in a directory applies its values to all pages in that directory. For example, `src/pages/pages.json` sets the default layout for every page in `src/pages/`:

```json
{
  "layout": "layouts/base.njk"
}
```

This means individual pages don't need to declare `layout:` in their own front matter.

---

## 6. Customise the header and footer

### Header — `src/_includes/partials/header.njk`

The header is a Nunjucks partial included on every page via the base layout. Edit it to change the site title link, navigation items, or structure.

**Adding a nav link:**

```njk
<li>
  <a href="/contact/"{% if page.url == "/contact/" %} aria-current="page"{% endif %}>
    Contact
  </a>
</li>
```

The `aria-current="page"` attribute is applied when `page.url` matches the link's href — this is important for accessibility and should be preserved on every nav link.

### Footer — `src/_includes/partials/footer.njk`

Edit this file to change the copyright line, add footer links, or include additional content.

```njk
<footer>
  <p>&copy; {{ site.author }}. All rights reserved.</p>
</footer>
```

### Adding a new partial

1. Create a file in `src/_includes/partials/`, e.g. `src/_includes/partials/banner.njk`
2. Include it anywhere in a layout or page:

```njk
{% include "partials/banner.njk" %}
```

---

## 7. Add and edit pages

### Creating a new page

1. Create a `.njk` file in `src/pages/`:

```njk
---
title: Contact
description: Get in touch with us.
permalink: /contact/
---

<h1>Contact</h1>
<p>Email us at <a href="mailto:hello@example.com">hello@example.com</a>.</p>
```

2. Add a link to the page in `src/_includes/partials/header.njk`

3. The page will be available at `http://localhost:8080/contact/` immediately (the dev server reloads on save)

### Creating a custom layout

If a page needs a different structure (e.g. no nav, full-width content):

1. Create `src/_includes/layouts/minimal.njk`:

```njk
<!DOCTYPE html>
<html lang="{{ site.lang }}">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>{{ title }} · {{ site.title }}</title>
    <link rel="stylesheet" href="/assets/css/main.css">
  </head>
  <body>
    <main id="content">
      {{ content | safe }}
    </main>
  </body>
</html>
```

2. Reference it in a page's front matter:

```yaml
layout: layouts/minimal.njk
```

### The 404 page

`src/pages/404.njk` uses `permalink: /404.html` and is served automatically by most static hosts when a URL is not found. Edit its content but do not change the permalink.

---

## 8. Add global data

Any `.json` file placed in `src/_data/` is automatically available in all templates under its filename (without the extension).

**Example — add team members:**

Create `src/_data/team.json`:

```json
[
  { "name": "Alice", "role": "Designer" },
  { "name": "Bob", "role": "Developer" }
]
```

Use it in any template:

```njk
<ul>
  {% for member in team %}
    <li>{{ member.name }} — {{ member.role }}</li>
  {% endfor %}
</ul>
```

The existing `src/_data/site.json` follows the same pattern and is available as `{{ site.* }}` everywhere.

---

## 9. Add styles and assets

### CSS

All styles live in `src/assets/css/main.css`. There is no build step for CSS — it is copied as-is to `dist/assets/css/main.css`.

Add your own styles at the bottom of `main.css`, or create additional files and link them from `base.njk`:

```njk
<link rel="stylesheet" href="/assets/css/main.css">
<link rel="stylesheet" href="/assets/css/components.css">
```

### Images

Place images in `src/assets/img/`. They are copied to `dist/assets/img/` and served at `/assets/img/filename.ext`.

```njk
<img src="/assets/img/hero.jpg" alt="Describe the image here">
```

All images must have an `alt` attribute — the accessibility test suite will fail if any are missing.

### JavaScript

`src/assets/js/main.js` is the entry point for any custom JS. It is deferred and loaded on every page. Keep JS minimal — the site should work without it.

---

## 10. Run diagnostics and checks

Run these commands before committing or publishing.

### Format code

```bash
make fmt
```

Auto-formats all files with Prettier. Run this first if any lint check fails with formatting errors.

### Lint

```bash
make lint
```

Runs:

- **Prettier** — checks code formatting
- **ESLint** — checks JavaScript
- **Stylelint** — checks CSS

### Build and validate HTML

```bash
make build
```

Compiles `src/` → `dist/`, generates `sitemap.xml`, then validates the built HTML with `html-validate`. Fix any reported errors before publishing.

### Unit and e2e tests

```bash
make test
```

Runs unit tests (Node built-in runner) and Playwright e2e tests against the built site. The e2e tests check:

- Pages load and return HTTP 200
- Navigation links are present and work
- Skip link exists
- Site works with JavaScript disabled

### Accessibility audit

```bash
make a11y
```

Runs axe-core against every page and asserts zero violations. Fix all reported issues before publishing — the CI pipeline enforces this.

### Full CI gate (recommended before pushing)

```bash
make ci
```

Runs everything in order: lint → build (with HTML validation) → tests. This is identical to what runs in GitHub Actions. If `make ci` passes locally, the CI pipeline will pass.

### Lighthouse

```bash
make lighthouse
```

Runs Lighthouse CI against the built site and checks against the configured budgets:

| Category       | Minimum score |
| -------------- | ------------- |
| Performance    | 0.90          |
| Accessibility  | 0.95          |
| Best Practices | 0.95          |
| SEO            | 0.95          |

---

## 11. Publish your site

### Option A — GitHub Pages (simplest)

1. Push your repository to GitHub
2. Go to **Settings → Pages**
3. Set source to **GitHub Actions**
4. The `deploy.yml` workflow deploys automatically on every push to `main`

> GitHub Pages does not support custom HTTP headers (CSP, etc.). For production use, prefer Cloudflare Pages or Netlify.

### Option B — Cloudflare Pages

1. Connect your repository in the Cloudflare Pages dashboard
2. Set build settings:
   - **Build command**: `HOSTING_TARGET=cloudflare make build && HOSTING_TARGET=cloudflare ./scripts/copy-headers.sh`
   - **Output directory**: `dist`
3. Deploy

The security headers in `ops/headers/cloudflare/_headers` will be copied into `dist/` and served automatically.

### Option C — Netlify

**Option 1 — `_headers` file:**

1. Connect your repository in Netlify
2. Set build settings:
   - **Build command**: `HOSTING_TARGET=netlify make build && HOSTING_TARGET=netlify ./scripts/copy-headers.sh`
   - **Publish directory**: `dist`

**Option 2 — `netlify.toml`:**

```bash
cp ops/headers/netlify/netlify.toml ./netlify.toml
```

Commit the file to your repository root. Netlify will pick it up automatically and no build command changes are needed.

### Verify after deploy

Once live, confirm the following:

- [ ] Homepage loads at your domain
- [ ] `/about/` loads correctly
- [ ] `/nonexistent-page` shows your custom 404
- [ ] `/sitemap.xml` is accessible
- [ ] `/robots.txt` is accessible
- [ ] Page titles match your `site.json` values
- [ ] Open Graph previews show correct title, description, and image (use [opengraph.xyz](https://www.opengraph.xyz/) to check)
- [ ] Security headers are present (use [securityheaders.com](https://securityheaders.com/) to check — not applicable for GitHub Pages)
