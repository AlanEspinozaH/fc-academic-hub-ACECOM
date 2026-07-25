import { describe, expect, it, vi } from 'vitest';
import {
	ResourceObjectStoreError,
	createR2ResourceObjectStore,
	type ResourceObjectWrite,
} from './resource-object-store';

const encoder = new TextEncoder();

const STORAGE_KEY =
	'resources/11111111-1111-1111-1111-111111111111/22222222-2222-2222-2222-222222222222.pdf';

const makeWrite = (): ResourceObjectWrite => ({
	storageKey: STORAGE_KEY,
	bytes: encoder.encode('%PDF-1.7\n%%EOF\n'),
	contentType: 'application/pdf',
});

const makeStoredObject = (): R2Object =>
	({
		key: STORAGE_KEY,
	}) as R2Object;

const makeStoredObjectBody = (bytes: Uint8Array): R2ObjectBody =>
	({
		key: STORAGE_KEY,
		arrayBuffer: async () => bytes.buffer.slice(0),
	}) as R2ObjectBody;

const makeBucket = () => {
	const put = vi.fn(async (): Promise<R2Object | null> => makeStoredObject());
	const get = vi.fn(async (): Promise<R2ObjectBody | null> =>
		makeStoredObjectBody(makeWrite().bytes),
	);
	const deleteObject = vi.fn(async (): Promise<void> => undefined);

	const bucket = {
		put,
		get,
		delete: deleteObject,
	} as unknown as Pick<R2Bucket, 'put' | 'get' | 'delete'>;

	return {
		bucket,
		put,
		get,
		deleteObject,
	};
};

describe('R2 resource object store', () => {
	it('writes the exact storage key and bytes with HTTP content type metadata', async () => {
		const { bucket, put } = makeBucket();
		const store = createR2ResourceObjectStore(bucket);
		const input = makeWrite();

		await store.write(input);

		expect(put).toHaveBeenCalledTimes(1);
		expect(put).toHaveBeenCalledWith(input.storageKey, input.bytes, {
			httpMetadata: {
				contentType: 'application/pdf',
			},
		});
	});

	it('does not generate or modify the storage key', async () => {
		const { bucket, put } = makeBucket();
		const store = createR2ResourceObjectStore(bucket);
		const input = makeWrite();
		const opaqueStorageKey = 'opaque-storage-key-without-resource-semantics';

		await store.write({
			...input,
			storageKey: opaqueStorageKey,
		});

		expect(put).toHaveBeenCalledWith(opaqueStorageKey, input.bytes, {
			httpMetadata: {
				contentType: input.contentType,
			},
		});
	});

	it('reads exact bytes from the exact storage key', async () => {
		const { bucket, get } = makeBucket();
		const store = createR2ResourceObjectStore(bucket);
		const expectedBytes = makeWrite().bytes;

		get.mockResolvedValueOnce(makeStoredObjectBody(expectedBytes));

		await expect(store.read(STORAGE_KEY)).resolves.toEqual({ bytes: expectedBytes });
		expect(get).toHaveBeenCalledTimes(1);
		expect(get).toHaveBeenCalledWith(STORAGE_KEY);
	});

	it('returns null when the private object is missing', async () => {
		const { bucket, get } = makeBucket();
		const store = createR2ResourceObjectStore(bucket);

		get.mockResolvedValueOnce(null);

		await expect(store.read(STORAGE_KEY)).resolves.toBeNull();
	});

	it('maps an R2 read exception to a typed error without exposing the storage key', async () => {
		const { bucket, get } = makeBucket();
		const store = createR2ResourceObjectStore(bucket);

		get.mockRejectedValueOnce(new Error(`R2 failure for ${STORAGE_KEY}`));

		const operation = store.read(STORAGE_KEY);

		await expect(operation).rejects.toMatchObject({
			name: 'ResourceObjectStoreError',
			code: 'READ_FAILED',
			message: 'Private resource object read failed',
		});
		await expect(operation).rejects.not.toHaveProperty(
			'message',
			expect.stringContaining(STORAGE_KEY),
		);
	});

	it('deletes the exact storage key', async () => {
		const { bucket, deleteObject } = makeBucket();
		const store = createR2ResourceObjectStore(bucket);

		await store.delete(STORAGE_KEY);

		expect(deleteObject).toHaveBeenCalledTimes(1);
		expect(deleteObject).toHaveBeenCalledWith(STORAGE_KEY);
	});

	it('maps an R2 write exception to a typed error without exposing the storage key', async () => {
		const { bucket, put } = makeBucket();
		const store = createR2ResourceObjectStore(bucket);

		put.mockRejectedValueOnce(new Error(`R2 failure for ${STORAGE_KEY}`));

		const operation = store.write(makeWrite());

		await expect(operation).rejects.toMatchObject({
			name: 'ResourceObjectStoreError',
			code: 'WRITE_FAILED',
			message: 'Private resource object write failed',
		});
		await expect(operation).rejects.toBeInstanceOf(ResourceObjectStoreError);
		await expect(operation).rejects.not.toHaveProperty(
			'message',
			expect.stringContaining(STORAGE_KEY),
		);
	});

	it('treats a null R2 put result as a typed write failure', async () => {
		const { bucket, put } = makeBucket();
		const store = createR2ResourceObjectStore(bucket);

		put.mockResolvedValueOnce(null);

		await expect(store.write(makeWrite())).rejects.toMatchObject({
			name: 'ResourceObjectStoreError',
			code: 'WRITE_FAILED',
			message: 'Private resource object write failed',
		});
	});

	it('maps an R2 delete exception to a typed error without exposing the storage key', async () => {
		const { bucket, deleteObject } = makeBucket();
		const store = createR2ResourceObjectStore(bucket);

		deleteObject.mockRejectedValueOnce(new Error(`R2 failure for ${STORAGE_KEY}`));

		const operation = store.delete(STORAGE_KEY);

		await expect(operation).rejects.toMatchObject({
			name: 'ResourceObjectStoreError',
			code: 'DELETE_FAILED',
			message: 'Private resource object deletion failed',
		});
		await expect(operation).rejects.toBeInstanceOf(ResourceObjectStoreError);
		await expect(operation).rejects.not.toHaveProperty(
			'message',
			expect.stringContaining(STORAGE_KEY),
		);
	});
});
