import { createBrowserClient } from '@supabase/ssr';
import type { SupabaseClient } from '@supabase/supabase-js';
import { getSupabaseConfig, type SupabaseEnv } from './config';
import type { SupabaseDatabase } from './types';

export type SupabaseBrowserClient = SupabaseClient<SupabaseDatabase>;

let browserClient: SupabaseBrowserClient | undefined;

export const getSupabaseBrowserClient = (env?: SupabaseEnv): SupabaseBrowserClient => {
	if (typeof window === 'undefined') {
		throw new Error('Supabase browser client can only run in the browser.');
	}

	if (browserClient) {
		return browserClient;
	}

	const config = getSupabaseConfig(env);

	browserClient = createBrowserClient<SupabaseDatabase>(config.url, config.publishableKey, {
		isSingleton: true,
	});

	return browserClient;
};
