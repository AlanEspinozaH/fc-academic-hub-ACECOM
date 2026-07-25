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

	it('maps thrown network errors and malformed rows to READ_FAILED', async () => {
		const { client, rpc } = makeClient();
		const persistence = createSupabaseResourceFileReadPersistence(client);

		rpc.mockRejectedValueOnce(new Error('network unavailable'));
		await expect(persistence.getDescriptor(RESOURCE_ID, FILE_ID)).rejects.toMatchObject({
			code: 'READ_FAILED',
		});

		rpc.mockResolvedValueOnce({
			data: [{ ...descriptorRow, content_type: 'text/html' }],
			error: null,
		});
		await expect(persistence.getDescriptor(RESOURCE_ID, FILE_ID)).rejects.toMatchObject({
			code: 'READ_FAILED',
		});
	});
});
