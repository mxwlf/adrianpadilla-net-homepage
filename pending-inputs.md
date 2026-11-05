# Open items

What is genuinely still outstanding on this site. This started as the template's
scaffolding checklist; most of it has since been answered, and the answered
items were removed rather than left to be re-read. What they resolved to is
recorded at the bottom.

---

## 1. The social card image is missing, and the site advertises it

`src/_data/site.json` sets `"socialImage": "/assets/img/social-card.png"`, so
every page emits:

```html
<meta property="og:image" content="https://adrianpadilla.net/assets/img/social-card.png" />
```

That file does not exist. Verified against the live site:

```console
$ curl -sI https://adrianpadilla.net/assets/img/social-card.png | head -1
HTTP/2 404
```

So link previews on Slack, LinkedIn, iMessage and anything else that reads
Open Graph currently resolve an image that 404s. `.claude/rules/seo.md` requires
`og:image` on all public pages, so this is a live rule violation, not a nicety.

**Needs:** a 1200×630 PNG or JPG at `src/assets/img/social-card.png`. Nothing in
the build needs changing — the path is already wired up and fingerprinted.

If a card is not wanted, the alternative is to remove `socialImage` from
`site.json` and drop the `og:image` tag from the layout, which also means
amending the SEO rule. A missing tag is better than a broken one; an actual
image is better than both.

---

## 2. The "Me" page is still a stub

`src/pages/about/me.njk` is 17 lines: a name, a handle, and a LinkedIn link. The
prototype it was ported from carried lorem ipsum in place of a bio, so there was
nothing to bring across.

**Needs:** the bio.

---

## 3. Visual regression tests: wanted as a merge gate?

The origin spec listed visual regression as "optional, team choice". Nothing has
been built either way, so this is still an open decision rather than a task.

- **Yes** — catches unintended layout changes, at the cost of maintaining
  baseline screenshots and the flake that comes with them.
- **No** — less CI friction; rely on review and the Lighthouse budgets.

Worth noting that the gate is already fairly heavy: `ci`, `lighthouse`,
`dependency-review`, `osv-scan` and `gitleaks` all block a merge, with `infra`
and `actions-lock` reporting alongside.

---

## Resolved, for the record

| Was                                                   | Resolution                                                                                                                                              |
| ----------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Site identity placeholders                            | `src/_data/site.json` is filled in — real URL, title, description, author                                                                               |
| Hosting provider (Pages / Netlify / Cloudflare / AWS) | **Azure Static Web Apps**, two environments. See [`docs/deployment.md`](docs/deployment.md)                                                             |
| MCP server skeleton for an issue tracker              | `.mcp.json` carries Playwright; the issue-tracker placeholder is gone                                                                                   |
| Node version pinned per workflow                      | `.nvmrc` is the single source, read by every `setup-node` step. Now Node 24                                                                             |
| Domain and DNS                                        | `adrianpadilla.net` is live, zone in the `connectivity` subscription. `test.adrianpadilla.net` is covered in [`docs/deployment.md`](docs/deployment.md) |
