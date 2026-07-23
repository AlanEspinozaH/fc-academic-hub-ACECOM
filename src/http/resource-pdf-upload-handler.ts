import {
	ResourcePdfUploadError,
	type ResourcePdfUploadOrchestrator,
} from '../application/resource-pdf-upload';
import {
	RESOURCE_PDF_MAX_BYTES,
	ResourcePdfValidationError,
} from '../domain/resource-file-validation';
import { hasValidSameOriginHeader } from '../infrastructure/auth/http';
import type { SupabaseServerClient } from '../infrastructure/supabase/server';

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const RESOURCE_PDF_UPLOAD_MULTIPART_OVERHEAD_BYTES = 64 * 1024;

export const RESOURCE_PDF_UPLOAD_MAX_BODY_BYTES =
	RESOURCE_PDF_MAX_BYTES + RESOURCE_PDF_UPLOAD_MULTIPART_OVERHEAD_BYTES;

class ResourcePdfUploadBodyTooLargeError extends Error {}

export interface ResourcePdfUploadHttpDependencies {
	createUploader(supabase: SupabaseServerClient): ResourcePdfUploadOrchestrator;
}

export interface ResourcePdfUploadHttpInput {
	readonly request: Request;
	readonly resourceId: string | undefined;
	readonly auth: App.Locals['auth'];
}

interface ErrorBody {
	readonly error: {
		readonly code: string;
		readonly message: string;
	};
}

const jsonResponse = (body: unknown, status: number): Response =>
	new Response(JSON.stringify(body), {
		status,
		headers: {
			'cache-control': 'no-store',
			'content-type': 'application/json; charset=utf-8',
		},
	});

const errorResponse = (code: string, message: string, status: number): Response =>
	jsonResponse(
		{
			error: {
				code,
				message,
			},
		} satisfies ErrorBody,
		status,
	);

const normalizeResourceId = (resourceId: string | undefined): string | null => {
	if (!resourceId) {
		return null;
	}

	const normalized = resourceId.trim().toLowerCase();

	return UUID_PATTERN.test(normalized) ? normalized : null;
};

const isMultipartFormData = (request: Request): boolean => {
	const contentType = request.headers.get('content-type');

	if (!contentType) {
		return false;
	}

	const [mediaType] = contentType.split(';', 1);

	return mediaType?.trim().toLowerCase() === 'multipart/form-data';
};

const readRequestBodyWithLimit = async (request: Request): Promise<Uint8Array<ArrayBuffer>> => {
	if (request.body === null) {
		return new Uint8Array();
	}

	const reader = request.body.getReader();
	const chunks: Uint8Array[] = [];
	let totalBytes = 0;

	try {
		while (true) {
			const { done, value } = await reader.read();

			if (done) {
				break;
			}

			totalBytes += value.byteLength;

			if (totalBytes > RESOURCE_PDF_UPLOAD_MAX_BODY_BYTES) {
				await reader.cancel();
				throw new ResourcePdfUploadBodyTooLargeError();
			}

			chunks.push(value);
		}
	} finally {
		reader.releaseLock();
	}

	const body = new Uint8Array(totalBytes);
	let offset = 0;

	for (const chunk of chunks) {
		body.set(chunk, offset);
		offset += chunk.byteLength;
	}

	return body;
};

const validationErrorResponse = (error: ResourcePdfValidationError): Response =>
	errorResponse(error.code, error.message, error.code === 'FILE_TOO_LARGE' ? 413 : 400);

const uploadErrorResponse = (error: ResourcePdfUploadError): Response => {
	switch (error.code) {
		case 'RESERVATION_FAILED':
		case 'FINALIZATION_FAILED':
			return errorResponse(error.code, error.message, 409);

		case 'RESERVATION_OUTCOME_UNKNOWN':
		case 'FINALIZATION_OUTCOME_UNKNOWN':
			return errorResponse(error.code, error.message, 503);

		case 'STORAGE_WRITE_FAILED':
			return errorResponse(error.code, error.message, 503);

		case 'STORAGE_KEY_FAILED':
		case 'COMPENSATION_FAILED':
			return errorResponse(error.code, error.message, 500);
	}
};

