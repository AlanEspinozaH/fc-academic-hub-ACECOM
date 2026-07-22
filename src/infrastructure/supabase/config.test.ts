import { afterEach, describe, expect, it, vi } from 'vitest';
import { resolveSupabaseConfig, type SupabaseEnv } from './config';

const validEnv = {
	PUBLIC_SUPABASE_URL: 'https://fc-academic-hub.supabase.co',
	PUBLIC_SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_valid_test_key',
} satisfies SupabaseEnv;

describe('resolveSupabaseConfig', () => {
	it('returns an immutable config for valid environment values', () => {
		const config = resolveSupabaseConfig(validEnv);

		expect(config).toEqual({
			url: validEnv.PUBLIC_SUPABASE_URL,
			publishableKey: validEnv.PUBLIC_SUPABASE_PUBLISHABLE_KEY,
		});
		expect(Object.isFrozen(config)).toBe(true);
	});

	it('rejects a missing Supabase URL', () => {
		expect(() =>
			resolveSupabaseConfig({
				PUBLIC_SUPABASE_PUBLISHABLE_KEY: validEnv.PUBLIC_SUPABASE_PUBLISHABLE_KEY,
			}),
		).toThrow(/PUBLIC_SUPABASE_URL/);
	});

	it('rejects a missing publishable key', () => {
		expect(() =>
			resolveSupabaseConfig({
				PUBLIC_SUPABASE_URL: validEnv.PUBLIC_SUPABASE_URL,
			}),
		).toThrow(/PUBLIC_SUPABASE_PUBLISHABLE_KEY/);
	});

	it('rejects an invalid URL', () => {
		expect(() =>
			resolveSupabaseConfig({
				...validEnv,
				PUBLIC_SUPABASE_URL: 'ftp://fc-academic-hub.supabase.co',
			}),
		).toThrow(/http or https/);
	});

	it('rejects placeholder values', () => {
		expect(() =>
			resolveSupabaseConfig({
				...validEnv,
				PUBLIC_SUPABASE_URL: 'https://your-project-ref.supabase.co',
			}),
		).toThrow(/placeholder/);
	});

	it('does not expose key values in validation errors', () => {
		const sensitiveValue = 'sb_publishable_should_not_appear';

		expect(() =>
			resolveSupabaseConfig({
				PUBLIC_SUPABASE_URL: validEnv.PUBLIC_SUPABASE_URL,
				PUBLIC_SUPABASE_PUBLISHABLE_KEY: `<${sensitiveValue}>`,
			}),
		).toThrow(
			expect.objectContaining({
				message: expect.not.stringContaining(sensitiveValue),
			}),
		);
	});
});

describe('Supabase browser module', () => {
	afterEach(() => {
		vi.doUnmock('@supabase/ssr');
		vi.resetModules();
	});

	it('does not create the browser client while importing the module', async () => {
		const createBrowserClient = vi.fn<() => { readonly mockedClient: true }>(() => ({
			mockedClient: true,
		}));

		vi.doMock('@supabase/ssr', () => ({
			createBrowserClient,
		}));

		await import('./browser');

		expect(createBrowserClient).not.toHaveBeenCalled();
	});
});
