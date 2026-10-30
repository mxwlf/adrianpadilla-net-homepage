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
    // src/assets/js/ ships to the browser as classic <script> tags, not as
    // modules and not through Node: it needs the browser globals, and
    // `document.currentScript` is only populated for classic scripts.
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
    ignores: ["dist/", "node_modules/", ".cache/", ".venv/", ".lighthouseci/"],
  },
];
