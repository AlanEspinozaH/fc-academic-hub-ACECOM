import { createServerClient, parseCookieHeader, type CookieOptions } from '@supabase/ssr';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { AstroCookies, AstroCookieSetOptions } from 'astro';
import { getSupabaseConfig, type SupabaseEnv } from './config';
import type { SupabaseDatabase } from './types';

export type SupabaseServerClient = SupabaseClient<SupabaseDatabase>;

export interface SupabaseServerClientContext {
	readonly request: Request;
	readonly cookies: AstroCookies;
	readonly responseHeaders: Headers;
}

const toAstroCookieSetOptions = (options: CookieOptions): AstroCookieSetOptions =>
	options as AstroCookieSetOptions;

export const createSupabaseServerClient = (
	context: SupabaseServerClientContext,
	env?: SupabaseEnv,
): SupabaseServerClient => {
	const config = getSupabaseConfig(env);

	return createServerClient<SupabaseDatabase>(config.url, config.publishableKey, {
		cookies: {
			getAll() {
				return parseCookieHeader(context.request.headers.get('Cookie') ?? '');
			},
			setAll(cookiesToSet, headers) {
				for (const { name, value, options } of cookiesToSet) {
					context.cookies.set(name, value, toAstroCookieSetOptions(options));
				}

				for (const [name, value] of Object.entries(headers)) {
					context.responseHeaders.set(name, value);
				}
			},
		},
	});
};
