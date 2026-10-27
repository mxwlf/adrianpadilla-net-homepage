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
    // `.venv/` holds the pinned pre-commit tooling (`make setup`); some of its
    // Python packages vendor browser JS that is not ours to lint.
    ignores: ["dist/", "node_modules/", ".cache/", ".venv/", ".lighthouseci/"],
  },
];
