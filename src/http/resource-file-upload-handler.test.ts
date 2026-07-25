import { describe, expect, it, vi } from 'vitest';
import {
	ResourceFileUploadError,
	type ResourceFileUploadOrchestrator,
} from '../application/resource-file-upload';
import { ResourceFileValidationError } from '../domain/resource-file-validation';
import type { SupabaseServerClient } from '../infrastructure/supabase/server';

import {
	RESOURCE_FILE_UPLOAD_MAX_BODY_BYTES,
	handleResourceFileUploadRequest,
	type ResourceFileUploadHttpDependencies,
} from './resource-file-upload-handler';

const RESOURCE_ID = '11111111-2222-3333-4444-555555555555';
const FILE_ID = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
const ORIGIN = 'https://academic.example';

const supabase = {} as SupabaseServerClient;

const authenticated: App.Locals['auth'] = {
	status: 'authenticated',
	user: {
		id: '99999999-8888-7777-6666-555555555555',
		email: 'student@example.edu',
	},
	supabase,
};

const anonymous: App.Locals['auth'] = {
	status: 'anonymous',
	user: null,
	supabase,
};

const makeFormData = (): FormData => {
	const formData = new FormData();

	formData.set(
		'file',
		new File([new TextEncoder().encode('%PDF-1.7\n%%EOF\n')], 'exam.pdf', {
			type: 'text/plain',
		}),
	);
	formData.set('comment', '  ready for review  ');

	return formData;
};

const makeRequest = (body: FormData = makeFormData()): Request =>
	new Request(`${ORIGIN}/api/resources/${RESOURCE_ID}/files`, {
		method: 'POST',
		headers: {
			Origin: ORIGIN,
		},
		body,
	});

const makeDependencies = () => {
	const upload = vi.fn<ResourceFileUploadOrchestrator['upload']>(async () => ({
		fileId: FILE_ID,
	}));

	const uploader = {
		upload,
	} as ResourceFileUploadOrchestrator;

	const createUploader = vi.fn(() => uploader);

	const dependencies: ResourceFileUploadHttpDependencies = {
		createUploader,
	};

	return {
		dependencies,
		createUploader,
		upload,
	};
};

