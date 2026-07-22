import type { APIRoute } from 'astro';
import { resolveSafePostAuthRedirect } from '../../domain/auth/redirects';
import {
	createMethodNotAllowedResponse,
	createRedirectResponse,
	createSignInRedirectResponse,
} from '../../infrastructure/auth/http';
import type { SupabaseServerClient } from '../../infrastructure/supabase/server';

export const prerender = false;

const clearLocalSession = async (supabase: SupabaseServerClient): Promise<void> => {
	try {
		await supabase.auth.signOut({ scope: 'local' });
	} catch {
		// Best effort: do not expose cleanup failures in the callback response.
	}
};

export const GET: APIRoute = async ({ locals, request, url }) => {
	const next = resolveSafePostAuthRedirect(url.searchParams.get('next'));

	if (url.searchParams.has('error') || url.searchParams.has('error_description')) {
		return createSignInRedirectResponse(request, 'access_denied', next);
	}

	const code = url.searchParams.get('code')?.trim();

	if (!code) {
		return createSignInRedirectResponse(request, 'oauth_callback', next);
	}

	const supabase = locals.auth.supabase;

	if (!supabase) {
		return createSignInRedirectResponse(request, 'unconfigured', next);
	}

	let sessionEstablished = false;

	try {
		const { error: exchangeError } = await supabase.auth.exchangeCodeForSession(code);

		if (exchangeError) {
			return createSignInRedirectResponse(request, 'access_denied', next);
		}

		sessionEstablished = true;
		const { data, error: userError } = await supabase.auth.getUser();

		if (userError || !data.user) {
			await clearLocalSession(supabase);
			return createSignInRedirectResponse(request, 'access_denied', next);
		}

		return createRedirectResponse(next);
	} catch {
		if (sessionEstablished) {
			await clearLocalSession(supabase);
		}

		return createSignInRedirectResponse(request, 'access_denied', next);
	}
};

export const ALL: APIRoute = () => createMethodNotAllowedResponse('GET');
