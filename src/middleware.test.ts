import type { AstroCookies } from 'astro';
import { afterEach, describe, expect, it, vi, type Mock } from 'vitest';
import { onRequest } from './middleware';
import type {
	createSupabaseServerClient,
	SupabaseServerClient,
	SupabaseServerClientContext,
} from './infrastructure/supabase/server';

type MiddlewareContext = Parameters<typeof onRequest>[0];
type MiddlewareNext = Parameters<typeof onRequest>[1];
type CreateSupabaseServerClient = typeof createSupabaseServerClient;

type TestUser = {
	readonly id: string;
	readonly email?: string | null;
};

type TestGetUserResponse = {
	readonly data: {
		readonly user: TestUser | null;
	};
	readonly error: Error | null;
};

type TestGetUser = () => Promise<TestGetUserResponse>;
type TestGetSession = () => Promise<unknown>;

interface MockSupabaseClient {
	readonly auth: {
		readonly getUser: Mock<TestGetUser>;
		readonly getSession: Mock<TestGetSession>;
	};
	readonly label: string;
}

const middlewareMocks = vi.hoisted(() => {
	const createServerClient = vi.fn();
	const defineMiddleware = vi.fn((handler: unknown) => handler);

	return {
		createServerClient,
		defineMiddleware,
	};
});

vi.mock('astro:middleware', () => ({
	defineMiddleware: middlewareMocks.defineMiddleware,
}));

vi.mock('./infrastructure/supabase/server', () => ({
	createSupabaseServerClient: middlewareMocks.createServerClient,
}));

const createServerClientMock =
	middlewareMocks.createServerClient as Mock<CreateSupabaseServerClient>;

const createContext = () => {
	const locals: Partial<App.Locals> = {};
	const cookies = {
		set: vi.fn<AstroCookies['set']>(),
	} as unknown as AstroCookies;
	const context = {
		request: new Request('https://fc-academic-hub.test/courses'),
		cookies,
		locals,
	} as unknown as MiddlewareContext;

	return {
		context,
		locals,
	};
};

const createNext = (response: Response = new Response('ok')) =>
	vi.fn<MiddlewareNext>(async () => response);

const runMiddleware = async (
	context: MiddlewareContext,
	next: MiddlewareNext,
): Promise<Response> => {
	const response = await onRequest(context, next);

	if (!(response instanceof Response)) {
		throw new Error('Expected middleware to return a response.');
	}

	return response;
};

const createClient = (getUserResponse: TestGetUserResponse, label = 'client') => {
	const getUser = vi.fn<TestGetUser>(async () => getUserResponse);
	const getSession = vi.fn<TestGetSession>(async () => null);
	const client = {
		auth: {
			getUser,
			getSession,
		},
		label,
	} satisfies MockSupabaseClient;

	return {
		client,
		supabase: client as unknown as SupabaseServerClient,
		getUser,
		getSession,
	};
};

const readSetCookieHeaders = (headers: Headers): readonly string[] => {
	const headersWithSetCookie = headers as Headers & {
		readonly getSetCookie?: () => string[];
	};

	return headersWithSetCookie.getSetCookie?.() ?? [];
};