describe('resource file upload HTTP handler', () => {
	it('accepts a valid PDF with misleading declared MIME and returns only the file id', async () => {
		const { dependencies, createUploader, upload } = makeDependencies();

		const response = await handleResourceFileUploadRequest(
			{
				request: makeRequest(),
				resourceId: RESOURCE_ID.toUpperCase(),
				auth: authenticated,
			},
			dependencies,
		);

		expect(response.status).toBe(201);
		expect(response.headers.get('cache-control')).toBe('no-store');
		expect(response.headers.get('content-type')).toBe('application/json; charset=utf-8');
		await expect(response.json()).resolves.toEqual({
			fileId: FILE_ID,
		});

		expect(createUploader).toHaveBeenCalledWith(supabase);
		expect(upload).toHaveBeenCalledTimes(1);

		const uploadInput = upload.mock.calls[0]?.[0];

		expect(uploadInput).toMatchObject({
			resourceId: RESOURCE_ID,
			comment: 'ready for review',
			candidate: {
				filename: 'exam.pdf',
				declaredContentType: 'text/plain',
			},
		});

		expect(new TextDecoder().decode(uploadInput?.candidate.bytes)).toBe('%PDF-1.7\n%%EOF\n');
	});

	it.each([
		{
			filename: 'diagram.png',
			bytes: new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
			declaredContentType: 'image/jpeg',
		},
		{
			filename: 'photo.jpeg',
			bytes: new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0xff, 0xd9]),
			declaredContentType: 'image/png',
		},
	])(
		'passes $filename bytes and non-authoritative MIME to the generic uploader',
		async ({ filename, bytes, declaredContentType }) => {
			const { dependencies, upload } = makeDependencies();
			const formData = new FormData();
			formData.set('file', new File([bytes], filename, { type: declaredContentType }));

			const response = await handleResourceFileUploadRequest(
				{
					request: makeRequest(formData),
					resourceId: RESOURCE_ID,
					auth: authenticated,
				},
				dependencies,
			);

			expect(response.status).toBe(201);
			const candidate = upload.mock.calls[0]?.[0].candidate;
			expect(candidate).toMatchObject({ filename, declaredContentType });
			expect(candidate?.bytes).toEqual(bytes);
		},
	);

	it('rejects a cross-origin POST before creating an uploader', async () => {
		const { dependencies, createUploader } = makeDependencies();
		const request = makeRequest();

		request.headers.set('Origin', 'https://attacker.example');

		const response = await handleResourceFileUploadRequest(
			{
				request,
				resourceId: RESOURCE_ID,
				auth: authenticated,
			},
			dependencies,
		);

		expect(response.status).toBe(403);
		await expect(response.json()).resolves.toMatchObject({
			error: {
				code: 'FORBIDDEN_ORIGIN',
			},
		});
		expect(createUploader).not.toHaveBeenCalled();
	});

	it('requires an authenticated session', async () => {
		const { dependencies, createUploader } = makeDependencies();

		const response = await handleResourceFileUploadRequest(
			{
				request: makeRequest(),
				resourceId: RESOURCE_ID,
				auth: anonymous,
			},
			dependencies,
		);

		expect(response.status).toBe(401);
		await expect(response.json()).resolves.toMatchObject({
			error: {
				code: 'AUTHENTICATION_REQUIRED',
			},
		});
		expect(createUploader).not.toHaveBeenCalled();
	});

	it('returns 503 when authentication context is unavailable', async () => {
		const { dependencies, createUploader } = makeDependencies();

		const response = await handleResourceFileUploadRequest(
			{
				request: makeRequest(),
				resourceId: RESOURCE_ID,
				auth: {
					status: 'error',
					user: null,
					supabase,
				},
			},
			dependencies,
		);

		expect(response.status).toBe(503);
		expect(createUploader).not.toHaveBeenCalled();
	});

	it('rejects an invalid resource id before parsing the upload', async () => {
		const { dependencies, createUploader } = makeDependencies();

		const response = await handleResourceFileUploadRequest(
			{
				request: makeRequest(),
				resourceId: 'not-a-uuid',
				auth: authenticated,
			},
			dependencies,
		);

		expect(response.status).toBe(400);
		await expect(response.json()).resolves.toMatchObject({
			error: {
				code: 'INVALID_RESOURCE_ID',
			},
		});
		expect(createUploader).not.toHaveBeenCalled();
	});

	it('requires multipart form data', async () => {
		const { dependencies, createUploader } = makeDependencies();

		const response = await handleResourceFileUploadRequest(
			{
				request: new Request(`${ORIGIN}/api/resources/${RESOURCE_ID}/files`, {
					method: 'POST',
					headers: {
						Origin: ORIGIN,
						'content-type': 'application/json',
					},
					body: '{}',
				}),
				resourceId: RESOURCE_ID,
				auth: authenticated,
			},
			dependencies,
		);

		expect(response.status).toBe(415);
		expect(createUploader).not.toHaveBeenCalled();
	});

	it('rejects content types that only prefix-match multipart form data', async () => {
		const { dependencies, createUploader } = makeDependencies();

		const response = await handleResourceFileUploadRequest(
			{
				request: new Request(`${ORIGIN}/api/resources/${RESOURCE_ID}/files`, {
					method: 'POST',
					headers: {
						Origin: ORIGIN,
						'content-type': 'multipart/form-dataevil',
					},
					body: 'invalid',
				}),
				resourceId: RESOURCE_ID,
				auth: authenticated,
			},
			dependencies,
		);

		expect(response.status).toBe(415);
		await expect(response.json()).resolves.toMatchObject({
			error: {
				code: 'UNSUPPORTED_MEDIA_TYPE',
			},
		});
		expect(createUploader).not.toHaveBeenCalled();
	});

	it('rejects malformed multipart data', async () => {
		const { dependencies, createUploader } = makeDependencies();

		const response = await handleResourceFileUploadRequest(
			{
				request: new Request(`${ORIGIN}/api/resources/${RESOURCE_ID}/files`, {
					method: 'POST',
					headers: {
						Origin: ORIGIN,
						'content-type': 'multipart/form-data; boundary=missing',
					},
					body: 'broken multipart body',
				}),
				resourceId: RESOURCE_ID,
				auth: authenticated,
			},
			dependencies,
		);

		expect(response.status).toBe(400);
		await expect(response.json()).resolves.toMatchObject({
			error: {
				code: 'INVALID_MULTIPART_BODY',
			},
		});
		expect(createUploader).not.toHaveBeenCalled();
	});

	it('rejects an oversized multipart body before creating an uploader', async () => {
		const { dependencies, createUploader } = makeDependencies();

		const oversizedBody = new Uint8Array(RESOURCE_FILE_UPLOAD_MAX_BODY_BYTES + 1);

		const response = await handleResourceFileUploadRequest(
			{
				request: new Request(`${ORIGIN}/api/resources/${RESOURCE_ID}/files`, {
					method: 'POST',
					headers: {
						Origin: ORIGIN,
						'content-type': 'multipart/form-data; boundary=test',
					},
					body: oversizedBody,
				}),
				resourceId: RESOURCE_ID,
				auth: authenticated,
			},
			dependencies,
		);

		expect(response.status).toBe(413);

		await expect(response.json()).resolves.toMatchObject({
			error: {
				code: 'REQUEST_TOO_LARGE',
			},
		});

		expect(createUploader).not.toHaveBeenCalled();
	});

	it('requires the file field', async () => {
		const { dependencies, createUploader } = makeDependencies();
		const formData = new FormData();

		formData.set('comment', 'missing file');

		const response = await handleResourceFileUploadRequest(
			{
				request: makeRequest(formData),
				resourceId: RESOURCE_ID,
				auth: authenticated,
			},
			dependencies,
		);

		expect(response.status).toBe(400);
		await expect(response.json()).resolves.toEqual({
			error: {
				code: 'MISSING_FILE',
				message: 'Exactly one resource file is required',
			},
		});
		expect(createUploader).not.toHaveBeenCalled();
	});

	it('rejects multiple file fields', async () => {
		const { dependencies, createUploader } = makeDependencies();
		const formData = makeFormData();

		formData.append(
			'file',
			new File([new TextEncoder().encode('%PDF-1.7\n%%EOF\n')], 'second.pdf', {
				type: 'application/pdf',
			}),
		);

		const response = await handleResourceFileUploadRequest(
			{
				request: makeRequest(formData),
				resourceId: RESOURCE_ID,
				auth: authenticated,
			},
			dependencies,
		);

		expect(response.status).toBe(400);
		await expect(response.json()).resolves.toMatchObject({
			error: { code: 'MISSING_FILE' },
		});
		expect(createUploader).not.toHaveBeenCalled();
	});

	it('rejects a non-text comment', async () => {
		const { dependencies, createUploader } = makeDependencies();
		const formData = makeFormData();

		formData.set(
			'comment',
			new File(['not text'], 'comment.txt', {
				type: 'text/plain',
			}),
		);

		const response = await handleResourceFileUploadRequest(
			{
				request: makeRequest(formData),
				resourceId: RESOURCE_ID,
				auth: authenticated,
			},
			dependencies,
		);

		expect(response.status).toBe(400);
		await expect(response.json()).resolves.toMatchObject({
			error: {
				code: 'INVALID_COMMENT',
			},
		});
		expect(createUploader).not.toHaveBeenCalled();
	});

	it('maps ResourceFile validation failures to a safe client error', async () => {
		const { dependencies, upload } = makeDependencies();

		upload.mockRejectedValueOnce(
			new ResourceFileValidationError(
				'INVALID_PDF_HEADER',
				'resource file must begin with the %PDF- signature',
			),
		);

		const response = await handleResourceFileUploadRequest(
			{
				request: makeRequest(),
				resourceId: RESOURCE_ID,
				auth: authenticated,
			},
			dependencies,
		);

		expect(response.status).toBe(400);
		await expect(response.json()).resolves.toEqual({
			error: {
				code: 'INVALID_PDF_HEADER',
				message: 'resource file must begin with the %PDF- signature',
			},
		});
	});

	it('maps an unsupported future extension to a safe 400', async () => {
		const { dependencies, upload } = makeDependencies();
		const formData = new FormData();

		formData.set(
			'file',
			new File([new TextEncoder().encode('future bytes')], 'future.md', {
				type: 'text/markdown',
			}),
		);
		upload.mockRejectedValueOnce(
			new ResourceFileValidationError(
				'UNSUPPORTED_FILE_TYPE',
				'submitted file type is not currently supported',
			),
		);

		const response = await handleResourceFileUploadRequest(
			{
				request: makeRequest(formData),
				resourceId: RESOURCE_ID,
				auth: authenticated,
			},
			dependencies,
		);

		expect(response.status).toBe(400);
		await expect(response.json()).resolves.toEqual({
			error: {
				code: 'UNSUPPORTED_FILE_TYPE',
				message: 'submitted file type is not currently supported',
			},
		});
	});

	it('maps a deterministic reservation failure to 409', async () => {
		const { dependencies, upload } = makeDependencies();

		upload.mockRejectedValueOnce(
			new ResourceFileUploadError('RESERVATION_FAILED', 'Resource upload reservation failed'),
		);

		const response = await handleResourceFileUploadRequest(
			{
				request: makeRequest(),
				resourceId: RESOURCE_ID,
				auth: authenticated,
			},
			dependencies,
		);

		expect(response.status).toBe(409);
		await expect(response.json()).resolves.toMatchObject({
			error: {
				code: 'RESERVATION_FAILED',
			},
		});
	});

	it('preserves an unknown finalization outcome as a 503 error', async () => {
		const { dependencies, upload } = makeDependencies();

		upload.mockRejectedValueOnce(
			new ResourceFileUploadError(
				'FINALIZATION_OUTCOME_UNKNOWN',
				'Resource upload finalization outcome is unknown',
			),
		);

		const response = await handleResourceFileUploadRequest(
			{
				request: makeRequest(),
				resourceId: RESOURCE_ID,
				auth: authenticated,
			},
			dependencies,
		);

		expect(response.status).toBe(503);
		await expect(response.json()).resolves.toEqual({
			error: {
				code: 'FINALIZATION_OUTCOME_UNKNOWN',
				message: 'Resource upload finalization outcome is unknown',
			},
		});
	});

	it('does not expose unexpected internal error details', async () => {
		const { dependencies, upload } = makeDependencies();

		upload.mockRejectedValueOnce(new Error(`internal secret involving ${RESOURCE_ID}`));

		const response = await handleResourceFileUploadRequest(
			{
				request: makeRequest(),
				resourceId: RESOURCE_ID,
				auth: authenticated,
			},
			dependencies,
		);

		expect(response.status).toBe(500);

		const body = await response.text();

		expect(body).toContain('"code":"UPLOAD_FAILED"');
		expect(body).not.toContain('internal secret');
		expect(body).not.toContain(RESOURCE_ID);
	});
});
