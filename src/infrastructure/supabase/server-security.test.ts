import type { CookieMethodsServer } from '@supabase/ssr';
import type { AstroCookies } from 'astro';
import { describe, expect, it, vi } from 'vitest';
import type { SupabaseEnv } from './config';

const validEnv = {
	PUBLIC_SUPABASE_URL: 'https://fc-academic-hub.supabase.co',
	PUBLIC_SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_valid_test_key',
} satisfies SupabaseEnv;

type CreateServerClientOptions = {
	readonly global?: {
		readonly fetch?: typeof fetch;
	};
	readonly cookies: CookieMethodsServer;
};

type CreateServerClientMock = (
	url: string,
	key: string,
	options: CreateServerClientOptions,
) => {
	readonly url: string;
	readonly key: string;
	readonly options: CreateServerClientOptions;
};

const supabaseMocks = vi.hoisted(() => {
	const createServerClient = vi.fn<CreateServerClientMock>((url, key, options) => ({
		url,
		key,
		options,
	}));

	return {
		createServerClient,
	};
});

vi.mock('@supabase/ssr', async (importActual) => {
	const actual = await importActual<typeof import('@supabase/ssr')>();

	return {
		...actual,
		createServerClient: supabaseMocks.createServerClient,
	};
});

describe('createSupabaseServerClient security configuration', () => {
	it('injects a provider-token-redacting fetch wrapper without changing cookie semantics', async () => {
		const { createSupabaseServerClient } = await import('./server');
		const astroCookies = {
			set: vi.fn<AstroCookies['set']>(),
		} as unknown as AstroCookies;

		createSupabaseServerClient(
			{
				request: new Request('https://fc-academic-hub.test'),
				cookies: astroCookies,
				responseHeaders: new Headers(),
			},
			validEnv,
		);

		const options = supabaseMocks.createServerClient.mock.calls[0]?.[2];

		expect(options?.global?.fetch).toEqual(expect.any(Function));
	});
});
