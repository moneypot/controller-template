import { type CodegenConfig } from "@graphql-codegen/cli";

const config: CodegenConfig = {
  // Generate types from the schema.graphql file that hub server creates at launch
  schema: "schema.graphql",
  generates: {
    "src/__generated__/graphql.ts": {
      plugins: ["typescript"],
      config: {
        useTypeImports: true, // use `import type {}`
        enumsAsConst: true, // turn enums intotype {} as const

        // Tell codegen how to generate scalar types (default is string)
        scalars: {
          BigInt: {
            // Or "bigint" if you're using environments that support it
            input: "string",
            output: "string",
          },
          Cursor: {
            input: "string",
            output: "string",
          },
          Datetime: {
            input: "string",
            output: "Date",
          },
          JSON: {
            input: "Record<string, unknown>",
            output: "Record<string, unknown>",
          },
          UUID: {
            input: "string",
            output: "string",
          },
        },
      },
    },
  },
};
export default config;
