import type { APIRoute } from 'astro';
import { resolveSafePostAuthRedirect } from '../../domain/auth/redirects';
import {
	createForbiddenResponse,
	createMethodNotAllowedResponse,
	createRedirectResponse,
	createSignInRedirectResponse,
	getRequestOrigin,
	hasValidSameOriginHeader,
	readFormString,
} from '../../infrastructure/auth/http';

export const prerender = false;

export const POST: APIRoute = async ({ locals, request }) => {
	if (!hasValidSameOriginHeader(request)) {
		return createForbiddenResponse();
	}

	const next = resolveSafePostAuthRedirect(await readFormString(request, 'next'));

	if (locals.auth.status === 'authenticated') {
		return createRedirectResponse(next);
	}

	const supabase = locals.auth.supabase;

	if (!supabase) {
		return createSignInRedirectResponse(request, 'unconfigured', next);
	}

	const callbackUrl = new URL('/auth/callback', getRequestOrigin(request));
	callbackUrl.searchParams.set('next', next);

	try {
		const { data, error } = await supabase.auth.signInWithOAuth({
			provider: 'google',
			options: {
				redirectTo: callbackUrl.toString(),
			},
		});

		if (error || !data.url) {
			return createSignInRedirectResponse(request, 'oauth_unavailable', next);
		}

		return createRedirectResponse(data.url);
	} catch {
		return createSignInRedirectResponse(request, 'oauth_unavailable', next);
	}
};

export const ALL: APIRoute = () => createMethodNotAllowedResponse('POST');
