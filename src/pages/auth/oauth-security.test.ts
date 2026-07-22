import type { APIRoute } from 'astro';
import { describe, expect, it, vi } from 'vitest';
import type { SupabaseServerClient } from '../../infrastructure/supabase/server';
import { GET as callbackGet } from './callback';
import { POST as googlePost } from './google';
import { POST as signOutPost } from './sign-out';

type RouteContext = Parameters<APIRoute>[0];

type OAuthCredentials = {
	readonly provider: 'google';
	readonly options: {
		readonly redirectTo: string;
	};
};

type GetUserResult = {
	readonly data: {
		readonly user: { readonly id: string; readonly email: string | null } | null;
	};
	readonly error: Error | null;
};

const createSupabase = () => {
	const exchangeCodeForSession = vi.fn(async () => ({
		data: {
			session: {
				access_token: 'supabase-access-token',
			},
		},
		error: null,
	}));
	const getUser = vi.fn(async (): Promise<GetUserResult> => ({
		data: {
			user: {
				id: 'user-1',
				email: 'student@uni.pe',
			},
		},
		error: null,
	}));
	const signInWithOAuth = vi.fn(async (credentials: OAuthCredentials) => ({
		data: {
			provider: credentials.provider,
			url: `https://fc-academic-hub.supabase.co/auth/v1/authorize?provider=${credentials.provider}`,
		},
		error: null,
	}));
	const signOut = vi.fn(async () => ({ error: null }));

	const supabase = {
		auth: {
			exchangeCodeForSession,
			getUser,
			signInWithOAuth,
			signOut,
		},
	} as unknown as SupabaseServerClient;

	return {
		exchangeCodeForSession,
		getUser,
		signInWithOAuth,
		signOut,
		supabase,
	};
};

const createAuth = (
	supabase: SupabaseServerClient | null,
	status: App.Locals['auth']['status'] = supabase ? 'anonymous' : 'unconfigured',
): App.Locals['auth'] => ({
	status,
	user:
		status === 'authenticated'
			? {
					id: 'user-1',
					email: 'student@uni.pe',
				}
			: null,
	supabase,
});

const createRouteContext = (request: Request, auth: App.Locals['auth']): RouteContext =>
	({
		locals: {
			auth,
		},
		request,
		url: new URL(request.url),
	}) as unknown as RouteContext;

const callRoute = async (
	route: APIRoute,
	request: Request,
	auth: App.Locals['auth'],
): Promise<Response> => {
	const response = await route(createRouteContext(request, auth));

	if (!(response instanceof Response)) {
		throw new Error('Expected route to return a Response.');
	}

	return response;
};

const createPostRequest = (
	pathname: string,
	body: Record<string, string> = {},
	headers: HeadersInit = {},
): Request =>
	new Request('https://fc-academic-hub.test' + pathname, {
		body: new URLSearchParams(body),
		headers,
		method: 'POST',
	});

describe('OAuth flow security hardening', () => {
	it('rejects cross-origin OAuth start requests before contacting Supabase', async () => {
		const { signInWithOAuth, supabase } = createSupabase();
		const request = createPostRequest(
			'/auth/google',
			{ next: '/resources' },
			{ Origin: 'https://evil.example' },
		);

		const response = await callRoute(googlePost, request, createAuth(supabase));

		expect(response.status).toBe(403);
		expect(signInWithOAuth).not.toHaveBeenCalled();
	});

	it('does not restart OAuth for an already authenticated user', async () => {
		const { signInWithOAuth, supabase } = createSupabase();
		const request = createPostRequest(
			'/auth/google',
			{ next: '/resources' },
			{ Origin: 'https://fc-academic-hub.test' },
		);

		const response = await callRoute(googlePost, request, createAuth(supabase, 'authenticated'));

		expect(response.status).toBe(303);
		expect(response.headers.get('Location')).toBe('/resources');
		expect(signInWithOAuth).not.toHaveBeenCalled();
	});

	it('rejects auth routes as post-auth destinations before building redirectTo', async () => {
		const { signInWithOAuth, supabase } = createSupabase();
		const request = createPostRequest(
			'/auth/google',
			{ next: '/auth/sign-in' },
			{ Origin: 'https://fc-academic-hub.test' },
		);

		await callRoute(googlePost, request, createAuth(supabase));

		const credentials = signInWithOAuth.mock.calls[0]?.[0];
		const redirectTo = new URL(credentials?.options.redirectTo ?? '');

		expect(redirectTo.pathname).toBe('/auth/callback');
		expect(redirectTo.searchParams.get('next')).toBe('/');
	});

	it('clears the newly established local session when post-exchange user validation fails', async () => {
		const { getUser, signOut, supabase } = createSupabase();
		getUser.mockResolvedValue({
			data: {
				user: null,
			},
			error: new Error('internal validation detail'),
		});
		const request = new Request(
			'https://fc-academic-hub.test/auth/callback?code=auth-code&next=/resources',
		);

		const response = await callRoute(callbackGet, request, createAuth(supabase));

		expect(response.status).toBe(303);
		expect(response.headers.get('Location')).toContain('/auth/sign-in?');
		expect(response.headers.get('Location')).not.toContain('internal validation detail');
		expect(signOut).toHaveBeenCalledWith({ scope: 'local' });
	});

	it('does not redirect logout back into the authentication flow', async () => {
		const { supabase } = createSupabase();
		const request = createPostRequest(
			'/auth/sign-out',
			{ next: '/auth/sign-in' },
			{ Origin: 'https://fc-academic-hub.test' },
		);

		const response = await callRoute(signOutPost, request, createAuth(supabase, 'authenticated'));

		expect(response.status).toBe(303);
		expect(response.headers.get('Location')).toBe('/');
	});
});
