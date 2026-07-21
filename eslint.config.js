import js from '@eslint/js';
import tseslint from 'typescript-eslint';

export default [
	{
		ignores: [
			'dist/**',
			'.astro/**',
			'.wrangler/**',
			'node_modules/**',
			'worker-configuration.d.ts',
		],
	},
	js.configs.recommended,
	...tseslint.configs.strict,
	{
		files: ['**/*.ts'],
		rules: {
			'no-undef': 'off',
		},
	},
	{
		files: ['src/env.d.ts'],
		rules: {
			'@typescript-eslint/no-empty-object-type': 'off',
		},
	},
];
