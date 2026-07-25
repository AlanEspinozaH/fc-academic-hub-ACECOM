import { describe, expect, it, vi } from 'vitest';
import {
	ResourceFileReadError,
	type ResourceFileReader,
	type ResourceFileReadResult,
} from '../application/resource-file-read';
import type { SupabaseServerClient } from '../infrastructure/supabase/server';
import {
	handleResourceFileReadRequest,
	type ResourceFileReadHttpDependencies,
} from './resource-file-read-handler';

const RESOURCE_ID = '11111111-2222-3333-4444-555555555555';
const FILE_ID = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
const BYTES = new TextEncoder().encode('%PDF-1.7\nhttp\n%%EOF\n');
const supabase = {} as SupabaseServerClient;

const authenticated: App.Locals['auth'] = {
	status: 'authenticated',
	user: { id: '99999999-8888-7777-6666-555555555555', email: 'reader@uni.pe' },
	supabase,
};

const anonymous: App.Locals['auth'] = {
	status: 'anonymous',
	user: null,
	supabase,
};

const PDF_RESULT: ResourceFileReadResult = {
	resourceId: RESOURCE_ID,
	fileId: FILE_ID,
	displayFilename: 'Examen final.pdf',
	fileKind: 'pdf',
	normalizedExtension: '.pdf',
	contentType: 'application/pdf',
	byteSize: BYTES.byteLength,
	sha256: 'a'.repeat(64),
	storageKeyVersion: 'generic_v2',
	bytes: BYTES,
};

const IMAGE_RESULTS = [
	{
		...PDF_RESULT,
		displayFilename: 'Diagrama final.PNG',
		fileKind: 'image',
		normalizedExtension: '.png',
		contentType: 'image/png',
		storageKeyVersion: 'generic_v2',
	},
	{
		...PDF_RESULT,
		displayFilename: 'Fotografía final.jpeg',
		fileKind: 'image',
		normalizedExtension: '.jpeg',
		contentType: 'image/jpeg',
		storageKeyVersion: 'generic_v2',
	},
] satisfies readonly ResourceFileReadResult[];

const makeDependencies = (result: ResourceFileReadResult = PDF_RESULT) => {
	const read = vi.fn<ResourceFileReader['read']>(async () => result);
	const reader = { read } as ResourceFileReader;
	const createReader = vi.fn(() => reader);
	const dependencies: ResourceFileReadHttpDependencies = { createReader };

	return { dependencies, createReader, read };
};

const makeInput = (
	disposition: 'inline' | 'attachment' = 'inline',
	auth: App.Locals['auth'] = authenticated,
) => ({
	request: new Request(
		`https://academic.example/api/resources/${RESOURCE_ID}/files/${FILE_ID}/preview`,
	),
	resourceId: RESOURCE_ID,
	fileId: FILE_ID,
	disposition,
	auth,
});

