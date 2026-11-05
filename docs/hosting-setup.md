# Host configuration

How response headers reach the browser. For how a change reaches the site at
all, see [deployment.md](deployment.md).

The site is served by **Azure Static Web Apps**. There are two apps, one per
environment, each in its own Azure subscription:

| Environment | Hostname                   | Azure resource                    |
| ----------- | -------------------------- | --------------------------------- |
| production  | `adrianpadilla.net`, `www` | `adrianpadilla-net-homepage`      |
| test        | `test.adrianpadilla.net`   | `adrianpadilla-net-homepage-test` |

## Where the headers live

One file: **`staticwebapp.config.json`**, committed at the repository root. It
holds the `routes` cache rules and the `globalHeaders` block — Content Security
Policy, `Strict-Transport-Security`, `Permissions-Policy`.

It is **not** copied into the build output. `scripts/release-package.mjs` reads
it at packaging time and writes two variants into the release package:

```
host-config/prod/staticwebapp.config.json   the committed file, verbatim
host-config/test/staticwebapp.config.json   the same, plus X-Robots-Tag
```

The deploy then points Azure's `config_file_location` input at whichever
directory matches the environment. That is the whole mechanism, and it exists
for one reason: **host configuration is infrastructure, content is the
artifact.** Keeping the config out of `site/` is what lets both environments
serve a byte-identical site with one hash, while still differing in how the host
answers.

Both variants derive from the single committed file, so a CSP or HSTS change
cannot land in one environment and not the other. The only sanctioned
difference is `X-Robots-Tag: noindex, nofollow` on the test host — the test site
serves production's bytes, canonical URLs included, so the canonical asks search
engines not to index the staging host and the header tells them.

## Changing a header

1. Edit `staticwebapp.config.json`.
2. `make package RELEASE_VERSION=0.0.0-dev` and inspect both files under
   `release/host-config/`.
3. Open a pull request. The change reaches test on the next release and
   production when you promote it.

Both deploy jobs assert on the result rather than trusting it: the test deploy
requires `X-Robots-Tag: noindex` to be present **and** the canonical to still
point at production, and the production promotion requires that header to be
**absent** and a CSP to be present. Shipping the wrong variant fails the deploy
instead of quietly de-indexing the live site.

## Known gap

`globalHeaders` sets `Permissions-Policy`, `Strict-Transport-Security` and
`Content-Security-Policy`, but **not** `X-Content-Type-Options` or
`Referrer-Policy`, which `.claude/rules/security.md` requires. `X-Frame-Options`
is covered in effect by the CSP's `frame-ancestors 'none'`.
`Strict-Transport-Security` is also still at the trial value `max-age=300`
rather than a production lifetime.

Closing this changes live response headers, so it belongs in its own change with
its own verification. `monitor.yml` reports the two missing headers weekly.

## What used to be here

This file previously described choosing between Cloudflare Pages, Netlify and
GitHub Pages, and copying a provider-specific `_headers` file into `dist/` with
`HOSTING_TARGET=… ./scripts/copy-headers.sh`. None of that was ever used on this
site — it came from the template, the script was wired into no build step, and
its CSP had drifted from the one actually enforced. `ops/headers/` and
`scripts/copy-headers.sh` have been removed.
