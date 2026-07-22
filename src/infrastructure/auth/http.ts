import { resolveSafePostAuthRedirect } from '../../domain/auth/redirects';
import type { SignInErrorCode } from '../../domain/auth/sign-in-page';

const noStoreHeaders = {
	'cache-control': 'no-store',
} as const;

export const createRedirectResponse = (location: string, status = 303): Response =>
	new Response(null, {
		status,
		headers: {
			...noStoreHeaders,
			Location: location,
		},
	});

export const createMethodNotAllowedResponse = (allowedMethod: 'GET' | 'POST'): Response =>
	new Response(null, {
		status: 405,
		headers: {
			...noStoreHeaders,
			Allow: allowedMethod,
		},
	});

export const createForbiddenResponse = (): Response =>
	new Response(null, {
		status: 403,
		headers: noStoreHeaders,
	});

export const getRequestOrigin = (request: Request): string => new URL(request.url).origin;

export const createSignInRedirectResponse = (
	request: Request,
	errorCode: SignInErrorCode,
	next: string,
): Response => {
	const safeNext = resolveSafePostAuthRedirect(next);
	const signInUrl = new URL('/auth/sign-in', getRequestOrigin(request));

	signInUrl.searchParams.set('error', errorCode);
	signInUrl.searchParams.set('next', safeNext);

	return createRedirectResponse(signInUrl.pathname + signInUrl.search);
};

export const readFormString = async (
	request: Request,
	fieldName: string,
): Promise<string | null> => {
	try {
		const formData = await request.formData();
		const value = formData.get(fieldName);

		return typeof value === 'string' ? value : null;
	} catch {
		return null;
	}
};

export const hasValidSameOriginHeader = (request: Request): boolean => {
	const originHeader = request.headers.get('Origin');

	if (!originHeader) {
		return true;
	}

	try {
		const originUrl = new URL(originHeader);

		return (
			originUrl.origin === getRequestOrigin(request) &&
			originUrl.pathname === '/' &&
			originUrl.search === '' &&
			originUrl.hash === ''
		);
	} catch {
		return false;
	}
};
