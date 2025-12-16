// @ts-check
import eslint from "@eslint/js";
import { defineConfig, globalIgnores } from "eslint/config";
import tseslint from "typescript-eslint";

export default defineConfig(
  globalIgnores(["src/__generated__/"]),
  eslint.configs.recommended,
  tseslint.configs.recommended,
  tseslint.configs.strict
  //tseslint.configs.stylistic,
);
