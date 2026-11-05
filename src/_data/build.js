// Values derived at build time rather than hardcoded.
//
// Both are fixed at BUILD time, not deploy time. The pipeline builds once and
// promotes that package, so what a page shows is what was true when it was
// built: a release cut in December and promoted in January still shows the old
// year until the next release is built.
//
// The copyright year remains the only non-determinism in the build. The version
// is read from a committed file, so two builds of the same commit still agree,
// which is what lets a release be hash-verified on its way to production.

import { readFileSync } from "node:fs";

// version.txt is maintained by release-please and committed, so it is the one
// place the released version is recorded. Read here rather than passed in as an
// environment variable, and that is what makes a local build and the release
// build agree: release.yml checks out the tag, whose tree carries the bumped
// file. Nothing in CI has to remember to plumb a version through.
const version = readFileSync(new URL("../../version.txt", import.meta.url), "utf8").trim();

export default {
  year: new Date().getFullYear(),
  version,
};
