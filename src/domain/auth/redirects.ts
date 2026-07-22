const internalRedirectOrigin = 'https://fc-academic-hub.internal';
const schemePattern = /^[a-z][a-z0-9+.-]*:/iu;
const authPathPattern = /^\/auth(?:\/|$)/iu;

const hasControlCharacters = (value: string): boolean => {
	for (let index = 0; index < value.length; index += 1) {
		const characterCode = value.charCodeAt(index);

		if (characterCode <= 31 || characterCode === 127) {
			return true;
		}
	}

	return false;
};

const parseInternalRedirect = (value: string): string | null => {
	const candidate = value.trim();

	if (
		candidate.length === 0 ||
		candidate.includes('\\') ||
		candidate.startsWith('//') ||
		schemePattern.test(candidate) ||
		hasControlCharacters(candidate)
	) {
		return null;
	}

	if (!candidate.startsWith('/') && !candidate.startsWith('?') && !candidate.startsWith('#')) {
		return null;
	}

	try {
		const decodedCandidate = decodeURI(candidate);

		if (decodedCandidate.includes('\\') || hasControlCharacters(decodedCandidate)) {
			return null;
		}

		const parsedUrl = new URL(candidate, internalRedirectOrigin);

		if (parsedUrl.origin !== internalRedirectOrigin || !parsedUrl.pathname.startsWith('/')) {
			return null;
		}

		return parsedUrl.pathname + parsedUrl.search + parsedUrl.hash;
	} catch {
		return null;
	}
};

const isAuthenticationPath = (value: string): boolean => {
	try {
		const pathname = new URL(value, internalRedirectOrigin).pathname;
		const decodedPathname = decodeURIComponent(pathname);

		return authPathPattern.test(decodedPathname);
	} catch {
		return true;
	}
};

export const resolveSafeInternalRedirect = (
	value: string | null | undefined,
	fallback = '/',
): string => {
	const safeFallback = parseInternalRedirect(fallback) ?? '/';

	if (typeof value !== 'string') {
		return safeFallback;
	}

	return parseInternalRedirect(value) ?? safeFallback;
};

export const resolveSafePostAuthRedirect = (
	value: string | null | undefined,
	fallback = '/',
): string => {
	const internalFallback = resolveSafeInternalRedirect(fallback);
	const safeFallback = isAuthenticationPath(internalFallback) ? '/' : internalFallback;
	const candidate = resolveSafeInternalRedirect(value, safeFallback);

	return isAuthenticationPath(candidate) ? safeFallback : candidate;
};
