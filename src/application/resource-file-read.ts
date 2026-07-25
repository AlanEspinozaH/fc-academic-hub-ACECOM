import type { ResourceObjectStore } from '../infrastructure/r2/resource-object-store';
import { derivePrivateResourceStorageKey } from '../infrastructure/r2/resource-storage-key';
import {
	ResourceFileReadPersistenceError,
	type ResourceFileReadDescriptor,
	type ResourceFileReadPersistence,
} from '../infrastructure/supabase/resource-file-read-persistence';

export type ResourceFileReadErrorCode = 'NOT_FOUND' | 'READ_FAILED';

export class ResourceFileReadError extends Error {
	public readonly code: ResourceFileReadErrorCode;

	public constructor(code: ResourceFileReadErrorCode, message: string) {
		super(message);
		this.name = 'ResourceFileReadError';
		this.code = code;
	}
}

export interface ResourceFileReadInput {
	readonly resourceId: string;
	readonly fileId: string;
}

export interface ResourceFileReadResult extends ResourceFileReadDescriptor {
	readonly bytes: Uint8Array<ArrayBuffer>;
}

export interface ResourceFileReader {
	read(input: ResourceFileReadInput): Promise<ResourceFileReadResult>;
}

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const normalizeUuid = (value: string): string | null => {
	const normalized = value.trim().toLowerCase();

	return UUID_PATTERN.test(normalized) ? normalized : null;
};

const readError = (code: ResourceFileReadErrorCode, message: string): ResourceFileReadError =>
	new ResourceFileReadError(code, message);

const notFound = (): ResourceFileReadError => readError('NOT_FOUND', 'Resource file was not found');

const readFailed = (): ResourceFileReadError =>
	readError('READ_FAILED', 'Resource file read is unavailable');

const isPersistenceNotFound = (error: unknown): boolean =>
	error instanceof ResourceFileReadPersistenceError && error.code === 'NOT_FOUND';

export const createResourceFileReader = (
	persistence: ResourceFileReadPersistence,
	objectStore: ResourceObjectStore,
): ResourceFileReader =>
	Object.freeze({
		async read(input: ResourceFileReadInput): Promise<ResourceFileReadResult> {
			const resourceId = normalizeUuid(input.resourceId);
			const fileId = normalizeUuid(input.fileId);

			if (resourceId === null || fileId === null) {
				throw notFound();
			}

			let descriptor: ResourceFileReadDescriptor;

			try {
				descriptor = await persistence.getDescriptor(resourceId, fileId);
			} catch (error) {
				if (isPersistenceNotFound(error)) {
					throw notFound();
				}

				throw readFailed();
			}

			if (descriptor.resourceId !== resourceId || descriptor.fileId !== fileId) {
				throw readFailed();
			}

			let storageKey: string;

			try {
				storageKey = derivePrivateResourceStorageKey(
					descriptor.storageKeyVersion,
					descriptor.resourceId,
					descriptor.fileId,
				);
			} catch {
				throw readFailed();
			}

			try {
				const storedObject = await objectStore.read(storageKey);

				if (storedObject === null) {
					throw notFound();
				}

				return Object.freeze({
					...descriptor,
					bytes: storedObject.bytes,
				});
			} catch (error) {
				if (error instanceof ResourceFileReadError) {
					throw error;
				}

				throw readFailed();
			}
		},
	});
