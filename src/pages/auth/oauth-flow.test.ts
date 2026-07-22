import type { APIRoute } from 'astro';
import { describe, expect, it, vi, type Mock } from 'vitest';
import type { SupabaseServerClient } from '../../infrastructure/supabase/server';
import { GET as callbackGet } from './callback';
import { POST as googlePost } from './google';
import { ALL as callbackAll } from './callback';
import { ALL as googleAll } from './google';
import { ALL as signOutAll, POST as signOutPost } from './sign-out';

type RouteContext = Parameters<APIRoute>[0];

type OAuthCredentials = {
	readonly provider: 'google';
	readonly options: {
		readonly redirectTo: string;
	};
};

type OAuthResponse = {
	readonly data: {
		readonly provider: 'google';
		readonly url: string | null;
	};
	readonly error: Error | null;
};

type ExchangeCodeForSessionResponse = {
	readonly data: {
		readonly session: { readonly id: string } | null;
	};
	readonly error: Error | null;
};

type GetUserResponse = {
	readonly data: {
		readonly user: { readonly id: string; readonly email?: string | null } | null;
	};
	readonly error: Error | null;
};

type SignOutResponse = {
	readonly error: Error | null;
};

type SignInWithOAuth = (credentials: OAuthCredentials) => Promise<OAuthResponse>;
type ExchangeCodeForSession = (code: string) => Promise<ExchangeCodeForSessionResponse>;
type GetUser = () => Promise<GetUserResponse>;
type GetSession = () => Promise<unknown>;
type SignOut = (options: { readonly scope: 'local' }) => Promise<SignOutResponse>;

interface MockSupabaseClient {
	readonly auth: {
		readonly exchangeCodeForSession: Mock<ExchangeCodeForSession>;
		readonly getSession: Mock<GetSession>;
		readonly getUser: Mock<GetUser>;
		readonly signInWithOAuth: Mock<SignInWithOAuth>;
		readonly signOut: Mock<SignOut>;
	};
}

const createSupabase = () => {
	const client = {
		auth: {
			exchangeCodeForSession: vi.fn<ExchangeCodeForSession>(async () => ({
				data: {
					session: {
						id: 'session-1',
					},
				},
				error: null,
			})),
			getSession: vi.fn<GetSession>(async () => null),
			getUser: vi.fn<GetUser>(async () => ({
				data: {
					user: {
						id: 'user-1',
						email: 'student@example.edu',
					},
				},
				error: null,
			})),
			signInWithOAuth: vi.fn<SignInWithOAuth>(async () => ({
				data: {
					provider: 'google',
					url: 'https://supabase.example/auth/v1/authorize?provider=google',
				},
				error: null,
			})),
			signOut: vi.fn<SignOut>(async () => ({
				error: null,
			})),
		},
	} satisfies MockSupabaseClient;

	return {
		...client.auth,
		supabase: client as unknown as SupabaseServerClient,
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
					email: 'student@example.edu',
				}
			: null,
	supabase,
});

const createRouteContext = (
	request: Request,
	auth: App.Locals['auth'] = createAuth(null),
): RouteContext =>
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
	auth: App.Locals['auth'] = createAuth(null),
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

const parseLocation = (response: Response): URL => {
	const location = response.headers.get('Location');

	if (!location) {
		throw new Error('Expected response Location header.');
	}

	return new URL(location, 'https://fc-academic-hub.test');
};

