export type ResourceObjectStoreErrorCode = 'WRITE_FAILED' | 'READ_FAILED' | 'DELETE_FAILED';

export class ResourceObjectStoreError extends Error {
	public readonly code: ResourceObjectStoreErrorCode;

	public constructor(code: ResourceObjectStoreErrorCode, message: string) {
		super(message);
		this.name = 'ResourceObjectStoreError';
		this.code = code;
	}
}

export interface ResourceObjectWrite {
	readonly storageKey: string;
	readonly bytes: Uint8Array;
	readonly contentType: string;
}

export interface ResourceObjectRead {
	readonly bytes: Uint8Array<ArrayBuffer>;
}

export interface ResourceObjectStore {
	write(input: ResourceObjectWrite): Promise<void>;
	read(storageKey: string): Promise<ResourceObjectRead | null>;
	delete(storageKey: string): Promise<void>;
}

type ResourceR2Bucket = Pick<R2Bucket, 'put' | 'get' | 'delete'>;

const writeFailed = (): ResourceObjectStoreError =>
	new ResourceObjectStoreError('WRITE_FAILED', 'Private resource object write failed');

const readFailed = (): ResourceObjectStoreError =>
	new ResourceObjectStoreError('READ_FAILED', 'Private resource object read failed');

const deleteFailed = (): ResourceObjectStoreError =>
	new ResourceObjectStoreError('DELETE_FAILED', 'Private resource object deletion failed');

export const createR2ResourceObjectStore = (bucket: ResourceR2Bucket): ResourceObjectStore =>
	Object.freeze({
		async write(input: ResourceObjectWrite): Promise<void> {
			let storedObject: R2Object | null;

			try {
				storedObject = await bucket.put(input.storageKey, input.bytes, {
					httpMetadata: {
						contentType: input.contentType,
					},
				});
			} catch {
				throw writeFailed();
			}

			if (storedObject === null) {
				throw writeFailed();
			}
		},

		async read(storageKey: string): Promise<ResourceObjectRead | null> {
			try {
				const storedObject = await bucket.get(storageKey);

				if (storedObject === null) {
					return null;
				}

				return Object.freeze({
					bytes: new Uint8Array(await storedObject.arrayBuffer()),
				});
			} catch {
				throw readFailed();
			}
		},

		async delete(storageKey: string): Promise<void> {
			try {
				await bucket.delete(storageKey);
			} catch {
				throw deleteFailed();
			}
		},
	});
