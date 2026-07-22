import { defineMiddleware } from 'astro:middleware';
import {
	createSupabaseServerClient,
	type SupabaseServerClient,
} from './infrastructure/supabase/server';

type SupabaseGetUserResponse = Awaited<ReturnType<SupabaseServerClient['auth']['getUser']>>;
type SupabaseUser = NonNullable<SupabaseGetUserResponse['data']['user']>;
type HeadersWithSetCookie = Headers & {
	readonly getSetCookie: () => string[];
};

const isMissingSessionError = (error: unknown): boolean => {
	if (!(error instanceof Error)) {
		return false;
	}

	const message = error.message.toLowerCase();

	return error.name === 'AuthSessionMissingError' || message.includes('auth session missing');
};

const toLocalUser = (user: SupabaseUser): NonNullable<App.Locals['auth']['user']> => ({
	id: user.id,
	email: user.email ?? null,
});

const resolveAuthContext = async (supabase: SupabaseServerClient): Promise<App.Locals['auth']> => {
	try {
		const { data, error } = await supabase.auth.getUser();

		if (error && !isMissingSessionError(error)) {
			return {
				status: 'error',
				user: null,
				supabase,
			};
		}

		if (data.user) {
			return {
				status: 'authenticated',
				user: toLocalUser(data.user),
				supabase,
			};
		}

		return {
			status: 'anonymous',
			user: null,
			supabase,
		};
	} catch {
		return {
			status: 'error',
			user: null,
			supabase,
		};
	}
};

const applyResponseHeaders = (response: Response, responseHeaders: Headers): Response => {
	const headers = new Headers(response.headers);
	const headersWithSetCookie = responseHeaders as HeadersWithSetCookie;
	const setCookieHeaders = headersWithSetCookie.getSetCookie();

	for (const [name, value] of responseHeaders) {
		if (name.toLowerCase() === 'set-cookie') {
			continue;
		}

		headers.set(name, value);
	}

	for (const setCookieHeader of setCookieHeaders) {
		headers.append('Set-Cookie', setCookieHeader);
	}

	return new Response(response.body, {
		status: response.status,
		statusText: response.statusText,
		headers,
	});
};

export const onRequest = defineMiddleware(async (context, next) => {
	if (context.isPrerendered) {
		context.locals.auth = {
			status: 'anonymous',
			user: null,
			supabase: null,
		};

		return next();
	}

	const responseHeaders = new Headers();
	let supabase: SupabaseServerClient | null = null;

	try {
		supabase = createSupabaseServerClient({
			request: context.request,
			cookies: context.cookies,
			responseHeaders,
		});
	} catch {
		context.locals.auth = {
			status: 'unconfigured',
			user: null,
			supabase: null,
		};
	}

	if (supabase) {
		context.locals.auth = await resolveAuthContext(supabase);
	}

	const response = await next();

	return applyResponseHeaders(response, responseHeaders);
});
