// Assembles the immutable release package that every environment deploys from.
//
// The pipeline builds ONCE. This script turns that build into a versioned
// package, and both test and production later deploy the same `site/` bytes
// from it rather than rebuilding. That is what makes a promotion a promotion
// and not a second, unverified build — which is what the Azure Static Web Apps
// action does by default, since its Oryx container rebuilds the site
// server-side from source that never ran `make ci`.
//
// Layout:
//   site/                                      the built site, identical everywhere
//   host-config/prod/staticwebapp.config.json  derived from the committed base
//   host-config/test/staticwebapp.config.json  the same, plus X-Robots-Tag
//   reports/                                   lighthouse, html-validate, playwright, axe
//   sbom/bom.cdx.json                          CycloneDX SBOM
//   manifest.json                              what this is and where it came from
//   SHA256SUMS                                 over site/ and sbom/
//
// `site/` deliberately excludes staticwebapp.config.json. Host configuration is
// infrastructure, not content: it is selected at deploy time through the
// action's `config_file_location` input, so the content digest stays identical
// across environments. The committed staticwebapp.config.json is still copied
// into dist/ by eleventy.config.js, because the current production deploy reads
// it from there; this script drops it from the package rather than from dist/.

import { createHash } from "node:crypto";
import {
  cpSync,
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  realpathSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

const DIST_DIR = path.join(ROOT, "dist");
const REPORTS_DIR = path.join(ROOT, "reports");
const SBOM_FILE = path.join(ROOT, "sbom", "bom.cdx.json");
const BASE_CONFIG_FILE = path.join(ROOT, "staticwebapp.config.json");
const LOCKFILE = path.join(ROOT, "package-lock.json");
const OUT_DIR = path.join(ROOT, "release");

// Present in dist/ for the current production deploy, but not part of the
// environment-neutral content the package ships.
const SITE_EXCLUDED = new Set(["staticwebapp.config.json"]);

const MANIFEST_FIELDS = [
  "version",
  "commit",
  "builtAt",
  "nodeVersion",
  "lockfileSha256",
  "siteSha256",
];

// ---------------------------------------------------------------------------
// Pure logic (unit-tested in tests/unit/release-package.test.mjs)
// ---------------------------------------------------------------------------

// Both host configs are derived from the one committed base file so a CSP or
// HSTS change cannot land in one environment and not the other.
export function hostConfigVariants(base) {
  const prod = structuredClone(base);
  const test = structuredClone(base);

  // test.adrianpadilla.net serves the same bytes as production, including
  // canonical URLs that point at production. The canonical alone asks search
  // engines not to index the staging host; this tells them.
  test.globalHeaders = { ...test.globalHeaders, "X-Robots-Tag": "noindex, nofollow" };

  return { prod, test };
}

// `<sha256><two spaces><path>` per line, sorted by path, which is the format
// `sha256sum -c` parses. One space means text mode to some implementations and
// fails to parse in others.
export function renderSha256Sums(entries) {
  return [...entries]
    .sort((a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : 0))
    .map(({ sha256, path: relPath }) => `${sha256}  ${relPath}\n`)
    .join("");
}

export function buildManifest(fields) {
  const missing = MANIFEST_FIELDS.filter(
    (key) => fields[key] === undefined || fields[key] === null
  );

  if (missing.length > 0) {
    throw new Error(`release manifest is missing required field(s): ${missing.join(", ")}`);
  }

  return Object.fromEntries(MANIFEST_FIELDS.map((key) => [key, fields[key]]));
}

// ---------------------------------------------------------------------------
// Filesystem helpers
// ---------------------------------------------------------------------------

function listFiles(dir, subdir = "") {
  return readdirSync(path.join(dir, subdir), { withFileTypes: true }).flatMap((entry) => {
    const rel = subdir ? `${subdir}/${entry.name}` : entry.name;
    if (entry.isDirectory()) return listFiles(dir, rel);
    return [rel];
  });
}

function sha256File(file) {
  return createHash("sha256").update(readFileSync(file)).digest("hex");
}

// One digest standing for a whole tree: hash the rendered SHA256SUMS of its
// files, so the value changes if any file's contents or name changes.
function treeDigest(entries) {
  return createHash("sha256").update(renderSha256Sums(entries)).digest("hex");
}

function writeJson(file, value) {
  mkdirSync(path.dirname(file), { recursive: true });
  writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`);
}

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

function main() {
  const version = process.env.RELEASE_VERSION || process.argv[2];
  const commit = process.env.RELEASE_COMMIT || process.env.GITHUB_SHA;

  if (!version) {
    throw new Error("set RELEASE_VERSION (or pass the version as the first argument)");
  }
  if (!commit) {
    throw new Error("set RELEASE_COMMIT (or GITHUB_SHA) to the commit being released");
  }
  if (!existsSync(DIST_DIR)) {
    throw new Error(`${DIST_DIR} does not exist — run \`make build\` first`);
  }
  if (!existsSync(SBOM_FILE)) {
    throw new Error(`${SBOM_FILE} does not exist — run \`make sbom\` first`);
  }

  rmSync(OUT_DIR, { recursive: true, force: true });
  mkdirSync(OUT_DIR, { recursive: true });

  // site/ — the bytes every environment serves.
  const siteDir = path.join(OUT_DIR, "site");
  for (const rel of listFiles(DIST_DIR)) {
    if (SITE_EXCLUDED.has(rel)) continue;
    const dest = path.join(siteDir, rel);
    mkdirSync(path.dirname(dest), { recursive: true });
    cpSync(path.join(DIST_DIR, rel), dest);
  }

  // host-config/ — one directory per environment, each a valid
  // `config_file_location` for the Static Web Apps deploy action.
  const { prod, test } = hostConfigVariants(JSON.parse(readFileSync(BASE_CONFIG_FILE, "utf8")));
  writeJson(path.join(OUT_DIR, "host-config", "prod", "staticwebapp.config.json"), prod);
  writeJson(path.join(OUT_DIR, "host-config", "test", "staticwebapp.config.json"), test);

  // sbom/ and reports/.
  cpSync(SBOM_FILE, path.join(OUT_DIR, "sbom", "bom.cdx.json"));
  if (existsSync(REPORTS_DIR)) {
    cpSync(REPORTS_DIR, path.join(OUT_DIR, "reports"), { recursive: true });
  }

  // SHA256SUMS covers site/ and sbom/ — the things a deploy must be able to
  // prove it did not alter. reports/ and manifest.json are evidence about the
  // build, not payload, and manifest.json cannot hash itself.
  const hashed = ["site", "sbom"].flatMap((top) => {
    const dir = path.join(OUT_DIR, top);
    if (!existsSync(dir)) return [];
    return listFiles(dir).map((rel) => ({
      path: `${top}/${rel}`,
      sha256: sha256File(path.join(dir, rel)),
    }));
  });

  writeFileSync(path.join(OUT_DIR, "SHA256SUMS"), renderSha256Sums(hashed));

  const siteEntries = hashed.filter((entry) => entry.path.startsWith("site/"));

  writeJson(
    path.join(OUT_DIR, "manifest.json"),
    buildManifest({
      version,
      commit,
      builtAt: new Date().toISOString(),
      nodeVersion: process.version,
      lockfileSha256: sha256File(LOCKFILE),
      siteSha256: treeDigest(siteEntries),
    })
  );

  console.log(`release ${version} assembled in ${path.relative(ROOT, OUT_DIR)}/`);
  console.log(`  site files: ${siteEntries.length}`);
  console.log(`  site digest: ${treeDigest(siteEntries)}`);
}

const invokedDirectly =
  process.argv[1] && realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url));

if (invokedDirectly) {
  main();
}