describe('resource file read HTTP handler', () => {
	it.each([
		['inline', 'inline;'],
		['attachment', 'attachment;'],
	] as const)('delivers exact PDF bytes with safe %s headers', async (disposition, prefix) => {
		const { dependencies, createReader, read } = makeDependencies();
		const response = await handleResourceFileReadRequest(makeInput(disposition), dependencies);

		expect(response.status).toBe(200);
		expect(response.headers.get('content-type')).toBe('application/pdf');
		expect(response.headers.get('content-disposition')).toMatch(new RegExp(`^${prefix}`));
		expect(response.headers.get('content-disposition')).toContain(
			"filename*=UTF-8''Examen%20final.pdf",
		);
		expect(response.headers.get('x-content-type-options')).toBe('nosniff');
		expect(response.headers.get('cache-control')).toBe('private, no-store');
		expect(response.headers.get('content-length')).toBe(BYTES.byteLength.toString());
		expect(new Uint8Array(await response.arrayBuffer())).toEqual(BYTES);
		expect(createReader).toHaveBeenCalledWith(supabase);
		expect(read).toHaveBeenCalledWith({ resourceId: RESOURCE_ID, fileId: FILE_ID });
		expect(response.headers.has('etag')).toBe(false);
		expect(response.headers.has('x-resource-sha256')).toBe(false);
		expect(response.headers.has('x-storage-key-version')).toBe(false);
	});

	it.each(IMAGE_RESULTS)(
		'previews $normalizedExtension with canonical image headers',
		async (result) => {
			const { dependencies } = makeDependencies(result);
			const response = await handleResourceFileReadRequest(makeInput('inline'), dependencies);

			expect(response.status).toBe(200);
			expect(response.headers.get('content-type')).toBe(result.contentType);
			expect(response.headers.get('content-disposition')).toMatch(/^inline;/);
			expect(response.headers.get('x-content-type-options')).toBe('nosniff');
			expect(response.headers.get('cache-control')).toBe('private, no-store');
			expect(new Uint8Array(await response.arrayBuffer())).toEqual(BYTES);
		},
	);

	it.each(IMAGE_RESULTS)(
		'downloads $normalizedExtension with attachment disposition and canonical MIME',
		async (result) => {
			const { dependencies } = makeDependencies(result);
			const response = await handleResourceFileReadRequest(makeInput('attachment'), dependencies);

			expect(response.status).toBe(200);
			expect(response.headers.get('content-type')).toBe(result.contentType);
			expect(response.headers.get('content-disposition')).toMatch(/^attachment;/);
			expect(response.headers.get('x-content-type-options')).toBe('nosniff');
		},
	);

	it('uses the anonymous Supabase client so PostgreSQL can authorize public resources', async () => {
		const { dependencies, createReader } = makeDependencies();
		const response = await handleResourceFileReadRequest(
			makeInput('inline', anonymous),
			dependencies,
		);

		expect(response.status).toBe(200);
		expect(createReader).toHaveBeenCalledWith(supabase);
	});

	it.each(['not-a-uuid', undefined])(
		'returns 404 for an invalid or missing resource id',
		async (resourceId) => {
			const { dependencies, createReader } = makeDependencies();
			const response = await handleResourceFileReadRequest(
				{ ...makeInput(), resourceId },
				dependencies,
			);

			expect(response.status).toBe(404);
			expect(response.headers.get('cache-control')).toBe('private, no-store');
			expect(createReader).not.toHaveBeenCalled();
		},
	);

	it('returns 404 for an invalid file id without creating the read service', async () => {
		const { dependencies, createReader } = makeDependencies();
		const response = await handleResourceFileReadRequest(
			{ ...makeInput(), fileId: 'not-a-file-uuid' },
			dependencies,
		);

		expect(response.status).toBe(404);
		expect(createReader).not.toHaveBeenCalled();
	});

	it('returns the same 404 for missing, unauthorized, unstored, or missing-R2 results', async () => {
		const { dependencies, read } = makeDependencies();
		read.mockRejectedValueOnce(new ResourceFileReadError('NOT_FOUND', 'hidden'));

		const response = await handleResourceFileReadRequest(makeInput(), dependencies);

		expect(response.status).toBe(404);
		await expect(response.text()).resolves.toBe('');
	});

	it('returns safe 503 for auth configuration and service failures', async () => {
		const authError: App.Locals['auth'] = { status: 'error', user: null, supabase };
		const authDependencies = makeDependencies();
		const authResponse = await handleResourceFileReadRequest(
			makeInput('inline', authError),
			authDependencies.dependencies,
		);

		expect(authResponse.status).toBe(503);
		expect(authDependencies.createReader).not.toHaveBeenCalled();

		const readDependencies = makeDependencies();
		readDependencies.read.mockRejectedValueOnce(
			new ResourceFileReadError('READ_FAILED', `secret ${FILE_ID}`),
		);
		const readResponse = await handleResourceFileReadRequest(
			makeInput(),
			readDependencies.dependencies,
		);

		expect(readResponse.status).toBe(503);
		await expect(readResponse.text()).resolves.toBe('');
	});

	it('returns 405 with Allow GET for any other method', async () => {
		const { dependencies, createReader } = makeDependencies();
		const response = await handleResourceFileReadRequest(
			{
				...makeInput(),
				request: new Request('https://academic.example/file', { method: 'POST' }),
			},
			dependencies,
		);

		expect(response.status).toBe(405);
		expect(response.headers.get('allow')).toBe('GET');
		expect(createReader).not.toHaveBeenCalled();
	});
});
