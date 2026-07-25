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

interface ResourceFileReadDescriptorBase {
	readonly resourceId: string;
	readonly fileId: string;
	readonly displayFilename: string;
	readonly byteSize: number;
	readonly sha256: string | null;
}

export type ResourceFileReadDescriptor =
	| (ResourceFileReadDescriptorBase & {
			readonly fileKind: 'pdf';
			readonly normalizedExtension: '.pdf';
			readonly contentType: 'application/pdf';
			readonly storageKeyVersion: ResourceStorageKeyVersion;
	  })
	| (ResourceFileReadDescriptorBase & {
			readonly fileKind: 'image';
			readonly normalizedExtension: '.png';
			readonly contentType: 'image/png';
			readonly storageKeyVersion: 'generic_v2';
	  })
	| (ResourceFileReadDescriptorBase & {
			readonly fileKind: 'image';
			readonly normalizedExtension: '.jpg' | '.jpeg';
			readonly contentType: 'image/jpeg';
			readonly storageKeyVersion: 'generic_v2';
	  });

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
		typeof row.byte_size !== 'number' ||
		!Number.isSafeInteger(row.byte_size) ||
		row.byte_size <= 0 ||
		(row.sha256 !== null && typeof row.sha256 !== 'string') ||
		!isStorageKeyVersion(row.storage_key_version)
	) {
		return null;
	}

	const base = {
		resourceId: row.resource_id,
		fileId: row.file_id,
		displayFilename: row.display_filename,
		byteSize: row.byte_size,
		sha256: row.sha256,
	};

	if (
		row.file_kind === 'pdf' &&
		row.normalized_extension === '.pdf' &&
		row.content_type === 'application/pdf'
	) {
		return Object.freeze({
			...base,
			fileKind: 'pdf',
			normalizedExtension: '.pdf',
			contentType: 'application/pdf',
			storageKeyVersion: row.storage_key_version,
		});
	}

	if (row.file_kind !== 'image' || row.storage_key_version !== 'generic_v2') {
		return null;
	}

	if (row.normalized_extension === '.png' && row.content_type === 'image/png') {
		return Object.freeze({
			...base,
			fileKind: 'image',
			normalizedExtension: '.png',
			contentType: 'image/png',
			storageKeyVersion: 'generic_v2',
		});
	}

	if (
		(row.normalized_extension === '.jpg' || row.normalized_extension === '.jpeg') &&
		row.content_type === 'image/jpeg'
	) {
		return Object.freeze({
			...base,
			fileKind: 'image',
			normalizedExtension: row.normalized_extension,
			contentType: 'image/jpeg',
			storageKeyVersion: 'generic_v2',
		});
	}

	return null;
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
