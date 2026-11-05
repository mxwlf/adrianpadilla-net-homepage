import js from "@eslint/js";
import globals from "globals";

export default [
  js.configs.recommended,
  {
    languageOptions: {
      ecmaVersion: "latest",
      sourceType: "module",
      globals: {
        ...globals.node,
      },
    },
    rules: {
      "no-unused-vars": ["error", { argsIgnorePattern: "^_" }],
    },
  },
  {
    // Everything under src/assets/js ships to the browser, not to Node, and as
    // classic <script> tags rather than modules — `document.currentScript`,
    // which analytics.js reads its measurement id from, is only populated for
    // those.
    files: ["src/assets/js/**/*.js"],
    languageOptions: {
      sourceType: "script",
      globals: {
        ...globals.browser,
      },
    },
  },
  {
    // `.venv/` holds the pinned pre-commit tooling (`make setup`); some of its
    // Python packages vendor browser JS that is not ours to lint.
    //
    // `release/`, `reports/` and `sbom/` are release-packaging output. Linting
    // them would re-lint copies of src/assets/js under the wrong config: the
    // browser-globals block above is keyed on the src path, so the fingerprinted
    // copies in release/site/assets/js would fail `no-undef` on `window`.
    ignores: [
      "dist/",
      "node_modules/",
      ".cache/",
      ".venv/",
      ".lighthouseci/",
      "release/",
      "reports/",
      "sbom/",
    ],
  },
];
