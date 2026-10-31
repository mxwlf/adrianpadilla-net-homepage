import { createHash } from "node:crypto";
import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";

const ASSET_SRC_DIR = "src/assets";
const HASH_LENGTH = 8;

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
    const contents = readFileSync(path.join(ASSET_SRC_DIR, rel));
    const hash = createHash("sha256").update(contents).digest("hex").slice(0, HASH_LENGTH);

    const ext = path.posix.extname(rel);
    const dir = path.posix.dirname(rel);
    const hashed = `${path.posix.basename(rel, ext)}.${hash}${ext}`;
    const outRel = dir === "." ? hashed : `${dir}/${hashed}`;

    return {
      from: `${ASSET_SRC_DIR}/${rel}`,
      to: `assets/${outRel}`,
      url: `/assets/${rel}`,
      hashedUrl: `/assets/${outRel}`,
    };
  });
}

export default function (eleventyConfig) {
  const assets = collectAssets();
  const hashedUrls = Object.fromEntries(assets.map((a) => [a.url, a.hashedUrl]));

  if (assets.length > 0) {
    for (const asset of assets) {
      eleventyConfig.addPassthroughCopy({ [asset.from]: asset.to });
    }
  } else {
    eleventyConfig.addPassthroughCopy("src/assets");
  }

  eleventyConfig.addPassthroughCopy("src/static");

  // Clients that ask for /favicon.ico without reading the markup — feed
  // readers, link unfurlers, bookmark tools — only ever look at the site root,
  // so this one lands there rather than under the fingerprinted /assets/.
  eleventyConfig.addPassthroughCopy({ "src/favicon.ico": "favicon.ico" });

  // SWA reads its config from the root of output_location, not the repo root.
  eleventyConfig.addPassthroughCopy({
    "staticwebapp.config.json": "staticwebapp.config.json",
  });

  // Resolves a source asset URL to the URL it was emitted under. Paths that
  // were not fingerprinted — a dev build, or a reference to a file absent from
  // src/assets — pass through unchanged, so every call still yields a usable
  // URL rather than failing the build.
  eleventyConfig.addFilter("asset", (url) => hashedUrls[url] ?? url);

  return {
    dir: {
      input: "src",
      output: "dist",
      includes: "_includes",
      data: "_data",
    },
    templateFormats: ["njk", "md", "html"],
    htmlTemplateEngine: "njk",
    markdownTemplateEngine: "njk",
  };
}
