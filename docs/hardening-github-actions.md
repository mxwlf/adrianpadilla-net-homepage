# Hardening GitHub Actions supply chain

What was done to this repository, why each piece exists, and how to apply the
same thing elsewhere. Written to be portable — nothing below is specific to a
static site.

There are four changes. Three are GitHub Actions supply-chain features; the
fourth is a one-line git fix that turned out to matter more than it looks.

| #   | Change                                         | Where it lives                   | Prevents                                                      |
| --- | ---------------------------------------------- | -------------------------------- | ------------------------------------------------------------- |
| 1   | Pin actions to commit SHAs, enforced by policy | workflow files + a repo setting  | a moved tag running code you never reviewed                   |
| 2   | Dependabot grouping and cooldown               | `.github/dependabot.yml`         | unmergeable split updates; adopting a release minutes old     |
| 3   | Workflow dependency lockfile                   | `.github/workflows/actions.lock` | the same, plus **transitive** actions and repository takeover |
| 4   | `-merge` on lock files                         | `.gitattributes`                 | a silently corrupted lock file                                |

**Do them in this order.** 2 before 1, because pinning without automated updates
just freezes your dependencies. 1 or 3 before enforcing anything, because the
policies block every workflow run in a repository that is not ready.

---

## 1. Pin actions to commit SHAs

### What it is

`uses: actions/checkout@v7` is a _mutable_ reference. GitHub resolves it at run
time to whatever commit the `v7` tag points at. Tags can be moved. If an
upstream maintainer's account is compromised and a tag is repointed, your next
CI run executes the attacker's code with your `GITHUB_TOKEN` and your secrets.

Pinning to a full-length commit SHA removes that: a commit hash cannot be
repointed at different content.

```yaml
# before — resolves at run time
- uses: actions/checkout@v7

# after — immutable, with the version kept readable
- uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7
```

**Keep the trailing `# v7` comment.** It is not decoration: Dependabot reads
that convention and updates the SHA _and_ the comment together. Drop it and you
keep the pin but lose the updates, which is how pins rot.

### Enforcing it

GitHub can reject unpinned workflows instead of leaving it to code review. The
setting is a repository (or organization, or enterprise) Actions policy:

```sh
# Check
gh api repos/OWNER/REPO/actions/permissions --jq .sha_pinning_required

# Enable — send the other fields too, a PUT replaces the whole object
gh api --method PUT repos/OWNER/REPO/actions/permissions \
  -F enabled=true -f allowed_actions=all -F sha_pinning_required=true
```

A non-compliant workflow then fails at the **`Set up job`** step, before any
action executes:

> The actions `actions/checkout@v7` and `lycheeverse/lychee-action@v2` are not
> allowed in `OWNER/REPO` because all actions must be pinned to a full-length
> commit SHA.

### Before you enable it

**Audit first.** Enabling this while any `uses:` is unpinned blocks _every_
workflow run in the repository:

```sh
git grep -hoE 'uses: *[^ ]+' -- .github/workflows/ | grep -vE '@[0-9a-f]{40}$'
```

No output means you are clear. Resolve a tag to its SHA with:

```sh
gh api repos/actions/checkout/git/ref/tags/v7 --jq '.object.sha'
# if that returns an annotated tag object, dereference it:
gh api repos/actions/checkout/git/tags/<sha> --jq '.object.sha'
```

Resolve them through the API rather than from memory. Doing this by hand, I
pinned one action to a SHA I had assumed and it was wrong — the workflow would
simply have failed to start.

### The surprise

**Re-running a historical run fails.** A re-run replays the workflow file from
_that run's_ commit, so anything from before you pinned is now blocked and
cannot be re-run. Push the change again on a current commit instead.

### Docs

