import { describe, expect, it, vi } from 'vitest';
import type { ResourceObjectStore } from '../infrastructure/r2/resource-object-store';
import type { ResourceStorageKeyVersion } from '../infrastructure/r2/resource-storage-key';
import {
	ResourceFileReadPersistenceError,
	type ResourceFileReadDescriptor,
	type ResourceFileReadPersistence,
} from '../infrastructure/supabase/resource-file-read-persistence';
import { createResourceFileReader } from './resource-file-read';

const RESOURCE_ID = '11111111-2222-3333-4444-555555555555';
const FILE_ID = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
const BYTES = new TextEncoder().encode('%PDF-1.7\nread\n%%EOF\n');

const makeDescriptor = (
	storageKeyVersion: ResourceStorageKeyVersion = 'generic_v2',
): ResourceFileReadDescriptor => ({
	resourceId: RESOURCE_ID,
	fileId: FILE_ID,
	displayFilename: 'Examen final.pdf',
	fileKind: 'pdf',
	normalizedExtension: '.pdf',
	contentType: 'application/pdf',
	byteSize: BYTES.byteLength,
	sha256: 'a'.repeat(64),
	storageKeyVersion,
});

const makeDependencies = () => {
	const getDescriptor = vi.fn(async (): Promise<ResourceFileReadDescriptor> => makeDescriptor());
	const persistence = { getDescriptor } as ResourceFileReadPersistence;
	const read = vi.fn<ResourceObjectStore['read']>(async () => ({ bytes: BYTES }));
	const objectStore = { read } as unknown as ResourceObjectStore;

	return { persistence, objectStore, getDescriptor, read };
};

describe('resource file reader', () => {
	it.each([
		['generic_v2', `resources/${RESOURCE_ID}/${FILE_ID}`],
		['legacy_pdf_v1', `resources/${RESOURCE_ID}/${FILE_ID}.pdf`],
	] as const)('authorizes before reading the %s private object', async (version, storageKey) => {
		const dependencies = makeDependencies();
		dependencies.getDescriptor.mockResolvedValueOnce(makeDescriptor(version));
		const reader = createResourceFileReader(dependencies.persistence, dependencies.objectStore);

		await expect(reader.read({ resourceId: RESOURCE_ID, fileId: FILE_ID })).resolves.toEqual({
			...makeDescriptor(version),
			bytes: BYTES,
		});

		expect(dependencies.getDescriptor).toHaveBeenCalledWith(RESOURCE_ID, FILE_ID);
		expect(dependencies.read).toHaveBeenCalledWith(storageKey);
		expect(dependencies.getDescriptor.mock.invocationCallOrder[0]).toBeLessThan(
			dependencies.read.mock.invocationCallOrder[0] ?? 0,
		);
	});

	it('does not access R2 when PostgreSQL returns no descriptor', async () => {
		const dependencies = makeDependencies();
		dependencies.getDescriptor.mockRejectedValueOnce(
			new ResourceFileReadPersistenceError('NOT_FOUND', 'Resource file was not found'),
		);
		const reader = createResourceFileReader(dependencies.persistence, dependencies.objectStore);

		await expect(reader.read({ resourceId: RESOURCE_ID, fileId: FILE_ID })).rejects.toMatchObject({
			code: 'NOT_FOUND',
		});
		expect(dependencies.read).not.toHaveBeenCalled();
	});

	it('does not access R2 when PostgreSQL is unavailable', async () => {
		const dependencies = makeDependencies();
		dependencies.getDescriptor.mockRejectedValueOnce(
			new ResourceFileReadPersistenceError('READ_FAILED', 'descriptor unavailable'),
		);
		const reader = createResourceFileReader(dependencies.persistence, dependencies.objectStore);

		await expect(reader.read({ resourceId: RESOURCE_ID, fileId: FILE_ID })).rejects.toMatchObject({
			code: 'READ_FAILED',
		});
		expect(dependencies.read).not.toHaveBeenCalled();
	});

	it('rejects invalid domain ids before persistence or R2 access', async () => {
		const dependencies = makeDependencies();
		const reader = createResourceFileReader(dependencies.persistence, dependencies.objectStore);

		await expect(reader.read({ resourceId: 'not-a-uuid', fileId: FILE_ID })).rejects.toMatchObject({
			code: 'NOT_FOUND',
		});
		expect(dependencies.getDescriptor).not.toHaveBeenCalled();
		expect(dependencies.read).not.toHaveBeenCalled();
	});

	it('does not access R2 when the authorized descriptor has an invalid layout', async () => {
		const dependencies = makeDependencies();
		dependencies.getDescriptor.mockResolvedValueOnce({
			...makeDescriptor(),
			storageKeyVersion: 'unknown_layout' as ResourceStorageKeyVersion,
		});
		const reader = createResourceFileReader(dependencies.persistence, dependencies.objectStore);

		await expect(reader.read({ resourceId: RESOURCE_ID, fileId: FILE_ID })).rejects.toMatchObject({
			code: 'READ_FAILED',
		});
		expect(dependencies.read).not.toHaveBeenCalled();
	});

	it('does not access R2 for a mismatched descriptor pair', async () => {
		const dependencies = makeDependencies();
		dependencies.getDescriptor.mockResolvedValueOnce({
			...makeDescriptor(),
			resourceId: '99999999-2222-3333-4444-555555555555',
		});
		const reader = createResourceFileReader(dependencies.persistence, dependencies.objectStore);

		await expect(reader.read({ resourceId: RESOURCE_ID, fileId: FILE_ID })).rejects.toMatchObject({
			code: 'READ_FAILED',
		});
		expect(dependencies.read).not.toHaveBeenCalled();
	});

	it('maps a missing R2 object to the same NOT_FOUND result', async () => {
		const dependencies = makeDependencies();
		dependencies.read.mockResolvedValueOnce(null);
		const reader = createResourceFileReader(dependencies.persistence, dependencies.objectStore);

		await expect(reader.read({ resourceId: RESOURCE_ID, fileId: FILE_ID })).rejects.toMatchObject({
			code: 'NOT_FOUND',
		});
	});

	it('maps R2 failures to a safe READ_FAILED result', async () => {
		const dependencies = makeDependencies();
		dependencies.read.mockRejectedValueOnce(new Error(`R2 failed for ${FILE_ID}`));
		const reader = createResourceFileReader(dependencies.persistence, dependencies.objectStore);

		const operation = reader.read({ resourceId: RESOURCE_ID, fileId: FILE_ID });

		await expect(operation).rejects.toMatchObject({
			code: 'READ_FAILED',
			message: 'Resource file read is unavailable',
		});
		await expect(operation).rejects.not.toHaveProperty('message', expect.stringContaining(FILE_ID));
	});
});
