import { afterEach, describe, expect, it, vi } from 'vitest';
import type { SupabaseEnv } from './config';

const validEnv = {
	PUBLIC_SUPABASE_URL: 'https://fc-academic-hub.supabase.co',
	PUBLIC_SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_valid_test_key',
} satisfies SupabaseEnv;

type CreateBrowserClientOptions = {
	readonly global?: {
		readonly fetch?: typeof fetch;
	};
	readonly isSingleton?: boolean;
};

type CreateBrowserClientMock = (
	url: string,
	key: string,
	options: CreateBrowserClientOptions,
) => {
	readonly url: string;
	readonly key: string;
	readonly options: CreateBrowserClientOptions;
};

const supabaseMocks = vi.hoisted(() => {
	const createBrowserClient = vi.fn<CreateBrowserClientMock>((url, key, options) => ({
		url,
		key,
		options,
	}));

	return {
		createBrowserClient,
	};
});

vi.mock('@supabase/ssr', () => ({
	createBrowserClient: supabaseMocks.createBrowserClient,
}));

afterEach(() => {
	vi.resetModules();
	vi.unstubAllGlobals();
	supabaseMocks.createBrowserClient.mockClear();
});

describe('getSupabaseBrowserClient security configuration', () => {
	it('injects the provider-token-redacting fetch wrapper and preserves singleton behavior', async () => {
		vi.stubGlobal('window', {});
		const { getSupabaseBrowserClient } = await import('./browser');

		getSupabaseBrowserClient(validEnv);

		const options = supabaseMocks.createBrowserClient.mock.calls[0]?.[2];

		expect(options?.global?.fetch).toEqual(expect.any(Function));
		expect(options?.isSingleton).toBe(true);
	});
});
