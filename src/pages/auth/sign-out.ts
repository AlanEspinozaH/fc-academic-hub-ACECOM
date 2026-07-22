import type { APIRoute } from 'astro';
import { resolveSafePostAuthRedirect } from '../../domain/auth/redirects';
import {
	createForbiddenResponse,
	createMethodNotAllowedResponse,
	createRedirectResponse,
	hasValidSameOriginHeader,
	readFormString,
} from '../../infrastructure/auth/http';

export const prerender = false;

export const POST: APIRoute = async ({ locals, request }) => {
	if (!hasValidSameOriginHeader(request)) {
		return createForbiddenResponse();
	}

	const next = resolveSafePostAuthRedirect(await readFormString(request, 'next'));
	const supabase = locals.auth.supabase;

	if (supabase) {
		try {
			await supabase.auth.signOut({ scope: 'local' });
		} catch {
			// Logout is idempotent from the application perspective.
		}
	}

	return createRedirectResponse(next);
};

export const ALL: APIRoute = () => createMethodNotAllowedResponse('POST');