describe('Google OAuth start endpoint', () => {
	it('starts OAuth with the Google provider and an application callback redirect', async () => {
		const { signInWithOAuth, supabase } = createSupabase();
		const request = createPostRequest('/auth/google', {
			next: '/resources?course=cc#files',
		});

		const response = await callRoute(googlePost, request, createAuth(supabase));

		expect(response.status).toBe(303);
		expect(response.headers.get('Location')).toBe(
			'https://supabase.example/auth/v1/authorize?provider=google',
		);
		expect(signInWithOAuth).toHaveBeenCalledWith({
			provider: 'google',
			options: {
				redirectTo: expect.any(String) as string,
			},
		});

		const credentials = signInWithOAuth.mock.calls[0]?.[0];
		const redirectTo = new URL(credentials?.options.redirectTo ?? '');

		expect(redirectTo.origin).toBe('https://fc-academic-hub.test');
		expect(redirectTo.pathname).toBe('/auth/callback');
		expect(redirectTo.searchParams.get('next')).toBe('/resources?course=cc#files');
		expect(Object.keys(credentials?.options ?? {})).toEqual(['redirectTo']);
	});

	it('rejects absolute next paths before building redirectTo', async () => {
		const { signInWithOAuth, supabase } = createSupabase();
		const request = createPostRequest('/auth/google', {
			next: 'https://evil.example/callback',
		});

		await callRoute(googlePost, request, createAuth(supabase));

		const credentials = signInWithOAuth.mock.calls[0]?.[0];
		const redirectTo = new URL(credentials?.options.redirectTo ?? '');

		expect(redirectTo.searchParams.get('next')).toBe('/');
	});

	it('rejects protocol-relative next paths before building redirectTo', async () => {
		const { signInWithOAuth, supabase } = createSupabase();
		const request = createPostRequest('/auth/google', {
			next: '//evil.example/callback',
		});

		await callRoute(googlePost, request, createAuth(supabase));

		const credentials = signInWithOAuth.mock.calls[0]?.[0];
		const redirectTo = new URL(credentials?.options.redirectTo ?? '');

		expect(redirectTo.searchParams.get('next')).toBe('/');
	});

	it('returns a controlled sign-in error when OAuth cannot start', async () => {
		const { signInWithOAuth, supabase } = createSupabase();
		const internalDetail = 'raw upstream authorization details';
		const request = createPostRequest('/auth/google', {
			next: '/resources',
		});

		signInWithOAuth.mockResolvedValue({
			data: {
				provider: 'google',
				url: null,
			},
			error: new Error(internalDetail),
		});

		const response = await callRoute(googlePost, request, createAuth(supabase));
		const location = parseLocation(response);

		expect(location.pathname).toBe('/auth/sign-in');
		expect(location.searchParams.get('error')).toBe('oauth_unavailable');
		expect(location.searchParams.get('next')).toBe('/resources');
		expect(response.headers.get('Location')).not.toContain(internalDetail);
	});

	it('rejects an unconfigured environment with a controlled sign-in redirect', async () => {
		const request = createPostRequest('/auth/google', {
			next: '/courses',
		});

		const response = await callRoute(googlePost, request, createAuth(null));
		const location = parseLocation(response);

		expect(response.status).toBe(303);
		expect(location.pathname).toBe('/auth/sign-in');
		expect(location.searchParams.get('error')).toBe('unconfigured');
		expect(location.searchParams.get('next')).toBe('/courses');
	});

	it('rejects non-POST OAuth starts', async () => {
		const request = new Request('https://fc-academic-hub.test/auth/google', {
			method: 'GET',
		});

		const response = await callRoute(googleAll, request);

		expect(response.status).toBe(405);
		expect(response.headers.get('Allow')).toBe('POST');
	});
});

