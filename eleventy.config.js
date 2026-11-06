import { createHash } from "node:crypto";
import { mkdirSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";

import CleanCSS from "clean-css";

const ASSET_SRC_DIR = "src/assets";
const OUTPUT_DIR = "dist";
const HASH_LENGTH = 8;

// CSS MINIFICATION
// ----------------
// The stylesheet is heavily commented on purpose — the reasoning behind a
// contrast ratio or a vendor prefix belongs next to the declaration it
// explains. Shipping those comments is a different question: they were 47% of
// the file, and Lighthouse's `unminified-css` audit only ignores an unminified
// stylesheet while its estimated savings stay under a hard-coded 2048 bytes.
// This repository sat ~150 bytes under that cliff, so a single added comment
// could turn the lighthouse job red, which is exactly what happened in #75.
//
// Minifying here removes the cliff rather than rationing comments: savings drop
// to ~0, so the audit has nothing to report no matter how much the source grows.
//
// clean-css is pure JavaScript with one dependency and no prebuilt binaries,
// which is the same supply-chain test that ruled out the extract-zip successor
// in .claude/rules/security.md. `level: 1` is per-declaration only: it strips
// comments and whitespace and normalises values, but never reorders or merges
// rules, so cascade order — which this stylesheet depends on for its theme
// overrides — is preserved exactly.
export const minifyCss = (source) => {
  const { styles, errors } = new CleanCSS({ level: 1, returnPromise: false }).minify(source);

  // A minifier that silently emits broken CSS would be worse than none: the
  // build must stop instead of shipping a stylesheet nobody checked.
  if (errors.length > 0) {
    throw new Error(`clean-css failed:\n${errors.join("\n")}`);
  }

  return styles;
};

// Build-time transforms, by extension. An asset with no entry here is copied
// through byte for byte.
const ASSET_TRANSFORMS = { ".css": minifyCss };

// ASSET FINGERPRINTING
// --------------------
// Emits each asset under a filename containing a hash of its contents
// (main.css -> main.1a2b3c4d.css). That is what makes the one-year immutable
// Cache-Control on /assets/* in staticwebapp.config.json safe: changing a file
// changes its name, so a cached copy can never go stale. Without the hash, the
// same header would pin visitors to an old main.css for up to a year.
//
// Only real builds are fingerprinted. Hashes are computed once when this config
// loads, so under `eleventy --serve` they would go stale on the first edit and
// the page would request a filename that no longer exists; dev keeps the plain
// names instead. Eleventy sets ELEVENTY_RUN_MODE to build | serve | watch
// before loading this file.
const FINGERPRINT = process.env.ELEVENTY_RUN_MODE === "build";

// Relative, forward-slashed paths of every file under src/assets.
function listAssetFiles(subdir = "") {
  const entries = readdirSync(path.join(ASSET_SRC_DIR, subdir), {
    withFileTypes: true,
  });

  return entries.flatMap((entry) => {
    const rel = subdir ? `${subdir}/${entry.name}` : entry.name;
    if (entry.isDirectory()) return listAssetFiles(rel);
    // Dotfiles (.gitkeep) hold empty directories in git; they are not assets.
    if (entry.name.startsWith(".")) return [];
    return [rel];
  });
}

// One entry per asset: where it comes from, where it is written, and the URL
// templates reference it by.
function collectAssets() {
  if (!FINGERPRINT) return [];

  return listAssetFiles().map((rel) => {
    const ext = path.posix.extname(rel);
    const transform = ASSET_TRANSFORMS[ext];

    // The hash has to be of the bytes that are actually served, so the
    // transform runs first. Hashing the source instead would name the file
    // after content it does not contain, and a source-only edit — reflowing a
    // comment that minification strips — would change the URL without
    // changing the response, re-downloading an identical file.
    const source = readFileSync(path.join(ASSET_SRC_DIR, rel));
    const transformed = transform ? Buffer.from(transform(source.toString("utf8"))) : null;
    const contents = transformed ?? source;

    const hash = createHash("sha256").update(contents).digest("hex").slice(0, HASH_LENGTH);

    const dir = path.posix.dirname(rel);
    const hashed = `${path.posix.basename(rel, ext)}.${hash}${ext}`;
    const outRel = dir === "." ? hashed : `${dir}/${hashed}`;

    return {
      from: `${ASSET_SRC_DIR}/${rel}`,
      to: `assets/${outRel}`,
      url: `/assets/${rel}`,
      hashedUrl: `/assets/${outRel}`,
      transformed,
    };
  });
}

export default function (eleventyConfig) {
  const assets = collectAssets();
  const hashedUrls = Object.fromEntries(assets.map((a) => [a.url, a.hashedUrl]));

  if (assets.length > 0) {
    for (const asset of assets.filter((a) => a.transformed === null)) {
      eleventyConfig.addPassthroughCopy({ [asset.from]: asset.to });
    }

    // Transformed assets are written here rather than copied: passthrough copy
    // moves bytes verbatim, so it would emit the unminified source under a
    // filename whose hash describes the minified bytes. Writing after the
    // build keeps the name and the content from drifting apart.
    const generated = assets.filter((a) => a.transformed !== null);

    if (generated.length > 0) {
      eleventyConfig.on("eleventy.after", () => {
        for (const asset of generated) {
          const out = path.join(OUTPUT_DIR, asset.to);
          mkdirSync(path.dirname(out), { recursive: true });
          writeFileSync(out, asset.transformed);
        }
      });
    }
  } else {
    // Dev builds skip fingerprinting (see above) and therefore minification
    // too, which is what keeps the stylesheet readable in devtools while
    // `eleventy --serve` is running.
    eleventyConfig.addPassthroughCopy("src/assets");
  }

  eleventyConfig.addPassthroughCopy("src/static");

  // Clients that ask for /favicon.ico without reading the markup — feed
  // readers, link unfurlers, bookmark tools — only ever look at the site root,
  // so this one lands there rather than under the fingerprinted /assets/.
  eleventyConfig.addPassthroughCopy({ "src/favicon.ico": "favicon.ico" });

  // staticwebapp.config.json is deliberately NOT copied into the output.
  //
  // It used to be, because the old deploy handed Azure the repo root and let
  // Oryx rebuild, and SWA reads its config from the root of output_location.
  // Deployment now uploads a prebuilt package and selects the host config with
  // the action's `config_file_location` input, so the config lives outside
  // site/ and each environment gets its own — see scripts/release-package.mjs.
  // Copying it here would put production's headers inside the content digest
  // that is supposed to be identical in every environment.

  // Resolves a source asset URL to the URL it was emitted under. Paths that
  // were not fingerprinted — a dev build, or a reference to a file absent from
  // src/assets — pass through unchanged, so every call still yields a usable
  // URL rather than failing the build.
  eleventyConfig.addFilter("asset", (url) => hashedUrls[url] ?? url);

  return {
    dir: {
      input: "src",
      output: OUTPUT_DIR,
      includes: "_includes",
      data: "_data",
    },
    templateFormats: ["njk", "md", "html"],
    htmlTemplateEngine: "njk",
    markdownTemplateEngine: "njk",
  };
}
