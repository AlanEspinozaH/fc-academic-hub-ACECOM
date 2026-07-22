import type { CookieMethodsServer, CookieOptions } from '@supabase/ssr';
import type { AstroCookies } from 'astro';
import { describe, expect, it, vi } from 'vitest';
import type { SupabaseEnv } from './config';

const validEnv = {
	PUBLIC_SUPABASE_URL: 'https://fc-academic-hub.supabase.co',
	PUBLIC_SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_valid_test_key',
} satisfies SupabaseEnv;

type CreateServerClientOptions = {
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

describe('createSupabaseServerClient', () => {
	it('uses request cookies through getAll and writes Supabase cookies through AstroCookies', async () => {
		const { createSupabaseServerClient } = await import('./server');
		const setCookie = vi.fn<AstroCookies['set']>();
		const astroCookies = {
			set: setCookie,
		} as unknown as AstroCookies;
		const responseHeaders = new Headers();
		const request = new Request('https://fc-academic-hub.test', {
			headers: {
				Cookie: 'first=one; sb-access-token=request-token; encoded=value%202',
			},
		});
		const expires = new Date('2030-01-02T03:04:05.000Z');
		const cookieOptions = {
			path: '/',
			domain: 'fc-academic-hub.test',
			expires,
			maxAge: 3600,
			httpOnly: true,
			secure: true,
			sameSite: 'lax',
		} satisfies CookieOptions;

		createSupabaseServerClient(
			{
				request,
				cookies: astroCookies,
				responseHeaders,
			},
			validEnv,
		);

		const options = supabaseMocks.createServerClient.mock.calls[0]?.[2];

		expect(options?.cookies.getAll()).toEqual([
			{
				name: 'first',
				value: 'one',
			},
			{
				name: 'sb-access-token',
				value: 'request-token',
			},
			{
				name: 'encoded',
				value: 'value 2',
			},
		]);

		options?.cookies.setAll?.(
			[
				{
					name: 'sb-refresh-token',
					value: 'response-token',
					options: cookieOptions,
				},
			],
			{
				'Cache-Control': 'private, no-store',
				Pragma: 'no-cache',
			},
		);

		expect(setCookie).toHaveBeenCalledWith('sb-refresh-token', 'response-token', cookieOptions);
		expect(setCookie.mock.calls[0]?.[2]).toBe(cookieOptions);
		expect(responseHeaders.get('Cache-Control')).toBe('private, no-store');
		expect(responseHeaders.get('Pragma')).toBe('no-cache');
	});
});