describe('OAuth callback endpoint', () => {
	it('redirects to sign-in when the callback has no code', async () => {
		const { exchangeCodeForSession, supabase } = createSupabase();
		const request = new Request('https://fc-academic-hub.test/auth/callback?next=/courses');

		const response = await callRoute(callbackGet, request, createAuth(supabase));
		const location = parseLocation(response);

		expect(location.pathname).toBe('/auth/sign-in');
		expect(location.searchParams.get('error')).toBe('oauth_callback');
		expect(exchangeCodeForSession).not.toHaveBeenCalled();
	});

	it('handles provider errors without reflecting untrusted values', async () => {
		const { exchangeCodeForSession, supabase } = createSupabase();
		const untrustedDescription = 'do not show this upstream detail';
		const request = new Request(
			'https://fc-academic-hub.test/auth/callback?error=server_error&error_description=' +
				encodeURIComponent(untrustedDescription) +
				'&next=/resources',
		);

		const response = await callRoute(callbackGet, request, createAuth(supabase));
		const location = parseLocation(response);

		expect(location.pathname).toBe('/auth/sign-in');
		expect(location.searchParams.get('error')).toBe('access_denied');
		expect(response.headers.get('Location')).not.toContain(untrustedDescription);
		expect(exchangeCodeForSession).not.toHaveBeenCalled();
	});

	it('exchanges a code, validates the user and redirects to next', async () => {
		const { exchangeCodeForSession, getSession, getUser, supabase } = createSupabase();
		const request = new Request(
			'https://fc-academic-hub.test/auth/callback?code=auth-code&next=%2Fresources%3Fcourse%3Dcc%23files',
		);

		const response = await callRoute(callbackGet, request, createAuth(supabase));

		expect(response.status).toBe(303);
		expect(response.headers.get('Location')).toBe('/resources?course=cc#files');
		expect(response.headers.get('Location')).not.toContain('code=');
		expect(response.headers.has('Set-Cookie')).toBe(false);
		expect(exchangeCodeForSession).toHaveBeenCalledWith('auth-code');
		expect(getUser).toHaveBeenCalledOnce();
		expect(getSession).not.toHaveBeenCalled();
		expect(exchangeCodeForSession.mock.invocationCallOrder[0]).toBeLessThan(
			getUser.mock.invocationCallOrder[0] ?? 0,
		);
	});

	it('redirects with a generic institutional access error when exchange fails', async () => {
		const { exchangeCodeForSession, getUser, supabase } = createSupabase();
		const internalDetail = 'institutional domain trigger SQL detail';
		const request = new Request(
			'https://fc-academic-hub.test/auth/callback?code=auth-code&next=/resources',
		);

		exchangeCodeForSession.mockResolvedValue({
			data: {
				session: null,
			},
			error: new Error(internalDetail),
		});

		const response = await callRoute(callbackGet, request, createAuth(supabase));
		const location = parseLocation(response);

		expect(location.pathname).toBe('/auth/sign-in');
		expect(location.searchParams.get('error')).toBe('access_denied');
		expect(response.headers.get('Location')).not.toContain(internalDetail);
		expect(getUser).not.toHaveBeenCalled();
	});

	it('redirects with a generic error when user validation fails after exchange', async () => {
		const { getUser, supabase } = createSupabase();
		const request = new Request('https://fc-academic-hub.test/auth/callback?code=auth-code');

		getUser.mockResolvedValue({
			data: {
				user: null,
			},
			error: new Error('raw user validation detail'),
		});

		const response = await callRoute(callbackGet, request, createAuth(supabase));
		const location = parseLocation(response);

		expect(location.pathname).toBe('/auth/sign-in');
		expect(location.searchParams.get('error')).toBe('access_denied');
	});

	it('rejects non-GET callbacks', async () => {
		const request = new Request('https://fc-academic-hub.test/auth/callback', {
			method: 'POST',
		});

		const response = await callRoute(callbackAll, request);

		expect(response.status).toBe(405);
		expect(response.headers.get('Allow')).toBe('GET');
	});
});

describe('sign-out endpoint', () => {
	it('rejects non-POST logout requests', async () => {
		const request = new Request('https://fc-academic-hub.test/auth/sign-out', {
			method: 'GET',
		});

		const response = await callRoute(signOutAll, request);

		expect(response.status).toBe(405);
		expect(response.headers.get('Allow')).toBe('POST');
	});

	it('signs out locally and redirects to a safe internal route', async () => {
		const { signOut, supabase } = createSupabase();
		const request = createPostRequest(
			'/auth/sign-out',
			{
				next: '/resources',
				session: 'ignored',
				token: 'ignored',
				user_id: 'ignored',
			},
			{
				Origin: 'https://fc-academic-hub.test',
			},
		);

		const response = await callRoute(signOutPost, request, createAuth(supabase, 'authenticated'));

		expect(response.status).toBe(303);
		expect(response.headers.get('Location')).toBe('/resources');
		expect(response.headers.has('Set-Cookie')).toBe(false);
		expect(signOut).toHaveBeenCalledWith({
			scope: 'local',
		});
	});

	it('rejects logout requests from an external origin', async () => {
		const { signOut, supabase } = createSupabase();
		const request = createPostRequest(
			'/auth/sign-out',
			{
				next: '/resources',
			},
			{
				Origin: 'https://evil.example',
			},
		);

		const response = await callRoute(signOutPost, request, createAuth(supabase, 'authenticated'));

		expect(response.status).toBe(403);
		expect(signOut).not.toHaveBeenCalled();
	});

	it('treats a missing session as an idempotent logout result', async () => {
		const { signOut, supabase } = createSupabase();
		const request = createPostRequest('/auth/sign-out', {
			next: '/courses',
		});

		signOut.mockResolvedValue({
			error: new Error('session already absent'),
		});

		const response = await callRoute(signOutPost, request, createAuth(supabase));

		expect(response.status).toBe(303);
		expect(response.headers.get('Location')).toBe('/courses');
		expect(signOut).toHaveBeenCalledWith({
			scope: 'local',
		});
	});
});
