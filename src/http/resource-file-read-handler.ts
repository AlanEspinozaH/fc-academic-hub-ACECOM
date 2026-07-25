import { ResourceFileReadError, type ResourceFileReader } from '../application/resource-file-read';
import { createMethodNotAllowedResponse } from '../infrastructure/auth/http';
import type { SupabaseServerClient } from '../infrastructure/supabase/server';
import { buildContentDisposition, type ContentDispositionMode } from './content-disposition';

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export interface ResourceFileReadHttpDependencies {
	createReader(supabase: SupabaseServerClient): ResourceFileReader;
}

export interface ResourceFileReadHttpInput {
	readonly request: Request;
	readonly resourceId: string | undefined;
	readonly fileId: string | undefined;
	readonly disposition: ContentDispositionMode;
	readonly auth: App.Locals['auth'];
}

const normalizeUuid = (value: string | undefined): string | null => {
	if (!value) {
		return null;
	}

	const normalized = value.trim().toLowerCase();

	return UUID_PATTERN.test(normalized) ? normalized : null;
};

const privateNoStoreHeaders = {
	'cache-control': 'private, no-store',
} as const;

const notFoundResponse = (): Response =>
	new Response(null, {
		status: 404,
		headers: privateNoStoreHeaders,
	});

const unavailableResponse = (): Response =>
	new Response(null, {
		status: 503,
		headers: privateNoStoreHeaders,
	});

const responseContentType = (canonicalContentType: string): string =>
	canonicalContentType === 'text/plain' ? 'text/plain; charset=utf-8' : canonicalContentType;

export const handleResourceFileReadRequest = async (
	input: ResourceFileReadHttpInput,
	dependencies: ResourceFileReadHttpDependencies,
): Promise<Response> => {
	if (input.request.method !== 'GET') {
		return createMethodNotAllowedResponse('GET');
	}

	const resourceId = normalizeUuid(input.resourceId);
	const fileId = normalizeUuid(input.fileId);

	if (resourceId === null || fileId === null) {
		return notFoundResponse();
	}

	if (
		(input.auth.status !== 'anonymous' && input.auth.status !== 'authenticated') ||
		input.auth.supabase === null
	) {
		return unavailableResponse();
	}

	let reader: ResourceFileReader;

	try {
		reader = dependencies.createReader(input.auth.supabase);
	} catch {
		return unavailableResponse();
	}

	try {
		const result = await reader.read({ resourceId, fileId });

		return new Response(result.bytes, {
			status: 200,
			headers: {
				'cache-control': 'private, no-store',
				'content-disposition': buildContentDisposition(input.disposition, result.displayFilename),
				'content-length': result.bytes.byteLength.toString(),
				'content-type': responseContentType(result.contentType),
				'x-content-type-options': 'nosniff',
			},
		});
	} catch (error) {
		if (error instanceof ResourceFileReadError && error.code === 'NOT_FOUND') {
			return notFoundResponse();
		}

		return unavailableResponse();
	}
};
