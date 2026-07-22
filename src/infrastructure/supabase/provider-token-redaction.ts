const providerTokenKeys = new Set(['provider_token', 'provider_refresh_token']);

type RedactionResult = {
	readonly changed: boolean;
	readonly value: unknown;
};

const redactProviderTokenFields = (value: unknown): RedactionResult => {
	if (Array.isArray(value)) {
		let changed = false;
		const redactedItems = value.map((item) => {
			const result = redactProviderTokenFields(item);
			changed ||= result.changed;
			return result.value;
		});

		return {
			changed,
			value: changed ? redactedItems : value,
		};
	}

	if (typeof value !== 'object' || value === null) {
		return {
			changed: false,
			value,
		};
	}

	let changed = false;
	const redactedObject: Record<string, unknown> = {};

	for (const [key, nestedValue] of Object.entries(value)) {
		if (providerTokenKeys.has(key)) {
			changed = true;
			continue;
		}

		const result = redactProviderTokenFields(nestedValue);
		changed ||= result.changed;
		redactedObject[key] = result.value;
	}

	return {
		changed,
		value: changed ? redactedObject : value,
	};
};

const resolveRequestUrl = (input: RequestInfo | URL, baseUrl: URL): URL | null => {
	try {
		if (input instanceof Request) {
			return new URL(input.url);
		}

		return new URL(input.toString(), baseUrl);
	} catch {
		return null;
	}
};

const createAuthTokenEndpoint = (supabaseUrl: string): URL => {
	const baseUrl = new URL(supabaseUrl);
	const basePath = baseUrl.pathname.replace(/\/+$/u, '');

	return new URL(`${basePath}/auth/v1/token`, baseUrl.origin);
};

export const createProviderTokenRedactingFetch = (
	supabaseUrl: string,
	baseFetch: typeof fetch = globalThis.fetch,
): typeof fetch => {
	const tokenEndpoint = createAuthTokenEndpoint(supabaseUrl);

	return async (input, init) => {
		const response = await baseFetch(input, init);
		const requestUrl = resolveRequestUrl(input, tokenEndpoint);

		if (
			!requestUrl ||
			requestUrl.origin !== tokenEndpoint.origin ||
			requestUrl.pathname !== tokenEndpoint.pathname ||
			!response.ok
		) {
			return response;
		}

		let payload: unknown;

		try {
			payload = await response.clone().json();
		} catch {
			return response;
		}

		const redacted = redactProviderTokenFields(payload);

		if (!redacted.changed) {
			return response;
		}

		const headers = new Headers(response.headers);
		headers.delete('content-encoding');
		headers.delete('content-length');
		headers.delete('transfer-encoding');

		return new Response(JSON.stringify(redacted.value), {
			status: response.status,
			statusText: response.statusText,
			headers,
		});
	};
};
