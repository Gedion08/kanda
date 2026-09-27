// @ts-check
import eslint from '@eslint/js';
import globals from 'globals';
import tseslint from 'typescript-eslint';

const typed = [...tseslint.configs.strictTypeChecked, ...tseslint.configs.stylisticTypeChecked].map(
  (config) => ({ ...config, files: ['**/*.{ts,tsx}'] }),
);

export default tseslint.config(
  {
    ignores: [
      '**/node_modules/**',
      '**/dist/**',
      '**/coverage/**',
      '**/.turbo/**',
      '**/generated/**',
      '**/.ponder/**',
      'contracts/**',
    ],
  },
  eslint.configs.recommended,
  ...typed,
  {
    files: ['**/*.{ts,tsx}'],
    languageOptions: {
      globals: { ...globals.node },
      parserOptions: { projectService: true, tsconfigRootDir: import.meta.dirname },
    },
    rules: {
      // AGENTS.md: never use floats for money. Parse amounts with the bigint helpers in @kanda/shared.
      'no-restricted-globals': [
        'error',
        {
          name: 'parseFloat',
          message: 'Money is bigint base units; use the decimal helpers in @kanda/shared.',
        },
      ],
      'no-restricted-properties': [
        'error',
        {
          object: 'Number',
          property: 'parseFloat',
          message: 'Money is bigint base units; use @kanda/shared.',
        },
        { property: 'toFixed', message: 'Format money with formatMoney / decimal helpers, not floats.' },
      ],
      // Structured logging only (pino with PII scrubbing, L4 section 13).
      'no-console': 'error',
    },
  },
);
