import type { ResourceStorageKeyVersion } from '../r2/resource-storage-key';
import type { SupabaseServerClient } from './server';
import type { SupabaseDatabase } from './types';

export type ResourceFileReadPersistenceErrorCode = 'NOT_FOUND' | 'READ_FAILED';

export class ResourceFileReadPersistenceError extends Error {
	public readonly code: ResourceFileReadPersistenceErrorCode;

	public constructor(code: ResourceFileReadPersistenceErrorCode, message: string) {
		super(message);
		this.name = 'ResourceFileReadPersistenceError';
		this.code = code;
	}
}

export interface ResourceFileReadDescriptor {
	readonly resourceId: string;
	readonly fileId: string;
	readonly displayFilename: string;
	readonly fileKind: 'pdf';
	readonly normalizedExtension: '.pdf';
	readonly contentType: 'application/pdf';
	readonly byteSize: number;
	readonly sha256: string | null;
	readonly storageKeyVersion: ResourceStorageKeyVersion;
}

export interface ResourceFileReadPersistence {
	getDescriptor(resourceId: string, fileId: string): Promise<ResourceFileReadDescriptor>;
}

type ResourceFileReadRpcClient = Pick<SupabaseServerClient, 'rpc'>;

type ResourceFileReadRpcRow =
	SupabaseDatabase['public']['CompositeTypes']['resource_file_read_descriptor'];

const persistenceError = (
	code: ResourceFileReadPersistenceErrorCode,
	message: string,
): ResourceFileReadPersistenceError => new ResourceFileReadPersistenceError(code, message);

const notFound = (): ResourceFileReadPersistenceError =>
	persistenceError('NOT_FOUND', 'Resource file was not found');

const readFailed = (): ResourceFileReadPersistenceError =>
	persistenceError('READ_FAILED', 'Resource file descriptor read failed');

const isStorageKeyVersion = (value: unknown): value is ResourceStorageKeyVersion =>
	value === 'legacy_pdf_v1' || value === 'generic_v2';

const toDescriptor = (row: ResourceFileReadRpcRow): ResourceFileReadDescriptor | null => {
	if (
		typeof row.resource_id !== 'string' ||
		typeof row.file_id !== 'string' ||
		typeof row.display_filename !== 'string' ||
		row.file_kind !== 'pdf' ||
		row.normalized_extension !== '.pdf' ||
		row.content_type !== 'application/pdf' ||
		typeof row.byte_size !== 'number' ||
		!Number.isSafeInteger(row.byte_size) ||
		row.byte_size <= 0 ||
		(row.sha256 !== null && typeof row.sha256 !== 'string') ||
		!isStorageKeyVersion(row.storage_key_version)
	) {
		return null;
	}

	return Object.freeze({
		resourceId: row.resource_id,
		fileId: row.file_id,
		displayFilename: row.display_filename,
		fileKind: row.file_kind,
		normalizedExtension: row.normalized_extension,
		contentType: row.content_type,
		byteSize: row.byte_size,
		sha256: row.sha256,
		storageKeyVersion: row.storage_key_version,
	});
};

export const createSupabaseResourceFileReadPersistence = (
	client: ResourceFileReadRpcClient,
): ResourceFileReadPersistence =>
	Object.freeze({
		async getDescriptor(resourceId: string, fileId: string): Promise<ResourceFileReadDescriptor> {
			let response;

			try {
				response = await client.rpc('get_resource_file_read_descriptor', {
					resource_id: resourceId,
					file_id: fileId,
				});
			} catch {
				throw readFailed();
			}

			if (response.error !== null) {
				throw readFailed();
			}

			if (response.data === null || response.data.length === 0) {
				throw notFound();
			}

			if (response.data.length !== 1) {
				throw readFailed();
			}

			const descriptor = toDescriptor(response.data[0]);

			if (descriptor === null) {
				throw readFailed();
			}

			return descriptor;
		},
	});