export const handleResourcePdfUploadRequest = async (
	input: ResourcePdfUploadHttpInput,
	dependencies: ResourcePdfUploadHttpDependencies,
): Promise<Response> => {
	if (!hasValidSameOriginHeader(input.request)) {
		return errorResponse('FORBIDDEN_ORIGIN', 'Request origin is not allowed', 403);
	}

	if (input.auth.status === 'anonymous') {
		return errorResponse('AUTHENTICATION_REQUIRED', 'Authentication is required', 401);
	}

	if (input.auth.status !== 'authenticated' || input.auth.supabase === null) {
		return errorResponse(
			'AUTHENTICATION_UNAVAILABLE',
			'Authentication service is unavailable',
			503,
		);
	}

	const resourceId = normalizeResourceId(input.resourceId);

	if (resourceId === null) {
		return errorResponse('INVALID_RESOURCE_ID', 'Resource id must be a valid UUID', 400);
	}

	if (!isMultipartFormData(input.request)) {
		return errorResponse(
			'UNSUPPORTED_MEDIA_TYPE',
			'Request content type must be multipart/form-data',
			415,
		);
	}

	let requestBody: Uint8Array<ArrayBuffer>;

	try {
		requestBody = await readRequestBodyWithLimit(input.request);
	} catch (error) {
		if (error instanceof ResourcePdfUploadBodyTooLargeError) {
			return errorResponse('REQUEST_TOO_LARGE', 'Multipart request body is too large', 413);
		}

		return errorResponse('INVALID_MULTIPART_BODY', 'Multipart request body is invalid', 400);
	}

	let formData: FormData;

	try {
		const contentType = input.request.headers.get('content-type') ?? '';

		formData = await new Response(requestBody, {
			headers: {
				'content-type': contentType,
			},
		}).formData();
	} catch {
		return errorResponse('INVALID_MULTIPART_BODY', 'Multipart request body is invalid', 400);
	}

	const fileEntry = formData.get('file');

	if (!(fileEntry instanceof File)) {
		return errorResponse('MISSING_FILE', 'A PDF file is required', 400);
	}

	if (fileEntry.size > RESOURCE_PDF_MAX_BYTES) {
		return errorResponse(
			'FILE_TOO_LARGE',
			`Resource PDF cannot exceed ${RESOURCE_PDF_MAX_BYTES} bytes`,
			413,
		);
	}

	const commentEntry = formData.get('comment');

	if (commentEntry !== null && typeof commentEntry !== 'string') {
		return errorResponse('INVALID_COMMENT', 'Comment must be text', 400);
	}

	const comment = commentEntry?.trim() || undefined;

	let bytes: Uint8Array;

	try {
		bytes = new Uint8Array(await fileEntry.arrayBuffer());
	} catch {
		return errorResponse('INVALID_FILE_BODY', 'Resource file body could not be read', 400);
	}

	let uploader: ResourcePdfUploadOrchestrator;

	try {
		uploader = dependencies.createUploader(input.auth.supabase);
	} catch {
		return errorResponse(
			'UPLOAD_SERVICE_UNAVAILABLE',
			'Resource upload service is unavailable',
			503,
		);
	}

	try {
		const result = await uploader.upload({
			resourceId,
			candidate: {
				filename: fileEntry.name,
				contentType: fileEntry.type,
				bytes,
			},
			comment,
		});

		return jsonResponse(
			{
				fileId: result.fileId,
			},
			201,
		);
	} catch (error) {
		if (error instanceof ResourcePdfValidationError) {
			return validationErrorResponse(error);
		}

		if (error instanceof ResourcePdfUploadError) {
			return uploadErrorResponse(error);
		}

		return errorResponse('UPLOAD_FAILED', 'Resource upload failed', 500);
	}
};