describe('session middleware', () => {
	afterEach(() => {
		createServerClientMock.mockReset();
	});

	it('sets unconfigured auth state when Supabase environment is unavailable', async () => {
		const { context, locals } = createContext();
		const next = createNext();

		createServerClientMock.mockImplementation(() => {
			throw new Error('Missing Supabase URL. Set PUBLIC_SUPABASE_URL in .env.local.');
		});

		await runMiddleware(context, next);

		expect(locals.auth).toEqual({
			status: 'unconfigured',
			user: null,
			supabase: null,
		});
		expect(next).toHaveBeenCalledOnce();
	});

	it('sets anonymous auth state for a missing Supabase session', async () => {
		const { context, locals } = createContext();
		const next = createNext();
		const error = new Error('Auth session missing');
		error.name = 'AuthSessionMissingError';
		const { supabase } = createClient({
			data: {
				user: null,
			},
			error,
		});

		createServerClientMock.mockReturnValue(supabase);

		await runMiddleware(context, next);

		expect(locals.auth).toEqual({
			status: 'anonymous',
			user: null,
			supabase,
		});
		expect(next).toHaveBeenCalledOnce();
	});

	it('sets authenticated auth state with the safe user shape', async () => {
		const { context, locals } = createContext();
		const next = createNext();
		const { supabase } = createClient({
			data: {
				user: {
					id: 'user-123',
					email: 'student@example.edu',
				},
			},
			error: null,
		});

		createServerClientMock.mockReturnValue(supabase);

		await runMiddleware(context, next);

		expect(locals.auth).toEqual({
			status: 'authenticated',
			user: {
				id: 'user-123',
				email: 'student@example.edu',
			},
			supabase,
		});
	});

	it('sets error auth state when getUser fails unexpectedly', async () => {
		const { context, locals } = createContext();
		const next = createNext();
		const { supabase, getUser } = createClient({
			data: {
				user: null,
			},
			error: null,
		});

		getUser.mockRejectedValue(new Error('Supabase auth unavailable'));
		createServerClientMock.mockReturnValue(supabase);

		await runMiddleware(context, next);

		expect(locals.auth).toEqual({
			status: 'error',
			user: null,
			supabase,
		});
	});

	it('propagates Set-Cookie headers written by Supabase', async () => {
		const { context } = createContext();
		const next = createNext();
		const { supabase } = createClient({
			data: {
				user: null,
			},
			error: null,
		});

		createServerClientMock.mockImplementation((supabaseContext: SupabaseServerClientContext) => {
			supabaseContext.responseHeaders.append(
				'Set-Cookie',
				'sb-refresh-token=response-token; Path=/; HttpOnly; Secure',
			);

			return supabase;
		});

		const response = await runMiddleware(context, next);

		expect(readSetCookieHeaders(response.headers)).toContain(
			'sb-refresh-token=response-token; Path=/; HttpOnly; Secure',
		);
	});

	it('propagates Cache-Control and Pragma headers written by Supabase', async () => {
		const { context } = createContext();
		const next = createNext(
			new Response('ok', {
				headers: {
					'Cache-Control': 'public, max-age=60',
				},
			}),
		);
		const { supabase } = createClient({
			data: {
				user: null,
			},
			error: null,
		});

		createServerClientMock.mockImplementation((supabaseContext: SupabaseServerClientContext) => {
			supabaseContext.responseHeaders.set('Cache-Control', 'private, no-store');
			supabaseContext.responseHeaders.set('Pragma', 'no-cache');

			return supabase;
		});

		const response = await runMiddleware(context, next);

		expect(response.headers.get('Cache-Control')).toBe('private, no-store');
		expect(response.headers.get('Pragma')).toBe('no-cache');
	});

	it('does not call getSession for authorization', async () => {
		const { context } = createContext();
		const next = createNext();
		const { supabase, getUser, getSession } = createClient({
			data: {
				user: null,
			},
			error: null,
		});

		createServerClientMock.mockReturnValue(supabase);

		await runMiddleware(context, next);

		expect(getUser).toHaveBeenCalledOnce();
		expect(getSession).not.toHaveBeenCalled();
	});

	it('creates an isolated Supabase client context per request', async () => {
		const first = createContext();
		const second = createContext();
		const firstNext = createNext();
		const secondNext = createNext();
		const firstClient = createClient(
			{
				data: {
					user: null,
				},
				error: null,
			},
			'first-client',
		);
		const secondClient = createClient(
			{
				data: {
					user: null,
				},
				error: null,
			},
			'second-client',
		);

		createServerClientMock
			.mockReturnValueOnce(firstClient.supabase)
			.mockReturnValueOnce(secondClient.supabase);

		await runMiddleware(first.context, firstNext);
		await runMiddleware(second.context, secondNext);

		expect(createServerClientMock).toHaveBeenCalledTimes(2);
		expect(first.locals.auth?.supabase).toBe(firstClient.supabase);
		expect(second.locals.auth?.supabase).toBe(secondClient.supabase);
		expect(first.locals.auth?.supabase).not.toBe(second.locals.auth?.supabase);
		expect(createServerClientMock.mock.calls[0]?.[0].responseHeaders).not.toBe(
			createServerClientMock.mock.calls[1]?.[0].responseHeaders,
		);
	});
});
