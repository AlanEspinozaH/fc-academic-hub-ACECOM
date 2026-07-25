import { describe, expect, it, vi } from 'vitest';
import {
	ResourceFileReadPersistenceError,
	createSupabaseResourceFileReadPersistence,
} from './resource-file-read-persistence';
import type { SupabaseServerClient } from './server';

const RESOURCE_ID = '11111111-2222-3333-4444-555555555555';
const FILE_ID = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';

const descriptorRow = {
	resource_id: RESOURCE_ID,
	file_id: FILE_ID,
	display_filename: 'Examen final.pdf',
	file_kind: 'pdf',
	normalized_extension: '.pdf',
	content_type: 'application/pdf',
	byte_size: 1234,
	sha256: 'a'.repeat(64),
	storage_key_version: 'legacy_pdf_v1',
} as const;

const makeClient = () => {
	const rpc = vi.fn();
	const client = { rpc } as unknown as Pick<SupabaseServerClient, 'rpc'>;

	return { client, rpc };
};

describe('Supabase resource file read persistence', () => {
	it('returns a domain-safe descriptor from the public RPC', async () => {
		const { client, rpc } = makeClient();
		const persistence = createSupabaseResourceFileReadPersistence(client);

		rpc.mockResolvedValueOnce({ data: [descriptorRow], error: null });

		await expect(persistence.getDescriptor(RESOURCE_ID, FILE_ID)).resolves.toEqual({
			resourceId: RESOURCE_ID,
			fileId: FILE_ID,
			displayFilename: 'Examen final.pdf',
			fileKind: 'pdf',
			normalizedExtension: '.pdf',
			contentType: 'application/pdf',
			byteSize: 1234,
			sha256: 'a'.repeat(64),
			storageKeyVersion: 'legacy_pdf_v1',
		});
		expect(rpc).toHaveBeenCalledWith('get_resource_file_read_descriptor', {
			resource_id: RESOURCE_ID,
			file_id: FILE_ID,
		});
		expect(rpc.mock.calls[0]?.[1]).not.toHaveProperty('storage_key');
	});

	it.each([
		{
			display_filename: 'Diagram.PNG',
			file_kind: 'image',
			normalized_extension: '.png',
			content_type: 'image/png',
		},
		{
			display_filename: 'Photo.JPG',
			file_kind: 'image',
			normalized_extension: '.jpg',
			content_type: 'image/jpeg',
		},
		{
			display_filename: 'Photo.jpeg',
			file_kind: 'image',
			normalized_extension: '.jpeg',
			content_type: 'image/jpeg',
		},
	] as const)(
		'returns the canonical operational descriptor for $normalized_extension',
		async ({ display_filename, file_kind, normalized_extension, content_type }) => {
			const { client, rpc } = makeClient();
			const persistence = createSupabaseResourceFileReadPersistence(client);
			rpc.mockResolvedValueOnce({
				data: [
					{
						...descriptorRow,
						display_filename,
						file_kind,
						normalized_extension,
						content_type,
						storage_key_version: 'generic_v2',
					},
				],
				error: null,
			});

			await expect(persistence.getDescriptor(RESOURCE_ID, FILE_ID)).resolves.toEqual({
				resourceId: RESOURCE_ID,
				fileId: FILE_ID,
				displayFilename: display_filename,
				fileKind: file_kind,
				normalizedExtension: normalized_extension,
				contentType: content_type,
				byteSize: 1234,
				sha256: 'a'.repeat(64),
				storageKeyVersion: 'generic_v2',
			});
		},
	);

	it.each([
		['README.MD', 'markdown', '.md'],
		['formula.tex', 'tex', '.tex'],
		['notes.txt', 'text', '.txt'],
		['Main.java', 'source', '.java'],
		['solution.py', 'source', '.py'],
		['main.c', 'source', '.c'],
		['header.h', 'source', '.h'],
		['main.cpp', 'source', '.cpp'],
		['header.hpp', 'source', '.hpp'],
		['app.js', 'source', '.js'],
		['types.ts', 'source', '.ts'],
		['main.rs', 'source', '.rs'],
		['main.go', 'source', '.go'],
		['query.sql', 'source', '.sql'],
		['run.sh', 'source', '.sh'],
	] as const)(
		'returns the canonical generic_v2 textual descriptor for %s',
		async (displayFilename, fileKind, normalizedExtension) => {
			const { client, rpc } = makeClient();
			const persistence = createSupabaseResourceFileReadPersistence(client);
			rpc.mockResolvedValueOnce({
				data: [
					{
						...descriptorRow,
						display_filename: displayFilename,
						file_kind: fileKind,
						normalized_extension: normalizedExtension,
						content_type: 'text/plain',
						storage_key_version: 'generic_v2',
					},
				],
				error: null,
			});

			await expect(persistence.getDescriptor(RESOURCE_ID, FILE_ID)).resolves.toEqual({
				resourceId: RESOURCE_ID,
				fileId: FILE_ID,
				displayFilename,
				fileKind,
				normalizedExtension,
				contentType: 'text/plain',
				byteSize: 1234,
				sha256: 'a'.repeat(64),
				storageKeyVersion: 'generic_v2',
			});
		},
	);

	it.each([null, []])('maps a zero-row result to NOT_FOUND', async (data) => {
		const { client, rpc } = makeClient();
		const persistence = createSupabaseResourceFileReadPersistence(client);

		rpc.mockResolvedValueOnce({ data, error: null });

		await expect(persistence.getDescriptor(RESOURCE_ID, FILE_ID)).rejects.toMatchObject({
			name: 'ResourceFileReadPersistenceError',
			code: 'NOT_FOUND',
			message: 'Resource file was not found',
		});
	});

	it('maps PostgREST errors to a safe READ_FAILED error', async () => {
		const { client, rpc } = makeClient();
		const persistence = createSupabaseResourceFileReadPersistence(client);

		rpc.mockResolvedValueOnce({
			data: null,
			error: { message: `private failure for ${FILE_ID}` },
		});

		const operation = persistence.getDescriptor(RESOURCE_ID, FILE_ID);

		await expect(operation).rejects.toBeInstanceOf(ResourceFileReadPersistenceError);
		await expect(operation).rejects.toMatchObject({
			code: 'READ_FAILED',
			message: 'Resource file descriptor read failed',
		});
		await expect(operation).rejects.not.toHaveProperty('message', expect.stringContaining(FILE_ID));
	});

	it('maps thrown network errors to READ_FAILED', async () => {
		const { client, rpc } = makeClient();
		const persistence = createSupabaseResourceFileReadPersistence(client);

		rpc.mockRejectedValueOnce(new Error('network unavailable'));
		await expect(persistence.getDescriptor(RESOURCE_ID, FILE_ID)).rejects.toMatchObject({
			code: 'READ_FAILED',
		});
	});

	it.each([
		{ content_type: 'text/html' },
		{
			file_kind: 'image',
			normalized_extension: '.png',
			content_type: 'image/jpeg',
			storage_key_version: 'generic_v2',
		},
		{
			file_kind: 'image',
			normalized_extension: '.jpg',
			content_type: 'image/png',
			storage_key_version: 'generic_v2',
		},
		{
			file_kind: 'image',
			normalized_extension: '.pdf',
			content_type: 'application/pdf',
			storage_key_version: 'generic_v2',
		},
		{
			file_kind: 'pdf',
			normalized_extension: '.png',
			content_type: 'image/png',
			storage_key_version: 'generic_v2',
		},
		{
			file_kind: 'image',
			normalized_extension: '.png',
			content_type: 'image/png',
			storage_key_version: 'legacy_pdf_v1',
		},
		{
			file_kind: 'source',
			normalized_extension: '.json',
			content_type: 'text/plain',
			storage_key_version: 'generic_v2',
		},
		{
			file_kind: 'markdown',
			normalized_extension: '.txt',
			content_type: 'text/plain',
			storage_key_version: 'generic_v2',
		},
		{
			file_kind: 'tex',
			normalized_extension: '.py',
			content_type: 'text/plain',
			storage_key_version: 'generic_v2',
		},
		{
			file_kind: 'text',
			normalized_extension: '.md',
			content_type: 'text/plain',
			storage_key_version: 'generic_v2',
		},
		{
			file_kind: 'source',
			normalized_extension: '.js',
			content_type: 'application/javascript',
			storage_key_version: 'generic_v2',
		},
		{
			file_kind: 'markdown',
			normalized_extension: '.md',
			content_type: 'text/html',
			storage_key_version: 'generic_v2',
		},
		{
			file_kind: 'markdown',
			normalized_extension: '.md',
			content_type: 'text/plain',
			storage_key_version: 'legacy_pdf_v1',
		},
		{
			file_kind: 'tex',
			normalized_extension: '.tex',
			content_type: 'text/plain',
			storage_key_version: 'legacy_pdf_v1',
		},
		{
			file_kind: 'text',
			normalized_extension: '.txt',
			content_type: 'text/plain',
			storage_key_version: 'legacy_pdf_v1',
		},
		{
			file_kind: 'source',
			normalized_extension: '.py',
			content_type: 'text/plain',
			storage_key_version: 'legacy_pdf_v1',
		},
	])('rejects malformed or unsupported descriptor metadata %#', async (overrides) => {
		const { client, rpc } = makeClient();
		const persistence = createSupabaseResourceFileReadPersistence(client);
		rpc.mockResolvedValueOnce({
			data: [{ ...descriptorRow, ...overrides }],
			error: null,
		});

		await expect(persistence.getDescriptor(RESOURCE_ID, FILE_ID)).rejects.toMatchObject({
			code: 'READ_FAILED',
		});
	});
});
