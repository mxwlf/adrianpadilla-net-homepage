# Hosting Setup Guide

## Choosing a hosting provider

This template includes pre-configured security headers for multiple providers:

| Provider         | Headers file                                     | Preview deploys | Custom headers |
| ---------------- | ------------------------------------------------ | --------------- | -------------- |
| Cloudflare Pages | `ops/headers/cloudflare/_headers`                | Yes             | Yes            |
| Netlify          | `ops/headers/netlify/_headers` or `netlify.toml` | Yes             | Yes            |
| GitHub Pages     | N/A                                              | Limited         | Not supported  |

## Configuring headers

### Option 1: Automatic (recommended)

Set the `HOSTING_TARGET` environment variable and use the copy script:

```bash
# For Cloudflare Pages
HOSTING_TARGET=cloudflare ./scripts/copy-headers.sh

# For Netlify
HOSTING_TARGET=netlify ./scripts/copy-headers.sh
```

This copies the correct `_headers` file into `dist/` during build.

### Option 2: Manual

Copy the appropriate headers file into your `dist/` directory:

```bash
# Cloudflare
cp ops/headers/cloudflare/_headers dist/_headers

# Netlify (_headers file)
cp ops/headers/netlify/_headers dist/_headers

# Netlify (netlify.toml — place in repo root, not dist)
cp ops/headers/netlify/netlify.toml ./netlify.toml
```

## Build integration

The `make build` target builds the site. To include headers, run the copy script after build:

```bash
make build
HOSTING_TARGET=cloudflare ./scripts/copy-headers.sh
```

Or set `HOSTING_TARGET` in your CI environment variables so it runs automatically.

## GitHub Pages note

GitHub Pages does not support custom response headers (CSP, HSTS, etc.). If you need security headers, consider Cloudflare Pages or Netlify instead.
