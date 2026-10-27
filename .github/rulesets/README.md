# Branch protection as code

The JSON files in this directory are this repository's GitHub **rulesets** —
branch protection — stored as code. Manage them from the repository root:

```sh
make rulesets-apply     # create/update the rulesets on GitHub
make rulesets-diff      # fail if GitHub no longer matches these files
make rulesets-export    # overwrite these files from GitHub (after a UI edit)
```

All three run [`scripts/github-rulesets.sh`](../../scripts/github-rulesets.sh),
which talks to `/repos/{owner}/{repo}/rulesets` via `gh api`. The `gh ruleset`
command group is read-only (`check`, `list`, `view`), so it cannot do this.

This file covers how the rules are _stored and rebuilt_, and which of this
site's checks gate a merge. The pattern comes from
[`git-template`](https://github.com/mxwlf/git-template); the required-check list
below is specific to this repository.

## What the shipped rulesets enforce

`main-protection` is the only ruleset here, because the workflow is
**trunk-based**: `main` is the sole long-lived branch, and everything else is a
short-lived branch that exists only long enough to carry one pull request. A
feature branch needs no rules, since it cannot reach `main` except through a
reviewed, CI-gated pull request.

| `main-protection`         |                                                                  |
| ------------------------- | ---------------------------------------------------------------- |
| Enforcement               | `active`                                                         |
| Direct pushes             | blocked — pull request required, from any branch                 |
| Required checks           | `ci`, `lighthouse`, `dependency-review`, `osv-scan`, `gitleaks`  |
| Branch must be up to date | yes                                                              |
| Approvals                 | 1, admins may bypass in a PR                                     |
| Merge methods             | merge commits only (see below)                                   |
| Signed commits            | required                                                         |
| Force push / deletion     | blocked                                                          |

Three consequences worth knowing:

- **Merges must happen through GitHub.** Direct pushes to `main` are blocked, and
  `required_signatures` means whatever lands there must be signed. GitHub signs
  the merge commit it creates, which satisfies the rule. A local push will be
  rejected.
- **The merge method is a merge commit, chosen to preserve authorship.** A merge
  commit adds one new object and leaves the branch's own commits untouched, so
  each keeps the signature its author made. Squash and rebase both rewrite
  history: a squash collapses the branch into one new GitHub-signed commit, and a
  rebase rewrites every commit — which _discards_ the author's signature, leaving
  GitHub nothing to re-sign with. Listing `rebase` alongside
  `required_signatures` yields a merge button that always fails with _"Base
  branch requires signed commits. Rebase merges cannot be automatically signed by
  GitHub."_ The cost of merge commits is that `main` is not linear; that is the
  deliberate trade for keeping author signatures in the history.
- **The admin bypass is real.** `bypass_mode: "pull_request"` lets an admin merge
  a pull request whose checks are red. It prevents an accidental merge, not a
  deliberate one. On this single-maintainer repo it is also what makes
  `required_approving_review_count: 1` satisfiable at all, since you cannot
  approve your own pull request.

## The required checks, and why these five

Each `context` below is the name GitHub reports a check under — the **job id**
in the workflow (or the job's `name:`, when it sets one). Rename a job and the
required check is never reported, so the pull request waits on it forever.
Change both together.

| Context             | Workflow         | Gates                                               |
| ------------------- | ---------------- | --------------------------------------------------- |
| `ci`                | `ci.yml`         | `make ci` — git hygiene, lint, build, tests         |
| `lighthouse`        | `lighthouse.yml` | Lighthouse lab budgets (perf ≥0.90, a11y/SEO ≥0.95) |
| `dependency-review` | `security.yml`   | New dependencies, failing on severity ≥ high        |
| `osv-scan`          | `security.yml`   | Known vulnerabilities in the dependency tree        |
| `gitleaks`          | `secrets.yml`    | Hardcoded secrets                                   |

Two checks that run on pull requests are deliberately **not** required:

- **`codeql`** (`security.yml`) carries `if: github.event_name != 'pull_request'`,
  so it is skipped on every pull request. GitHub reports a job skipped by its own
  `if:` as _successful_, so requiring it would add a check that is always green
  and signals nothing. CodeQL still runs on pushes to `main` and weekly, which is
  where its findings land. Make it required only if you first change that `if:`
  so the job actually runs on pull requests.
- **`lychee`** (`linkcheck.yml`) resolves external URLs, so it fails on other
  people's outages and rate limits. Blocking a merge on the uptime of third-party
  sites trades more false stops than it prevents bad merges; it runs on pull
  requests and weekly as a report.

Because `strict_required_status_checks_policy` is on, the branch must also be up
to date with `main` before merging — if `main` moves, update the branch and let
all five run again.

## The ruleset cannot enable a merge method the repository forbids

`allowed_merge_methods` only _narrows_ what the repository already permits. The
repository has its own `allow_merge_commit` / `allow_squash_merge` /
`allow_rebase_merge` switches, they are not part of any ruleset, and this file
cannot set them. Ask for a method the repository has switched off and the merge is
refused outright:

> Merge commits are not allowed on this repository.

This repository already has merge commits enabled, so nothing is needed here. If
that ever changes, enable it under **Settings → General → Pull Requests**, or:

```sh
gh api --method PATCH repos/OWNER/REPO -F allow_merge_commit=true
```

This is the one part of the gate that `make rulesets-apply` cannot reproduce for
you, because it lives on the repository rather than in a ruleset.

## What is portable between repositories

These files only reference ids that mean the same thing everywhere:

- **`integration_id: 15368`** in `required_status_checks` is the GitHub Actions
  app — a global app id, identical in every repository. All five required checks
  are GitHub Actions jobs, so they all use it.
- **`actor_type: "RepositoryRole"`, `actor_id: 5`** is the repository admin
  role. Role ids are global too.

Do **not** commit rulesets that reference `actor_type: "Team"` or specific
users: those ids are scoped to one organization or account and will resolve to
the wrong thing, or fail, in another repo.

Ruleset **ids** are likewise per repository, which is why `apply` matches on the
`name` field instead. Rename a ruleset in one of these files and the next
`apply` creates a second one rather than renaming the original.

## Why these targets are not part of `make ci`

Rulesets are admin API surface. A workflow's default `GITHUB_TOKEN` cannot read
them and cannot be granted the rights via `permissions:`, so a `rulesets-diff`
step in CI would fail for reasons that have nothing to do with the code under
test — and it would break the rule that `make ci` behaves the same on a laptop
as in a pipeline. Run these locally, or from a workflow with an admin PAT if you
want drift detection enforced.

## Editing

JSON has no comments. `scripts/github-rulesets.sh` strips any key beginning with
`_`, so a `"_comment"` key in these files is harmless — but `make rulesets-export`
regenerates them verbatim from the API and will drop it. Durable explanation
belongs in this file.

These files are listed in [`.prettierignore`](../../.prettierignore) on purpose.
`make rulesets-export` writes them in the canonical form the script normalizes to
(2-space indent, sorted keys, one array element per line); Prettier collapses
short arrays, so letting it reformat them would make every export dirty the tree
and every `make lint` undo the export.

If you change protection in the GitHub UI, run `make rulesets-export` to bring
the change back into the repo; otherwise the next `make rulesets-apply` will
silently revert it.

**`apply` never deletes.** It creates and updates the rulesets named by the files
here, and ignores anything else on the repo. Removing a file therefore leaves its
ruleset live on GitHub — delete that one yourself:

```sh
id=$(gh api repos/OWNER/REPO/rulesets --jq '.[] | select(.name=="NAME") | .id')
gh api --method DELETE repos/OWNER/REPO/rulesets/$id
```

The omission is deliberate: a prune step would give a script that runs against
any repo the power to remove protection it did not create.