- [Secure use reference — using third-party actions](https://docs.github.com/en/actions/reference/security/secure-use)
- [Governing execution of Actions workflows](https://docs.github.com/en/actions/how-tos/administer/control-workflow-execution)
- [About Actions policies](https://docs.github.com/en/actions/concepts/about-actions-policies)
- [REST: Actions permissions](https://docs.github.com/en/rest/actions/permissions)

---

## 2. Dependabot grouping and cooldown

### What it is

Dependabot's default is **one pull request per dependency**. Two problems follow,
and the second is not about noise at all.

**Noise.** Eight open pull requests from a single run, each needing its own
review and its own CI.

**Unmergeable updates.** Some packages must move in lockstep. Here, `stylelint`
16 → 17 failed `npm ci` outright:

```
While resolving: stylelint-config-standard@37.0.0
Found: stylelint@17.16.0
Could not resolve dependency: peer stylelint@"^16.13.0"
```

The fix was to raise `stylelint-config-standard` at the same time — which
one-pull-request-per-dependency makes **structurally impossible**. That pull
request could never go green, and would have sat open forever. Grouping is the
only way Dependabot will put both halves of one upgrade in one place where they
can be verified together.

### Configuration

```yaml
version: 2
updates:
  - package-ecosystem: "npm"
    directory: "/"
    schedule:
      interval: "weekly"
    groups:
      npm:
        applies-to: version-updates
        patterns: ["*"]
      npm-security:
        applies-to: security-updates
        patterns: ["*"]

  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
    cooldown:
      default-days: 7
    groups:
      actions:
        applies-to: version-updates
        patterns: ["*"]
      actions-security:
        applies-to: security-updates
        patterns: ["*"]
```

**`cooldown`** delays adopting brand-new releases. The window just after a
release is when a compromised upstream account does the most damage, and waiting
a week costs you nothing. It never delays _security_ updates. Note that
`default-days` is the only cooldown option `github-actions` supports —
`semver-major-days` and friends are for npm and similar.

### Things worth knowing

- **`patterns: ["*"]` puts majors in the group too**, so one failing update fails
  the whole group. The alternative is `update-types: ["minor", "patch"]` on the
  catch-all, letting majors fall through to individual pull requests. Pick
  deliberately; both are defensible.
- **A dependency matching several groups joins the first one it matches**, so
  order narrower rules above catch-alls.
- **Groups cannot span ecosystems.** They are defined per `updates:` entry, so
  one pull request per ecosystem is the floor.
- **The default open-PR limit is 5 per ecosystem**, which is why a backlog stalls.
- **`target-branch` is best left unset.** Dependabot targets the repository's
  default branch and follows it when that changes. Setting it pins Dependabot to
  one branch and silently stops it tracking the default.

### Docs

- [Dependabot options reference](https://docs.github.com/en/code-security/reference/supply-chain-security/dependabot-options-reference) — `groups`, `cooldown`, `open-pull-requests-limit`, `target-branch`

---

## 3. Workflow dependency lockfile

### What it is

A lockfile at **`.github/workflows/actions.lock`** that pins every action your
workflows depend on to a commit — including the ones _your actions_ use. It is
generated by a GitHub CLI extension and never edited by hand.

```yaml
version: "v0.0.3"
workflows:
  ".github/workflows/ci.yml":
    - "actions/checkout@v7.0.1"
dependencies:
  "actions/checkout@v7.0.1":
    ref: "v7.0.1"
    commit: "sha1-3d3c42e5aac5ba805825da76410c181273ba90b1"
    owner_id: 44036562
    repo_id: 197814629
```

Those are this repository's real values. Note the `sha1-` prefix — the commit is
algorithm-tagged rather than a bare hex string. (Quoting and indentation above
have been normalised by this repo's formatter; the generated file uses single
quotes and four-space indents.)

Workflow files go back to readable version tags; the lockfile holds the commit.

### Why it beats SHA pinning

Two things a SHA in a `uses:` line **cannot** do:

**Transitive dependencies.** Actions used by your actions. Generating the
lockfile here immediately surfaced one that every SHA pin in the repository had
missed: `actions/attest`, pulled in by `actions/attest-build-provenance`. A SHA
pin covers the action you named and nothing underneath it.

**Repository identity.** Each entry records the source repository's numeric
`owner_id` and `repo_id`. If the name later resolves to a _different_
repository — a rename, or an account takeover and re-registration — it is
rejected at run time. A commit SHA cannot detect that, because the SHA is only
meaningful relative to a repository.

It also records `ref`, and requires the locked commit to still be _reachable_
from that ref, so a force-push that orphans the commit is an error rather than a
silent change.

### Using it

```sh
gh extension install github/gh-actions-lock

gh actions-lock                # scan .github/workflows/, pin everything, write the lockfile
gh actions-lock --verify       # resolve every ref upstream; what CI should run
gh actions-lock --verify-local # offline coverage check, no network or token
```

`--verify` is the authoritative one — it catches moved tags, orphaned commits
and changed repository identity. `--verify-local` only checks that every `uses:`
has an entry, but needs no network or credentials, which makes it usable in a
pre-commit hook.

Regenerate whenever you add a workflow or change a `uses:`. Dependabot updates
the workflow reference and the lockfile entry in the same pull request for
workflows already onboarded, so the two cannot drift.

### A verification job

Enforcement is only safe if the lockfile stays current, so check it on every
pull request:

```yaml
name: Actions lockfile
on:
  pull_request:
  push:
    branches: [main]
permissions:
  contents: read
jobs:
  actions-lock:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v7.0.1
      - env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: gh extension install github/gh-actions-lock
      - env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: gh actions-lock --verify
```

`gh` is preinstalled on GitHub-hosted runners; the extension is not. The default
token is enough to read public action repositories.

**Give this job no `paths:` filter.** A required status check that does not run
on every pull request is never reported, and GitHub waits on it forever. Leaving
the filter off is what lets you make it required.

**Verify, never generate, in CI.** The job must not be able to rewrite the file
it is checking.

### It composes with SHA pinning

The documentation says a lockfile satisfies the SHA-pinning policy for onboarded
workflows. That is worth testing rather than trusting, because the lockfile
_removes_ the SHAs the policy appears to demand. Tested here: a pull request
replaced every SHA with a tag while `sha_pinning_required` was active, and every
check passed. The two policies are independent checks that layer.

### Enforcing it

A second policy, **Require lockfile**, blocks runs of workflows that are not
onboarded — including workflows with **no `uses:` at all**.

| Workflow                                         | SHA pinning            | Require lockfile |
| ------------------------------------------------ | ---------------------- | ---------------- |
| In the lockfile                                  | passes, no SHAs needed | passes           |
| Not in the lockfile, `uses:` pinned to SHAs      | passes                 | **blocked**      |
| Not in the lockfile, `uses:` on tags or branches | **blocked**            | **blocked**      |

Caveats, in rough order of how likely they are to bite:

- **Evaluate mode is GitHub Enterprise Cloud only.** Elsewhere the policy is
  active or off, with no dry run. Get the verification job reporting first.
- **Reusable workflows are not covered by the caller's lockfile.** If you call
  one from another repository, that repository needs its own lockfile or this
  policy blocks your workflow.
- **Local `./` actions are never locked**, because they run whatever is in the
  runner's workspace. Use `--migrate-local-actions` to rewrite them to the
  `$/` form, which is pinned to the workflow's own commit.
- I was **unable to configure this policy through the REST API** on a personal
  account. `GET /repos/OWNER/REPO/actions/policies` answers and a rules-less
  policy can be created, but no rule type for the lockfile requirement was
  accepted. The feature is version-gated in the docs. Check
  **Settings → Actions → Policies** in the web UI for whether it is offered to
  you.

The lockfile and its verification job are valuable without the policy — they are
what actually pins the dependencies. The policy only adds a runtime backstop.

### Docs

- [Workflow dependency lockfiles — concepts](https://docs.github.com/en/actions/concepts/security/workflow-dependency-lockfiles)
- [Locking action dependencies in a repository's workflows](https://docs.github.com/en/actions/how-tos/secure-your-work/lock-workflow-dependencies)
- [Enforcing workflow lockfiles](https://docs.github.com/en/actions/how-tos/administer/enforce-workflow-lockfiles)
- [`github/gh-actions-lock`](https://github.com/github/gh-actions-lock) — the extension, and its [troubleshooting guide](https://github.com/github/gh-actions-lock/blob/main/docs/troubleshooting.md)
- [REST: Actions policies](https://docs.github.com/en/rest/actions/policies)
- Short link the tool prints: [gh.io/actions-lockfile](https://gh.io/actions-lockfile)

---

## 4. Stop git merging lock files

Not an Actions feature, but it broke a pull request mid-way through this work and
the fix is one line.

### What happened

Clicking **Update branch** on a pull request merged `main` into it, and git
produced a `package-lock.json` that was **invalid JSON** — it blended two
versions of the same dependency objects and stopped parsing partway through. No
conflict markers, so nothing looked wrong.

One corrupt file, three red checks, three different-looking errors:

- `npm ci` → `EUSAGE`, _"can only install with an existing package-lock.json"_
- Lighthouse → the same `npm ci`
- The vulnerability scanner → `could not extract: invalid character '"' after
object key:value pair`, and so reported **0 packages**

That third one is the worst of them: a scanner reporting success while scanning
nothing.

### The fix

`.gitattributes` commonly marks lock files `-diff`, which only hides the noise
in a diff. Add **`-merge`**:

```gitattributes
*.lock            text -diff -merge
package-lock.json text eol=lf -diff -merge
pnpm-lock.yaml    text eol=lf -diff -merge
yarn.lock         text -diff -merge
```

Git then keeps your branch's version and **declares a conflict** instead of
inventing a blend. The only correct resolution becomes the obvious one:

```sh
git checkout --ours package-lock.json && npm install
```

Verified on a scratch repository: merging two divergent lock files now reports a
conflict, and the file left in the tree is intact and still parses.

### Docs

- [`gitattributes` — `merge`](https://git-scm.com/docs/gitattributes#_merge)

---

## Applying this to another repository

A rough order of operations, assuming you start from nothing:

1. **Add `.github/dependabot.yml`** with grouping and cooldown. Do this first —
   pinning without automated updates means your pins rot.
2. **Fix `.gitattributes`** if it covers lock files. One line, prevents a class
   of silent corruption.
3. **Pin your actions**, or adopt the lockfile, or both. If you only do one, the
   lockfile is the stronger choice: transitive coverage and repository identity.
   SHA pinning needs no extra tooling, which matters if contributors or
   downstream clones cannot be asked to install a `gh` extension.
4. **Add the verification job** before enforcing anything, with no `paths:`
   filter so it can be required.
5. **Audit, then enable the policy.** Confirm every workflow is covered first:
   enabling either policy in a repository that is not ready blocks every run.
6. **Make the check required** in branch protection — but only after the job has
   reported at least once, or pull requests will wait on a context that has
   never existed.

A note on templates specifically: a lockfile in a template repository propagates
to every clone, and those clones inherit both the `gh` extension requirement and
a lockfile that goes stale the moment they add a workflow of their own. That may
be exactly what you want — it forces onboarding — but it is a real imposition on
downstream users, and worth deciding rather than inheriting.
